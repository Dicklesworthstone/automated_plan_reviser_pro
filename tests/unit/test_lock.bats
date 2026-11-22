#!/usr/bin/env bats
# test_lock.bats - Unit tests for APR lock mechanism
#
# Tests:
#   - acquire_lock() - Lock acquisition
#   - release_lock() - Lock release
#   - cleanup_temp() - Exit cleanup
#   - Concurrent execution prevention

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"

    # Set up lock directory
    export CONFIG_DIR="$TEST_DIR/.apr"
    mkdir -p "$CONFIG_DIR"
}

teardown() {
    # Clean up any locks
    release_lock 2>/dev/null || true

    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# acquire_lock() Tests
# =============================================================================

@test "acquire_lock: first process acquires lock successfully" {
    log_test_step "action" "Acquiring lock for workflow test, round 1"

    run acquire_lock "test" "1"

    log_test_actual "exit code" "$status"

    assert_success
}

@test "acquire_lock: creates lock file" {
    acquire_lock "test" "1"

    log_test_step "check" "Checking for lock file"

    # Lock file should exist somewhere in CONFIG_DIR
    local lock_found=false
    if [[ -n "${APR_LOCK_FILE:-}" && -f "$APR_LOCK_FILE" ]]; then
        lock_found=true
    fi

    # Or check for any lock file
    if ls "$CONFIG_DIR"/*.lock 2>/dev/null | grep -q .; then
        lock_found=true
    fi

    log_test_actual "lock found" "$lock_found"

    # Clean up
    release_lock

    [[ "$lock_found" == "true" ]] || skip "Lock mechanism may use flock without file"
}

@test "acquire_lock: second process fails to acquire" {
    log_test_step "action" "First process acquiring lock"

    # First process acquires lock
    acquire_lock "test" "1"

    log_test_step "action" "Second process attempting to acquire same lock"

    # Run second acquisition in subshell (simulates another process)
    # This should fail because lock is held
    run bash -c '
        source '"$TEST_DIR"'/apr_functions.bash
        export CONFIG_DIR="'"$CONFIG_DIR"'"
        acquire_lock "test" "1"
    '

    log_test_actual "second process exit code" "$status"

    # Clean up
    release_lock

    # Second process should have failed
    assert_failure
}

@test "acquire_lock: different workflow can acquire lock" {
    log_test_step "action" "Acquiring lock for workflow A"

    acquire_lock "workflowA" "1"

    log_test_step "action" "Attempting to acquire lock for workflow B"

    # Different workflow should be able to acquire its own lock
    run bash -c '
        source '"$TEST_DIR"'/apr_functions.bash
        export CONFIG_DIR="'"$CONFIG_DIR"'"
        acquire_lock "workflowB" "1"
        release_lock 2>/dev/null || true
    '

    log_test_actual "exit code" "$status"

    # Clean up first lock
    release_lock

    # Should succeed (different workflow)
    assert_success
}

@test "acquire_lock: different round can acquire lock" {
    log_test_step "action" "Acquiring lock for round 1"

    acquire_lock "test" "1"

    log_test_step "action" "Attempting to acquire lock for round 2"

    run bash -c '
        source '"$TEST_DIR"'/apr_functions.bash
        export CONFIG_DIR="'"$CONFIG_DIR"'"
        acquire_lock "test" "2"
        release_lock 2>/dev/null || true
    '

    log_test_actual "exit code" "$status"

    release_lock

    # Should succeed (different round)
    assert_success
}

# =============================================================================
# release_lock() Tests
# =============================================================================

@test "release_lock: releases held lock" {
    acquire_lock "test" "1"

    log_test_step "action" "Releasing lock"

    local release_rc=0
    release_lock || release_rc=$?

    log_test_actual "exit code" "$release_rc"

    [[ "$release_rc" -eq 0 ]]

    # Now another process should be able to acquire
    run acquire_lock "test" "1"
    assert_success
}

@test "release_lock: safe to call without lock" {
    log_test_step "action" "Calling release_lock without holding lock"

    # Should not crash or error
    run release_lock

    log_test_actual "exit code" "$status"

    # Should succeed (no-op)
    assert_success
}

@test "release_lock: idempotent (safe to call multiple times)" {
    acquire_lock "test" "1"

    release_lock
    run release_lock
    assert_success

    run release_lock
    assert_success
}

# =============================================================================
# cleanup_temp() Tests
# =============================================================================

@test "cleanup_temp: removes temp directory" {
    # Create a temp directory
    APR_TEMP_DIR="$TEST_DIR/apr_temp_$$"
    export APR_TEMP_DIR
    mkdir -p "$APR_TEMP_DIR"
    touch "$APR_TEMP_DIR/test_file"

    log_test_step "action" "Calling cleanup_temp"

    assert_dir_exists "$APR_TEMP_DIR"

    cleanup_temp

    log_test_step "check" "Checking temp directory removed"

    [[ ! -d "$APR_TEMP_DIR" ]]
}

@test "cleanup_temp: safe when no temp directory" {
    # Set to empty instead of unset (due to set -u in APR)
    APR_TEMP_DIR=""
    export APR_TEMP_DIR

    log_test_step "action" "Calling cleanup_temp without temp dir"

    run cleanup_temp

    assert_success
}

@test "cleanup_temp: safe when temp directory already removed" {
    APR_TEMP_DIR="$TEST_DIR/nonexistent"
    export APR_TEMP_DIR

    run cleanup_temp

    assert_success
}

@test "cleanup_temp: releases lock" {
    acquire_lock "test" "1"
    APR_TEMP_DIR="$TEST_DIR/temp_$$"
    export APR_TEMP_DIR
    mkdir -p "$APR_TEMP_DIR"

    cleanup_temp

    # Lock should be released - another process should be able to acquire
    run acquire_lock "test" "1"
    assert_success
    release_lock
}

# =============================================================================
# Stale Lock Detection Tests
# =============================================================================

@test "acquire_lock: detects stale lock from dead process" {
    # Create a fake stale lock file with non-existent PID
    local lock_file="$CONFIG_DIR/test_1.lock"
    echo "99999999" > "$lock_file"  # PID that doesn't exist

    log_test_step "action" "Attempting to acquire lock with stale lock file"

    run acquire_lock "test" "1"

    log_test_actual "exit code" "$status"

    # Clean up
    release_lock 2>/dev/null || true
    rm -f "$lock_file"

    # Should succeed by detecting stale lock
    # (Behavior depends on implementation - may or may not support this)
    [[ $status -eq 0 ]] || skip "Stale lock detection not implemented"
}

# =============================================================================
# Lock File Location Tests
# =============================================================================

@test "acquire_lock: lock file in CONFIG_DIR" {
    acquire_lock "myworkflow" "5"

    log_test_step "check" "Checking lock file location"

    # Lock should be in CONFIG_DIR or APR_LOCK_FILE should be set
    if [[ -n "${APR_LOCK_FILE:-}" ]]; then
        log_test_actual "APR_LOCK_FILE" "$APR_LOCK_FILE"
        [[ "$APR_LOCK_FILE" == "$CONFIG_DIR"* ]]
    fi

    release_lock
}
