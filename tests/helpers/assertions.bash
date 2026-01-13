#!/usr/bin/env bash
# assertions.bash - Custom assertions for APR tests
#
# These complement bats-assert with APR-specific checks.
# All assertions log their inputs and results for debugging.

# =============================================================================
# Exit Code Assertions
# =============================================================================

# assert_exit_code - Assert specific exit code
# Usage: assert_exit_code expected_code
assert_exit_code() {
    local expected="$1"
    local actual="${status:-}"

    log_test_expected "exit code" "$expected"
    log_test_actual "exit code" "$actual"

    if [[ "$actual" != "$expected" ]]; then
        log_test_error "Exit code mismatch: expected $expected, got $actual"
        fail "Expected exit code $expected, got $actual"
    fi
}

# assert_success_silent - Assert success without output check
assert_success_silent() {
    log_test_expected "exit code" "0"
    log_test_actual "exit code" "${status:-}"

    if [[ "${status:-1}" -ne 0 ]]; then
        log_test_error "Expected success (0), got ${status:-1}"
        fail "Expected success, got exit code ${status:-1}"
    fi
}

# =============================================================================
# Stream Assertions (Critical for APR - stderr/stdout separation)
# =============================================================================

# assert_stderr_only - Assert output went only to stderr
# Usage: assert_stderr_only
# Requires capture_streams to have been called first
assert_stderr_only() {
    log_test_step "check" "Verifying output went to stderr only"

    if [[ -n "${CAPTURED_STDOUT:-}" ]]; then
        log_test_error "Unexpected stdout output: $CAPTURED_STDOUT"
        fail "Expected no stdout output, but got: $CAPTURED_STDOUT"
    fi

    if [[ -z "${CAPTURED_STDERR:-}" ]]; then
        log_test_warning "stderr was empty (may be expected)"
    fi

    log_test_step "check" "Confirmed: output went to stderr only"
}

# assert_stdout_only - Assert output went only to stdout
# Usage: assert_stdout_only
# Requires capture_streams to have been called first
assert_stdout_only() {
    log_test_step "check" "Verifying output went to stdout only"

    if [[ -n "${CAPTURED_STDERR:-}" ]]; then
        log_test_error "Unexpected stderr output: $CAPTURED_STDERR"
        fail "Expected no stderr output, but got: $CAPTURED_STDERR"
    fi

    if [[ -z "${CAPTURED_STDOUT:-}" ]]; then
        log_test_warning "stdout was empty (may be expected)"
    fi

    log_test_step "check" "Confirmed: output went to stdout only"
}

# assert_no_ansi - Assert output contains no ANSI escape codes
# Usage: assert_no_ansi "$output"
assert_no_ansi() {
    local output="$1"

    log_test_step "check" "Verifying no ANSI escape codes in output"

    # Check for ANSI escape sequences (ESC[...)
    if [[ "$output" =~ $'\x1b\[' ]]; then
        log_test_error "Found ANSI escape codes in output"
        fail "Output contains ANSI escape codes (should be disabled with NO_COLOR=1)"
    fi

    log_test_step "check" "Confirmed: no ANSI codes in output"
}

# =============================================================================
# JSON Assertions (for Robot Mode)
# =============================================================================

# assert_valid_json - Assert output is valid JSON
# Usage: assert_valid_json "$output"
assert_valid_json() {
    local output="$1"

    log_test_step "check" "Validating JSON structure"

    if ! printf '%s' "$output" | jq . > /dev/null 2>&1; then
        log_test_error "Invalid JSON: $output"
        fail "Output is not valid JSON"
    fi

    log_test_step "check" "Confirmed: valid JSON"
}

# assert_json_value - Assert JSON field has expected value
# Usage: assert_json_value "$json" ".path.to.field" "expected_value"
assert_json_value() {
    local json="$1"
    local path="$2"
    local expected="$3"

    log_test_step "check" "Checking JSON path $path"

    local actual
    actual=$(printf '%s' "$json" | jq -r "$path" 2>/dev/null)

    log_test_expected "$path" "$expected"
    log_test_actual "$path" "$actual"

    if [[ "$actual" != "$expected" ]]; then
        log_test_error "JSON value mismatch at $path"
        fail "Expected $path to be '$expected', got '$actual'"
    fi
}

# assert_json_field_exists - Assert JSON field exists
# Usage: assert_json_field_exists "$json" ".path.to.field"
assert_json_field_exists() {
    local json="$1"
    local path="$2"

    log_test_step "check" "Checking JSON field exists: $path"

    # Check if field exists (we don't need the value, just existence check)
    printf '%s' "$json" | jq -e "$path" >/dev/null 2>&1 || {
        log_test_error "JSON field not found: $path"
        fail "Expected JSON field $path to exist"
    }

    log_test_step "check" "Confirmed: field $path exists"
}

