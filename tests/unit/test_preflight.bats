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
# Opt-in exact argv capture for prompt binding cases. Capability probes have no
# file arguments and never create records. Preserve original fixture behavior.
if [[ -n "${APR_FIXTURE_PROMPT_DIR:-}" ]]; then
    has_files=false
    for arg in "$@"; do [[ "$arg" != --file ]] || has_files=true; done
    if [[ "$has_files" == true ]]; then
        record=0
        [[ ! -f "$APR_FIXTURE_PROMPT_DIR/count" ]] || record=$(cat "$APR_FIXTURE_PROMPT_DIR/count")
        record=$((record + 1))
        printf '%s\n' "$record" > "$APR_FIXTURE_PROMPT_DIR/count"
        args=("$@")
        for ((idx=0; idx<${#args[@]}; idx++)); do
            case "${args[idx]}" in
                -p) printf '%s' "${args[idx+1]}" > "$APR_FIXTURE_PROMPT_DIR/prompt-$record" ;;
                --file) printf '%s\0' "${args[idx+1]}" >> "$APR_FIXTURE_PROMPT_DIR/files-$record" ;;
            esac
        done
    fi
fi
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

create_manifest_probe_spy() {
    mkdir -p "$TEST_DIR/manifest-spy"
    local tool
    for tool in oracle npx; do
        cat > "$TEST_DIR/manifest-spy/$tool" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$APR_MANIFEST_PROBES"
exit 97
EOF
        chmod +x "$TEST_DIR/manifest-spy/$tool"
    done
    export APR_MANIFEST_PROBES="$TEST_DIR/manifest-probes"
    export PATH="$TEST_DIR/manifest-spy:$PATH"
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
    # Offline validation still needs real metadata/QC tools; only Oracle/npx
    # are intentionally absent. Missing hashing tools is a different failure.
    local tool
    for tool in base64 tr tee wc sha256sum; do
        ln -s "$(command -v "$tool")" "$mock_bin/$tool"
    done

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

@test "preflight_check: never edits an installed Oracle and names removed stability knobs" {
    create_docs
    setup_mock_oracle
    # A global install beside the oracle on PATH, holding the exact Oracle 0.8.x
    # lines that apr used to rewrite in place with sed.
    local installed="$TEST_DIR/lib/node_modules/@steipete/oracle/dist/src/browser/actions/assistantResponse.js"
    mkdir -p "$(dirname "$installed")"
    printf '%s\n' 'const minStableMs = shortAnswer ? 8000 : 1200;' 'const stableTarget = shortAnswer ? 6 : 3;' > "$installed"
    local before
    before=$(cat "$installed")
    unset APR_ORACLE_MIN_STABLE_MS APR_ORACLE_SHORT_STABLE_MS APR_ORACLE_SETTLE_WINDOW_MS APR_ORACLE_STABLE_CYCLES

    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    log_test_actual "stderr" "$CAPTURED_STDERR"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" != *truncat* && "$CAPTURED_STDERR" != *assistantResponse* && "$CAPTURED_STDERR" != *'No longer used'* ]]

    export APR_ORACLE_MIN_STABLE_MS=45000 APR_ORACLE_STABLE_CYCLES=12
    capture_streams preflight_check "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    log_test_actual "stderr" "$CAPTURED_STDERR"
    [[ "$CAPTURED_STATUS" -eq 2 ]]
    [[ "$CAPTURED_STDERR" == *'No longer used (apr does not patch Oracle): APR_ORACLE_MIN_STABLE_MS APR_ORACLE_STABLE_CYCLES'* ]]
    [[ "$CAPTURED_STDERR" == *ORACLE_TERMINAL_MIN_STABLE_MS* && "$CAPTURED_STDERR" != *truncat* ]]

    [[ "$(cat "$installed")" == "$before" && ! -e "$installed.apr-backup" ]]
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
    [[ "$output" == *"README not found: $TEST_PROJECT/MISSING_README.md"* && "$output" == *APR_ERROR_CODE=config_error* ]]
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

@test "robot_validate: workflow not found returns canonical config_error" {
    mkdir -p ".apr/workflows"
    echo "default_workflow: default" > ".apr/config.yaml"

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "config_error"
    jq -e 'any(.data.findings.errors[];.source.file==".apr/workflows/default.yaml" and (.hint|length)>0 and .code=="config_error")' <<< "$CAPTURED_STDOUT"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=config_error"* ]]
}

@test "robot_validate: README missing populates errors" {
    printf '%s\n' "# SPEC" > "$TEST_PROJECT/SPEC.md"
    write_workflow_config "$TEST_PROJECT/MISSING_README.md" "$TEST_PROJECT/SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "config_error"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "README not found: $TEST_PROJECT/MISSING_README.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=config_error"* ]]
}

@test "robot_validate: spec missing populates errors" {
    printf '%s\n' "# README" > "$TEST_PROJECT/README.md"
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/MISSING_SPEC.md"
    setup_mock_oracle

    capture_streams robot_validate 1

    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "config_error"
    assert_json_array_contains "$CAPTURED_STDOUT" ".data.errors" "Spec not found: $TEST_PROJECT/MISSING_SPEC.md"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=config_error"* ]]
}

@test "robot_validate: local validity stays usable without Oracle" {
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
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_value "$CAPTURED_STDOUT" ".code" "ok"
    jq -e '.data.valid and (.data.errors|length)==0 and (.data.findings.errors|length)==0 and (.data.resolved.prompt_hash|test("^[a-f0-9]{64}$"))' <<< "$CAPTURED_STDOUT"
    [[ -z "$CAPTURED_STDERR" ]]
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

@test "manifest: hash and size retain binary NUL nonUTF8 CRLF and trailing newlines" {
    printf '\000\377A\r\n\n' > "$TEST_PROJECT/binary"
    capture_streams document_file_metadata "$TEST_PROJECT/binary" readme required
    [[ "$CAPTURED_STATUS" -eq 0 && -z "$CAPTURED_STDERR" ]]
    assert_json_value "$CAPTURED_STDOUT" '.bytes' 6
    assert_json_value "$CAPTURED_STDOUT" '.sha256' c2d6098cbf68842ad602337645fae2e17f40f4282f66c573cf5945274971cab9
    [[ "$(wc -c < "$TEST_PROJECT/binary")" -eq 6 ]]
}

@test "manifest: empty file has exact zero bytes and standard SHA256" {
    touch "$TEST_PROJECT/empty"
    capture_streams document_file_metadata "$TEST_PROJECT/empty" spec required
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.bytes' 0
    assert_json_value "$CAPTURED_STDOUT" '.sha256' e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
}

@test "manifest: duplicate basenames quoted newline and leadingdash paths remain distinct" {
    local name=$'-quote"\\line\n.md' manifest
    mkdir -p left right
    printf a > "left/$name"
    printf b > "right/$name"
    manifest=$(build_document_manifest "left/$name" "right/$name" '' false)
    [[ "$(jq '[.files[] | select(.included)] | length' <<< "$manifest")" -eq 2 ]]
    [[ "$(jq -r '.files[] | select(.role=="readme") | .path | @base64' <<< "$manifest")" == "$(printf '%s' "left/$name" | base64 | tr -d '\r\n')" ]]
    [[ "$(jq -r '.files[] | select(.role=="spec") | .path | @base64' <<< "$manifest")" == "$(printf '%s' "right/$name" | base64 | tr -d '\r\n')" ]]
    [[ "$(jq '[.files[] | select(.included) | .sha256] | unique | length' <<< "$manifest")" -eq 2 ]]
    capture_streams format_document_manifest "$manifest"
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDOUT" == *'\\line\n.md'* ]]
}

@test "manifest: repeated JSON and reordered locale-independent text are byte-identical" {
    create_docs
    local first second reversed text
    first=$(build_document_manifest README.md SPEC.md IMPL.md true optional)
    second=$(LC_ALL=C build_document_manifest README.md SPEC.md IMPL.md true optional)
    [[ "$first" == "$second" ]]
    reversed=$(jq '.files |= reverse' <<< "$first")
    text=$(format_document_manifest "$first")
    [[ "$text" == "$(LC_ALL=C format_document_manifest "$reversed")" ]]
    [[ "$(jq -r '.files | map(.role) | join(",")' <<< "$first")" == implementation,readme,spec ]]
}

@test "manifest: same-size content change changes hash without losing either observation" {
    printf aaaa > sample
    local first second
    first=$(document_file_metadata sample readme required)
    printf bbbb > sample
    second=$(document_file_metadata sample readme required)
    [[ "$(jq -r .sha256 <<< "$first")" != "$(jq -r .sha256 <<< "$second")" ]]
    [[ "$(jq .bytes <<< "$first")" -eq 4 && "$(jq .bytes <<< "$second")" -eq 4 ]]
}

@test "manifest: missing optional implementation records reason without fabricated hash" {
    create_docs
    local manifest
    manifest=$(build_document_manifest README.md SPEC.md missing.md true impl_every_n)
    assert_json_value "$manifest" '.files[0].included' false
    assert_json_value "$manifest" '.files[0].reason' impl_every_n
    assert_json_value "$manifest" '.files[0].skip_reason' missing_optional
    [[ "$(jq '.files[0].bytes==null and .files[0].sha256==null' <<< "$manifest")" == true ]]
    manifest=$(build_document_manifest README.md SPEC.md '' true optional)
    assert_json_value "$manifest" '.files[0].skip_reason' not_configured
}

@test "manifest: unrequested present implementation is explicitly skipped" {
    create_docs
    local manifest
    manifest=$(build_document_manifest README.md SPEC.md IMPL.md false optional)
    assert_json_value "$manifest" '.files[0].skip_reason' not_requested
    assert_json_value "$manifest" '.files[0].included' false
    [[ "$(jq '.files[0].bytes==null and .files[0].sha256==null' <<< "$manifest")" == true ]]
}

@test "manifest: missing required or directory document fails without partial stdout" {
    create_docs
    capture_streams build_document_manifest README.md missing.md '' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Cannot read document metadata'* ]]
    capture_streams build_document_manifest README.md "$TEST_PROJECT" '' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" ]]
}

@test "manifest: requested unreadable implementation fails without partial stdout" {
    create_docs
    chmod 000 IMPL.md
    [[ ! -r IMPL.md ]]
    capture_streams build_document_manifest README.md SPEC.md IMPL.md true optional
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Cannot read document metadata'* ]]
}

@test "manifest: failed digest utility cannot publish partial success" {
    create_docs
    sha256sum() { cat >/dev/null; return 9; }
    capture_streams build_document_manifest README.md SPEC.md '' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Failed to hash/count'* ]]
}

@test "manifest: failed byte stream cannot publish partial success" {
    create_docs
    tee() { cat >/dev/null; return 9; }
    capture_streams build_document_manifest README.md SPEC.md '' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Failed to hash/count'* ]]
}

@test "manifest: invalid UTF8 skipped path is rejected rather than silently replaced" {
    create_docs
    capture_streams build_document_manifest README.md SPEC.md $'bad\377.md' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'valid UTF-8'* ]]
}

@test "manifest: public JSON preview skips every Oracle probe and creates no run artifacts" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    create_manifest_probe_spy
    capture_streams bash "$APR_SCRIPT" run 1 --show-manifest --json --render --wait
    [[ "$CAPTURED_STATUS" -eq 0 && ! -e "$APR_MANIFEST_PROBES" ]]
    [[ "$(jq '[.files[] | select(.included)] | length' <<< "$CAPTURED_STDOUT")" -eq 2 ]]
    [[ ! -d .apr/rounds && ! -d .apr/locks && ! -d .apr/.locks && ! -d .apr/logs ]]
    [[ "$CAPTURED_STDOUT" != *'Current local document'* ]]
}

@test "manifest: public text preview is stderr-only and names its observation boundary" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    create_manifest_probe_spy
    capture_streams bash "$APR_SCRIPT" run 1 --show-manifest
    [[ "$CAPTURED_STATUS" -eq 0 && -z "$CAPTURED_STDOUT" && ! -e "$APR_MANIFEST_PROBES" ]]
    [[ "$CAPTURED_STDERR" == *'not a sent attachment receipt'* && "$CAPTURED_STDERR" == *'sha256='* ]]
}

