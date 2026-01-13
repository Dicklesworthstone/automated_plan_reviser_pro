#!/usr/bin/env bash
# run_tests.sh - Main test runner for APR tests
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh unit         # Run only unit tests
#   ./run_tests.sh integration  # Run only integration tests
#   ./run_tests.sh e2e          # Run only e2e tests
#   ./run_tests.sh -v           # Verbose output
#   ./run_tests.sh -f pattern   # Filter tests by pattern

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BATS_BIN="$SCRIPT_DIR/lib/bats-core/bin/bats"

# Default options
VERBOSE=false
FILTER=""
TEST_DIRS=()
JOBS=1
TAP_OUTPUT=false
LOG_DIR="$SCRIPT_DIR/logs"

# Colors (disabled if NO_COLOR is set)
if [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# Helper Functions
# =============================================================================

usage() {
    cat << EOF
APR Test Runner

Usage: $(basename "$0") [options] [test_suite...]

Test Suites:
  unit          Run unit tests only
  integration   Run integration tests only
  e2e           Run end-to-end tests only
  all           Run all tests (default)

Options:
  -v, --verbose     Verbose output
  -f, --filter PAT  Only run tests matching pattern
  -j, --jobs N      Run N tests in parallel (default: 1)
  -t, --tap         Output in TAP format
  -l, --log-dir DIR Directory for test logs (default: tests/logs)
  -h, --help        Show this help message

Examples:
  $(basename "$0")                    # Run all tests
  $(basename "$0") unit               # Run unit tests only
  $(basename "$0") -v -f version      # Run tests matching 'version' verbosely
  $(basename "$0") -j 4 unit          # Run unit tests with 4 parallel jobs
EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

check_dependencies() {
    # Check for BATS
    if [[ ! -x "$BATS_BIN" ]]; then
        log_error "BATS not found at $BATS_BIN"
        log_info "Run: git submodule update --init --recursive"
        exit 1
    fi

    # Check for jq (required for JSON tests)
    if ! command -v jq &>/dev/null; then
        log_warning "jq not found - some tests may be skipped"
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--filter)
            FILTER="$2"
            shift 2
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -t|--tap)
            TAP_OUTPUT=true
            shift
            ;;
        -l|--log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        unit|integration|e2e|all)
            case "$1" in
                unit)
                    TEST_DIRS+=("$SCRIPT_DIR/unit")
                    ;;
                integration)
                    TEST_DIRS+=("$SCRIPT_DIR/integration")
                    ;;
                e2e)
                    TEST_DIRS+=("$SCRIPT_DIR/e2e")
                    ;;
                all)
                    TEST_DIRS+=("$SCRIPT_DIR/unit" "$SCRIPT_DIR/integration" "$SCRIPT_DIR/e2e")
                    ;;
            esac
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Default to all tests if none specified
if [[ ${#TEST_DIRS[@]} -eq 0 ]]; then
    TEST_DIRS=("$SCRIPT_DIR/unit" "$SCRIPT_DIR/integration" "$SCRIPT_DIR/e2e")
fi

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "APR Test Runner"
    log_info "==============="

    # Check dependencies
    check_dependencies

    # Create log directory
    mkdir -p "$LOG_DIR"
    local log_file
    log_file="$LOG_DIR/test_run_$(date '+%Y%m%d_%H%M%S').log"

    # Build BATS options
    local bats_opts=()

    if [[ "$VERBOSE" == "true" ]]; then
        bats_opts+=("--verbose-run")
    fi

    if [[ -n "$FILTER" ]]; then
        bats_opts+=("--filter" "$FILTER")
    fi

    if [[ "$JOBS" -gt 1 ]]; then
        bats_opts+=("--jobs" "$JOBS")
    fi

    if [[ "$TAP_OUTPUT" == "true" ]]; then
        bats_opts+=("--tap")
    else
        bats_opts+=("--pretty")
    fi

    # Collect test files
    local test_files=()
    for dir in "${TEST_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$dir" -name '*.bats' -type f -print0 2>/dev/null | sort -z)
        fi
    done

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warning "No test files found"
        exit 0
    fi

    log_info "Found ${#test_files[@]} test file(s)"
    log_info "Log file: $log_file"
    log_info ""

    # Export environment for tests
    export TEST_LOG_DIR="$LOG_DIR"
    local test_verbosity
    test_verbosity=$([[ "$VERBOSE" == "true" ]] && echo 2 || echo 1)
    export TEST_VERBOSITY="$test_verbosity"
    export PROJECT_ROOT

    # Run BATS
    local exit_code=0
    "$BATS_BIN" "${bats_opts[@]}" "${test_files[@]}" 2>&1 | tee "$log_file" || exit_code=$?

    # Summary
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        log_success "All tests passed!"
    else
        log_error "Some tests failed (exit code: $exit_code)"
    fi

    log_info "Full log: $log_file"

    return $exit_code
}

main "$@"
