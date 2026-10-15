#!/usr/bin/env bats
# Keep the deterministic shell contract suite in the regular unit-test run.
# It extracts production functions; no copied resolver implementation is used.

run_identity_case() {
    run env APR_SCRIPT="$BATS_TEST_DIRNAME/../../apr" \
        bash "$BATS_TEST_DIRNAME/../regression/session_identity.sh" "$1"
    if [[ "$status" -ne 0 ]]; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}

@test "session identity: normalized collisions use the exact private destination" {
    run_identity_case normalized_collision
}

@test "session identity: rewritten pre-launch sessions remain ineligible" {
    run_identity_case preexisting_rewritten
}

@test "session identity: old future missing and malformed creation evidence is refused" {
    run_identity_case creation_evidence
}

@test "session identity: metadata must bind both output destination and session ID" {
    run_identity_case destination_and_id
}

@test "session identity: ambiguous candidates never select the newest session" {
    run_identity_case ambiguous
}

@test "session identity: same-second retries exclude earlier producer attempts" {
    run_identity_case retry
}

@test "session identity: interleaved producers resolve concurrently without cross-attachment" {
    run_identity_case interleaved_producers
}

@test "session identity: a snapshot replacement during metadata scanning invalidates the result" {
    run_identity_case snapshot_changes_during_scan
}

@test "session identity: partial metadata is refused until atomic publication" {
    run_identity_case atomic_metadata_publication
}

@test "session identity: symlinked session directories and metadata are refused" {
    run_identity_case symlinks
}

@test "session identity: missing empty and malformed inventories fail closed" {
    run_identity_case invalid_inventory
}

@test "session identity: unsafe session identifiers cannot become attachment targets" {
    run_identity_case unsafe_identity
}
