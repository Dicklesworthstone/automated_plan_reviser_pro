#!/usr/bin/env bats
# test_robot.bats - Unit tests for APR robot mode JSON functions
#
# Tests:
#   - robot_json() formatting + compact mode
#   - robot_status() configured/unconfigured
#   - robot_workflows() listing + not_configured error
#   - robot_init() creates config structure
#   - robot_validate() success + validation_failed
#   - robot_history() not_found error
#   - robot_run() invalid argument error
#   - robot_stats() missing metrics error

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"

    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available"
    fi
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# robot_json() Tests
# =============================================================================

@test "robot_json: emits valid JSON with hint and meta (stdout only)" {
    ROBOT_COMPACT=false

    capture_streams robot_json true "ok" '{"value":1}' "Test hint"

    assert_stdout_only
    assert_valid_json "$CAPTURED_STDOUT"
    assert_json_value "$CAPTURED_STDOUT" ".ok" "true"
    assert_json_value "$CAPTURED_STDOUT" ".code" "ok"
    assert_json_value "$CAPTURED_STDOUT" ".data.value" "1"
    assert_json_value "$CAPTURED_STDOUT" ".hint" "Test hint"
    assert_json_field_exists "$CAPTURED_STDOUT" ".meta.v"
    assert_json_field_exists "$CAPTURED_STDOUT" ".meta.ts"
}

@test "robot_json: omits hint when not provided" {
    ROBOT_COMPACT=false

    capture_streams robot_json true "ok" '{"value":2}'

    assert_stdout_only
    assert_valid_json "$CAPTURED_STDOUT"

    local has_hint
    has_hint=$(echo "$CAPTURED_STDOUT" | jq -r 'has("hint")')
    [[ "$has_hint" == "false" ]]
}

@test "robot_json: compact mode produces minified output" {
    ROBOT_COMPACT=true

    run robot_json true "ok" '{"value":3}'

    assert_success
    assert_valid_json "$output"

    local compact
    compact=$(echo "$output" | jq -c .)
    [[ "$output" == "$compact" ]]
}

# =============================================================================
# robot_status() Tests
# =============================================================================

@test "robot_status: reports unconfigured project with hint" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    run robot_status

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.configured" "false"

    local has_hint
    has_hint=$(echo "$output" | jq -r 'has("hint")')
    [[ "$has_hint" == "true" ]]
}

@test "robot_status: reports configured project with workflow list" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    setup_mock_oracle
    setup_test_workflow "alpha"
    WORKFLOW="alpha"

    run robot_status

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.configured" "true"
    assert_json_value "$output" ".data.default_workflow" "alpha"
    assert_json_value "$output" ".data.workflow_count" "1"
    echo "$output" | jq -e '.data.workflows | index("alpha")' > /dev/null
}

# =============================================================================
# robot_workflows() Tests
# =============================================================================

@test "robot_workflows: returns not_configured when missing .apr" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    run robot_workflows

    assert_failure
    assert_robot_error "$output" "not_configured"
}

@test "robot_workflows: lists workflow names and descriptions" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    setup_test_workflow "beta"

    run robot_workflows

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.workflows[0].name" "beta"
    assert_json_value "$output" ".data.workflows[0].description" "Test workflow for beta"
}

# =============================================================================
# robot_help() Tests
# =============================================================================

@test "robot_help: returns commands and options" {
    ROBOT_COMPACT=true

    run robot_help

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.commands.status" "System overview (config, workflows, oracle)"
    assert_json_value "$output" ".data.options[\"-w, --workflow NAME\"]" "Workflow name (default: from config)"
}

# =============================================================================
# robot_init() Tests
# =============================================================================

@test "robot_init: creates config directory and config file" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    run robot_init

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.created" "true"
    assert_dir_exists "$TEST_PROJECT/.apr"
    assert_file_exists "$TEST_PROJECT/.apr/config.yaml"
}

# =============================================================================
# robot_validate() Tests
# =============================================================================

@test "robot_validate: returns validation_failed when missing config" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    run robot_validate

    assert_failure
    assert_robot_error "$output" "validation_failed"
    assert_json_value "$output" ".data.valid" "false"
}

@test "robot_validate: returns ok for valid workflow and round" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    setup_mock_oracle
    setup_test_workflow "gamma"
    WORKFLOW="gamma"

    run robot_validate 1

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.valid" "true"
}

# =============================================================================
# robot_history() and robot_run() error paths
# =============================================================================

@test "robot_history: returns not_found when rounds directory missing" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1
    WORKFLOW="default"

    run robot_history

    assert_failure
    assert_robot_error "$output" "not_found"
}

@test "robot_history: returns sorted rounds when present" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1
    WORKFLOW="default"

    mkdir -p ".apr/rounds/$WORKFLOW"
    echo "Round 2" > ".apr/rounds/$WORKFLOW/round_2.md"
    echo "Round 1" > ".apr/rounds/$WORKFLOW/round_1.md"

    run robot_history

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.count" "2"
    assert_json_value "$output" ".data.rounds[0].round" "1"
    assert_json_value "$output" ".data.rounds[1].round" "2"
}

@test "robot_run: returns invalid_argument for non-numeric round" {
    ROBOT_COMPACT=true

    run robot_run "abc"

    assert_failure
    assert_robot_error "$output" "invalid_argument"
}

@test "robot_run: starts oracle process in background" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1

    setup_mock_oracle
    setup_test_workflow "delta"
    WORKFLOW="delta"

    run robot_run 1

    assert_success
    assert_robot_success "$output"
    assert_json_value "$output" ".data.status" "running"
    # PID should be an integer
    echo "$output" | jq -e '.data.pid | type == "number"' > /dev/null
}

# =============================================================================
# robot_stats() error path
# =============================================================================

@test "robot_stats: returns not_found when metrics missing" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1
    WORKFLOW="default"

    run robot_stats

    assert_failure
    assert_robot_error "$output" "not_found"
}

@test "robot_diff: compares rounds with correct direction" {
    ROBOT_COMPACT=true
    cd "$TEST_PROJECT" || return 1
    
    # Setup workflow and rounds
    WORKFLOW="diff_test"
    mkdir -p ".apr/workflows" ".apr/rounds/$WORKFLOW"
    echo "name: $WORKFLOW" > ".apr/workflows/$WORKFLOW.yaml"
    
    echo "A" > ".apr/rounds/$WORKFLOW/round_3.md"
    echo "B" > ".apr/rounds/$WORKFLOW/round_5.md"
    
    # Run robot_diff 3 5
    run robot_diff "3" "5"
    
    assert_success
    assert_robot_success "$output"
    
    # Check JSON structure matches Old -> New
    assert_json_value "$output" ".data.comparing.from" "3"
    assert_json_value "$output" ".data.comparing.to" "5"
}
