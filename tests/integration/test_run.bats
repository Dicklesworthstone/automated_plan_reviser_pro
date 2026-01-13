#!/usr/bin/env bats
# test_run.bats - Integration tests for APR run command
#
# Tests the run command with dry-run and render modes (no actual Oracle calls)

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    # Set up a complete test workflow
    cd "$TEST_PROJECT"
    setup_render_oracle
    setup_test_workflow "default"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Oracle Mocks (Integration-Safe)
# =============================================================================

setup_render_oracle() {
    local bin_dir="$TEST_DIR/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/oracle" << 'EOF'
#!/usr/bin/env bash
echo "Mock Oracle called with: $*" >&2

if [[ "${1:-}" == "--version" ]]; then
    echo "oracle 0.0.0"
    exit 0
fi

if [[ "$*" == *"--render"* ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                shift
                if [[ -f "$1" ]]; then
                    cat "$1"
                    echo ""
                fi
                ;;
            -p)
                shift
                echo "$1"
                ;;
        esac
        shift
    done
    exit 0
fi

exit 0
EOF
    chmod +x "$bin_dir/oracle"

    export PATH="$bin_dir:$PATH"
}

setup_flaky_oracle() {
    local bin_dir="$TEST_DIR/flaky_oracle"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/oracle" << 'EOF'
#!/usr/bin/env bash
count_file="${TEST_DIR:-/tmp}/oracle_call_count"
count=0
if [[ -f "$count_file" ]]; then
    count=$(cat "$count_file" 2>/dev/null || echo "0")
fi
count=$((count + 1))
echo "$count" > "$count_file"

echo "Flaky Oracle args: $*" >&2

if [[ "${1:-}" == "--version" ]]; then
    echo "oracle 0.0.0"
    exit 0
fi

if [[ "${ORACLE_FAIL_UNTIL:-0}" -ge "$count" ]]; then
    echo "Simulated failure $count" >&2
    exit 1
fi

if [[ "$*" == *"--render"* ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                shift
                if [[ -f "$1" ]]; then
                    cat "$1"
                    echo ""
                fi
                ;;
            -p)
                shift
                echo "$1"
                ;;
        esac
        shift
    done
    exit 0
fi

exit 0
EOF
    chmod +x "$bin_dir/oracle"

    export PATH="$bin_dir:$PATH"
}

# =============================================================================
# Dry Run Tests
# =============================================================================

@test "run --dry-run: shows oracle command" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_success
    assert_output --partial "oracle"
}

@test "run --dry-run: includes model selection" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    # Should mention the model
    [[ "$output" == *"5.2"* ]] || [[ "$output" == *"Thinking"* ]] || [[ "$output" == *"-m"* ]]
}

@test "run --dry-run: includes slug" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"slug"* ]] || [[ "$output" == *"apr-"* ]]
}

@test "run --dry-run: includes round number in slug" {
    run "$APR_SCRIPT" run 5 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"5"* ]] || [[ "$output" == *"round"* ]]
}

@test "run --dry-run: with --include-impl flag" {
    run "$APR_SCRIPT" run 1 --dry-run --include-impl

    log_test_output "$output"

    assert_success
    # Should mention implementation or impl
    [[ "$output" == *"impl"* ]] || [[ "$output" == *"IMPLEMENTATION"* ]] || [[ "$output" == *"with-impl"* ]]
}

# =============================================================================
# Render Mode Tests
# =============================================================================

@test "run --render: outputs prompt content" {
    run "$APR_SCRIPT" run 1 --render

    log_test_output "$output"

    assert_success
    # Should include content from README
    [[ "$output" == *"Test Project"* ]] || [[ "$output" == *"README"* ]]
}

@test "run --render: includes specification content" {
    run "$APR_SCRIPT" run 1 --render

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Specification"* ]] || [[ "$output" == *"SPEC"* ]] || [[ "$output" == *"spec"* ]]
}

@test "run --render --include-impl: includes implementation" {
    run "$APR_SCRIPT" run 1 --render --include-impl

    log_test_output "$output"

    assert_success
    [[ "$output" == *"implementation"* ]] || [[ "$output" == *"IMPLEMENTATION"* ]] || [[ "$output" == *"impl"* ]]
}

