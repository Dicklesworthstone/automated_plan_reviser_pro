#!/usr/bin/env bats
# test_exit_codes.bats - Unit tests for APR exit codes and error handling

# Load test helpers
load '../helpers/test_helper.bash'

# =============================================================================
# EXIT_SUCCESS (0) - Successful Operations
# =============================================================================

@test "apr --help returns EXIT_SUCCESS (0)" {
    run "$APR_SCRIPT" --help
    assert_exit_code 0
}

@test "apr --version returns EXIT_SUCCESS (0)" {
    run "$APR_SCRIPT" --version
    assert_exit_code 0
}

@test "apr help returns EXIT_SUCCESS (0)" {
    run "$APR_SCRIPT" help
    assert_exit_code 0
}

@test "apr robot help returns EXIT_SUCCESS (0)" {
    run "$APR_SCRIPT" robot help
    assert_exit_code 0
}

@test "apr list with no workflows returns EXIT_SUCCESS (0)" {
    cd "$TEST_PROJECT"
    mkdir -p .apr/workflows

    run "$APR_SCRIPT" list
    # Returns 0 even with no workflows
    assert_exit_code 0
}

# =============================================================================
# EXIT_USAGE_ERROR (2) - Bad Arguments
# =============================================================================

@test "apr with invalid command returns EXIT_USAGE_ERROR (2)" {
    run "$APR_SCRIPT" invalidcommand
    assert_exit_code 2
}

@test "apr run without round number returns EXIT_USAGE_ERROR (2)" {
    run "$APR_SCRIPT" run
    assert_exit_code 2
}

@test "apr run with non-numeric round returns EXIT_USAGE_ERROR (2)" {
    cd "$TEST_PROJECT"
    setup_test_workflow

    run "$APR_SCRIPT" run abc
    assert_exit_code 2
}

@test "apr show without round number returns EXIT_USAGE_ERROR (2)" {
    run "$APR_SCRIPT" show
    assert_exit_code 2
}

@test "apr attach without session name returns EXIT_USAGE_ERROR (2)" {
    run "$APR_SCRIPT" attach
    assert_exit_code 2
}

@test "apr robot run without round number returns error" {
    capture_streams "$APR_SCRIPT" robot run --compact
    status="$CAPTURED_STATUS"
    output="$CAPTURED_STDOUT"

    # Robot mode returns JSON with ok:false for missing argument
    assert_exit_code 2
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "usage_error"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=usage_error"* ]]
}

@test "apr robot validate without round number returns error" {
    capture_streams "$APR_SCRIPT" robot validate --compact
    status="$CAPTURED_STATUS"
    output="$CAPTURED_STDOUT"

    # Robot mode returns JSON with ok:false for missing argument
    assert_exit_code 2
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "usage_error"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=usage_error"* ]]
}

# =============================================================================
# EXIT_CONFIG_ERROR (4) - Config Problems
# =============================================================================

@test "apr run in directory without .apr returns EXIT_CONFIG_ERROR (4)" {
    cd "$TEST_PROJECT"
    # No .apr directory

    run "$APR_SCRIPT" run 1 --dry-run
    assert_exit_code 4
}

@test "apr run with nonexistent workflow returns EXIT_CONFIG_ERROR (4)" {
    cd "$TEST_PROJECT"
    mkdir -p .apr/workflows
    echo "default_workflow: default" > .apr/config.yaml

    run "$APR_SCRIPT" run 1 -w nonexistent --dry-run
    assert_exit_code 4
}

@test "apr show with missing round file returns EXIT_CONFIG_ERROR (4)" {
    cd "$TEST_PROJECT"
    setup_test_workflow

    run "$APR_SCRIPT" show 99
    # Round 99 doesn't exist
    assert_exit_code 4
}

@test "apr diff with missing rounds returns EXIT_CONFIG_ERROR (4)" {
    cd "$TEST_PROJECT"
    setup_test_workflow

    run "$APR_SCRIPT" diff 1 2
    # Neither round exists
    assert_exit_code 4
}

@test "apr history with no rounds returns EXIT_SUCCESS but shows empty" {
    cd "$TEST_PROJECT"
    setup_test_workflow

    run "$APR_SCRIPT" history
    # Returns success but shows no rounds
    assert_exit_code 0
    assert_output --partial "No rounds"
}

# =============================================================================
# EXIT_DEPENDENCY_ERROR (3) - Missing Dependencies
# =============================================================================

