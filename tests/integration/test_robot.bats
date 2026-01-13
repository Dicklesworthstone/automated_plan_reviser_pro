#!/usr/bin/env bats
# test_robot.bats - Integration tests for APR robot mode commands
#
# Tests: robot status, init, workflows, validate, run, history, stats, help

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
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Robot Status / Init
# =============================================================================

@test "apr robot status: unconfigured project" {
    run "$APR_SCRIPT" robot status

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.configured" "false"
}

@test "apr robot init: creates .apr structure" {
    run "$APR_SCRIPT" robot init

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_dir_exists ".apr"
    assert_file_exists ".apr/config.yaml"
}

# =============================================================================
# Robot Workflows / Validate
# =============================================================================

@test "apr robot workflows: lists configured workflows" {
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot workflows

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.workflows[0].name" "robot"
}

@test "apr robot validate: ok for valid workflow and round" {
    setup_mock_oracle
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot validate 1 -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.valid" "true"
}

@test "apr robot validate: error when missing round" {
    run "$APR_SCRIPT" robot validate

    log_test_output "$output"

    assert_failure
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "validation_failed"
}

# =============================================================================
# Robot Run / History / Stats
# =============================================================================

@test "apr robot run: returns session JSON" {
    setup_mock_oracle
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot run 1 -w robot

    log_test_output "$output"

    assert_success
    # Extract JSON from output - the robot output is pretty-printed JSON
    # Filter out non-JSON lines (Mock Oracle debug output goes to stderr but BATS captures both)
    local json_output
    # Use sed to extract from first { to matching } (the JSON block)
    json_output=$(echo "$output" | sed -n '/^{$/,/^}$/p')
    if [[ -z "$json_output" ]]; then
        # Fallback: try to find compact JSON on a single line
        json_output=$(echo "$output" | grep -E '^\{.*\}$' | head -1)
    fi
    assert_valid_json "$json_output"
    assert_json_value "$json_output" ".ok" "true"
    assert_json_value "$json_output" ".data.workflow" "robot"
    assert_json_value "$json_output" ".data.round" "1"
}

@test "apr robot run: rejects concurrent run for same round" {
    setup_mock_oracle
    setup_test_workflow "robot"

    export MOCK_ORACLE_SLEEP=3

    capture_streams "$APR_SCRIPT" robot run 1 -w robot --compact
    log_test_actual "first stdout" "$CAPTURED_STDOUT"
    log_test_actual "first stderr" "$CAPTURED_STDERR"
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"

    capture_streams "$APR_SCRIPT" robot run 1 -w robot --compact
    log_test_actual "second stdout" "$CAPTURED_STDOUT"
    log_test_actual "second stderr" "$CAPTURED_STDERR"
    [[ "$CAPTURED_STATUS" -ne 0 ]]
    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "false"
    assert_json_value "$CAPTURED_STDOUT" ".code" "already_exists"
}

@test "apr robot history: returns rounds list" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot"

    run "$APR_SCRIPT" robot history -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.count" "1"
    assert_json_value "$output" ".data.rounds[0].round" "1"
}

@test "apr robot stats: returns not_found when metrics missing" {
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot stats -w robot

    log_test_output "$output"

    assert_failure
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "not_found"
}

# =============================================================================
# Robot Show
# =============================================================================

@test "apr robot show: returns round content" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "# Round 1 Content\n\nThis is test content."

    run "$APR_SCRIPT" robot show 1 -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.round" "1"
    [[ "$output" == *"Round 1 Content"* ]]
}

@test "apr robot show: returns metadata" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "Hello World"

    run "$APR_SCRIPT" robot show 1 -w robot

    log_test_output "$output"

    assert_success
    # Should have stats
    echo "$output" | jq -e '.data.stats.chars' >/dev/null
    echo "$output" | jq -e '.data.stats.lines' >/dev/null
    echo "$output" | jq -e '.data.path' >/dev/null
}

