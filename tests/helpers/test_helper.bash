#!/usr/bin/env bash
# test_helper.bash - Common setup/teardown and utilities for APR tests
#
# This file is sourced by all BATS test files.
# It provides:
#   - Test environment setup/teardown
#   - APR function loading for unit tests
#   - Common fixtures and paths
#   - Custom assertions for APR-specific testing

# Strict mode for helper functions
set -euo pipefail

# =============================================================================
# Path Configuration
# =============================================================================

# Get the directory containing this helper
HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(dirname "$HELPERS_DIR")"
PROJECT_ROOT="$(dirname "$TESTS_DIR")"

# BATS libraries
BATS_LIB_DIR="$TESTS_DIR/lib"

# Load BATS helper libraries
load "$BATS_LIB_DIR/bats-support/load"
load "$BATS_LIB_DIR/bats-assert/load"

# Load our custom helpers
source "$HELPERS_DIR/logging.bash"
source "$HELPERS_DIR/assertions.bash"

# Fixtures directory
# shellcheck disable=SC2034  # Used by test files
FIXTURES_DIR="$TESTS_DIR/fixtures"

# APR script path
APR_SCRIPT="$PROJECT_ROOT/apr"

# =============================================================================
# Test Environment Setup/Teardown
# =============================================================================

# setup_test_environment - Create isolated temp directory for test
# Sets TEST_DIR, TEST_HOME, and configures XDG paths
setup_test_environment() {
    # Create unique temp directory for this test
    TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apr_test.XXXXXX")"
    export TEST_DIR

    # Create isolated home directory
    TEST_HOME="$TEST_DIR/home"
    mkdir -p "$TEST_HOME"
    export HOME="$TEST_HOME"

    # Configure XDG paths to use test directory
    export XDG_DATA_HOME="$TEST_DIR/data"
    export XDG_CACHE_HOME="$TEST_DIR/cache"
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

    # Create a test project directory
    TEST_PROJECT="$TEST_DIR/project"
    mkdir -p "$TEST_PROJECT"
    export TEST_PROJECT

    # Initialize as git repo (many APR features expect git)
    (cd "$TEST_PROJECT" && git init -q)

    # Disable colors and gum for deterministic output
    export NO_COLOR=1
    export APR_NO_GUM=1
    export CI=true

    # Disable update checks (unset, not =0, because script checks for empty)
    unset APR_CHECK_UPDATES 2>/dev/null || true

    # Log test setup
    log_test_step "setup" "Created test environment at $TEST_DIR"
}

# teardown_test_environment - Clean up test directory
teardown_test_environment() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        # Log before cleanup
        log_test_step "teardown" "Cleaning up $TEST_DIR"

        # Remove test directory
        rm -rf "$TEST_DIR"
    fi
}

# Standard BATS setup/teardown hooks
setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

# =============================================================================
# APR Function Loading (for Unit Tests)
# =============================================================================

# APR functions loaded flag
_APR_FUNCTIONS_LOADED=false

# load_apr_functions - Source APR script to access internal functions
# This allows unit testing of individual functions without running the full script
load_apr_functions() {
    if [[ "$_APR_FUNCTIONS_LOADED" == "true" ]]; then
        return 0
    fi

    # We need to source apr but prevent it from running main()
    # APR uses 'main "$@"' at the end, so we need to intercept

    # Create a modified version that doesn't call main
    local apr_functions="$TEST_DIR/apr_functions.bash"

    # Extract everything except the final main call
    sed '/^main "\$@"$/d' "$APR_SCRIPT" > "$apr_functions"

    # Source the functions
    # shellcheck disable=SC1090
    source "$apr_functions"

    _APR_FUNCTIONS_LOADED=true
    log_test_step "load" "Loaded APR functions from $APR_SCRIPT"
}

# =============================================================================
# Test Fixture Helpers
# =============================================================================

# setup_test_workflow - Create a complete test workflow configuration
# Usage: setup_test_workflow [workflow_name]
setup_test_workflow() {
    local workflow="${1:-default}"

    cd "$TEST_PROJECT" || return 1

    # Create sample documents
    cat > README.md << 'EOF'
# Test Project

This is a test project for APR testing.

## Features
- Feature 1
- Feature 2
EOF

    cat > SPECIFICATION.md << 'EOF'
# Specification

## Overview
This is the specification document.

## Requirements
1. Requirement A
2. Requirement B
EOF

    cat > IMPLEMENTATION.md << 'EOF'
# Implementation

## Architecture
Description of the implementation.
EOF

    # Create .apr directory structure
    mkdir -p ".apr/workflows" ".apr/rounds/$workflow" ".apr/templates"

    # Create config.yaml
    cat > .apr/config.yaml << EOF
default_workflow: $workflow
EOF

    # Create workflow config
    cat > ".apr/workflows/${workflow}.yaml" << EOF
name: $workflow
description: Test workflow for $workflow

documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: IMPLEMENTATION.md

oracle:
  model: "5.2 Thinking"
  thinking_time: heavy

rounds:
  output_dir: .apr/rounds/$workflow

template: |
  First, read this README:

  <readme>
  {{README}}
  </readme>

  Now read the specification:

  <spec>
  {{SPEC}}
  </spec>

  Please analyze and provide feedback.

template_with_impl: |
  First, read this README:

  <readme>
  {{README}}
  </readme>

  Now read the specification:

  <spec>
  {{SPEC}}
  </spec>

  And the implementation:

  <implementation>
  {{IMPL}}
  </implementation>

  Please analyze and provide feedback.
EOF

    log_test_step "fixture" "Created test workflow '$workflow' in $TEST_PROJECT"
}