# assert_robot_success - Assert robot mode response indicates success
# Usage: assert_robot_success "$output"
assert_robot_success() {
    local output="$1"

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "true"
}

# assert_robot_error - Assert robot mode response indicates error with code
# Usage: assert_robot_error "$output" "expected_code"
assert_robot_error() {
    local output="$1"
    local expected_code="$2"

    assert_valid_json "$output"
    assert_json_value "$output" ".ok" "false"
    assert_json_value "$output" ".code" "$expected_code"
}

# =============================================================================
# File System Assertions
# =============================================================================

# assert_file_exists - Assert file exists
# Usage: assert_file_exists "path"
assert_file_exists() {
    local path="$1"

    log_test_step "check" "Checking file exists: $path"

    if [[ ! -f "$path" ]]; then
        log_test_error "File not found: $path"
        fail "Expected file to exist: $path"
    fi

    log_test_step "check" "Confirmed: file exists"
}

# assert_dir_exists - Assert directory exists
# Usage: assert_dir_exists "path"
assert_dir_exists() {
    local path="$1"

    log_test_step "check" "Checking directory exists: $path"

    if [[ ! -d "$path" ]]; then
        log_test_error "Directory not found: $path"
        fail "Expected directory to exist: $path"
    fi

    log_test_step "check" "Confirmed: directory exists"
}

# assert_file_contains - Assert file contains string
# Usage: assert_file_contains "path" "string"
assert_file_contains() {
    local path="$1"
    local string="$2"

    log_test_step "check" "Checking file $path contains: $string"

    assert_file_exists "$path"

    if ! grep -q "$string" "$path"; then
        log_test_error "String not found in file"
        log_test_actual "file content" "$(cat "$path")"
        fail "Expected file $path to contain: $string"
    fi

    log_test_step "check" "Confirmed: file contains string"
}

# assert_file_not_contains - Assert file does not contain string
# Usage: assert_file_not_contains "path" "string"
assert_file_not_contains() {
    local path="$1"
    local string="$2"

    log_test_step "check" "Checking file $path does NOT contain: $string"

    assert_file_exists "$path"

    if grep -q "$string" "$path"; then
        log_test_error "Unexpected string found in file"
        fail "Expected file $path to NOT contain: $string"
    fi

    log_test_step "check" "Confirmed: file does not contain string"
}

# assert_executable - Assert file is executable
# Usage: assert_executable "path"
assert_executable() {
    local path="$1"

    log_test_step "check" "Checking file is executable: $path"

    assert_file_exists "$path"

    if [[ ! -x "$path" ]]; then
        log_test_error "File is not executable"
        fail "Expected file to be executable: $path"
    fi

    log_test_step "check" "Confirmed: file is executable"
}

# =============================================================================
# Version Assertions
# =============================================================================

# assert_version_format - Assert string is valid semver
# Usage: assert_version_format "version"
assert_version_format() {
    local version="$1"

    log_test_step "check" "Validating version format: $version"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_test_error "Invalid version format"
        fail "Expected semver format (X.Y.Z), got: $version"
    fi

    log_test_step "check" "Confirmed: valid semver format"
}

# =============================================================================
# Timing Assertions
# =============================================================================

# assert_completes_within - Assert command completes within timeout
# Usage: assert_completes_within seconds command [args...]
assert_completes_within() {
    local timeout="$1"
    shift

    log_test_step "check" "Running command with ${timeout}s timeout: $*"

    local start_time end_time duration
    start_time=$(date +%s)

    if ! timeout "$timeout" "$@"; then
        log_test_error "Command timed out or failed"
        fail "Command did not complete within ${timeout}s: $*"
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    log_test_step "check" "Command completed in ${duration}s (limit: ${timeout}s)"
}

# =============================================================================
# Output Pattern Assertions
# =============================================================================

# assert_output_matches - Assert output matches regex pattern
# Usage: assert_output_matches "$output" "pattern"
assert_output_matches() {
    local output="$1"
    local pattern="$2"

    log_test_step "check" "Checking output matches pattern: $pattern"

    if [[ ! "$output" =~ $pattern ]]; then
        log_test_error "Pattern not matched"
        log_test_actual "output" "$output"
        fail "Expected output to match pattern: $pattern"
    fi

    log_test_step "check" "Confirmed: output matches pattern"
}

# assert_line_count - Assert output has expected number of lines
# Usage: assert_line_count "$output" expected_count
assert_line_count() {
    local output="$1"
    local expected="$2"

    local actual
    actual=$(echo "$output" | wc -l | tr -d ' ')

    log_test_expected "line count" "$expected"
    log_test_actual "line count" "$actual"

    if [[ "$actual" -ne "$expected" ]]; then
        log_test_error "Line count mismatch"
        fail "Expected $expected lines, got $actual"
    fi
}
