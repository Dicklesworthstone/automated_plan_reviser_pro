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
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.workflow" "robot"
    assert_json_value "$output" ".data.round" "1"
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