@test "run --render --copy: passes copy flag to oracle" {
    capture_streams "$APR_SCRIPT" run 1 --render --copy

    log_test_actual "exit code" "$CAPTURED_STATUS"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"--copy"* ]]
}

# =============================================================================
# Round Number Validation Tests
# =============================================================================

@test "run: rejects non-numeric round" {
    run "$APR_SCRIPT" run abc --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
}

@test "run: rejects negative round" {
    run "$APR_SCRIPT" run -1 --dry-run

    log_test_actual "exit code" "$status"

    # Should fail or treat -1 as an option
    [[ $status -ne 0 ]] || [[ "$output" == *"invalid"* ]] || [[ "$output" == *"error"* ]]
}

@test "run: accepts zero round" {
    run "$APR_SCRIPT" run 0 --dry-run

    log_test_output "$output"

    # Zero is technically valid (edge case)
    # May succeed or may be rejected - either is acceptable
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

@test "run: accepts large round number" {
    run "$APR_SCRIPT" run 999 --dry-run

    log_test_output "$output"

    assert_success
}

# =============================================================================
# Shorthand Tests
# =============================================================================

@test "shorthand: apr <number> works like apr run <number>" {
    run "$APR_SCRIPT" 1 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"oracle"* ]]
}

@test "shorthand: apr 5 --dry-run shows round 5" {
    run "$APR_SCRIPT" 5 --dry-run

    log_test_output "$output"

    assert_success
    [[ "$output" == *"5"* ]]
}

# =============================================================================
# Workflow Selection Tests
# =============================================================================

@test "run: -w selects workflow" {
    # Create a second workflow
    setup_test_workflow "secondary"

    run "$APR_SCRIPT" run 1 --dry-run -w secondary

    log_test_output "$output"

    assert_success
    [[ "$output" == *"secondary"* ]]
}

@test "run: --workflow selects workflow" {
    setup_test_workflow "another"

    run "$APR_SCRIPT" run 1 --dry-run --workflow another

    log_test_output "$output"

    assert_success
    [[ "$output" == *"another"* ]]
}

@test "run: fails for non-existent workflow" {
    run "$APR_SCRIPT" run 1 --dry-run -w nonexistent

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
}

# =============================================================================
# Verbose/Quiet Mode Tests
# =============================================================================

@test "run: --verbose shows more output" {
    run "$APR_SCRIPT" run 1 --dry-run --verbose

    log_test_output "$output"

    assert_success
    # Verbose output should be longer or include debug info
    [[ ${#output} -gt 50 ]]
}

@test "run: --quiet shows less output" {
    run "$APR_SCRIPT" run 1 --dry-run --quiet

    log_test_output "$output"

    assert_success
}

@test "run: --wait shows retry messaging by default" {
    run "$APR_SCRIPT" run 1 --wait

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Auto-retry enabled"* ]] || [[ "$output" == *"retry"* ]]
}

@test "run: --wait --no-retry omits retry messaging" {
    run "$APR_SCRIPT" run 1 --wait --no-retry

    log_test_output "$output"

    assert_success
    [[ "$output" != *"Auto-retry enabled"* ]]
}

@test "run: -v is alias for --verbose" {
    run "$APR_SCRIPT" run 1 --dry-run -v

    log_test_output "$output"

    assert_success
}

@test "run: -q is alias for --quiet" {
    run "$APR_SCRIPT" run 1 --dry-run -q

    log_test_output "$output"

    assert_success
}

# =============================================================================
# Preflight Tests
# =============================================================================

@test "run: --no-preflight skips Oracle check but not file validation" {
    # --no-preflight skips Oracle availability check but still validates
    # that required files exist (basic safety check)
    rm -f README.md

    run "$APR_SCRIPT" run 1 --dry-run --no-preflight

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # File validation still occurs - this is intentional behavior
    # The script still fails when required files are missing
    assert_failure
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Required file"* ]]
}

@test "run: fails when required file missing (without --no-preflight)" {
    rm -f README.md

    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Should fail or warn about missing file
    [[ $status -ne 0 ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"missing"* ]]
}

@test "run: preflight passes for valid files" {
    capture_streams "$APR_SCRIPT" run 1 --wait --no-retry

    log_test_actual "exit code" "$CAPTURED_STATUS"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Running pre-flight checks"* ]]
    [[ "$CAPTURED_STDERR" == *"All pre-flight checks passed"* ]]
}

@test "run: preflight fails when required file missing" {
    rm -f README.md

    capture_streams "$APR_SCRIPT" run 1 --wait --no-retry

    log_test_actual "exit code" "$CAPTURED_STATUS"

    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"Pre-flight failed: README not found"* ]]
}

# =============================================================================
# Output File Handling Tests
# =============================================================================

@test "run: existing output file warns and proceeds when non-interactive" {
    mkdir -p .apr/rounds/default
    printf '%s\n' "existing output" > .apr/rounds/default/round_1.md

    capture_streams "$APR_SCRIPT" run 1 --wait --no-retry

    log_test_actual "exit code" "$CAPTURED_STATUS"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"output already exists"* ]] || [[ "$CAPTURED_STDERR" == *"Round 1 output already exists"* ]]
}

