#!/usr/bin/env bats
# test_preflight.bats - Unit tests for preflight_check and validation paths

# Load test helpers
load '../helpers/test_helper.bash'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
    cd "$TEST_PROJECT" || return
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Helper Functions
# =============================================================================

# A real local process implementing only the documented Oracle CLI boundary.
# It never contacts a model/browser. Probe invocations do not count as launches.
create_oracle_failure_fixture() {
    mkdir -p "$TEST_DIR/oracle-bin"
    cat > "$TEST_DIR/oracle-bin/oracle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    --version) printf '%s\n' 'oracle 1.0.0'; exit 0 ;;
    --help) printf '%s\n' '--notify --browser-attachments --write-output'; exit 0 ;;
    status)
        printf '%s\n' "$$" >> "$APR_FIXTURE_COUNT.status"
        if [[ "$APR_FIXTURE_MODE" == busy_hanging_status ]]; then
            trap '' TERM
            sleep 60 &
            printf '%s\n' "$!" >> "$APR_FIXTURE_COUNT.status"
            wait
        fi
        printf '%s\n' 'ERROR: busy: local session listing is only advisory' >&2
        exit "${APR_FIXTURE_STATUS_EXIT:-0}"
        ;;
esac
for arg in "$@"; do
    if [[ "$arg" == --render ]]; then
        printf '%s\n' 'Offline notification capability preview.'
        exit 0
    fi
done
count=0
[[ ! -f "$APR_FIXTURE_COUNT" ]] || count=$(cat "$APR_FIXTURE_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$APR_FIXTURE_COUNT"
case "$APR_FIXTURE_MODE" in
    busy) printf '%s\n' 'ERROR: busy: another review is active' >&2; exit 1 ;;
    browser_busy) printf '%s\n' 'User error (browser-automation): busy' >&2; exit 7 ;;
    busy_for|busy_hanging_status)
        if [[ "$count" -le "${APR_FIXTURE_BUSY_RESPONSES:-4}" ]]; then
            printf '%s\n' 'ERROR: busy: another review is active' >&2
            exit 7
        fi
        ;;
    busy_success|busy_auth)
        if [[ "$count" -eq 1 ]]; then
            printf '%s\n' 'ERROR: busy' >&2
            exit 1
        fi
        if [[ "$APR_FIXTURE_MODE" == busy_auth ]]; then
            printf '%s\n' 'ERROR: authentication failed' >&2
            exit 19
        fi
        ;;
    numeric_12) printf '%s\n' 'ERROR: authentication failed' >&2; exit 12 ;;
    unrelated) printf '%s\n' 'ERROR: device or resource busy' >&2; exit 23 ;;
    stdout_busy) printf '%s\n' 'ERROR: busy'; printf '%s\n' 'ERROR: authentication failed' >&2; exit 19 ;;
    success_busy) printf '%s\n' 'ERROR: busy' >&2 ;;
    slow_success) sleep 2 ;;
esac
printf 'Useful stdout\r\n'
printf 'Useful stderr\r\n' >&2
while [[ $# -gt 0 ]]; do
    if [[ "$1" == --write-output ]]; then
        shift
        case "$APR_FIXTURE_MODE" in
            missing_output) ;;
            incomplete_output) printf '%s\n' 'Incomplete response.' > "$1" ;;
            *) for ((i=0; i<100; i++)); do printf '%s\n' 'A complete deterministic local fixture response.'; done > "$1" ;;
        esac
    fi
    shift
done
EOF
    chmod +x "$TEST_DIR/oracle-bin/oracle"
    export APR_FIXTURE_COUNT="$TEST_DIR/oracle-count"
    export APR_FIXTURE_MODE="${1:-busy}"
    export PATH="$TEST_DIR/oracle-bin:$PATH"
    export APR_NO_NPX=1
    ORACLE_CMD=("$TEST_DIR/oracle-bin/oracle")
    MAX_RETRY_ATTEMPTS=1
    INITIAL_BACKOFF=0
    # Existing detector cases exercise ordinary retry semantics. Busy-wait
    # tests below explicitly enable a budget without changing their assertions.
    ORACLE_BUSY_WAIT_SECONDS=0
    [[ -x "${ORACLE_CMD[0]}" && "$MAX_RETRY_ATTEMPTS" -eq 1 && "$INITIAL_BACKOFF" -eq 0 ]]
}