@test "manifest: public preview records explicit and cadence inclusion reasons" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    create_manifest_probe_spy
    capture_streams bash "$APR_SCRIPT" run 3 --show-manifest --json --include-impl
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.files[0].included' true
    assert_json_value "$CAPTURED_STDOUT" '.files[0].reason' optional
    printf '\n  impl_every_n: 4\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 4 --show-manifest --json
    [[ "$CAPTURED_STATUS" -eq 0 && ! -e "$APR_MANIFEST_PROBES" ]]
    assert_json_value "$CAPTURED_STDOUT" '.files[0].reason' impl_every_n
    assert_json_value "$CAPTURED_STDOUT" '.files[0].included' true
}

@test "manifest: public missing required file returns config_error without partial JSON" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/missing.md"
    create_manifest_probe_spy
    capture_streams bash "$APR_SCRIPT" run 1 --show-manifest --json
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && ! -e "$APR_MANIFEST_PROBES" ]]
    [[ "$CAPTURED_STDERR" == *'APR_ERROR_CODE=config_error'* ]]
}

@test "manifest: real shasum fallback preserves binary digest and byte count" {
    printf '\000\377A\r\n\n' > binary
    command() {
        if [[ "${1:-}" == -v && "${2:-}" == sha256sum ]]; then return 1; fi
        builtin command "$@"
    }
    capture_streams document_file_metadata binary readme required
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.bytes' 6
    assert_json_value "$CAPTURED_STDOUT" '.sha256' c2d6098cbf68842ad602337645fae2e17f40f4282f66c573cf5945274971cab9
}