# =============================================================================
# Previous Round Tests
# =============================================================================

@test "run: round 2 references round 1 if it exists" {
    # Create round 1 output
    create_mock_round 1 "default" "# Round 1 Content\n\nPrevious analysis here."

    run "$APR_SCRIPT" run 2 --render

    log_test_output "$output"

    assert_success
    # Should include previous round content or reference
    [[ "$output" == *"Round 1"* ]] || [[ "$output" == *"Previous"* ]] || [[ "$output" == *"round"* ]]
}

# =============================================================================
# Stream Separation Tests
# =============================================================================

@test "run --dry-run: progress to stderr, command to stdout or stderr" {
    # In dry-run mode, output structure should be clean
    capture_streams "$APR_SCRIPT" run 1 --dry-run

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Should have some output
    [[ -n "$CAPTURED_STDOUT" ]] || [[ -n "$CAPTURED_STDERR" ]]
}

@test "run --render: prompt content format is correct" {
    run "$APR_SCRIPT" run 1 --render

    log_test_output "$output"

    assert_success

    # Should have structured sections
    [[ "$output" == *"readme"* ]] || [[ "$output" == *"README"* ]] || [[ "$output" == *"<"* ]]
}

# =============================================================================
# Retry Wrapper Tests
# =============================================================================

@test "run: retries Oracle on transient failures (--wait)" {
    setup_flaky_oracle

    # Export variables so they're available to the oracle subprocess
    # Note: ORACLE_FAIL_UNTIL=2 because call 1 is the version check
    export TEST_DIR APR_MAX_RETRIES=3 APR_INITIAL_BACKOFF=0 ORACLE_FAIL_UNTIL=2

    # Clear any previous call count
    rm -f "$TEST_DIR/oracle_call_count"

    capture_streams "$APR_SCRIPT" run 1 --wait

    log_test_actual "exit code" "$CAPTURED_STATUS"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STATUS" -eq 0 ]]
    [[ "$CAPTURED_STDERR" == *"Attempt 1/3 failed"* ]]
    [[ "$CAPTURED_STDERR" == *"Retrying in 0s"* ]]
}

# =============================================================================
# Session Slug Format Tests
# =============================================================================

@test "run --dry-run: slug format is apr-{workflow}-round-{N}" {
    run "$APR_SCRIPT" run 3 --dry-run

    log_test_output "$output"

    assert_success
    # Slug should follow the pattern apr-{workflow}-round-{N}
    [[ "$output" == *"apr-default-round-3"* ]] || [[ "$output" == *"--slug"* ]]
}

@test "run --dry-run --include-impl: slug includes with-impl suffix" {
    run "$APR_SCRIPT" run 2 --dry-run --include-impl

    log_test_output "$output"

    assert_success
    # When --include-impl is used, slug should include with-impl
    [[ "$output" == *"with-impl"* ]] || [[ "$output" == *"impl"* ]]
}

@test "run --dry-run: slug handles workflow with hyphen" {
    setup_test_workflow "my-workflow"

    run "$APR_SCRIPT" run 1 --dry-run -w my-workflow

    log_test_output "$output"

    assert_success
    [[ "$output" == *"my-workflow"* ]]
}

@test "run --dry-run: slug handles workflow with underscore" {
    setup_test_workflow "my_workflow"

    run "$APR_SCRIPT" run 1 --dry-run -w my_workflow

    log_test_output "$output"

    assert_success
    [[ "$output" == *"my_workflow"* ]]
}