@test "apr robot show: returns not_found for missing round" {
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot show 99 -w robot

    log_test_output "$output"

    assert_failure
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "not_found"
}

# =============================================================================
# Robot Diff
# =============================================================================

@test "apr robot diff: compares two rounds" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "Line 1\nLine 2"
    create_mock_round 2 "robot" "Line 1\nLine 2\nLine 3"

    run "$APR_SCRIPT" robot diff 2 -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.comparing.from" "1"
    assert_json_value "$output" ".data.comparing.to" "2"
}

@test "apr robot diff: returns change stats" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "Original content"
    create_mock_round 2 "robot" "Changed content\nNew line"

    run "$APR_SCRIPT" robot diff 2 -w robot

    log_test_output "$output"

    assert_success
    # Should have stats
    echo "$output" | jq -e '.data.stats.before' >/dev/null
    echo "$output" | jq -e '.data.stats.after' >/dev/null
    echo "$output" | jq -e '.data.stats.changes' >/dev/null
}

@test "apr robot diff: explicit round comparison" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot"
    create_mock_round 2 "robot"
    create_mock_round 3 "robot"

    run "$APR_SCRIPT" robot diff 3 1 -w robot

    log_test_output "$output"

    assert_success
    assert_json_value "$output" ".data.comparing.from" "1"
    assert_json_value "$output" ".data.comparing.to" "3"
}

@test "apr robot diff: fails for round 1 without comparison" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot"

    run "$APR_SCRIPT" robot diff 1 -w robot

    log_test_output "$output"

    assert_failure
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "invalid_argument"
}

# =============================================================================
# Robot Integrate
# =============================================================================

@test "apr robot integrate: returns integration prompt" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "# GPT Feedback\n\n- Suggestion 1\n- Suggestion 2"

    run "$APR_SCRIPT" robot integrate 1 -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.round" "1"
    # Should have prompt content
    echo "$output" | jq -e '.data.prompt' >/dev/null
}

@test "apr robot integrate: prompt includes spec path" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot"

    run "$APR_SCRIPT" robot integrate 1 -w robot

    log_test_output "$output"

    assert_success
    assert_json_value "$output" ".data.spec_path" "SPECIFICATION.md"
    [[ "$output" == *"specification"* ]] || [[ "$output" == *"SPECIFICATION.md"* ]]
}

@test "apr robot integrate: returns stats" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot" "Some content here"

    run "$APR_SCRIPT" robot integrate 1 -w robot

    log_test_output "$output"

    assert_success
    # Should have size stats
    echo "$output" | jq -e '.data.stats.round_chars' >/dev/null
    echo "$output" | jq -e '.data.stats.prompt_chars' >/dev/null
}

@test "apr robot integrate: fails for missing round" {
    setup_test_workflow "robot"

    run "$APR_SCRIPT" robot integrate 99 -w robot

    log_test_output "$output"

    assert_failure
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "not_found"
}

# =============================================================================
# Robot Stats with Data
# =============================================================================

@test "apr robot stats: returns metrics when available" {
    setup_test_workflow "robot"
    create_mock_round 1 "robot"
    create_mock_round 2 "robot"

    # Run backfill with run to handle any exit code
    run "$APR_SCRIPT" backfill -w robot
    log_test_output "$output"
    assert_success

    run "$APR_SCRIPT" robot stats -w robot

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    # Should have round data
    echo "$output" | jq -e '.data.round_count' >/dev/null
}

# =============================================================================
# Robot Help
# =============================================================================

@test "apr robot help: returns command list" {
    run "$APR_SCRIPT" robot help

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.commands.status" "System overview (config, workflows, oracle)"
}

@test "apr robot help: includes new commands" {
    run "$APR_SCRIPT" robot help

    log_test_output "$output"

    assert_success
    # Should include show, diff, integrate
    [[ "$output" == *"show"* ]]
    [[ "$output" == *"diff"* ]]
    [[ "$output" == *"integrate"* ]]
}