@test "manifest: hash and size describe one stream even when source grows after hashing" {
    printf aaaa > sample
    export APR_MANIFEST_CHANGE_PATH="$TEST_PROJECT/sample"
    sha256sum() {
        local digest
        digest=$(command sha256sum) || return $?
        printf bbbb >> "$APR_MANIFEST_CHANGE_PATH"
        printf '%s\n' "$digest"
    }
    capture_streams document_file_metadata sample readme required
    [[ "$CAPTURED_STATUS" -eq 0 && "$(wc -c < sample)" -eq 8 ]]
    assert_json_value "$CAPTURED_STDOUT" '.bytes' 4
    [[ "$(jq -r '.sha256' <<< "$CAPTURED_STDOUT")" == "$(printf aaaa | command sha256sum | cut -d ' ' -f 1)" ]]
}

@test "manifest: asynchronous size collector failure cannot publish a hash-only result" {
    create_docs
    wc() { cat >/dev/null; return 9; }
    capture_streams build_document_manifest README.md SPEC.md '' false
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Failed to hash/count'* ]]
}

@test "manifest: missing jq returns the matching dependency tag without partial output" {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    SHOW_MANIFEST=true STATS_JSON=true
    [[ "$SHOW_MANIFEST" == true && "$STATS_JSON" == true ]]
    command() {
        if [[ "${1:-}" == -v && "${2:-}" == jq ]]; then return 1; fi
        builtin command "$@"
    }
    capture_streams run_round 1
    [[ "$CAPTURED_STATUS" -eq 3 && -z "$CAPTURED_STDOUT" ]]
    [[ "$CAPTURED_STDERR" == *'APR_ERROR_CODE=dependency_missing'* && "$CAPTURED_STDERR" != *'APR_ERROR_CODE=config_error'* ]]
}

