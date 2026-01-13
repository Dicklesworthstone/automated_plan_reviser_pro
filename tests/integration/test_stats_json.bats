#!/usr/bin/env bats
# test_stats_json.bats - Integration tests for stats JSON output
#
# Tests: apr stats --json and --export json

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi

    cd "$TEST_PROJECT"
    setup_test_workflow "default"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Tests
# =============================================================================

@test "apr stats --json: outputs empty object when metrics missing" {
    capture_streams "$APR_SCRIPT" stats --json

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    assert_valid_json "$CAPTURED_STDOUT"
    # Empty JSON object
    [[ "$(echo "$CAPTURED_STDOUT" | jq -r 'keys | length')" -eq 0 ]]
}

@test "apr stats --export json: outputs metrics JSON" {
    # Initialize metrics (--export requires metrics to exist)
    setup_test_metrics "default"

    run "$APR_SCRIPT" stats --export json

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_field_exists "$output" ".schema_version"
    assert_json_field_exists "$output" ".rounds"
}
