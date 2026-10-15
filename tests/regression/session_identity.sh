#!/usr/bin/env bash
# Deterministic identity contract checks against APR's production functions.
# Run directly or through tests/unit/test_session_identity.bats. No Oracle,
# browser, network, wall-clock sleeps, or BATS dependencies are required here.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
APR_SOURCE=${APR_SCRIPT:-"$ROOT/apr"}
[[ -r "$APR_SOURCE" ]] || { echo "APR source not readable: $APR_SOURCE" >&2; exit 1; }
command -v jq >/dev/null || { echo 'jq is required' >&2; exit 1; }

# Isolate the real functions, rather than mock/reimplement the resolver or run
# APR's CLI entry point. Top-level closing braces delimit these shell functions.
for name in oracle_session_snapshot resolve_oracle_session_id oracle_session_for_run; do
    definition=$(awk -v name="$name" '
        $0 == name "() {" { inside=1 }
        inside { print }
        inside && $0 == "}" { exit }
    ' "$APR_SOURCE")
    [[ -n "$definition" ]] || { echo "Missing production function: $name" >&2; exit 1; }
    eval "$definition"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/apr-session-identity.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
# All timestamps are deterministic, including dates written by snapshot().
NOW=1792108800
CREATED=2026-10-16T00:00:00.123Z
date() {
    if [[ "$*" == '+%s' ]]; then printf '%s\n' "$NOW"; else command date "$@"; fi
}

reset_case() {
    local name="$1"
    CASE="$TMP/$name"
    export ORACLE_HOME_DIR="$CASE/oracle home"
    export APR_LEDGER_DIR="$CASE/project with spaces/.apr/runs/Site.OVERVIEW_Independent/round_7.ABC123"
    export APR_RUN_OUTPUT="$APR_LEDGER_DIR/output.md"
    mkdir -p "$ORACLE_HOME_DIR/sessions" "$APR_LEDGER_DIR"
    MARKER="$APR_LEDGER_DIR/oracle-session-start"
}

session() {
    local id="$1" out="${2:-$APR_RUN_OUTPUT}" created="${3:-$CREATED}"
    mkdir -p "$ORACLE_HOME_DIR/sessions/$id"
    command jq -nc --arg id "$id" --arg out "$out" --arg created "$created" '
        {id:$id,createdAt:$created,status:"completed",mode:"browser",
         options:{writeOutputPath:$out},browser:{}}
    ' > "$ORACLE_HOME_DIR/sessions/$id/meta.json"
}

expect() {
    local want="$1" actual
    # The unknown case must return success plus no identifier, not an error
    # that aborts APR under errexit or a guessed requested slug.
    actual=$(oracle_session_for_run)
    [[ "$actual" == "$want" ]] || {
        printf 'Expected identity <%s>, got <%s>\n' "$want" "$actual" >&2
        return 1
    }
}

case_normalized_collision() {
    reset_case normalized
    session apr-site-overview-independen-round /old/output.md
    oracle_session_snapshot "$MARKER"
    # A different round/workflow with the same five normalized words appears
    # after the snapshot too; both names and creation times are plausible.
    session apr-site-overview-independen-round-2 /other/current/output.md
    session apr-site-overview-independen-round-12
    expect apr-site-overview-independen-round-12
}

case_preexisting_rewritten() {
    reset_case preexisting
    session apr-site-overview-independen-round
    oracle_session_snapshot "$MARKER"
    # Even freshly rewritten, destination-matching metadata cannot turn a
    # session already present before launch into this invocation's session.
    session apr-site-overview-independen-round
    touch "$ORACLE_HOME_DIR/sessions/apr-site-overview-independen-round/meta.json"
    expect ''
}

case_creation_evidence() {
    local stamp
    for stamp in 2020-01-01T00:00:00Z 2099-01-01T00:00:00Z not-a-timestamp; do
        reset_case "creation-$stamp"
        oracle_session_snapshot "$MARKER"
        session apr-untrusted-round "$APR_RUN_OUTPUT" "$stamp"
        expect ''
    done
    reset_case missing-created
    oracle_session_snapshot "$MARKER"
    session apr-untrusted-round
    command jq 'del(.createdAt)' "$ORACLE_HOME_DIR/sessions/apr-untrusted-round/meta.json" > "$CASE/meta.next"
    mv "$CASE/meta.next" "$ORACLE_HOME_DIR/sessions/apr-untrusted-round/meta.json"
    expect ''
}

case_destination_and_id() {
    local change
    for change in 'del(.options.writeOutputPath)' '.options.writeOutputPath = "output.md"' '.options.writeOutputPath += ".other"' '.id = "apr-another-round"' 'del(.id)'; do
        reset_case "binding-${change//\//_}"
        oracle_session_snapshot "$MARKER"
        session apr-current-round
        command jq "$change" "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json" > "$CASE/meta.next"
        mv "$CASE/meta.next" "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json"
        expect ''
    done
}

case_ambiguous() {
    reset_case ambiguous
    oracle_session_snapshot "$MARKER"
    session apr-current-round
    session apr-current-round-2
    expect ''
}

case_retry() {
    reset_case retry
    oracle_session_snapshot "$MARKER"
    session apr-normalized-round
    expect apr-normalized-round
    # Retry keeps its private destination, but snapshots the previous attempt.
    # The clock deliberately does not tick: timestamps alone are insufficient.
    oracle_session_snapshot "$MARKER"
    expect ''
    session apr-normalized-round-2
    expect apr-normalized-round-2
}

case_interleaved_producers() {
    reset_case interleaved
    local a="$APR_LEDGER_DIR" b="$CASE/project with spaces/.apr/runs/Other/round_8.DEF456"
    mkdir -p "$b"
    # Both launches take inventories before either session is allocated.
    oracle_session_snapshot "$a/oracle-session-start"
    oracle_session_snapshot "$b/oracle-session-start"
    session apr-site-overview-independen-round "$b/output.md"
    session apr-site-overview-independen-round-2 "$a/output.md"
    # Resolve concurrently, with opposite allocation order and equal dates.
    (oracle_session_for_run > "$CASE/a.id") &
    local pid_a=$!
    (APR_LEDGER_DIR="$b" APR_RUN_OUTPUT="$b/output.md" oracle_session_for_run > "$CASE/b.id") &
    local pid_b=$!
    wait "$pid_a"
    wait "$pid_b"
    [[ "$(cat "$CASE/a.id")" == apr-site-overview-independen-round-2 ]]
    [[ "$(cat "$CASE/b.id")" == apr-site-overview-independen-round ]]
}

case_snapshot_changes_during_scan() {
    reset_case snapshot-race
    oracle_session_snapshot "$MARKER"
    session apr-current-round
    # Deterministically interleave a retry after the scan's metadata read.
    # Use a file side effect since resolution runs in command substitution.
    jq() {
        command jq "$@"
        printf '%s\napr-current-round\n' "$NOW" > "$MARKER.next"
        mv "$MARKER.next" "$MARKER"
    }
    expect ''
    unset -f jq
    session apr-current-round-2
    expect apr-current-round-2
}

case_atomic_metadata_publication() {
    reset_case publication
    oracle_session_snapshot "$MARKER"
    mkdir -p "$ORACLE_HOME_DIR/sessions/apr-current-round"
    printf '{"id":' > "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json"
    expect ''
    # Oracle writes metadata to a temporary file and atomically renames it.
    session apr-temporary-round
    command jq '.id = "apr-current-round"' "$ORACLE_HOME_DIR/sessions/apr-temporary-round/meta.json" > "$CASE/meta.next"
    rm -rf "$ORACLE_HOME_DIR/sessions/apr-temporary-round"
    mv "$CASE/meta.next" "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json"
    expect apr-current-round
}

case_symlinks() {
    reset_case symlink-directory
    oracle_session_snapshot "$MARKER"
    session apr-current-round
    mv "$ORACLE_HOME_DIR/sessions/apr-current-round" "$CASE/target"
    ln -s "$CASE/target" "$ORACLE_HOME_DIR/sessions/apr-current-round"
    expect ''
    reset_case symlink-metadata
    oracle_session_snapshot "$MARKER"
    session apr-current-round
    mv "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json" "$CASE/meta.target"
    ln -s "$CASE/meta.target" "$ORACLE_HOME_DIR/sessions/apr-current-round/meta.json"
    expect ''
}

case_invalid_inventory() {
    reset_case inventory
    session apr-current-round
    expect ''
    : > "$MARKER"
    expect ''
    printf 'not-an-epoch\n' > "$MARKER"
    expect ''
}

case_unsafe_identity() {
    reset_case unsafe
    oracle_session_snapshot "$MARKER"
    session 'apr.current.round'
    session '--harvest'
    expect ''
}

cases=(normalized_collision preexisting_rewritten creation_evidence destination_and_id
       ambiguous retry interleaved_producers snapshot_changes_during_scan
       atomic_metadata_publication symlinks invalid_inventory unsafe_identity)
if (( $# > 0 )); then
    requested="$1"
    found=false
    for name in "${cases[@]}"; do [[ "$name" != "$requested" ]] || found=true; done
    [[ "$found" == true ]] || { echo "Unknown case: $requested" >&2; exit 2; }
    cases=("$requested")
fi
printf '1..%s\n' "${#cases[@]}"
i=0
for name in "${cases[@]}"; do
    # Deliberately NOT an if/&& condition: keep errexit active inside each
    # case so any failed assertion terminates instead of being masked later.
    ( "case_$name" )
    i=$((i + 1))
    printf 'ok %s - %s\n' "$i" "$name"
done
