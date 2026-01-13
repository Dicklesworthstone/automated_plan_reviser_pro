#!/usr/bin/env bats
# test_formatting.bats - Unit tests for formatting helpers
#
# Tests:
#   - format_bytes
#   - format_float
#   - format_iso_date
#   - dashboard_format_duration
#   - dashboard_iso_to_epoch

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# format_bytes()
# =============================================================================

@test "format_bytes: handles zero and small values" {
    run format_bytes 0
    assert_success
    assert_output "0B"

    run format_bytes 512
    assert_success
    assert_output "512B"
}

@test "format_bytes: formats kilobytes and megabytes" {
    run format_bytes 1024
    assert_success
    assert_output "1.0K"

    run format_bytes 1048576
    assert_success
    assert_output "1.0M"
}

# =============================================================================
# format_float()
# =============================================================================

@test "format_float: formats numbers to two decimals" {
    run format_float 0.5
    assert_success
    assert_output "0.50"
}

@test "format_float: handles leading dot (bc output)" {
    run format_float ".5"
    assert_success
    assert_output "0.50"
    
    run format_float ".0"
    assert_success
    assert_output "0.00"
}

@test "format_float: returns '-' for null input" {
    run format_float null
    assert_success
    assert_output -- "-"
}

# =============================================================================
# format_iso_date()
# =============================================================================

@test "format_iso_date: extracts YYYY-MM-DD" {
    run format_iso_date "2026-01-12T10:00:00Z"
    assert_success
    assert_output "2026-01-12"
}

# =============================================================================
# dashboard_format_duration()
# =============================================================================

@test "dashboard_format_duration: formats hours and minutes" {
    run dashboard_format_duration 3661
    assert_success
    assert_output "1h 1m"
}

@test "dashboard_format_duration: formats minutes when under an hour" {
    run dashboard_format_duration 300
    assert_success
    assert_output "5m"
}

# =============================================================================
# dashboard_iso_to_epoch()
# =============================================================================

@test "dashboard_iso_to_epoch: returns numeric epoch" {
    run dashboard_iso_to_epoch "2026-01-12T10:00:00Z"
    assert_success
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "dashboard_iso_to_epoch: empty input returns 0" {
    run dashboard_iso_to_epoch ""
    assert_success
    assert_output "0"
}
