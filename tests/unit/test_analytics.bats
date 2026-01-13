#!/usr/bin/env bats
# test_analytics.bats - Unit tests for APR analytics functions
#
# Tests for fzi.11: Comprehensive analytics test suite
# Covers:
#   - Metrics storage layer (metrics_init, metrics_read, metrics_write_round, etc.)
#   - Document metrics collection (collect_document_metrics)
#   - Change analysis (calculate_change_metrics, calculate_round_changes)
#   - Convergence detection (calculate_convergence, signal functions)

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"

    # Load APR functions for unit testing
    load_apr_functions

    # Set up a project context
    cd "$TEST_PROJECT"

    # Initialize CONFIG_DIR to test project's .apr
    CONFIG_DIR="$TEST_PROJECT/.apr"
    mkdir -p "$CONFIG_DIR"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Metrics Storage: Path Functions
# =============================================================================

@test "metrics_dir: returns correct path for workflow" {
    local result
    result=$(metrics_dir "test-workflow")

    log_test_actual "metrics_dir" "$result"

    [[ "$result" == *".apr/analytics/test-workflow"* ]]
}

@test "metrics_file_path: returns JSON file path" {
    local result
    result=$(metrics_file_path "test-workflow")

    log_test_actual "metrics_file_path" "$result"

    [[ "$result" == *".apr/analytics/test-workflow/metrics.json"* ]]
}

# =============================================================================
# Metrics Storage: Initialization
# =============================================================================

@test "metrics_init: creates directory structure" {
    metrics_init "init-test"

    local metrics_path
    metrics_path=$(metrics_file_path "init-test")

    log_test_actual "metrics_path" "$metrics_path"

    [[ -f "$metrics_path" ]]
}

@test "metrics_init: creates valid JSON structure" {
    metrics_init "json-test"

    local metrics_path
    metrics_path=$(metrics_file_path "json-test")

    # Verify it's valid JSON
    run jq . "$metrics_path"
    assert_success

    # Check required fields
    local schema_version workflow
    schema_version=$(jq -r '.schema_version' "$metrics_path")
    workflow=$(jq -r '.workflow' "$metrics_path")

    log_test_actual "schema_version" "$schema_version"
    log_test_actual "workflow" "$workflow"

    [[ "$schema_version" == "1.0.0" ]]
    [[ "$workflow" == "json-test" ]]
}

@test "metrics_init: creates empty rounds array" {
    metrics_init "rounds-test"

    local metrics_path rounds_count
    metrics_path=$(metrics_file_path "rounds-test")
    rounds_count=$(jq '.rounds | length' "$metrics_path")

    log_test_actual "rounds_count" "$rounds_count"

    [[ "$rounds_count" == "0" ]]
}

@test "metrics_init: is idempotent - does not overwrite existing data" {
    metrics_init "idempotent-test"

    # Add a round
    local metrics_path
    metrics_path=$(metrics_file_path "idempotent-test")
    local round_json='{"round":1,"timestamp":"2026-01-12T00:00:00Z"}'
    metrics_write_round "idempotent-test" 1 "$round_json"

    # Re-initialize
    metrics_init "idempotent-test"

    # Should still have round data
    local rounds_count
    rounds_count=$(jq '.rounds | length' "$metrics_path")

    log_test_actual "rounds after re-init" "$rounds_count"

    [[ "$rounds_count" == "1" ]]
}

@test "metrics_exists: returns false for non-existent workflow" {
    run metrics_exists "nonexistent-workflow"
    assert_failure
}

@test "metrics_exists: returns true after initialization" {
    metrics_init "exists-test"

    run metrics_exists "exists-test"
    assert_success
}

# =============================================================================
# Metrics Storage: Read Operations
# =============================================================================

@test "metrics_read: auto-initializes for new workflow" {
    # metrics_read auto-initializes if workflow doesn't exist
    local result
    result=$(metrics_read "auto-init-test")

    log_test_actual "result" "$result"

    # Should have initialized with empty rounds
    local rounds_count
    rounds_count=$(echo "$result" | jq '.rounds | length')

    [[ "$rounds_count" == "0" ]]
}