configure_busy_wait_fixture() {
    create_oracle_failure_fixture "${1:-busy_for}"
    export APR_BUSY_WAIT_SECONDS="${2:-10}" APR_BUSY_MIN_SLEEP=1 APR_BUSY_MAX_SLEEP=1 APR_BUSY_STATUS_TIMEOUT=1
    export APR_FIXTURE_BUSY_RESPONSES="${3:-2}"
    ORACLE_BUSY_WAIT_SECONDS="$APR_BUSY_WAIT_SECONDS"
    ORACLE_BUSY_MIN_SLEEP=1 ORACLE_BUSY_MAX_SLEEP=1 ORACLE_BUSY_STATUS_TIMEOUT=1
    [[ "$ORACLE_BUSY_WAIT_SECONDS" == "$APR_BUSY_WAIT_SECONDS" && "$ORACLE_BUSY_MIN_SLEEP" -eq 1 && "$ORACLE_BUSY_MAX_SLEEP" -eq 1 && "$ORACLE_BUSY_STATUS_TIMEOUT" -eq 1 ]]
}

create_docs() {
    local dir="${1:-$TEST_PROJECT}"
    mkdir -p "$dir"

    # Keep fixtures comfortably above preflight "suspiciously small" thresholds.
    cat > "$dir/README.md" <<'EOF'
# README

This is a test README for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF

    cat > "$dir/SPEC.md" <<'EOF'
# SPEC

This is a test spec for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF

    cat > "$dir/IMPL.md" <<'EOF'
# IMPL

This is a test implementation doc for APR preflight unit tests.
It is intentionally long enough to avoid size warnings.
EOF

    log_test_step "fixture" "Created test docs in $dir"
}

write_workflow_config() {
    local readme_path="$1"
    local spec_path="$2"
    local impl_path="${3:-}"

    mkdir -p ".apr/workflows"

    {
        echo "name: default"
        echo "description: Test workflow"
        echo "documents:"
        echo "  readme: $readme_path"
        echo "  spec: $spec_path"
        if [[ -n "$impl_path" ]]; then
            echo "  implementation: $impl_path"
        fi
        echo "oracle:"
        echo "  model: \"5.2 Thinking\""
        echo "rounds:"
        echo "  output_dir: .apr/rounds/default"
    } > ".apr/workflows/default.yaml"

    echo "default_workflow: default" > ".apr/config.yaml"
}

create_oracle_version_fail() {
    local mock_bin="$TEST_DIR/mock_oracle_fail"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/oracle" << 'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    exit 1
fi
echo "mock oracle ok"
exit 0
EOF
    chmod +x "$mock_bin/oracle"

    echo "$mock_bin"
}

create_path_without_oracle() {
    local mock_bin="$TEST_DIR/no_oracle_bin"
    mkdir -p "$mock_bin"

    ln -s "$(command -v jq)" "$mock_bin/jq"
    ln -s "$(command -v awk)" "$mock_bin/awk"
    ln -s "$(command -v date)" "$mock_bin/date"
    # Keep enough coreutils available for test helpers (capture_streams, logging).
    ln -s "$(command -v mktemp)" "$mock_bin/mktemp"
    ln -s "$(command -v mkdir)" "$mock_bin/mkdir"
    ln -s "$(command -v rm)" "$mock_bin/rm"
    ln -s "$(command -v cat)" "$mock_bin/cat"

    echo "$mock_bin"
}

assert_json_array_contains() {
    local json="$1"
    local path="$2"
    local expected="$3"

    if ! echo "$json" | jq -e --arg exp "$expected" "$path | index(\$exp)" > /dev/null; then
        log_test_error "Expected $path to include: $expected"
        fail "Expected $path to include: $expected"
    fi
}

# =============================================================================
# preflight_check() Tests
# =============================================================================

@test "preflight_check: happy path returns 0" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
}

