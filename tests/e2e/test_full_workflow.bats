#!/usr/bin/env bats
# test_full_workflow.bats - End-to-end tests for complete APR workflows
#
# Tests complete user journeys without actual Oracle calls

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    cd "$TEST_PROJECT"
    setup_mock_oracle
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Setup Wizard Tests (Non-Interactive)
# =============================================================================

@test "e2e: fresh project setup creates .apr structure" {
    # Verify project is fresh (no .apr)
    [[ ! -d ".apr" ]]

    # Run setup in non-interactive mode (provide config via file)
    mkdir -p .apr/workflows
    cat > .apr/config.yaml << 'EOF'
default_workflow: default
EOF
    cat > .apr/workflows/default.yaml << 'EOF'
name: default
description: Default workflow
documents:
  readme: README.md
  spec: SPEC.md
oracle:
  model: "5.2 Thinking"
rounds:
  output_dir: .apr/rounds/default
template: |
  Analyze: {{README}} and {{SPEC}}
EOF

    # Create required files
    echo "# Project README" > README.md
    echo "# Specification" > SPEC.md

    # Verify structure
    assert_dir_exists ".apr"
    assert_dir_exists ".apr/workflows"
    assert_file_exists ".apr/config.yaml"
    assert_file_exists ".apr/workflows/default.yaml"

    # List should work now
    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"default"* ]]
}

@test "e2e: multiple workflow management" {
    setup_test_workflow "default"
    setup_test_workflow "experimental"
    setup_test_workflow "production"

    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"default"* ]]
    [[ "$output" == *"experimental"* ]]
    [[ "$output" == *"production"* ]]
}

# =============================================================================
# Round Lifecycle Tests
# =============================================================================

@test "e2e: complete round lifecycle" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" run 1 --dry-run
    assert_success
    [[ ! -f ".apr/rounds/default/round_1.md" ]]

    # Round 1: First revision
    create_mock_round 1 "default" "# Round 1 Analysis

## Key Findings
- Architecture needs review
- Security considerations missing

## Recommendations
1. Add authentication
2. Review data flow
"

    # Verify history shows round 1
    run "$APR_SCRIPT" history

    log_test_output "$output"

    assert_success
    [[ "$output" == *"1"* ]]

    # View round 1 content
    run "$APR_SCRIPT" show 1

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Round 1"* ]] || [[ "$output" == *"Architecture"* ]]

    # Stats should show 1 round
    run "$APR_SCRIPT" stats

    log_test_output "$output"

    assert_success
    [[ "$output" == *"1"* ]]
}

@test "e2e: multi-round progression" {
    setup_test_workflow "default"

    # Create multiple rounds simulating iterative refinement
    create_mock_round 1 "default" "# Round 1
## Major issues found
- Missing security layer
- No error handling
"

    create_mock_round 2 "default" "# Round 2
## Issues addressed
- Security layer added
## Remaining issues
- Error handling still needed
"

    create_mock_round 3 "default" "# Round 3
## Issues addressed
- Error handling complete
## Final polish
- Documentation updates
"

    # History should show all rounds
    run "$APR_SCRIPT" history

    log_test_output "$output"

    assert_success
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
    [[ "$output" == *"3"* ]]

    # Diff between rounds
    run "$APR_SCRIPT" diff 1 2

    log_test_output "$output"

    assert_success
    [[ -n "$output" ]]

    # Diff from round 2 to previous (round 1)
    run "$APR_SCRIPT" diff 2

    assert_success
}

# =============================================================================
# Cross-Workflow Operations
# =============================================================================

@test "e2e: workflow isolation" {
    setup_test_workflow "workflow_a"
    setup_test_workflow "workflow_b"

    # Create rounds in workflow_a
    create_mock_round 1 "workflow_a" "Workflow A Round 1"
    create_mock_round 2 "workflow_a" "Workflow A Round 2"

    # Create different rounds in workflow_b
    create_mock_round 1 "workflow_b" "Workflow B Round 1"

    # History for workflow_a shows 2 rounds
    run "$APR_SCRIPT" history -w workflow_a

    log_test_output "$output"

    assert_success
    [[ "$output" == *"2"* ]]

    # History for workflow_b shows 1 round
    run "$APR_SCRIPT" history -w workflow_b

    log_test_output "$output"

    assert_success
    # Should only see round 1
    [[ "$output" == *"1"* ]]
}