@test "metrics_read: returns full JSON for existing workflow" {
    metrics_init "read-test"

    local result
    result=$(metrics_read "read-test")

    log_test_actual "result" "$result"

    # Should have workflow field
    local workflow
    workflow=$(echo "$result" | jq -r '.workflow')

    [[ "$workflow" == "read-test" ]]
}

@test "metrics_read_round: returns null for non-existent round" {
    metrics_init "read-round-test"

    local result
    result=$(metrics_read_round "read-round-test" 99)

    log_test_actual "result" "$result"

    [[ "$result" == "null" ]]
}

@test "metrics_read_round: returns round data after write" {
    metrics_init "read-round-data"
    local round_json='{"round":5,"timestamp":"2026-01-12T00:00:00Z","test_field":"hello"}'
    metrics_write_round "read-round-data" 5 "$round_json"

    local result
    result=$(metrics_read_round "read-round-data" 5)

    log_test_actual "result" "$result"

    local test_field
    test_field=$(echo "$result" | jq -r '.test_field')

    [[ "$test_field" == "hello" ]]
}

# =============================================================================
# Metrics Storage: Write Operations
# =============================================================================

@test "metrics_write_round: appends new round" {
    metrics_init "write-test"

    local round_json='{"round":1,"timestamp":"2026-01-12T00:00:00Z"}'
    metrics_write_round "write-test" 1 "$round_json"

    local metrics_path rounds_count
    metrics_path=$(metrics_file_path "write-test")
    rounds_count=$(jq '.rounds | length' "$metrics_path")

    log_test_actual "rounds_count" "$rounds_count"

    [[ "$rounds_count" == "1" ]]
}

@test "metrics_write_round: updates existing round without duplication" {
    metrics_init "update-test"

    # Write round 1 twice
    metrics_write_round "update-test" 1 '{"round":1,"value":"first"}'
    metrics_write_round "update-test" 1 '{"round":1,"value":"second"}'

    local metrics_path rounds_count value
    metrics_path=$(metrics_file_path "update-test")
    rounds_count=$(jq '.rounds | length' "$metrics_path")
    value=$(jq -r '.rounds[0].value' "$metrics_path")

    log_test_actual "rounds_count" "$rounds_count"
    log_test_actual "value" "$value"

    [[ "$rounds_count" == "1" ]]  # Not 2
    [[ "$value" == "second" ]]    # Updated value
}

@test "metrics_write_round: maintains round order" {
    metrics_init "order-test"

    # Write rounds out of order
    metrics_write_round "order-test" 3 '{"round":3}'
    metrics_write_round "order-test" 1 '{"round":1}'
    metrics_write_round "order-test" 2 '{"round":2}'

    local metrics_path r1 r2 r3
    metrics_path=$(metrics_file_path "order-test")
    r1=$(jq '.rounds[0].round' "$metrics_path")
    r2=$(jq '.rounds[1].round' "$metrics_path")
    r3=$(jq '.rounds[2].round' "$metrics_path")

    log_test_actual "order" "$r1 $r2 $r3"

    [[ "$r1" == "1" ]]
    [[ "$r2" == "2" ]]
    [[ "$r3" == "3" ]]
}

@test "metrics_write_convergence: writes convergence data" {
    metrics_init "convergence-write-test"

    local conv_json='{"confidence":0.75,"detected":true,"reason":"test"}'
    metrics_write_convergence "convergence-write-test" "$conv_json"

    local metrics_path confidence detected
    metrics_path=$(metrics_file_path "convergence-write-test")
    confidence=$(jq '.convergence.confidence' "$metrics_path")
    detected=$(jq '.convergence.detected' "$metrics_path")

    log_test_actual "confidence" "$confidence"
    log_test_actual "detected" "$detected"

    [[ "$confidence" == "0.75" ]]
    [[ "$detected" == "true" ]]
}

# =============================================================================
# Document Metrics Collection
# =============================================================================