@test "preflight_check: README missing returns 1" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not found"* ]]
}

@test "preflight_check: README not readable returns 1" {
    create_docs
    chmod 000 "$TEST_PROJECT/README.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"README not readable"* ]]
}

@test "preflight_check: Spec missing returns 1" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not found"* ]]
}

@test "preflight_check: Spec not readable returns 1" {
    create_docs
    chmod 000 "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Spec not readable"* ]]
}

@test "preflight_check: impl missing returns warning (2)" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/MISSING_IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not found"* ]]
}

@test "preflight_check: impl not readable returns warning (2)" {
    create_docs
    chmod 000 "$TEST_PROJECT/IMPL.md"
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Implementation not readable"* ]]
}

@test "preflight_check: impl valid returns 0" {
    create_docs
    setup_mock_oracle

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
}

@test "preflight_check: oracle missing returns 1" {
    create_docs
    check_oracle() { return 1; }

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *"Oracle not available"* ]]
}

@test "preflight_check: oracle version check failure returns warning (2)" {
    create_docs
    local mock_bin
    mock_bin="$(create_oracle_version_fail)"
    local original_path="$PATH"
    PATH="$mock_bin:$PATH"
    export PATH

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    PATH="$original_path"
    export PATH

    log_test_actual "exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *"Could not verify Oracle version"* ]]
}

# =============================================================================
# run_round() Validation Path Tests
# =============================================================================

@test "run_round: missing workflow config returns EXIT_CONFIG_ERROR" {
    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; run_round 1'

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 4 ]]
}

@test "run_round: missing required document returns EXIT_CONFIG_ERROR" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 4 ]]
    [[ "$output" == *"Required file not found"* ]]
}

@test "run_round: include_impl with no implementation configured warns and continues" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; INCLUDE_IMPL=true; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Implementation document not configured; skipping"* ]]
}

@test "run_round: include_impl with missing file warns and continues" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/MISSING_IMPL.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; INCLUDE_IMPL=true; DRY_RUN=true; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Implementation file not found"* ]]
}

@test "run_round: existing output can cancel with prompt" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    mkdir -p ".apr/rounds/default"
    printf '%s\n' "existing" > ".apr/rounds/default/round_1.md"

    run bash -c 'source "$TEST_DIR/apr_functions.bash"; cd "$TEST_PROJECT"; SKIP_PREFLIGHT=true; can_prompt() { return 0; }; confirm() { return 1; }; run_round 1' 2>&1

    log_test_actual "exit code" "$status"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Cancelled."* ]]
}

# =============================================================================
# robot_validate() Tests
# =============================================================================

@test "robot_validate: missing round number returns usage_error" {
    capture_streams robot_validate

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "usage_error"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Round number required"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=usage_error"* ]]
}

@test "robot_validate: not initialized returns not_configured" {
    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "not_configured"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Not initialized - run 'apr robot init'"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=not_configured"* ]]
}

@test "robot_validate: workflow not found returns validation_failed" {
    mkdir -p ".apr/workflows"
    echo "default_workflow: default" > ".apr/config.yaml"

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Workflow 'default' not found"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: README missing populates errors" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "README not found: $TEST_PROJECT/MISSING_README.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: spec missing populates errors" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/MISSING_SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Spec not found: $TEST_PROJECT/MISSING_SPEC.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: oracle missing populates errors" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"

    local original_path="$PATH"
    local mock_path
    mock_path="$(create_path_without_oracle)"
    PATH="$mock_path"
    export PATH

    capture_streams robot_validate 1

    PATH="$original_path"
    export PATH

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "validation_failed"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Oracle not available"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=validation_failed"* ]]
}

@test "robot_validate: previous round missing yields warnings but ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 2

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.warnings" "Previous round 1 not found - starting fresh?"
    [[ -z "$CAPTURED_STDERR" ]]
}

