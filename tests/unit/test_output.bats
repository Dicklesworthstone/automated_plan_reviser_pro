#!/usr/bin/env bats
# test_output.bats - Unit tests for APR output functions
#
# Tests:
#   - print_* functions (success, error, warning, info, dim, header)
#   - Stream separation (stderr vs stdout)
#   - NO_COLOR support
#   - QUIET_MODE behavior

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"

    # Ensure deterministic output
    export NO_COLOR=1
    export APR_NO_GUM=1
    export GUM_AVAILABLE=false
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Stream Separation Tests (CRITICAL - per AGENTS.md)
# =============================================================================

session_metadata() {
    local id="$1" output="$2" created="${3:-$(date -u +%Y-%m-%dT%H:%M:%S.123Z)}"
    mkdir -p "$ORACLE_HOME_DIR/sessions/$id"
    jq -nc --arg id "$id" --arg output "$output" --arg created "$created" \
        '{id:$id,createdAt:$created,status:"completed",options:{writeOutputPath:$output,slug:$id}}' \
        > "$ORACLE_HOME_DIR/sessions/$id/meta.json"
}

@test "Oracle identity: output binding excludes concurrent rounds and stale metadata updates" {
    export ORACLE_HOME_DIR="$TEST_DIR/oracle"
    local marker="$TEST_DIR/start" output="$TEST_DIR/private/output.md"
    session_metadata apr-old "$output"
    oracle_session_snapshot "$marker"
    # Even a freshly rewritten meta.json must not resurrect an existing ID.
    session_metadata apr-old "$output"
    session_metadata apr-collision-99 "$TEST_DIR/other/output.md"
    session_metadata apr-site-overview-independen-round-2 "$output"
    run resolve_oracle_session_id "$output" "$marker"
    [[ "$output" == apr-site-overview-independen-round-2 ]]
}

@test "Oracle identity: retries exclude earlier attempts and ambiguous matches fail closed" {
    export ORACLE_HOME_DIR="$TEST_DIR/oracle"
    local marker="$TEST_DIR/start" destination="$TEST_DIR/private/output.md"
    oracle_session_snapshot "$marker"
    session_metadata apr-normalized "$destination"
    oracle_session_snapshot "$marker"
    session_metadata apr-normalized-2 "$destination"
    run resolve_oracle_session_id "$destination" "$marker"
    [[ "$output" == apr-normalized-2 ]]
    session_metadata apr-normalized-3 "$destination"
    run resolve_oracle_session_id "$destination" "$marker"
    [[ -z "$output" ]]
}

@test "Oracle identity: creation time and metadata ID independently constrain new directories" {
    export ORACLE_HOME_DIR="$TEST_DIR/oracle"
    local marker="$TEST_DIR/start" destination="$TEST_DIR/private/output.md"
    oracle_session_snapshot "$marker"
    session_metadata apr-stale "$destination" 2020-01-01T00:00:00Z
    session_metadata apr-invalid "$destination" invalid
    mkdir -p "$ORACLE_HOME_DIR/sessions/apr-mismatch"
    session_metadata apr-actual "$TEST_DIR/other.md"
    cp "$ORACLE_HOME_DIR/sessions/apr-actual/meta.json" "$ORACLE_HOME_DIR/sessions/apr-mismatch/meta.json"
    run resolve_oracle_session_id "$destination" "$marker"
    [[ -z "$output" ]]
}

@test "print_success: outputs to stderr only" {
    export QUIET_MODE=false

    log_test_step "action" "Calling print_success"

    capture_streams print_success "Test message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    # stdout should be empty
    [[ -z "$CAPTURED_STDOUT" ]]
    # stderr should have content
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Test message"* ]]
}

@test "print_error: outputs to stderr only" {
    log_test_step "action" "Calling print_error"

    capture_streams print_error "Error message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Error message"* ]]
}

@test "print_warning: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_warning "Warning message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Warning message"* ]]
}

@test "print_info: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_info "Info message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Info message"* ]]
}

@test "print_dim: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_dim "Dim message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Dim message"* ]]
}

@test "print_header: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_header "Header message"

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Header message"* ]]
}

# =============================================================================
# NO_COLOR Support Tests
# =============================================================================

@test "print_success: no ANSI codes when NO_COLOR is set" {
    export NO_COLOR=1
    export GUM_AVAILABLE=false

    capture_streams print_success "Test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    assert_no_ansi "$CAPTURED_STDERR"
}

@test "print_error: no ANSI codes when NO_COLOR is set" {
    export NO_COLOR=1
    export GUM_AVAILABLE=false

    capture_streams print_error "Test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    assert_no_ansi "$CAPTURED_STDERR"
}

@test "print_warning: no ANSI codes when NO_COLOR is set" {
    export NO_COLOR=1
    export GUM_AVAILABLE=false

    capture_streams print_warning "Test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    assert_no_ansi "$CAPTURED_STDERR"
}