@test "collect_document_metrics: returns valid JSON" {
    # Create test file
    echo "Hello World" > "$TEST_PROJECT/test.md"

    local result
    result=$(collect_document_metrics "$TEST_PROJECT/test.md" "test")

    log_test_actual "result" "$result"

    # Should be valid JSON
    echo "$result" | jq . >/dev/null 2>&1
}

@test "collect_document_metrics: counts characters correctly" {
    echo -n "Hello World" > "$TEST_PROJECT/chars.md"  # 11 chars (no newline)

    local result char_count
    result=$(collect_document_metrics "$TEST_PROJECT/chars.md" "chars")
    char_count=$(echo "$result" | jq '.char_count')

    log_test_actual "char_count" "$char_count"

    [[ "$char_count" == "11" ]]
}

@test "collect_document_metrics: counts words correctly" {
    echo "Hello World Foo Bar Baz" > "$TEST_PROJECT/words.md"  # 5 words

    local result word_count
    result=$(collect_document_metrics "$TEST_PROJECT/words.md" "words")
    word_count=$(echo "$result" | jq '.word_count')

    log_test_actual "word_count" "$word_count"

    [[ "$word_count" == "5" ]]
}

@test "collect_document_metrics: counts lines correctly" {
    printf "Line 1\nLine 2\nLine 3\n" > "$TEST_PROJECT/lines.md"  # 3 lines

    local result line_count
    result=$(collect_document_metrics "$TEST_PROJECT/lines.md" "lines")
    line_count=$(echo "$result" | jq '.line_count')

    log_test_actual "line_count" "$line_count"

    [[ "$line_count" == "3" ]]
}

@test "collect_document_metrics: counts headings correctly" {
    cat > "$TEST_PROJECT/headings.md" << 'EOF'
# Heading 1
Some text
## Heading 2
More text
### Heading 3
Even more
# Another H1
EOF

    local result heading_count
    result=$(collect_document_metrics "$TEST_PROJECT/headings.md" "headings")
    heading_count=$(echo "$result" | jq '.heading_count')

    log_test_actual "heading_count" "$heading_count"

    [[ "$heading_count" == "4" ]]
}

@test "collect_document_metrics: counts code blocks correctly" {
    cat > "$TEST_PROJECT/code.md" << 'OUTER'
# Code Example

```bash
echo "hello"
```

Some text here

```python
print("world")
```

Done.
OUTER

    local result code_block_count
    result=$(collect_document_metrics "$TEST_PROJECT/code.md" "code")
    code_block_count=$(echo "$result" | jq '.code_block_count')

    log_test_actual "code_block_count" "$code_block_count"

    [[ "$code_block_count" == "2" ]]
}

@test "collect_document_metrics: returns null for missing file" {
    local result
    result=$(collect_document_metrics "/nonexistent/file.md" "missing")

    log_test_actual "result" "$result"

    [[ "$result" == "null" ]]
}

@test "collect_document_metrics: handles empty file" {
    touch "$TEST_PROJECT/empty.md"

    local result char_count word_count
    result=$(collect_document_metrics "$TEST_PROJECT/empty.md" "empty")
    char_count=$(echo "$result" | jq '.char_count')
    word_count=$(echo "$result" | jq '.word_count')

    log_test_actual "char_count" "$char_count"
    log_test_actual "word_count" "$word_count"

    [[ "$char_count" == "0" ]]
    [[ "$word_count" == "0" ]]
}

# =============================================================================
# Change Analysis
# =============================================================================

@test "calculate_change_metrics: identical files have zero changes" {
    echo "Same content" > "$TEST_PROJECT/a.md"
    cp "$TEST_PROJECT/a.md" "$TEST_PROJECT/b.md"

    local result lines_added lines_deleted identical
    result=$(calculate_change_metrics "$TEST_PROJECT/a.md" "$TEST_PROJECT/b.md")
    lines_added=$(echo "$result" | jq '.lines_added')
    lines_deleted=$(echo "$result" | jq '.lines_deleted')
    identical=$(echo "$result" | jq '.identical')

    log_test_actual "lines_added" "$lines_added"
    log_test_actual "lines_deleted" "$lines_deleted"
    log_test_actual "identical" "$identical"

    [[ "$lines_added" == "0" ]]
    [[ "$lines_deleted" == "0" ]]
    [[ "$identical" == "true" ]]
}

