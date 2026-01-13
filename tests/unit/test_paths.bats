#!/usr/bin/env bats
# test_paths.bats - Unit tests for XDG paths and APR home/cache settings
#
# Tests:
#   - APR_HOME default (XDG_DATA_HOME)
#   - APR_CACHE default (XDG_CACHE_HOME)
#   - APR_HOME/APR_CACHE overrides
#   - HOME fallbacks when XDG vars unset

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
# XDG Defaults
# =============================================================================

@test "APR_HOME defaults to XDG_DATA_HOME/apr" {
    log_test_actual "APR_HOME" "$APR_HOME"
    [[ "$APR_HOME" == "$XDG_DATA_HOME/apr" ]]
}

@test "APR_CACHE defaults to XDG_CACHE_HOME/apr" {
    log_test_actual "APR_CACHE" "$APR_CACHE"
    [[ "$APR_CACHE" == "$XDG_CACHE_HOME/apr" ]]
}

# =============================================================================
# Overrides and Fallbacks
# =============================================================================

@test "APR_HOME respects APR_HOME override" {
    local tmp_script="$TEST_DIR/apr_env_override.bash"
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$tmp_script"

    local expected="$TEST_DIR/custom_apr_home"
    run bash -c "APR_HOME=\"$expected\"; XDG_DATA_HOME=\"$TEST_DIR/xdg\"; HOME=\"$TEST_HOME\"; source \"$tmp_script\"; echo \"\$APR_HOME\""

    assert_success
    [[ "$output" == "$expected" ]]
}

@test "APR_CACHE respects APR_CACHE override" {
    local tmp_script="$TEST_DIR/apr_env_cache_override.bash"
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$tmp_script"

    local expected="$TEST_DIR/custom_apr_cache"
    run bash -c "APR_CACHE=\"$expected\"; XDG_CACHE_HOME=\"$TEST_DIR/xdg_cache\"; HOME=\"$TEST_HOME\"; source \"$tmp_script\"; echo \"\$APR_CACHE\""

    assert_success
    [[ "$output" == "$expected" ]]
}

@test "APR_HOME falls back to HOME/.local/share/apr when XDG_DATA_HOME unset" {
    local tmp_script="$TEST_DIR/apr_env_fallback.bash"
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$tmp_script"

    local expected="$TEST_HOME/.local/share/apr"
    run bash -c "XDG_DATA_HOME=\"\"; APR_HOME=\"\"; HOME=\"$TEST_HOME\"; source \"$tmp_script\"; echo \"\$APR_HOME\""

    assert_success
    [[ "$output" == "$expected" ]]
}

@test "APR_CACHE falls back to HOME/.cache/apr when XDG_CACHE_HOME unset" {
    local tmp_script="$TEST_DIR/apr_env_cache_fallback.bash"
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$tmp_script"

    local expected="$TEST_HOME/.cache/apr"
    run bash -c "XDG_CACHE_HOME=\"\"; APR_CACHE=\"\"; HOME=\"$TEST_HOME\"; source \"$tmp_script\"; echo \"\$APR_CACHE\""

    assert_success
    [[ "$output" == "$expected" ]]
}