@test "robot_validate: all valid returns ok true" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_value "$CAPTURED_STDOUT" ".code" "ok"
    [[ -z "$CAPTURED_STDERR" ]]
}
@test "Oracle busy classifier accepts explicit failing stderr signatures only" {
    local diagnostic="$TEST_DIR/diagnostic"
    local text
    for text in 'ERROR: busy' ' ERROR: busy: another review is active' 'User error (browser-automation): busy' 'error: BUSY' $'\033[31mERROR: busy\033[0m'; do
        printf '%s\n' "$text" > "$diagnostic"
        run oracle_failure_kind 1 "$diagnostic"
        [[ "$status" -eq 0 && "$output" == busy ]]
        run oracle_failure_kind 0 "$diagnostic"
        [[ "$status" -eq 0 && "$output" == ok ]]
    done
}

@test "Oracle busy classifier rejects unrelated errors and word-boundary near misses" {
    local diagnostic="$TEST_DIR/diagnostic"
    local text
    for text in 'ERROR: device or resource busy' 'ERROR: busybox missing' 'ERROR: business rule failed' 'User error (browser-automation): business failure' 'A document quotes ERROR: busy' 'ERROR: authentication failed' 'ERROR: busy_retry_unavailable'; do
        printf '%s\n' "$text" > "$diagnostic"
        run oracle_failure_kind 12 "$diagnostic"
        [[ "$status" -eq 0 && "$output" == oracle_error ]]
    done
    run oracle_failure_kind 1 "$TEST_DIR/missing"
    [[ "$status" -eq 0 && "$output" == oracle_error ]]
}

@test "Oracle success preserves exact stdout stderr and one real process invocation" {
    create_oracle_failure_fixture success
    printf 'Useful stdout\r\n' > "$TEST_DIR/expected-out"
    printf 'Useful stderr\r\n' > "$TEST_DIR/expected-err"
    run_oracle_with_retry > "$TEST_DIR/actual-out" 2> "$TEST_DIR/actual-err"
    cmp "$TEST_DIR/expected-out" "$TEST_DIR/actual-out"
    cmp "$TEST_DIR/expected-err" "$TEST_DIR/actual-err"
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "Oracle busy maps to APR exit12 while retaining the native status and stderr" {
    create_oracle_failure_fixture browser_busy
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 12 && "$ORACLE_EXIT_CODE" -eq 7 && "$ORACLE_FAILURE_KIND" == busy ]]
    [[ -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'User error (browser-automation): busy'* ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "Oracle successful stderr and failing stdout lookalikes never establish busy" {
    create_oracle_failure_fixture success_busy
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 0 && "$ORACLE_FAILURE_KIND" == ok ]]
    APR_FIXTURE_MODE=stdout_busy
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 19 && "$ORACLE_FAILURE_KIND" == oracle_error ]]
    [[ "$CAPTURED_STDOUT" == 'ERROR: busy' && "$CAPTURED_STDERR" == *'ERROR: authentication failed'* ]]
}

@test "Oracle busy followed by success clears the earlier classification" {
    create_oracle_failure_fixture busy_success
    MAX_RETRY_ATTEMPTS=2
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 0 && "$ORACLE_EXIT_CODE" -eq 0 && "$ORACLE_FAILURE_KIND" == ok ]]
    [[ "$CAPTURED_STDOUT" == $'Useful stdout\r' && "$CAPTURED_STDERR" == *'ERROR: busy'* ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
}

@test "Oracle final authentication failure cannot reuse an earlier busy classification" {
    create_oracle_failure_fixture busy_auth
    MAX_RETRY_ATTEMPTS=2
    capture_streams run_oracle_recorded "$TEST_DIR/result" true
    [[ "$CAPTURED_STATUS" -eq 19 && "$ORACLE_FAILURE_KIND" == oracle_error ]]
    [[ "$(cat "$TEST_DIR/result")" == $'19\noracle_error' ]]
    [[ "$CAPTURED_STDERR" == *'ERROR: busy'* && "$CAPTURED_STDERR" == *'ERROR: authentication failed'* ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
}

@test "Oracle diagnostic sink failure never relaunches a successful producer" {
    create_oracle_failure_fixture success
    MAX_RETRY_ATTEMPTS=3
    [[ "$MAX_RETRY_ATTEMPTS" -eq 3 ]]
    tee() { cat >&2; return 1; }
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 1 && "$ORACLE_EXIT_CODE" -eq 0 && "$ORACLE_FAILURE_KIND" == capture_error ]]
    [[ "$CAPTURED_STDOUT" == $'Useful stdout\r' && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "human foreground no-retry reports Oracle busy with the semantic exit" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture busy
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -eq 12 && "$CAPTURED_STDERR" == *'APR_ERROR_CODE=busy'* ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 && ! -f .apr/rounds/default/round_1.md ]]
}

@test "human immediate background busy does not report a successful launch" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture busy
    capture_streams bash "$APR_SCRIPT" run 1 --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -eq 12 && "$CAPTURED_STDERR" == *'APR_ERROR_CODE=busy'* ]]
    [[ "$CAPTURED_STDERR" != *'Oracle running in background'* ]]
}

