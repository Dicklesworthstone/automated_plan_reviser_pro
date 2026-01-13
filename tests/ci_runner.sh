#!/usr/bin/env bash
# ci_runner.sh - CI-specific test runner for APR
#
# This script is optimized for CI environments (GitHub Actions, etc.)
# It produces:
#   - JUnit XML output for CI integration
#   - TAP output for logging
#   - Clear exit codes for CI pass/fail
#
# Usage:
#   ./ci_runner.sh              # Run all tests
#   ./ci_runner.sh unit         # Run specific suite
#   ./ci_runner.sh --junit      # Output JUnit XML

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BATS_BIN="$SCRIPT_DIR/lib/bats-core/bin/bats"

# CI-specific settings
export CI=true
export NO_COLOR=1
export APR_NO_GUM=1
export APR_CHECK_UPDATES=0

# Output directories
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/results}"
JUNIT_FILE="$RESULTS_DIR/junit.xml"
TAP_FILE="$RESULTS_DIR/results.tap"
# shellcheck disable=SC2034  # Reserved for future use
LOG_FILE="$RESULTS_DIR/test.log"

# Test configuration
TEST_SUITE="${1:-all}"
JUNIT_OUTPUT=false

# Parse additional options
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --junit)
            JUNIT_OUTPUT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

preflight() {
    log "Running pre-flight checks..."

    # Check BATS
    if [[ ! -x "$BATS_BIN" ]]; then
        die "BATS not found. Run: git submodule update --init --recursive"
    fi
    log "  BATS: OK ($("$BATS_BIN" --version))"

    # Check Bash version
    local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    if (( BASH_VERSINFO[0] < 4 )); then
        die "Bash 4.0+ required, found $bash_version"
    fi
    log "  Bash: OK ($bash_version)"

    # Check jq
    if command -v jq &>/dev/null; then
        log "  jq: OK ($(jq --version))"
    else
        log "  jq: MISSING (some tests may be skipped)"
    fi

    # Check APR script
    if [[ ! -x "$PROJECT_ROOT/apr" ]]; then
        die "APR script not found or not executable"
    fi
    log "  APR: OK"

    # Create results directory
    mkdir -p "$RESULTS_DIR"
    log "  Results dir: $RESULTS_DIR"

    log "Pre-flight checks passed"
    echo ""
}

# =============================================================================
# Test Execution
# =============================================================================

run_tests() {
    local test_dirs=()

    case "$TEST_SUITE" in
        unit)
            test_dirs=("$SCRIPT_DIR/unit")
            ;;
        integration)
            test_dirs=("$SCRIPT_DIR/integration")
            ;;
        e2e)
            test_dirs=("$SCRIPT_DIR/e2e")
            ;;
        all|*)
            test_dirs=("$SCRIPT_DIR/unit" "$SCRIPT_DIR/integration" "$SCRIPT_DIR/e2e")
            ;;
    esac

    # Collect test files
    local test_files=()
    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$dir" -name '*.bats' -type f -print0 2>/dev/null | sort -z)
        fi
    done

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log "No test files found for suite: $TEST_SUITE"
        echo "0 tests, 0 failures" > "$TAP_FILE"
        return 0
    fi

    log "Running ${#test_files[@]} test file(s) for suite: $TEST_SUITE"

    # Build BATS options
    local bats_opts=(
        "--tap"
        "--timing"
    )

    if [[ "$JUNIT_OUTPUT" == "true" ]]; then
        bats_opts+=("--formatter" "junit" "--output" "$RESULTS_DIR")
    fi

    # Export for tests
    export TEST_LOG_DIR="$RESULTS_DIR"
    export TEST_VERBOSITY=1
    export PROJECT_ROOT

    # Run tests
    local exit_code=0
    "$BATS_BIN" "${bats_opts[@]}" "${test_files[@]}" 2>&1 | tee "$TAP_FILE" || exit_code=$?

    return $exit_code
}

# =============================================================================
# Result Summary
# =============================================================================

summarize() {
    local exit_code="$1"

    echo ""
    log "========================================"
    log "TEST RESULTS"
    log "========================================"

    if [[ -f "$TAP_FILE" ]]; then
        # Parse TAP output for summary
        local total passed failed
        total=$(grep -c '^ok\|^not ok' "$TAP_FILE" 2>/dev/null || echo 0)
        passed=$(grep -c '^ok ' "$TAP_FILE" 2>/dev/null || echo 0)
        failed=$(grep -c '^not ok' "$TAP_FILE" 2>/dev/null || echo 0)

        log "Total:  $total"
        log "Passed: $passed"
        log "Failed: $failed"
    fi

    log "========================================"
    log "Results: $RESULTS_DIR"

    if [[ -f "$JUNIT_FILE" ]]; then
        log "JUnit:  $JUNIT_FILE"
    fi

    log "TAP:    $TAP_FILE"
    log "========================================"

    if [[ $exit_code -eq 0 ]]; then
        log "STATUS: PASSED"
    else
        log "STATUS: FAILED"

        # Show failed tests
        if [[ -f "$TAP_FILE" ]]; then
            echo ""
            log "Failed tests:"
            grep '^not ok' "$TAP_FILE" | while read -r line; do
                echo "  - $line"
            done
        fi
    fi

    return $exit_code
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "APR CI Test Runner"
    log "=================="
    log "Suite: $TEST_SUITE"
    log "JUnit: $JUNIT_OUTPUT"
    echo ""

    preflight

    local exit_code=0
    run_tests || exit_code=$?

    summarize $exit_code

    exit $exit_code
}

main