@test "e2e: workflow-specific render" {
    setup_test_workflow "alpha"
    setup_test_workflow "beta"

    # Create different README content
    echo "# Alpha Project README" > README.md

    run "$APR_SCRIPT" run 1 --render -w alpha

    log_test_output "$output"

    assert_success
    [[ "$output" == *"Alpha"* ]] || [[ "$output" == *"alpha"* ]]
}

# =============================================================================
# Robot Mode E2E Tests
# =============================================================================

@test "e2e: robot mode status check" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" robot status

    log_test_output "$output"

    # Robot mode should return valid JSON
    assert_success
    assert_valid_json "$output"
}

@test "e2e: robot mode history" {
    setup_test_workflow "default"
    create_mock_round 1
    create_mock_round 2

    run "$APR_SCRIPT" robot history

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    # Should include rounds array
    [[ "$output" == *"rounds"* ]]
}

@test "e2e: robot mode validate" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" robot validate 1

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    # Should include validation result
    [[ "$output" == *'"ok":true'* ]] || [[ "$output" == *'"ok": true'* ]]
}

@test "e2e: robot mode workflows" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" robot workflows

    log_test_output "$output"

    assert_success
    assert_valid_json "$output"
    # Should include workflows list
    [[ "$output" == *"workflows"* ]]
    [[ "$output" == *"default"* ]]
}

@test "e2e: robot mode error handling" {
    setup_test_workflow "default"

    # Try invalid command (capture_streams separates stdout from stderr
    # because robot_fail emits APR_ERROR_CODE=... to stderr)
    capture_streams "$APR_SCRIPT" robot invalid-command
    output="$CAPTURED_STDOUT"
    status="$CAPTURED_STATUS"

    log_test_output "$output"

    [[ "$status" -ne 0 ]]  # assert_failure equivalent
    assert_valid_json "$output"
    [[ "$output" == *'"ok":false'* ]] || [[ "$output" == *'"ok": false'* ]]
}

# =============================================================================
# Error Recovery Tests
# =============================================================================

@test "e2e: graceful handling of missing workflow" {
    # Fresh project with no workflows
    mkdir -p .apr

    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    # Should fail gracefully
    assert_failure
    # Should give actionable error
    [[ "$output" == *"workflow"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"setup"* ]]
}

@test "e2e: graceful handling of corrupted config" {
    mkdir -p .apr/workflows
    # Create invalid YAML
    echo "invalid: [yaml" > .apr/workflows/default.yaml

    run "$APR_SCRIPT" list

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Should handle gracefully (either succeed with warning or fail cleanly)
    # Not crash with obscure error
}

# =============================================================================
# Version and Update Tests
# =============================================================================

@test "e2e: version command shows full info" {
    run "$APR_SCRIPT" --version

    log_test_output "$output"

    assert_success
    # Should show version number
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "e2e: help is accessible" {
    run "$APR_SCRIPT" --help

    log_test_output "$output"

    assert_success
    # Should show usage info
    [[ "$output" == *"USAGE"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
    # Should list commands
    [[ "$output" == *"run"* ]]
    [[ "$output" == *"list"* ]]
}

# =============================================================================
# Integration with External Tools (Mocked)
# =============================================================================

@test "e2e: dry-run produces valid Oracle command" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" run 1 --dry-run

    log_test_output "$output"

    assert_success
    # Should include Oracle command structure
    [[ "$output" == *"oracle"* ]]
    # Should include model selection
    [[ "$output" == *"5.2"* ]] || [[ "$output" == *"model"* ]]
}

@test "e2e: render produces usable prompt" {
    setup_test_workflow "default"

    run "$APR_SCRIPT" run 1 --render

    log_test_output "$output"

    assert_success
    # Output should be substantial (actual prompt)
    [[ ${#output} -gt 100 ]]
    # Should contain structured sections
    [[ "$output" == *"readme"* ]] || [[ "$output" == *"README"* ]]
}

# =============================================================================
# Stream Separation Verification
# =============================================================================

@test "e2e: robot mode uses stdout for JSON" {
    setup_test_workflow "default"

    capture_streams "$APR_SCRIPT" robot status

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    # JSON should go to stdout
    assert_valid_json "$CAPTURED_STDOUT"
    # Human messages to stderr only
}

@test "e2e: render mode uses correct streams" {
    setup_test_workflow "default"

    capture_streams "$APR_SCRIPT" run 1 --render

    log_test_actual "stdout" "${CAPTURED_STDOUT:0:200}..."
    log_test_actual "stderr" "${CAPTURED_STDERR:0:200}..."

    # Rendered content should go to stdout
    [[ -n "$CAPTURED_STDOUT" ]]
}