@test "robot immediate busy returns typed JSON with the real native exit and log" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture browser_busy
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 12 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' busy
    assert_json_value "$CAPTURED_STDOUT" '.ok' false
    assert_json_value "$CAPTURED_STDOUT" '.data.oracle_exit' 7
    local log_file
    log_file=$(jq -r '.data.log_file' <<< "$CAPTURED_STDOUT")
    [[ -f "$log_file" && "$(cat "$log_file")" == *'User error (browser-automation): busy'* ]]
}

@test "human completed background success retains the actual output and returns success" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture success
    capture_streams bash "$APR_SCRIPT" run 1 --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDERR" == *'Oracle completed; output retained'* ]]
    [[ -s .apr/rounds/default/round_1.md && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    [[ "$(head -n 1 .apr/rounds/default/round_1.md)" == 'A complete deterministic local fixture response.' ]]
}

@test "robot completed success and busy-then-success return real output once" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture busy_success
    export APR_MAX_RETRIES=2 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' ok
    assert_json_value "$CAPTURED_STDOUT" '.ok' true
    assert_json_value "$CAPTURED_STDOUT" '.data.status' completed
    [[ -s .apr/rounds/default/round_1.md && "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
    [[ "$CAPTURED_STDERR" != *'APR_ERROR_CODE=busy'* ]]
}

@test "human completed process without complete output remains a failure" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture incomplete_output
    capture_streams bash "$APR_SCRIPT" run 1 --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -ne 0 && "$CAPTURED_STDERR" != *'Oracle completed; output retained'* ]]
    [[ "$(cat .apr/rounds/default/round_1.md)" == 'Incomplete response.' ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "robot completed process without output never reports completed" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture missing_output
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' internal_error
    [[ ! -f .apr/rounds/default/round_1.md && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "robot ongoing worker remains running and eventually retains useful output" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture slow_success
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.status' running
    local attempt
    for ((attempt=0; attempt<30; attempt++)); do
        [[ -s .apr/rounds/default/round_1.md ]] && break
        sleep 0.1
    done
    [[ -s .apr/rounds/default/round_1.md && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    [[ "$(head -n 1 .apr/rounds/default/round_1.md)" == 'A complete deterministic local fixture response.' ]]
}

@test "robot immediate numeric exit12 without busy stderr stays a distinct failure" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture numeric_12
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' internal_error
    [[ "$CAPTURED_STDERR" != *'APR_ERROR_CODE=busy'* && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
}

@test "robot completed retry sequence exposes only its final unrelated failure" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture busy_auth
    export APR_MAX_RETRIES=2 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' internal_error
    [[ "$CAPTURED_STDERR" != *'APR_ERROR_CODE=busy'* && "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
}

@test "busy wait: public foreground recovers beyond generic retry limit with useful output" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    configure_busy_wait_fixture busy_for 10 4
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-preflight
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 5 ]]
    [[ -s .apr/rounds/default/round_1.md ]]
    [[ "$(head -n 1 .apr/rounds/default/round_1.md)" == 'A complete deterministic local fixture response.' ]]
    [[ "$CAPTURED_STDERR" == *'single-flight'* && "$CAPTURED_STDERR" == *'retrying in 1s'* ]]
    [[ "$(wc -l < "$APR_FIXTURE_COUNT.status")" -eq 4 ]]
}

@test "busy wait: finite budget returns busy12 with final producer status and no extra launch" {
    configure_busy_wait_fixture busy 1
    local started=$SECONDS
    capture_streams run_oracle_recorded "$TEST_DIR/result" true
    [[ "$CAPTURED_STATUS" -eq 12 && "$ORACLE_FAILURE_KIND" == busy && "$ORACLE_EXIT_CODE" -eq 1 ]]
    [[ "$(cat "$TEST_DIR/result")" == $'1\nbusy' && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *'wait budget exhausted'* && $((SECONDS - started)) -le 3 ]]
}

@test "busy wait: hanging TERM-ignoring status descendants consume the budget and cannot relabel busy" {
    configure_busy_wait_fixture busy_hanging_status 1 9
    local started=$SECONDS pid state
    capture_streams run_oracle_recorded "$TEST_DIR/result" true
    [[ "$CAPTURED_STATUS" -eq 12 && "$(cat "$TEST_DIR/result")" == $'7\nbusy' ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 && $((SECONDS - started)) -le 3 ]]
    [[ "$(wc -l < "$APR_FIXTURE_COUNT.status")" -eq 2 ]]
    while IFS= read -r pid; do
        state=$(ps -p "$pid" -o stat= || true)
        [[ -z "$state" || "$state" == Z* ]]
    done < "$APR_FIXTURE_COUNT.status"
}

@test "busy wait: later authentication retains native error despite failed advisory status" {
    configure_busy_wait_fixture busy_auth 10
    export APR_FIXTURE_STATUS_EXIT=19
    MAX_RETRY_ATTEMPTS=1
    capture_streams run_oracle_recorded "$TEST_DIR/result" true
    [[ "$CAPTURED_STATUS" -eq 19 && "$ORACLE_FAILURE_KIND" == oracle_error ]]
    [[ "$(cat "$TEST_DIR/result")" == $'19\noracle_error' && "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *'ERROR: authentication failed'* ]]
}

@test "busy wait: explicit infinite mode recovers with exact streams and no duplicate success" {
    configure_busy_wait_fixture busy_for infinite 2
    printf 'Useful stdout\r\n' > "$TEST_DIR/expected-out"
    run_oracle_with_retry > "$TEST_DIR/actual-out" 2> "$TEST_DIR/actual-err"
    cmp "$TEST_DIR/expected-out" "$TEST_DIR/actual-out"
    [[ "$ORACLE_FAILURE_KIND" == ok && "$ORACLE_EXIT_CODE" -eq 0 ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 3 && "$(cat "$TEST_DIR/actual-err")" == *$'Useful stderr\r'* ]]
}

@test "busy wait: no-retry stays one-shot even with an explicit infinite budget" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    configure_busy_wait_fixture busy infinite
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -eq 12 && "$CAPTURED_STDERR" == *'APR_ERROR_CODE=busy'* ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 && ! -e "$APR_FIXTURE_COUNT.status" ]]
}

@test "busy wait: public robot opts in and its detached worker retains completed output" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    configure_busy_wait_fixture busy_for 10 2
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.busy_policy' wait
    assert_json_value "$CAPTURED_STDOUT" '.data.status' running
    local attempt result_file
    for ((attempt=0; attempt<80; attempt++)); do
        [[ -s .apr/rounds/default/round_1.md ]] && break
        sleep 0.1
    done
    [[ -s .apr/rounds/default/round_1.md && "$(cat "$APR_FIXTURE_COUNT")" -eq 3 ]]
    result_file=$(find .apr/logs -name '*.result.*' -type f)
    for ((attempt=0; attempt<20; attempt++)); do
        [[ "$(cat "$result_file")" == $'0\nok' ]] && break
        sleep 0.1
    done
    [[ "$(cat "$result_file")" == $'0\nok' ]]
    [[ "$(head -n 1 .apr/rounds/default/round_1.md)" == 'A complete deterministic local fixture response.' ]]
}

@test "busy wait: robot default preserves its retry policy and returns structured busy" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_oracle_failure_fixture browser_busy
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 12 && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.policy' retry
    assert_json_value "$CAPTURED_STDOUT" '.data.busy' true
    [[ ! -e "$APR_FIXTURE_COUNT.status" ]]
}

@test "busy wait: configuration normalizes decimal and rejects overflow or zero delays" {
    [[ "$(oracle_busy_config_seconds 00008 5)" == 8 ]]
    [[ "$(oracle_busy_config_seconds 999999999999999999999 5)" == 5 ]]
    [[ "$(oracle_busy_config_seconds invalid 5)" == 5 ]]
    [[ "$(oracle_busy_config_seconds 86401 5)" == 5 ]]
    [[ "$(oracle_busy_config_seconds 0 5)" == 0 ]]
    export APR_BUSY_WAIT_SECONDS=00008 APR_BUSY_MIN_SLEEP=0 APR_BUSY_MAX_SLEEP=0 APR_BUSY_STATUS_TIMEOUT=0
    capture_streams bash -c 'source "$1"; printf "%s %s %s %s" "$ORACLE_BUSY_WAIT_SECONDS" "$ORACLE_BUSY_MIN_SLEEP" "$ORACLE_BUSY_MAX_SLEEP" "$ORACLE_BUSY_STATUS_TIMEOUT"' _ "$TEST_DIR/apr_functions.bash"
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDOUT" == '8 5 5 2' ]]
}

@test "busy wait: capped exponential delays recover without consuming ordinary attempts" {
    configure_busy_wait_fixture busy_for 10 3
    ORACLE_BUSY_MAX_SLEEP=2
    [[ "$ORACLE_BUSY_MAX_SLEEP" -eq 2 ]]
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *'retrying in 1s'* && "$CAPTURED_STDERR" == *'retrying in 2s'* ]]
    [[ "$CAPTURED_STDERR" != *'retrying in 4s'* && "$CAPTURED_STDOUT" == $'Useful stdout\r' ]]
}