# create_mock_round - Create a mock round output file
# Usage: create_mock_round <round_number> [workflow] [content]
create_mock_round() {
    local round="$1"
    local workflow="${2:-default}"
    local content="${3:-}"

    local rounds_dir="$TEST_PROJECT/.apr/rounds/$workflow"
    mkdir -p "$rounds_dir"

    local round_file="$rounds_dir/round_${round}.md"

    if [[ -z "$content" ]]; then
        content="# Round $round Analysis

## Summary
This is the analysis for round $round.

## Recommendations
1. First recommendation
2. Second recommendation

## Conclusion
Round $round complete.
"
    fi

    echo "$content" > "$round_file"
    log_test_step "fixture" "Created mock round $round at $round_file"
}

# setup_test_metrics - Create test metrics file for a workflow
# Usage: setup_test_metrics [workflow]
setup_test_metrics() {
    local workflow="${1:-default}"
    local metrics_dir="$TEST_PROJECT/.apr/analytics/$workflow"
    mkdir -p "$metrics_dir"

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$metrics_dir/metrics.json" << EOF
{
  "schema_version": "1.0.0",
  "workflow": "$workflow",
  "created_at": "$ts",
  "updated_at": "$ts",
  "rounds": [
    {
      "round": 1,
      "timestamp": "$ts",
      "size_bytes": 1024,
      "word_count": 150,
      "section_count": 3
    }
  ],
  "convergence": {
    "detected": false,
    "confidence": 0.0,
    "estimated_rounds_remaining": null,
    "signals": {}
  }
}
EOF
    log_test_step "fixture" "Created test metrics for workflow '$workflow'"
}

# =============================================================================
# Stream Capture Utilities
# =============================================================================

# capture_streams - Run a command and capture stdout/stderr separately
# Usage: capture_streams command [args...]
# Sets: CAPTURED_STDOUT, CAPTURED_STDERR, CAPTURED_STATUS
capture_streams() {
    local stdout_file stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    set +e
    "$@" > "$stdout_file" 2> "$stderr_file"
    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STATUS=$?
    set -e

    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STDOUT="$(cat "$stdout_file")"
    # shellcheck disable=SC2034  # Used by callers
    CAPTURED_STDERR="$(cat "$stderr_file")"

    rm -f "$stdout_file" "$stderr_file"
}

# =============================================================================
# Mock Oracle (for tests that don't need real Oracle)
# =============================================================================

# setup_mock_oracle - Create a mock oracle command for testing
setup_mock_oracle() {
    local mock_oracle="$TEST_DIR/bin/oracle"
    mkdir -p "$(dirname "$mock_oracle")"

    cat > "$mock_oracle" << 'EOF'
#!/usr/bin/env bash
# Mock Oracle for APR testing
# All debug output goes to stderr to avoid interfering with JSON responses
echo "Mock Oracle called with: $*" >&2

# Parse arguments for --render flag
render_mode=false
for arg in "$@"; do
    case "$arg" in
        --render) render_mode=true ;;
        --version) echo "oracle 0.8.4 (mock)"; exit 0 ;;
    esac
done

case "$1" in
    status)
        echo "No active sessions" >&2
        ;;
    session)
        echo "Session: $2" >&2
        ;;
    *)
        if [[ "$render_mode" == "true" ]]; then
            # Render mode: output bundle content to stdout (required for --render tests)
            echo "🧿 oracle 0.8.4 — Mock Oracle"
            echo "[SYSTEM]"
            echo "Mock Oracle render output"
            echo ""
            echo "[USER]"
            echo "Mock prompt content for testing"
        else
            # Simulate a long-running request - output to stderr only
            echo "Mock response for: $*" >&2
            sleep 1
        fi
        ;;
esac
exit 0
EOF
    chmod +x "$mock_oracle"

    # Add to PATH
    export PATH="$TEST_DIR/bin:$PATH"

    log_test_step "mock" "Created mock oracle at $mock_oracle"
}

# =============================================================================
# Utility Functions
# =============================================================================

# skip_if_no_oracle - Skip test if real Oracle is required but not available
skip_if_no_oracle() {
    if ! command -v oracle &>/dev/null; then
        skip "Oracle not available"
    fi
}

# skip_if_no_gum - Skip test if gum is required but not available
skip_if_no_gum() {
    if ! command -v gum &>/dev/null; then
        skip "gum not available"
    fi
}

# get_apr_version - Get APR version from VERSION file or script
get_apr_version() {
    if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
        cat "$PROJECT_ROOT/VERSION"
    else
        "$APR_SCRIPT" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
    fi
}
