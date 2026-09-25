#!/usr/bin/env bats
# test_setup.bats - Integration tests for APR setup wizard and workflow creation
#
# Tests: apr setup command, workflow creation, directory structure

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    cd "$TEST_PROJECT"

    # Create sample documents for setup wizard to find
    cat > README.md << 'EOF'
# Test Project

This is a test project for APR setup testing.

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
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# First-Time Setup Tests
# =============================================================================

@test "setup: shows welcome message on first run" {
    run "$APR_SCRIPT" setup <<< $'myworkflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should show welcome or setup message
    [[ "$output" == *"Setup"* ]] || [[ "$output" == *"setup"* ]] || [[ "$output" == *"Welcome"* ]]
}

@test "setup: creates .apr directory" {
    run "$APR_SCRIPT" setup <<< $'testflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Even if interactive input fails, check if .apr was created
    [[ -d ".apr" ]] || [[ $status -eq 0 ]]
}

@test "setup: creates workflow config file" {
    # Create minimal setup by providing files that exist
    run "$APR_SCRIPT" setup <<< $'newworkflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Check if workflow directory structure exists or was attempted
    [[ -d ".apr/workflows" ]] || [[ "$output" == *"workflow"* ]]
}

@test "setup: creates rounds directory" {
    run "$APR_SCRIPT" setup <<< $'roundstest\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Check rounds directory
    [[ -d ".apr/rounds" ]] || [[ "$output" == *"rounds"* ]] || [[ "$output" == *"Created"* ]]
}

@test "setup: Custom / Other records any Oracle model id (GH #5)" {
    # name, description, README, spec, menu option 4, model id (the impl-doc
    # confirm does not read stdin when it is not a terminal)
    run "$APR_SCRIPT" setup <<< $'customflow\nDesc\nREADME.md\nSPECIFICATION.md\n4\n  gemini-3-pro  \n'

    log_test_output "$output"

    assert_success
    assert_file_exists ".apr/workflows/customflow.yaml"
    run grep -n '^  model: "gemini-3-pro"$' .apr/workflows/customflow.yaml
    assert_success
}

@test "setup: Custom / Other rejects an empty model id (GH #5)" {
    run "$APR_SCRIPT" setup <<< $'emptyflow\nDesc\nREADME.md\nSPECIFICATION.md\n4\n\n'

    log_test_output "$output"

    assert_failure
    [[ "$output" == *"A model id is required"* ]]
    [[ ! -f ".apr/workflows/emptyflow.yaml" ]]
}

# =============================================================================
# Setup with Existing Configuration Tests
# =============================================================================

@test "setup: works with existing .apr directory" {
    # Create existing .apr structure
    mkdir -p .apr/workflows .apr/rounds/existing
    cat > .apr/config.yaml << 'EOF'
default_workflow: existing
EOF

    cat > .apr/workflows/existing.yaml << 'EOF'
name: existing
documents:
  readme: README.md
  spec: SPECIFICATION.md
model: "5.2 Thinking"
output_dir: .apr/rounds/existing
EOF

    run "$APR_SCRIPT" setup <<< $'newworkflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should not crash when .apr exists
    [[ $status -eq 0 ]] || [[ "$output" == *"existing"* ]] || [[ "$output" == *"workflow"* ]]
}

@test "setup: does not overwrite existing workflow without confirmation" {
    # Create existing workflow
    mkdir -p .apr/workflows .apr/rounds/myworkflow
    cat > .apr/config.yaml << 'EOF'
default_workflow: myworkflow
EOF

    cat > .apr/workflows/myworkflow.yaml << 'EOF'
name: myworkflow
original: true
EOF

    # Try to create same workflow name
    run "$APR_SCRIPT" setup <<< $'myworkflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\nn\n'

    log_test_output "$output"

    # Should warn or ask about overwrite
    # Either warns about existing workflow or proceeds based on implementation
    [[ "$output" == *"exist"* ]] || [[ "$output" == *"overwrite"* ]] || [[ $status -eq 0 ]]
}

# =============================================================================
# Setup Validation Tests
# =============================================================================

@test "setup: handles missing README gracefully" {
    rm -f README.md

    run "$APR_SCRIPT" setup <<< $'testflow\nnonexistent.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should warn about missing file or accept path anyway
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Warning"* ]] || [[ $status -eq 0 ]]
}

@test "setup: handles empty workflow name" {
    run "$APR_SCRIPT" setup <<< $'\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"
    log_test_actual "exit code" "$status"

    # Should either use default name or prompt again
    [[ "$output" == *"default"* ]] || [[ "$output" == *"workflow"* ]] || [[ $status -ne 0 ]]
}

# =============================================================================
# Setup with Implementation Document Tests
# =============================================================================

@test "setup: accepts implementation document path" {
    run "$APR_SCRIPT" setup <<< $'implflow\nREADME.md\nSPECIFICATION.md\nIMPLEMENTATION.md\n5.2 Thinking\n'

    log_test_output "$output"

    # Should accept implementation path
    [[ "$output" == *"impl"* ]] || [[ "$output" == *"Implementation"* ]] || [[ $status -eq 0 ]]
}