@test "busy wait: missing bounded status utility still recovers without a probe" {
    configure_busy_wait_fixture busy_for 10 1
    command() {
        if [[ "${1:-}" == -v && ( "${2:-}" == timeout || "${2:-}" == gtimeout ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
    [[ ! -e "$APR_FIXTURE_COUNT.status" && "$CAPTURED_STDOUT" == $'Useful stdout\r' ]]
}

@test "busy wait: diagnostic capture failure never replays the producer with waiting enabled" {
    configure_busy_wait_fixture success infinite
    tee() { cat >&2; return 1; }
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 1 && "$ORACLE_FAILURE_KIND" == capture_error && "$ORACLE_EXIT_CODE" -eq 0 ]]
    [[ "$(cat "$APR_FIXTURE_COUNT")" -eq 1 && ! -e "$APR_FIXTURE_COUNT.status" ]]
    [[ "$CAPTURED_STDOUT" == $'Useful stdout\r' ]]
}

@test "busy wait: generic backoff after busy respects the deadline and preserves authentication" {
    configure_busy_wait_fixture busy_auth 2
    MAX_RETRY_ATTEMPTS=3 INITIAL_BACKOFF=4
    local started=$SECONDS
    capture_streams run_oracle_recorded "$TEST_DIR/result" true
    [[ "$CAPTURED_STATUS" -eq 19 && "$ORACLE_FAILURE_KIND" == oracle_error ]]
    [[ "$(cat "$TEST_DIR/result")" == $'19\noracle_error' && "$(cat "$APR_FIXTURE_COUNT")" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *'retaining the final Oracle result'* && $((SECONDS - started)) -le 4 ]]
}

@test "busy wait: public foreground budget exhaustion retains the semantic busy exit" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    configure_busy_wait_fixture browser_busy 1
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-preflight
    [[ "$CAPTURED_STATUS" -eq 12 && "$CAPTURED_STDERR" == *'APR_ERROR_CODE=busy'* ]]
    [[ "$CAPTURED_STDERR" == *'wait budget exhausted'* && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    [[ ! -f .apr/rounds/default/round_1.md ]]
}