@test "apr run without Oracle shows dependency error" {
    cd "$TEST_PROJECT"
    setup_test_workflow

    # Hide oracle/npx from the script. Some environments include npx in /usr/bin,
    # which would otherwise trigger the npx fallback and attempt a real run.
    local offline_bin="$TEST_DIR/offline-tools" tool
    mkdir "$offline_bin"
    for tool in bash jq awk date mktemp mkdir cat base64 tr tee wc sha256sum;do
        ln -s "$(command -v "$tool")" "$offline_bin/$tool"
    done
    run env PATH="$offline_bin:/usr/bin:/bin" APR_NO_NPX=1 "$APR_SCRIPT" run 1

    # Should fail due to missing Oracle
    # Both class and diagnostic are required; local metadata tools are present.
    [[ $status -eq 3 && "$output" =~ [Oo]racle && "$output" == *APR_ERROR_CODE=dependency_missing* ]]
}

# =============================================================================
# Robot Mode Error Codes (JSON responses)
# =============================================================================

@test "apr robot status without config returns ok with configured=false" {
    cd "$TEST_PROJECT"
    # No .apr directory

    run "$APR_SCRIPT" robot status

    # robot status returns ok:true but with configured:false
    # This allows introspection without treating unconfigured as an error
    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.configured" "false"
}

@test "apr robot validate without config returns not_configured code" {
    cd "$TEST_PROJECT"
    # No .apr directory

    capture_streams "$APR_SCRIPT" robot validate 1 --compact
    status="$CAPTURED_STATUS"
    output="$CAPTURED_STDOUT"

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "not_configured"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=not_configured"* ]]
}

@test "apr robot workflows without config returns not_configured code" {
    cd "$TEST_PROJECT"
    # No .apr directory

    capture_streams "$APR_SCRIPT" robot workflows --compact
    status="$CAPTURED_STATUS"
    output="$CAPTURED_STDOUT"

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "not_configured"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=not_configured"* ]]
}

@test "apr robot init creates config and returns ok" {
    cd "$TEST_PROJECT"

    run "$APR_SCRIPT" robot init

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_dir_exists ".apr"
}

@test "apr robot status after init returns configured" {
    cd "$TEST_PROJECT"
    "$APR_SCRIPT" robot init >/dev/null

    run "$APR_SCRIPT" robot status

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
    assert_json_value "$output" ".data.configured" "true"
}

@test "apr robot validate with nonexistent workflow returns canonical config_error" {
    cd "$TEST_PROJECT"
    "$APR_SCRIPT" robot init >/dev/null

    capture_streams "$APR_SCRIPT" robot validate 1 -w nonexistent --compact
    status="$CAPTURED_STATUS"
    output="$CAPTURED_STDOUT"

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "config_error"
    jq -e 'any(.data.findings.errors[];.source.file==".apr/workflows/nonexistent.yaml" and .code=="config_error" and (.hint|length)>0)' <<< "$output"
    [[ "$CAPTURED_STDERR" == *"APR_ERROR_CODE=config_error"* ]]
}

# =============================================================================
# Exit Code Constants Verification
# =============================================================================

@test "EXIT_SUCCESS is defined as 0" {
    load_apr_functions

    [[ "$EXIT_SUCCESS" -eq 0 ]]
}

@test "EXIT_USAGE_ERROR is defined as 2" {
    load_apr_functions

    [[ "$EXIT_USAGE_ERROR" -eq 2 ]]
}

@test "EXIT_DEPENDENCY_ERROR is defined as 3" {
    load_apr_functions

    [[ "$EXIT_DEPENDENCY_ERROR" -eq 3 ]]
}

@test "EXIT_CONFIG_ERROR is defined as 4" {
    load_apr_functions

    [[ "$EXIT_CONFIG_ERROR" -eq 4 ]]
}

@test "EXIT_NETWORK_ERROR is defined as 10" {
    load_apr_functions

    [[ "$EXIT_NETWORK_ERROR" -eq 10 ]]
}

@test "EXIT_UPDATE_ERROR is defined as 11" {
    load_apr_functions

    [[ "$EXIT_UPDATE_ERROR" -eq 11 ]]
}

# =============================================================================
# Error Message Format
# =============================================================================

@test "error messages go to stderr" {
    capture_streams "$APR_SCRIPT" invalidcommand

    # Error message should be on stderr, not stdout
    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
}

@test "error messages include error prefix" {
    run "$APR_SCRIPT" invalidcommand 2>&1

    # Should include some error indicator
    [[ "$output" =~ ([Ee]rror|[Uu]nknown|[Ii]nvalid) ]]
}

@test "usage errors include help hint" {
    run "$APR_SCRIPT" run 2>&1

    # Should suggest --help or show usage
    [[ "$output" =~ (help|usage|Usage) ]] || [[ "$output" =~ [Rr]ound ]]
}