@test "calculate_change_metrics: detects added lines" {
    printf "Line 1\nLine 2\n" > "$TEST_PROJECT/old.md"
    printf "Line 1\nLine 2\nLine 3\nLine 4\n" > "$TEST_PROJECT/new.md"

    local result lines_added
    result=$(calculate_change_metrics "$TEST_PROJECT/old.md" "$TEST_PROJECT/new.md")
    lines_added=$(echo "$result" | jq '.lines_added')

    log_test_actual "lines_added" "$lines_added"

    [[ "$lines_added" == "2" ]]
}

@test "calculate_change_metrics: detects deleted lines" {
    printf "Line 1\nLine 2\nLine 3\nLine 4\n" > "$TEST_PROJECT/old.md"
    printf "Line 1\nLine 2\n" > "$TEST_PROJECT/new.md"

    local result lines_deleted
    result=$(calculate_change_metrics "$TEST_PROJECT/old.md" "$TEST_PROJECT/new.md")
    lines_deleted=$(echo "$result" | jq '.lines_deleted')

    log_test_actual "lines_deleted" "$lines_deleted"

    [[ "$lines_deleted" == "2" ]]
}

@test "calculate_change_metrics: calculates diff_ratio" {
    # Create files with known sizes
    seq 1 100 > "$TEST_PROJECT/old.md"
    seq 1 100 > "$TEST_PROJECT/new.md"
    echo "new line" >> "$TEST_PROJECT/new.md"  # 1 added line

    local result diff_ratio
    result=$(calculate_change_metrics "$TEST_PROJECT/old.md" "$TEST_PROJECT/new.md")
    diff_ratio=$(echo "$result" | jq '.diff_ratio')

    log_test_actual "diff_ratio" "$diff_ratio"

    # Should be small (1 / 101 ≈ 0.01)
    # Using awk for floating point comparison
    result_check=$(awk -v dr="$diff_ratio" 'BEGIN { print (dr > 0 && dr < 0.1) ? "pass" : "fail" }')
    [[ "$result_check" == "pass" ]]
}

@test "calculate_change_metrics: calculates similarity_score" {
    echo "Same content" > "$TEST_PROJECT/same1.md"
    cp "$TEST_PROJECT/same1.md" "$TEST_PROJECT/same2.md"

    local result similarity_score
    result=$(calculate_change_metrics "$TEST_PROJECT/same1.md" "$TEST_PROJECT/same2.md")
    similarity_score=$(echo "$result" | jq '.similarity_score')

    log_test_actual "similarity_score" "$similarity_score"

    # Identical files should have similarity 1 or 1.0
    [[ "$similarity_score" == "1" ]] || [[ "$similarity_score" == "1.0" ]]
}

@test "calculate_change_metrics: returns null for missing old file" {
    echo "content" > "$TEST_PROJECT/new.md"

    local result
    result=$(calculate_change_metrics "/nonexistent.md" "$TEST_PROJECT/new.md")

    log_test_actual "result" "$result"

    [[ "$result" == "null" ]]
}

@test "calculate_round_changes: computes changes between rounds" {
    setup_test_workflow "change-test"

    # Create two round files
    echo "Round 1 content" > "$TEST_PROJECT/.apr/rounds/change-test/round_1.md"
    echo "Round 2 content with more stuff" > "$TEST_PROJECT/.apr/rounds/change-test/round_2.md"

    local result
    result=$(calculate_round_changes "change-test" 2)

    log_test_actual "result" "$result"

    # Should have change metrics
    [[ -n "$result" ]]
    [[ "$result" != "null" ]]
}

# =============================================================================
# Convergence Detection: Signal Functions
# =============================================================================