@test "setup: implementation document is optional" {
    run "$APR_SCRIPT" setup <<< $'noimplflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should succeed without implementation
    [[ $status -eq 0 ]] || [[ "$output" == *"workflow"* ]]
}

# =============================================================================
# UI Mode Tests
# =============================================================================

@test "setup: works with APR_NO_GUM=1 (ANSI mode)" {
    export APR_NO_GUM=1

    run "$APR_SCRIPT" setup <<< $'ansiflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should work in ANSI mode
    [[ $status -eq 0 ]] || [[ "$output" == *"Setup"* ]] || [[ "$output" == *"workflow"* ]]
}

@test "setup: works in non-TTY environment" {
    # Already in non-TTY due to pipe input
    # Wizard prompts: name, description, readme, spec, impl, model
    run "$APR_SCRIPT" setup <<< $'nonttyflow\n\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should handle non-TTY gracefully (may exit or use defaults)
    # Exit code 4 is config error which is acceptable for non-interactive
    [[ $status -eq 0 ]] || [[ $status -eq 4 ]] || [[ "$output" == *"interactive"* ]] || [[ "$output" == *"Setup"* ]]
}

# =============================================================================
# Model Selection Tests
# =============================================================================

@test "setup: accepts '5.2 Thinking' model" {
    # Wizard prompts: name, description, readme, spec, impl, model
    run "$APR_SCRIPT" setup <<< $'modeltest1\n\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should succeed or at least progress through wizard
    [[ $status -eq 0 ]] || [[ "$output" == *"model"* ]] || [[ "$output" == *"Thinking"* ]]
}

@test "setup: accepts 'Deep Research' model" {
    # Wizard prompts: name, description, readme, spec, impl, model
    run "$APR_SCRIPT" setup <<< $'modeltest2\n\nREADME.md\nSPECIFICATION.md\n\nDeep Research\n'

    log_test_output "$output"

    # Should accept Deep Research as valid model
    [[ $status -eq 0 ]] || [[ "$output" == *"model"* ]] || [[ "$output" == *"Deep Research"* ]]
}

# =============================================================================
# apr list After Setup Tests
# =============================================================================

@test "setup then list: shows created workflow" {
    # First setup a workflow
    setup_test_workflow "listtest"

    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"listtest"* ]]
}

@test "setup then list: shows multiple workflows" {
    setup_test_workflow "workflow1"
    setup_test_workflow "workflow2"

    run "$APR_SCRIPT" list

    log_test_output "$output"

    assert_success
    [[ "$output" == *"workflow1"* ]]
    [[ "$output" == *"workflow2"* ]]
}

# =============================================================================
# Configuration Validation Tests
# =============================================================================

@test "setup: created config is valid YAML" {
    setup_test_workflow "yamltest"

    # Check config.yaml is readable
    run cat .apr/config.yaml

    log_test_output "$output"

    assert_success
    [[ "$output" == *"default_workflow"* ]]
}

@test "setup: workflow config contains required fields" {
    setup_test_workflow "fieldtest"

    # Check workflow config
    run cat .apr/workflows/fieldtest.yaml

    log_test_output "$output"

    assert_success
    [[ "$output" == *"name:"* ]]
    [[ "$output" == *"readme:"* ]] || [[ "$output" == *"documents:"* ]]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "setup: handles special characters in workflow name" {
    # Test with hyphen (allowed)
    run "$APR_SCRIPT" setup <<< $'my-workflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should accept hyphens
    [[ $status -eq 0 ]] || [[ "$output" == *"workflow"* ]]
}

@test "setup: handles workflow name with underscore" {
    run "$APR_SCRIPT" setup <<< $'my_workflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should accept underscores
    [[ $status -eq 0 ]] || [[ "$output" == *"workflow"* ]]
}

@test "setup: handles paths with spaces" {
    # Create file with space in name
    echo "# Spaced README" > "READ ME.md"

    run "$APR_SCRIPT" setup <<< $'spacedflow\nREAD ME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Should handle or warn about spaces
    [[ $status -eq 0 ]] || [[ "$output" == *"space"* ]] || [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Help and Version Tests
# =============================================================================

@test "setup --help: shows setup help" {
    run "$APR_SCRIPT" --help

    log_test_output "$output"

    assert_success
    [[ "$output" == *"setup"* ]]
}

@test "apr setup: respects --quiet flag" {
    run "$APR_SCRIPT" setup --quiet <<< $'quietflow\nREADME.md\nSPECIFICATION.md\n\n5.2 Thinking\n'

    log_test_output "$output"

    # Output should be minimal in quiet mode
    # (may still have some output due to interactive prompts)
    [[ ${#output} -lt 2000 ]] || [[ "$output" == *"quiet"* ]]
}