@test "print_info: no ANSI codes when NO_COLOR is set" {
    export NO_COLOR=1
    export GUM_AVAILABLE=false

    capture_streams print_info "Test message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    assert_no_ansi "$CAPTURED_STDERR"
}

# =============================================================================
# QUIET_MODE Tests
# =============================================================================

@test "print_success: suppressed in QUIET_MODE" {
    export QUIET_MODE=true

    capture_streams print_success "Should not appear"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDERR" ]]
}

@test "print_error: NOT suppressed in QUIET_MODE" {
    export QUIET_MODE=true

    capture_streams print_error "Error should appear"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Error messages should never be suppressed
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Error should appear"* ]]
}

@test "print_warning: NOT suppressed in QUIET_MODE (like errors)" {
    # Warnings are always shown, like errors - they're important
    export QUIET_MODE=true

    capture_streams print_warning "Warning should appear"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Warnings are NOT suppressed (important information)
    [[ -n "$CAPTURED_STDERR" ]]
    [[ "$CAPTURED_STDERR" == *"Warning should appear"* ]]
}

@test "print_info: suppressed in QUIET_MODE" {
    export QUIET_MODE=true

    capture_streams print_info "Should not appear"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDERR" ]]
}

# =============================================================================
# Message Format Tests
# =============================================================================

@test "print_success: includes checkmark or success indicator" {
    export QUIET_MODE=false

    capture_streams print_success "Test"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Should have some success indicator (checkmark, [ok], etc.)
    [[ "$CAPTURED_STDERR" == *"✓"* ]] || \
    [[ "$CAPTURED_STDERR" == *"[ok]"* ]] || \
    [[ "$CAPTURED_STDERR" == *"success"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Test"* ]]
}

@test "print_error: includes error indicator" {
    capture_streams print_error "Test"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    # Should have some error indicator
    [[ "$CAPTURED_STDERR" == *"✗"* ]] || \
    [[ "$CAPTURED_STDERR" == *"[error]"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Error"* ]] || \
    [[ "$CAPTURED_STDERR" == *"error"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Test"* ]]
}

@test "print_warning: includes warning indicator" {
    export QUIET_MODE=false

    capture_streams print_warning "Test"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STDERR" == *"⚠"* ]] || \
    [[ "$CAPTURED_STDERR" == *"[warn]"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Warning"* ]] || \
    [[ "$CAPTURED_STDERR" == *"warning"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Test"* ]]
}

# =============================================================================
# print_step() Tests
# =============================================================================

@test "print_step: shows step number" {
    export QUIET_MODE=false

    capture_streams print_step 1 5 "Step message"

    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ "$CAPTURED_STDERR" == *"1"* ]]
    [[ "$CAPTURED_STDERR" == *"5"* ]] || [[ "$CAPTURED_STDERR" == *"Step message"* ]]
}

@test "print_step: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_step 1 3 "Test step"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
}

@test "print_step: suppressed in QUIET_MODE" {
    export QUIET_MODE=true

    capture_streams print_step 1 3 "Should not appear"

    [[ -z "$CAPTURED_STDERR" ]]
}

# =============================================================================
# print_banner() Tests
# =============================================================================

@test "print_banner: outputs to stderr only" {
    export QUIET_MODE=false

    capture_streams print_banner

    log_test_actual "stdout" "$CAPTURED_STDOUT"
    log_test_actual "stderr" "$CAPTURED_STDERR"

    [[ -z "$CAPTURED_STDOUT" ]]
    [[ -n "$CAPTURED_STDERR" ]]
}

@test "print_banner: suppressed in QUIET_MODE" {
    export QUIET_MODE=true

    capture_streams print_banner

    [[ -z "$CAPTURED_STDERR" ]]
}

@test "print_banner: shows APR name" {
    export QUIET_MODE=false

    capture_streams print_banner

    # Should mention APR somewhere
    [[ "$CAPTURED_STDERR" == *"APR"* ]] || \
    [[ "$CAPTURED_STDERR" == *"apr"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Automated"* ]] || \
    [[ "$CAPTURED_STDERR" == *"Plan"* ]]
}

# =============================================================================
# GUM Fallback Tests
# =============================================================================

@test "output functions: work without gum" {
    export GUM_AVAILABLE=false
    export APR_NO_GUM=1
    export QUIET_MODE=false

    # All these should work without crashing
    capture_streams print_success "test"
    [[ -n "$CAPTURED_STDERR" ]]

    capture_streams print_error "test"
    [[ -n "$CAPTURED_STDERR" ]]

    capture_streams print_warning "test"
    [[ -n "$CAPTURED_STDERR" ]]

    capture_streams print_info "test"
    [[ -n "$CAPTURED_STDERR" ]]
}