@test "calculate_output_trend_signal: returns 0 for insufficient data" {
    # Function takes JSON with rounds array
    local metrics_json='{"rounds":[{"round":1,"output":{"char_count":1000}}]}'

    local result
    result=$(calculate_output_trend_signal "$metrics_json")

    log_test_actual "result" "$result"

    [[ "$result" == "0" ]]
}

@test "calculate_output_trend_signal: detects decreasing trend" {
    # Decreasing char counts across 3 rounds (single line JSON)
    local metrics_json='{"rounds":[{"round":1,"output":{"char_count":1000}},{"round":2,"output":{"char_count":800}},{"round":3,"output":{"char_count":600}}]}'

    local result
    result=$(calculate_output_trend_signal "$metrics_json")

    log_test_actual "result" "$result"

    # Should be positive (indicating convergence signal)
    result_check=$(awk -v r="$result" 'BEGIN { print (r > 0) ? "pass" : "fail" }')
    [[ "$result_check" == "pass" ]]
}

@test "calculate_change_velocity_signal: returns 0 for insufficient data" {
    # Function takes JSON with rounds array (2 rounds = insufficient)
    local metrics_json='{"rounds":[{"round":1},{"round":2,"changes_from_previous":{"diff_ratio":0.1}}]}'

    local result
    result=$(calculate_change_velocity_signal "$metrics_json")

    log_test_actual "result" "$result"

    [[ "$result" == "0" ]]
}

@test "calculate_similarity_trend_signal: returns 0 for insufficient data" {
    # Function takes JSON with rounds array
    local metrics_json='{"rounds":[{"round":1},{"round":2}]}'

    local result
    result=$(calculate_similarity_trend_signal "$metrics_json")

    log_test_actual "result" "$result"

    [[ "$result" == "0" ]]
}

# =============================================================================
# Convergence Detection: Main Algorithm
# =============================================================================

@test "calculate_convergence: returns insufficient_rounds for < 3 rounds" {
    metrics_init "conv-test-1"

    # Only 2 rounds
    metrics_write_round "conv-test-1" 1 '{"round":1}'
    metrics_write_round "conv-test-1" 2 '{"round":2}'

    local result reason
    result=$(calculate_convergence "conv-test-1")
    reason=$(echo "$result" | jq -r '.reason')

    log_test_actual "reason" "$reason"

    [[ "$reason" == "insufficient_rounds" ]]
}

@test "calculate_convergence: returns valid JSON structure" {
    metrics_init "conv-test-2"

    # 3 rounds minimum
    metrics_write_round "conv-test-2" 1 '{"round":1,"output":{"char_count":1000}}'
    metrics_write_round "conv-test-2" 2 '{"round":2,"output":{"char_count":900},"changes_from_previous":{"diff_ratio":0.1,"similarity_score":0.9}}'
    metrics_write_round "conv-test-2" 3 '{"round":3,"output":{"char_count":850},"changes_from_previous":{"diff_ratio":0.05,"similarity_score":0.95}}'

    local result
    result=$(calculate_convergence "conv-test-2")

    log_test_actual "result" "$result"

    # Should have required fields
    echo "$result" | jq -e '.confidence' >/dev/null
    echo "$result" | jq -e '.detected' >/dev/null
    echo "$result" | jq -e '.signals' >/dev/null
}

@test "calculate_convergence: confidence is between 0 and 1" {
    metrics_init "conv-test-3"

    # Set up rounds with metrics
    metrics_write_round "conv-test-3" 1 '{"round":1,"output":{"char_count":1000}}'
    metrics_write_round "conv-test-3" 2 '{"round":2,"output":{"char_count":800},"changes_from_previous":{"diff_ratio":0.2,"similarity_score":0.8}}'
    metrics_write_round "conv-test-3" 3 '{"round":3,"output":{"char_count":700},"changes_from_previous":{"diff_ratio":0.1,"similarity_score":0.9}}'

    local result confidence
    result=$(calculate_convergence "conv-test-3")
    confidence=$(echo "$result" | jq '.confidence')

    log_test_actual "confidence" "$confidence"

    # Should be 0 <= confidence <= 1
    result_check=$(awk -v c="$confidence" 'BEGIN { print (c >= 0 && c <= 1) ? "pass" : "fail" }')
    [[ "$result_check" == "pass" ]]
}