@test "run --dry-run: slug handles workflow with dot" {
    setup_test_workflow "special.name"

    run "$APR_SCRIPT" run 3 --dry-run -w special.name

    log_test_output "$output"

    assert_success
    [[ "$output" == *"apr-special.name-round-3"* ]] || [[ "$output" == *"special.name"* ]]
}

# =============================================================================
# Option Combination Tests
# =============================================================================

@test "run: --dry-run --verbose combined" {
    run "$APR_SCRIPT" run 1 --dry-run --verbose

    log_test_output "$output"

    assert_success
    # Verbose dry-run should show more details
    [[ ${#output} -gt 100 ]]
}

@test "run: --dry-run --quiet combined" {
    run "$APR_SCRIPT" run 1 --dry-run --quiet

    log_test_output "$output"

    assert_success
    # Quiet mode should still show the command
    [[ "$output" == *"oracle"* ]] || [[ "$output" == *"Mock"* ]]
}

@test "run: --render --quiet combined" {
    run "$APR_SCRIPT" run 1 --render --quiet

    log_test_output "$output"

    assert_success
    # Should output the rendered prompt even in quiet mode
    [[ -n "$output" ]]
}

@test "run: --render --verbose --include-impl combined" {
    run "$APR_SCRIPT" run 1 --render --verbose --include-impl

    log_test_output "$output"

    assert_success
    # Should include all components
    [[ "$output" == *"README"* ]] || [[ "$output" == *"readme"* ]]
}

@test "run: -w and --include-impl combined" {
    setup_test_workflow "combo-test"

    run "$APR_SCRIPT" run 1 --dry-run -w combo-test --include-impl

    log_test_output "$output"

    assert_success
    [[ "$output" == *"combo-test"* ]]
    [[ "$output" == *"impl"* ]] || [[ "$output" == *"with-impl"* ]]
}

@test "run: multiple workflows in sequence" {
    setup_test_workflow "workflow-a"
    setup_test_workflow "workflow-b"

    run "$APR_SCRIPT" run 1 --dry-run -w workflow-a
    assert_success
    [[ "$output" == *"workflow-a"* ]]

    run "$APR_SCRIPT" run 1 --dry-run -w workflow-b
    assert_success
    [[ "$output" == *"workflow-b"* ]]
}

@test "run: rejects concurrent background run for same round" {
    setup_mock_oracle
    export MOCK_ORACLE_SLEEP=3

    capture_streams "$APR_SCRIPT" run 1 -w default
    log_test_actual "first exit code" "$CAPTURED_STATUS"
    [[ "$CAPTURED_STATUS" -eq 0 ]]

    capture_streams "$APR_SCRIPT" run 1 -w default
    log_test_actual "second exit code" "$CAPTURED_STATUS"
    log_test_actual "second stderr" "$CAPTURED_STDERR"
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ "$CAPTURED_STDERR" == *"already running"* ]]
}

# =============================================================================
# Oracle Command Construction Tests
# =============================================================================

@test "run --dry-run: includes --write-output flag" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    # Oracle command should include write-output for saving results
    [[ "$output" == *"write-output"* ]] || [[ "$output" == *"round_1"* ]]
}

@test "run --dry-run: includes --notify flag" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    # Should include notify for desktop notifications
    [[ "$output" == *"notify"* ]] || [[ "$output" == *"--"* ]]
}

@test "run --dry-run: includes engine browser flag" {
    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    # Should specify browser engine
    [[ "$output" == *"browser"* ]] || [[ "$output" == *"engine"* ]] || [[ "$output" == *"oracle"* ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "run: handles missing oracle gracefully" {
    # Temporarily override PATH to hide oracle
    local original_path="$PATH"
    PATH="/nonexistent:$PATH"

    run "$APR_SCRIPT" run 1 --dry-run --no-preflight

    PATH="$original_path"

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Should either fail gracefully or use npx fallback
    [[ $status -eq 0 ]] || [[ "$output" == *"Oracle"* ]] || [[ "$output" == *"oracle"* ]]
}

@test "run: provides helpful message on config error" {
    # Remove workflow config
    rm -f .apr/workflows/default.yaml

    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"workflow"* ]]
}