@test "manifest: unsearchable parent is a real read error rather than missing optional" {
    create_docs
    mkdir sealed
    printf 'Useful implementation\n' > sealed/IMPL.md
    chmod 000 sealed
    [[ ! -x sealed && ! -e sealed/IMPL.md ]]
    capture_streams build_document_manifest README.md SPEC.md sealed/IMPL.md true optional
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" ]]
    [[ "$CAPTURED_STDERR" == *'Cannot search optional document parent'* ]]
}

@test "manifest: a genuinely absent optional parent is explicitly skipped" {
    create_docs
    local manifest
    manifest=$(build_document_manifest README.md SPEC.md missing-parent/IMPL.md true optional)
    assert_json_value "$manifest" '.files[0].skip_reason' missing_optional
    assert_json_value "$manifest" '.files[0].included' false
}

@test "manifest: parent enumeration failure never becomes an optional omission" {
    create_docs
    find() { printf '%s\n' 'fixture: directory read failed' >&2; return 9; }
    capture_streams build_document_manifest README.md SPEC.md missing.md true optional
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" ]]
    [[ "$CAPTURED_STDERR" == *'fixture: directory read failed'* && "$CAPTURED_STDERR" == *'Cannot inspect optional document parent'* ]]
}

create_prompt_binding_fixture() {
    create_docs
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    create_oracle_failure_fixture success
    export APR_FIXTURE_PROMPT_DIR="$TEST_DIR/prompt-records"
    mkdir -p "$APR_FIXTURE_PROMPT_DIR"
}