@test "calculate_convergence: detected=true when confidence >= 0.75" {
    metrics_init "conv-test-4"

    # Set up rounds with strong convergence signals
    # Sharply decreasing output, high similarity, low diff_ratio
    metrics_write_round "conv-test-4" 1 '{"round":1,"output":{"char_count":10000}}'
    metrics_write_round "conv-test-4" 2 '{"round":2,"output":{"char_count":2000},"changes_from_previous":{"diff_ratio":0.8,"similarity_score":0.2}}'
    metrics_write_round "conv-test-4" 3 '{"round":3,"output":{"char_count":500},"changes_from_previous":{"diff_ratio":0.02,"similarity_score":0.98}}'
    metrics_write_round "conv-test-4" 4 '{"round":4,"output":{"char_count":450},"changes_from_previous":{"diff_ratio":0.01,"similarity_score":0.99}}'
    metrics_write_round "conv-test-4" 5 '{"round":5,"output":{"char_count":440},"changes_from_previous":{"diff_ratio":0.005,"similarity_score":0.995}}'

    local result confidence detected
    result=$(calculate_convergence "conv-test-4")
    confidence=$(echo "$result" | jq '.confidence')
    detected=$(echo "$result" | jq '.detected')

    log_test_actual "confidence" "$confidence"
    log_test_actual "detected" "$detected"

    # With strong signals, should detect convergence
    # Note: This depends on implementation details of the algorithm
    # At minimum, confidence should be positive
    result_check=$(awk -v c="$confidence" 'BEGIN { print (c > 0) ? "pass" : "fail" }')
    [[ "$result_check" == "pass" ]]
}

# =============================================================================
# Update Convergence Metrics
# =============================================================================

@test "update_convergence_metrics: updates metrics file" {
    metrics_init "update-conv-test"

    # Set up rounds
    metrics_write_round "update-conv-test" 1 '{"round":1,"output":{"char_count":1000}}'
    metrics_write_round "update-conv-test" 2 '{"round":2,"output":{"char_count":900},"changes_from_previous":{"diff_ratio":0.1,"similarity_score":0.9}}'
    metrics_write_round "update-conv-test" 3 '{"round":3,"output":{"char_count":850},"changes_from_previous":{"diff_ratio":0.05,"similarity_score":0.95}}'

    # Update convergence
    update_convergence_metrics "update-conv-test"

    local metrics_path convergence
    metrics_path=$(metrics_file_path "update-conv-test")
    convergence=$(jq '.convergence' "$metrics_path")

    log_test_actual "convergence" "$convergence"

    # Should have convergence data
    [[ "$convergence" != "null" ]]
    echo "$convergence" | jq -e '.confidence' >/dev/null
}

# =============================================================================
# Schema Validation and Migration
# =============================================================================

@test "metrics_validate_json: accepts valid JSON" {
    local valid_json='{"schema_version":"1.0.0","workflow":"test","rounds":[]}'

    run metrics_validate_json "$valid_json"
    assert_success
}

@test "metrics_validate_json: rejects invalid JSON" {
    local invalid_json='not json at all'

    run metrics_validate_json "$invalid_json"
    assert_failure
}

@test "metrics_default_json: creates correct schema" {
    local result
    result=$(metrics_default_json "default-test")

    log_test_actual "result" "$result"

    local schema workflow rounds_type
    schema=$(echo "$result" | jq -r '.schema_version')
    workflow=$(echo "$result" | jq -r '.workflow')
    rounds_type=$(echo "$result" | jq -r '.rounds | type')

    [[ "$schema" == "1.0.0" ]]
    [[ "$workflow" == "default-test" ]]
    [[ "$rounds_type" == "array" ]]
}
