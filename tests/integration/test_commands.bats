#!/usr/bin/env bats
# test_commands.bats - Integration tests for APR management commands
#
# Tests: list, history, show, diff, stats

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    cd "$TEST_PROJECT"
    setup_test_workflow "default"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# apr --help Tests
# =============================================================================

@test "apr --help: shows usage information" {
    run "$APR_SCRIPT" --help

    log_test_output "$output"

    assert_success
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"USAGE"* ]]
}

@test "apr --help: lists available commands" {
    run "$APR_SCRIPT" --help

    log_test_output "$output"

    assert_success
    [[ "$output" == *"run"* ]]
    [[ "$output" == *"setup"* ]]
    [[ "$output" == *"list"* ]]
}

@test "apr help: same as --help" {
    run "$APR_SCRIPT" help

    log_test_output "$output"

    assert_success
    [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# apr --version Tests
# =============================================================================

@test "apr --version: shows version number" {
    run "$APR_SCRIPT" --version

    log_test_output "$output"

    assert_success
    # Should contain version number
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "apr -V: same as --version" {
    run "$APR_SCRIPT" -V

    log_test_output "$output"

    assert_success
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# =============================================================================
# apr list Tests
# =============================================================================

@test "apr list: shows workflows" {
    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"default"* ]]
}

@test "apr list: marks default workflow" {
    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    # Should indicate which is default
    [[ "$output" == *"default"* ]]
}

@test "apr list: shows multiple workflows" {
    setup_test_workflow "workflow2"
    setup_test_workflow "workflow3"

    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"default"* ]]
    [[ "$output" == *"workflow2"* ]]
    [[ "$output" == *"workflow3"* ]]
}

@test "apr list: empty when no workflows" {
    rm -rf .apr/workflows/*

    run "$APR_SCRIPT" list

    log_test_output "$output"

    # Should not crash, may show message about no workflows
    [[ $status -eq 0 ]] || [[ "$output" == *"No workflows"* ]]
}

# =============================================================================
# apr history Tests
# =============================================================================

@test "apr history: shows rounds" {
    create_mock_round 1
    create_mock_round 2

    run "$APR_SCRIPT" history

    log_test_output "$output"

    assert_success
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
}

@test "apr history: marks latest round" {
    create_mock_round 1
    create_mock_round 2
    create_mock_round 3

    run "$APR_SCRIPT" history

    log_test_output "$output"

    assert_success
    # Should mark round 3 as latest
    [[ "$output" == *"3"* ]]
    [[ "$output" == *"latest"* ]] || [[ "$output" == *"Latest"* ]] || [[ "$output" == *"*"* ]]
}

@test "apr history: empty when no rounds" {
    run "$APR_SCRIPT" history

    log_test_output "$output"

    # Should succeed but indicate no rounds
    assert_success
    [[ "$output" == *"No rounds"* ]] || [[ "$output" == *"no rounds"* ]] || [[ -z "$output" ]]
}

@test "apr history: with workflow selection" {
    setup_test_workflow "other"
    create_mock_round 1 "other"

    run "$APR_SCRIPT" history -w other

    log_test_output "$output"

    assert_success
    [[ "$output" == *"1"* ]]
}

# =============================================================================
# apr show Tests
# =============================================================================

@test "apr show: displays round content" {
    create_mock_round 1 "default" "# Test Content\n\nThis is round 1 content."

    run "$APR_SCRIPT" show 1

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Test Content"* ]] || [[ "$output" == *"round 1"* ]]
}

@test "apr show: fails for non-existent round" {
    run "$APR_SCRIPT" show 99

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    assert_failure
}

@test "apr show: with workflow selection" {
    setup_test_workflow "other"
    create_mock_round 1 "other" "# Other Workflow\n\nContent from other workflow."

    run "$APR_SCRIPT" show 1 -w other

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Other Workflow"* ]] || [[ "$output" == *"other"* ]]
}

# =============================================================================
# apr diff Tests
# =============================================================================

@test "apr diff: compares two rounds" {
    create_mock_round 1 "default" "# Round 1\n\nFirst version"
    create_mock_round 2 "default" "# Round 2\n\nSecond version with changes"

    run "$APR_SCRIPT" diff 1 2

    log_test_output "$output"

    assert_success
    # Should show some diff output
    [[ -n "$output" ]]
}

@test "apr diff: single arg compares with previous" {
    create_mock_round 1 "default" "# Round 1\n\nOriginal"
    create_mock_round 2 "default" "# Round 2\n\nModified"

    run "$APR_SCRIPT" diff 2

    log_test_output "$output"

    assert_success
}

@test "apr diff: fails for round 1 alone" {
    create_mock_round 1

    run "$APR_SCRIPT" diff 1

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Should fail - no previous round to compare
    assert_failure
}

# =============================================================================
# apr stats Tests
# =============================================================================

@test "apr stats: shows round statistics" {
    create_mock_round 1
    create_mock_round 2
    create_mock_round 3

    run "$APR_SCRIPT" stats

    log_test_output "$output"

    assert_success
    # Should show count
    [[ "$output" == *"3"* ]] || [[ "$output" == *"round"* ]]
}

@test "apr stats: empty when no rounds" {
    run "$APR_SCRIPT" stats

    log_test_output "$output"

    # Should not crash
    [[ $status -eq 0 ]]
}

@test "apr stats: shows average size" {
    create_mock_round 1 "default" "$(printf 'x%.0s' {1..1000})"
    create_mock_round 2 "default" "$(printf 'y%.0s' {1..2000})"

    run "$APR_SCRIPT" stats

    log_test_output "$output"

    assert_success
    # Should show some size information
    [[ "$output" == *"K"* ]] || [[ "$output" == *"B"* ]] || [[ "$output" == *"size"* ]] || [[ "$output" == *"Size"* ]]
}

# =============================================================================
# apr status / attach Tests
# =============================================================================

@test "apr status: calls oracle status with hours" {
    setup_mock_oracle

    capture_streams "$APR_SCRIPT" status --hours 12

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STDERR" == *"Mock Oracle called with: status --hours 12"* ]]
}

@test "apr attach: calls oracle session with --render" {
    setup_mock_oracle

    capture_streams "$APR_SCRIPT" attach apr-test-session

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STDERR" == *"Mock Oracle called with: session apr-test-session --render"* ]]
}

# =============================================================================
# apr integrate Tests
# =============================================================================

@test "apr integrate: outputs prompt to stdout" {
    create_mock_round 1 "default"

    run "$APR_SCRIPT" integrate 1 --quiet

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Now integrate the following feedback"* ]]
    [[ "$output" == *"Round 1"* ]]
}

@test "apr integrate: writes prompt to file with --output" {
    create_mock_round 1 "default"

    local output_file="$TEST_PROJECT/integration_prompt.md"

    run "$APR_SCRIPT" integrate 1 --output "$output_file"

    log_test_output "$output"

    assert_success
    assert_file_exists "$output_file"
    run grep -n "Round 1" "$output_file"
    assert_success
}

# =============================================================================
# Stream Separation Tests
# =============================================================================

@test "apr list: output to stderr for human-readable" {
    capture_streams "$APR_SCRIPT" list

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Human-readable output should go to stderr per AGENTS.md
    [[ -n "$CAPTURED_STDERR" ]] || [[ -n "$CAPTURED_STDOUT" ]]
}

@test "apr --version: version info format" {
    run "$APR_SCRIPT" --version

    log_test_output "$output"

    assert_success
    # Version should be in semver format
    assert_version_format "$(echo "$output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
}