assert_recorded_files() {
    local record="$1"
    shift
    printf '%s\0' "$@" > "$TEST_DIR/expected-files-$record"
    cmp "$TEST_DIR/expected-files-$record" "$APR_FIXTURE_PROMPT_DIR/files-$record"
}

# Real execution now consumes independent retained copies. Preserve the old
# selection/order/content contract and additionally bind actual NUL argv to
# snapshot role/basename, logical source identity and independently read bytes.
# Render/dry-run keep assert_recorded_files and their configured-path contract.
assert_recorded_snapshot_files() {
    local record="$1" actual source role bundle expected index=0
    shift
    local arguments=()
    while IFS= read -r -d '' actual; do arguments+=("$actual"); done < "$APR_FIXTURE_PROMPT_DIR/files-$record"
    [[ "${#arguments[@]}" -eq "$#" ]]
    for source in "$@"; do
        actual="${arguments[$index]}"
        role=readme
        if [[ "$index" -gt 0 ]]; then role=spec; [[ "$#" -ne 3 || "$index" -ne 1 ]] || role=implementation; fi
        [[ "$actual" == .apr/runs/default/*/inputs/"$role"/"${source##*/}" ]]
        bundle="${actual%/inputs/*}/inputs/bundle.json"
        expected=$(jq -r --arg role "$role" --arg source "$source" '.files[]|select(.role==$role and .source_path==$source)|.snapshot_path' "$bundle")
        [[ "$actual" == "${actual%/inputs/*}/$expected" && -f "$actual" && ! -L "$actual" ]]
        cmp "$source" "$actual"
        jq -e --arg role "$role" --arg hash "$(document_sha256_stdin < "$source")" --argjson bytes "$(wc -c < "$source" | tr -d ' ')" \
            'any(.files[];.role==$role and .sha256==$hash and .bytes==$bytes)' "$bundle"
        index=$((index+1))
    done
}

assert_recorded_document() {
    local record="$1" role="$2" path="$3" reason="$4" digest bytes
    digest=$(shasum -a 256 < "$path")
    digest="${digest%% *}"
    bytes=$(wc -c < "$path")
    bytes="${bytes//[[:space:]]/}"
    local prompt
    prompt=$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-$record")
    [[ "$prompt" == *"$role: path="*"; bytes=$bytes; sha256=$digest; reason=$reason"* ]]
}

@test "prompt binding: foreground sends exact selected files and observed byte metadata" {
    create_prompt_binding_fixture
    printf '\000\377A\r\n\n' > README.md
    capture_streams bash "$APR_SCRIPT" run 1 --include-impl --wait --no-retry --no-preflight
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    assert_recorded_snapshot_files 1 "$TEST_PROJECT/README.md" "$TEST_PROJECT/IMPL.md" "$TEST_PROJECT/SPEC.md"
    assert_recorded_document 1 readme README.md required
    assert_recorded_document 1 implementation IMPL.md optional
    assert_recorded_document 1 spec SPEC.md required
    local prompt
    prompt=$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")
    [[ "$prompt" == 'Observed local input metadata (not a sent attachment receipt):'* ]]
    [[ "$prompt" == *'bytes=6; sha256=c2d6098cbf68842ad602337645fae2e17f40f4282f66c573cf5945274971cab9'* ]]
    # The default prompt names the files Oracle appends, in the order they are sent.
    [[ "$prompt" == *'1. The README ("README.md"). Read it first.'* ]]
    [[ "$prompt" == *'2. A document detailing the implementation ("IMPL.md").'* ]]
    [[ "$prompt" == *'3. The plan (specification) to review ("SPEC.md").'* && "$prompt" != *'will be included by oracle'* ]]
    [[ -s .apr/rounds/default/round_1.md ]]
}

@test "prompt binding: robot completes once with clean JSON and omitted implementation metadata" {
    create_prompt_binding_fixture
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.status' completed
    assert_json_value "$CAPTURED_STDOUT" '.data.include_impl' false
    assert_recorded_snapshot_files 1 "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    assert_recorded_document 1 readme README.md required
    assert_recorded_document 1 spec SPEC.md required
    [[ "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")" == *'skipped=not_requested; reason=optional'* ]]
    [[ "$CAPTURED_STDOUT" != *'Observed local'* && -s .apr/rounds/default/round_1.md ]]
}

@test "prompt binding: cadence selects implementation for render robot validate and robot run" {
    create_prompt_binding_fixture
    printf '\n  impl_every_n: 4\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 4 --render
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDOUT" == 'Offline notification capability preview.' ]]
    assert_recorded_files 1 "$TEST_PROJECT/README.md" "$TEST_PROJECT/IMPL.md" "$TEST_PROJECT/SPEC.md"
    assert_recorded_document 1 implementation IMPL.md impl_every_n
    capture_streams bash "$APR_SCRIPT" robot validate 4 --compact
    [[ "$CAPTURED_STATUS" -eq 0 && ! -e "$APR_FIXTURE_COUNT" ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.valid' true
    capture_streams bash "$APR_SCRIPT" robot run 4 --compact
    [[ "$CAPTURED_STATUS" -eq 0 && "$(cat "$APR_FIXTURE_COUNT")" -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.include_impl' true
    assert_recorded_snapshot_files 2 "$TEST_PROJECT/README.md" "$TEST_PROJECT/IMPL.md" "$TEST_PROJECT/SPEC.md"
    cmp "$APR_FIXTURE_PROMPT_DIR/prompt-1" "$APR_FIXTURE_PROMPT_DIR/prompt-2"
}

@test "prompt binding: missing optional implementation retains request reason with two actual files" {
    create_prompt_binding_fixture
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/missing.md"
    printf '\n  impl_every_n: 4\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 4 --render
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_recorded_files 1 "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
    [[ "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")" == *'skipped=missing_optional; reason=impl_every_n'* ]]
    capture_streams bash "$APR_SCRIPT" robot run 4 --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.include_impl' false
    cmp "$APR_FIXTURE_PROMPT_DIR/prompt-1" "$APR_FIXTURE_PROMPT_DIR/prompt-2"
}

@test "prompt binding: dry run displays exactly the later render prompt and launches no review" {
    create_prompt_binding_fixture
    printf '\ntemplate: |\n  Keep this custom instruction verbatim.\n  Preserve useful work.\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 1 --dry-run
    [[ "$CAPTURED_STATUS" -eq 0 && -z "$CAPTURED_STDOUT" && ! -e "$APR_FIXTURE_COUNT" && ! -e "$APR_FIXTURE_PROMPT_DIR/count" ]]
    printf '%s\n' "$CAPTURED_STDERR" | awk '/^--- END ASSEMBLED PROMPT ---$/ {copy=0} copy {print} /^--- BEGIN ASSEMBLED PROMPT ---$/ {copy=1}' > "$TEST_DIR/dry-prompt"
    local dry_prompt
    dry_prompt=$(cat "$TEST_DIR/dry-prompt")
    [[ "$dry_prompt" == 'Observed local input metadata'* && "$dry_prompt" == *$'---\n\nKeep this custom instruction verbatim.\nPreserve useful work.' ]]
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDOUT" == 'Offline notification capability preview.' ]]
    [[ "$dry_prompt" == "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")" ]]
    assert_recorded_files 1 "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
}

@test "prompt binding: quoted curly filenames survive exact argv and strict final QC" {
    create_prompt_binding_fixture
    local name='the {{README}} "quoted".md'
    cp README.md "$name"
    write_workflow_config "$TEST_PROJECT/$name" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/IMPL.md"
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_recorded_files 1 "$TEST_PROJECT/$name" "$TEST_PROJECT/SPEC.md"
    local prompt line encoded_path
    prompt=$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")
    line=$(awk '/^readme: / {print}' <<< "$prompt")
    encoded_path="${line#readme: path=}"
    encoded_path="${encoded_path%%; basename=*}"
    [[ "$(jq -r . <<< "$encoded_path")" == "$name" ]]
    [[ "$prompt" != *'{{'* && "$prompt" != *'}}'* && "$prompt" == *'\u007b\u007bREADME\u007d\u007d'* ]]
    prompt_quality_check "$prompt" .apr/workflows/default.yaml assembled
}

@test "prompt binding: changed document content changes real render metadata without changing its template" {
    create_prompt_binding_fixture
    printf '\ntemplate: |\n  Keep this exact template.\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_recorded_document 1 spec SPEC.md required
    printf '\nUseful accretive specification.\n' >> SPEC.md
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_recorded_document 2 spec SPEC.md required
    [[ "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-1")" != "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-2")" ]]
    [[ "$(cat "$APR_FIXTURE_PROMPT_DIR/prompt-2")" == *$'---\n\nKeep this exact template.' ]]
    assert_recorded_files 2 "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md"
}

@test "prompt binding: public unreadable required input fails before render or output creation" {
    create_prompt_binding_fixture
    chmod 000 SPEC.md
    [[ ! -r SPEC.md ]]
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Cannot read document metadata'* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" && ! -d .apr/logs && ! -d .apr/.locks ]]
}

@test "prompt binding: missing configured README retains normal public preflight diagnostic" {
    create_prompt_binding_fixture
    write_workflow_config "$TEST_PROJECT/absent-README.md" "$TEST_PROJECT/SPEC.md"
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-retry
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *"README not found: $TEST_PROJECT/absent-README.md"* && "$CAPTURED_STDERR" == *APR_ERROR_CODE=config_error* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: requested directory implementation fails robot config instead of silently skipping" {
    create_prompt_binding_fixture
    mkdir implementation-directory
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/implementation-directory"
    capture_streams bash "$APR_SCRIPT" robot run 1 --include-impl --compact
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    assert_json_value "$CAPTURED_STDOUT" '.code' config_error
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" && ! -d .apr/.locks ]]
}

@test "prompt binding: robot validate rejects unsearchable requested parent with useful stderr" {
    create_prompt_binding_fixture
    mkdir sealed
    cp IMPL.md sealed/IMPL.md
    write_workflow_config "$TEST_PROJECT/README.md" "$TEST_PROJECT/SPEC.md" "$TEST_PROJECT/sealed/IMPL.md"
    chmod 000 sealed
    [[ ! -x sealed && ! -e sealed/IMPL.md ]]
    capture_streams bash "$APR_SCRIPT" robot validate 1 --include-impl --compact
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'Cannot search optional document parent'* ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.valid' false
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: robot validate still checks the unselected template variant" {
    create_prompt_binding_fixture
    printf '\ntemplate: |\n  Read the actual attached documents.\ntemplate_with_impl: |\n  {{IMPLEMENTATION}}\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" robot validate 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$(jq -r '.data.errors[]' <<< "$CAPTURED_STDOUT")" == *'(template_with_impl)'* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: large early unresolved template fails public final QC with zero producer launches" {
    create_prompt_binding_fixture
    printf '\ntemplate: |\n  {{README}}\n  ' >> .apr/workflows/default.yaml
    printf '%98304s\n' '' | tr ' ' x >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'Prompt contains unexpanded placeholders'* && "$CAPTURED_STDERR" == *APR_ERROR_CODE=validation_failed* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: large placeholder predicate rejects both tokens without SIGPIPE and retains large clean control" {
    local padding prompt
    padding=$(printf '%98304s' '' | tr ' ' x)
    capture_streams prompt_quality_check "{{README}}$padding" '' large
    [[ "$CAPTURED_STATUS" -eq 1 && "$PROMPT_QC_REASON" == *'unexpanded placeholders'* ]]
    capture_streams prompt_quality_check "}}$padding" '' large
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    capture_streams prompt_quality_check "$padding" '' large
    [[ "$CAPTURED_STATUS" -eq 0 && -z "$PROMPT_QC_REASON" ]]
    prompt=$(printf '{{README}}\n%.0s' {1..128})
    capture_streams prompt_quality_check "$prompt" '' multiline
    [[ "$CAPTURED_STATUS" -eq 1 && "$(awk '/^  multiline:/ {n++} END {print n}' <<< "$PROMPT_QC_DETAILS")" -eq 8 ]]
}

@test "prompt binding: robot validate propagates builder failure instead of empty green success" {
    create_prompt_binding_fixture
    build_revision_prompt() { printf '%s\n' 'fixture: assembly failed' >&2; return 4; }
    capture_streams robot_validate 1
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'fixture: assembly failed'* ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.valid' false
    [[ "$(jq -r '.data.errors[]' <<< "$CAPTURED_STDOUT")" == *'Cannot assemble selected prompt'* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: metadata collector failure rejects validate without swallowing diagnostic" {
    create_prompt_binding_fixture
    wc() { cat >/dev/null; printf '%s\n' 'fixture: count failed' >&2; return 9; }
    capture_streams robot_validate 1
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'fixture: count failed'* ]]
    assert_json_value "$CAPTURED_STDOUT" '.data.valid' false
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: final QC rejects injected generated metadata before human execution" {
    create_prompt_binding_fixture
    DRY_RUN=true
    [[ "$DRY_RUN" == true ]]
    build_document_manifest() { printf '%s\n' '{"v":1,"files":[{"role":"readme","path":"README.md","basename":"README.md","bytes":1,"sha256":"{{BAD}}","included":true,"reason":"required"},{"role":"spec","path":"SPEC.md","basename":"SPEC.md","bytes":1,"sha256":"ok","included":true,"reason":"required"},{"role":"implementation","path":"IMPL.md","basename":"IMPL.md","included":false,"reason":"optional","skip_reason":"not_requested"}]}'; }
    capture_streams run_round 1
    [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'Prompt contains unexpanded placeholders'* && "$CAPTURED_STDERR" == *APR_ERROR_CODE=validation_failed* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}

@test "prompt binding: real unreadable template configuration fails instead of using a default" {
    create_prompt_binding_fixture
    printf '\ntemplate: |\n  Keep this custom template.\n' >> .apr/workflows/default.yaml
    capture_streams load_prompt_template false .apr/workflows/default.yaml
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDOUT" == 'Keep this custom template.' ]]
    chmod 000 .apr/workflows/default.yaml
    [[ ! -r .apr/workflows/default.yaml ]]
    capture_streams load_prompt_template false .apr/workflows/default.yaml
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'Cannot read prompt template configuration'* ]]
    capture_streams load_prompt_template true .apr/workflows/default.yaml
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" ]]
}

@test "prompt binding: real failed template reader process rejects public render without fallback" {
    create_prompt_binding_fixture
    mkdir -p "$TEST_DIR/reader-bin"
    cat > "$TEST_DIR/reader-bin/awk" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -v && "${2:-}" == key=template* ]]; then
    printf '%s\n' 'fixture: template reader process failed' >&2
    exit 9
fi
exec /usr/bin/awk "$@"
EOF
    chmod +x "$TEST_DIR/reader-bin/awk"
    export PATH="$TEST_DIR/reader-bin:$PATH"
    capture_streams bash "$APR_SCRIPT" run 1 --render
    [[ "$CAPTURED_STATUS" -eq 4 && -z "$CAPTURED_STDOUT" && "$CAPTURED_STDERR" == *'fixture: template reader process failed'* ]]
    [[ ! -e "$APR_FIXTURE_PROMPT_DIR/count" && ! -e "$APR_FIXTURE_COUNT" ]]
}
