#!/usr/bin/env bash
# Offline CLI regression tests for scripts/recover_oracle_run.sh.
# Uses the actual APR resolver, ledger validator and output validation policy.
# Oracle is a deterministic process fixture with realistic meta.json and
# transcript output; it refuses every invocation other than a bound harvest.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
recover="$root/scripts/recover_oracle_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/apr-recovery-tests.XXXXXX")
readonly root recover work
real_date=$(command -v date)
export REAL_DATE="$real_date"

setup_case() {
    export CASE_ROOT="$work/$1"
    mkdir -p "$CASE_ROOT/project with spaces" "$CASE_ROOT/bin"
    cd "$CASE_ROOT/project with spaces"
    export HOME="$CASE_ROOT/home" ORACLE_HOME_DIR="$CASE_ROOT/oracle home" APR_NO_NPX=1
    mkdir -p "$HOME" "$ORACLE_HOME_DIR/sessions"
    export PATH="$CASE_ROOT/bin:$PATH"
    cat > "$CASE_ROOT/bin/date" <<'DATE'
#!/usr/bin/env bash
case "$*" in
    +%s) printf '%s\n' 1792065600 ;;
    '-u +%Y-%m-%dT%H:%M:%SZ') printf '%s\n' 2026-10-15T12:00:00Z ;;
    *) exec "$REAL_DATE" "$@" ;;
esac
DATE
    chmod +x "$CASE_ROOT/bin/date"
    workflow="Site.OVERVIEW_Independent-$(printf 'LongName%.0s' {1..20})"
    id=round_2.ABC123
    target="run:$workflow:$id"
    export RUN_DIR="$PWD/.apr/runs/$workflow/$id" SESSION_ID=apr-site-overview-independen-round-3
    mkdir -p "$RUN_DIR" ".apr/rounds/$workflow"
    export SESSION_META="$ORACLE_HOME_DIR/sessions/$SESSION_ID/meta.json"
    mkdir -p "${SESSION_META%/*}"
    jq -nc --arg id "$SESSION_ID" --arg out "$RUN_DIR/output.md" --arg cwd "$PWD" '
        {id:$id,createdAt:"2026-10-15T12:00:00.000Z",startedAt:"2026-10-15T12:00:00.000Z",
         status:"completed",mode:"browser",cwd:$cwd,promptPreview:"Review the specification.",
         options:{slug:$id,model:"gpt-5.2-pro",mode:"browser",writeOutputPath:$out,waitPreference:true},
         browser:{runtime:{conversationId:"conversation-bound-to-this-run",chromeTargetId:"target-3"}},
         lifecycle:{reattachCommand:("oracle session "+$id)}}' > "$SESSION_META"
    # Both earlier sessions used the same normalized base. The previous retry
    # also used this private output destination and has a freshly rewritten
    # timestamp; the pre-launch inventory must still exclude it.
    local previous
    for previous in apr-site-overview-independen-round apr-site-overview-independen-round-2; do
        mkdir -p "$ORACLE_HOME_DIR/sessions/$previous"
        jq --arg id "$previous" '.id=$id | .options.slug=$id' "$SESSION_META" > "$ORACLE_HOME_DIR/sessions/$previous/meta.json"
    done
    printf '%s\n' 1792065600 apr-site-overview-independen-round apr-site-overview-independen-round-2 > "$RUN_DIR/oracle-session-start"
    jq -nc --arg workflow "$workflow" --arg id "$id" --arg out "$RUN_DIR/output.md" '
        ("a"*64) as $hash |
        [{role:"readme",path:"README.md",basename:"README.md",bytes:128,sha256:$hash,included:true,reason:"required",skip_reason:null},
         {role:"spec",path:"SPEC.md",basename:"SPEC.md",bytes:256,sha256:$hash,included:true,reason:"required",skip_reason:null},
         {role:"implementation",path:"IMPL.md",basename:"IMPL.md",bytes:512,sha256:$hash,included:true,reason:"optional",skip_reason:null}] as $files |
        {schema_version:"1.0.0",run_id:$id,workflow:$workflow,round:2,slug:("apr-"+$workflow+"-round-2-with-impl"),
         state:"failed",started_at:"2026-10-15T12:00:00Z",finished_at:"2026-10-15T12:01:00Z",duration_ms:60000,
         config:{path:(".apr/workflows/"+$workflow+".yaml"),sha256:$hash},
         inputs:{status:"complete",files:($files|map(.inclusion_reason=.reason|del(.reason))),manifest:{v:1,files:$files},prompt_hash:$hash},
         invocation:{engine:"browser",model:"gpt-5.2-pro",thinking_time:"heavy",remote_host:null,
            oracle_flags_used:["--slug","--write-output"],oracle_args:["--write-output",$out]},
         execution:{attempts_count:2,retries_count:1,busy_wait_count:0,busy_wait_total_ms:0,retry_reasons:["oracle_error"]},
         outcome:{ok:false,code:"internal_error",exit_code:1,oracle_exit_code:0,output_path:$out}}
    ' > "$RUN_DIR/terminal.meta.json"
    {
        printf '# Partial producer review\n\n'
        for n in {1..80}; do printf 'Recommendation %s from the incomplete producer review.\n' "$n"; done
        printf 'The next important recommendation is incomplet'
    } > "$RUN_DIR/output.md"
    cp "$RUN_DIR/output.md" ".apr/rounds/$workflow/round_2.md"
    cp "$RUN_DIR/output.md" "$CASE_ROOT/original-output.md"
    cp "$RUN_DIR/terminal.meta.json" "$CASE_ROOT/original-terminal.json"
    {
        printf '# Complete harvested review\n\n'
        for n in {1..80}; do printf 'Recommendation %s from the correct bound Oracle session.\n' "$n"; done
        printf '\nAll recommendations are complete.\n'
    } > "$CASE_ROOT/expected.md"
    export HARVEST_MODE=complete
    cat > "$CASE_ROOT/bin/oracle" <<'ORACLE'
#!/usr/bin/env bash
set -euo pipefail
jq -nc --args '$ARGS.positional' -- "$@" >> "$CASE_ROOT/calls.jsonl"
[[ "$#" -eq 5 && "$1" == session && "$2" == "$SESSION_ID" && "$3" == --harvest && "$4" == --write-output ]] || exit 91
out="$5"
[[ "$out" == "$RUN_DIR"/recovery.*/harvest.md ]] || exit 92
reported_id="$SESSION_ID" state=completed integrity=matched
case "$HARVEST_MODE" in
    wrong_banner) reported_id=apr-another-round ;;
    running) state=running ;;
    unverified) integrity=unverified ;;
esac
if [[ "$HARVEST_MODE" != missing_banner ]]; then
    printf '\033[34mSession: %s\033[0m\nTarget: target-3\nState: %s\nModel: GPT Pro\n' "$reported_id" "$state"
    printf 'URL: https://chatgpt.com/c/conversation-bound-to-this-run\nAssistant turns: 1\nCapture identity: %s\n' "$integrity"
    printf 'Signals: stop=no send=yes\nLast user: Review the specification.\n'
fi
printf '%s\n' '---'
printf 'Reading the bound browser conversation.\n' >&2
case "$HARVEST_MODE" in
    failed)
        printf 'Partial failed harvest.\n' > "$out"
        printf 'Browser transport interrupted.\n' >&2
        exit 7 ;;
    partial) cp "$RUN_DIR/output.md" "$out" ;;
    rebound)
        jq '.options.writeOutputPath="/another/run/output.md"' "$SESSION_META" > "$CASE_ROOT/rebound.json"
        cp "$CASE_ROOT/rebound.json" "$SESSION_META"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    recreated)
        jq '.createdAt="2026-10-15T12:00:00.001Z"' "$SESSION_META" > "$CASE_ROOT/recreated.json"
        cp "$CASE_ROOT/recreated.json" "$SESSION_META"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    conversation_changed)
        jq '.browser.runtime.conversationId="another-conversation"' "$SESSION_META" > "$CASE_ROOT/conversation.json"
        cp "$CASE_ROOT/conversation.json" "$SESSION_META"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    new_target)
        jq '.browser.runtime.chromeTargetId="recovered-new-chrome-target"' "$SESSION_META" > "$CASE_ROOT/new-target.json"
        cp "$CASE_ROOT/new-target.json" "$SESSION_META"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    marker_changed)
        printf 'concurrent-attempt\n' >> "$RUN_DIR/oracle-session-start"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    terminal_changed)
        printf '\n' >> "$RUN_DIR/terminal.meta.json"
        cp "$CASE_ROOT/expected.md" "$out" ;;
    symlink) ln -s "$CASE_ROOT/expected.md" "$out" ;;
    blocked)
        : > "$CASE_ROOT/harvest-entered"
        # Handshake, not a guessed duration: the test releases this producer.
        for n in {1..500}; do
            [[ ! -e "$CASE_ROOT/release-harvest" ]] || break
            sleep 0.01
        done
        [[ -e "$CASE_ROOT/release-harvest" ]] || exit 93
        cp "$CASE_ROOT/expected.md" "$out" ;;
    complete|wrong_banner|running|unverified|missing_banner) cp "$CASE_ROOT/expected.md" "$out" ;;
    *) exit 94 ;;
esac
# Oracle persists fresh harvest metadata as part of the real operation. The
# logical conversation stays stable even when Chrome was reopened in a new tab.
jq --arg state "$state" '
    (.browser.runtime.conversationId // "conversation-bound-to-this-run") as $conversation |
    .browser.harvest={conversationId:$conversation,url:("https://chatgpt.com/c/"+$conversation),state:$state}
' "$SESSION_META" > "$CASE_ROOT/harvest-meta.json"
cp "$CASE_ROOT/harvest-meta.json" "$SESSION_META"
cat "$CASE_ROOT/expected.md"
ORACLE
    chmod +x "$CASE_ROOT/bin/oracle"
}

invoke() {
    local expected="$1"; shift
    local status=0
    "$recover" "${@:-$target}" > "$CASE_ROOT/result.json" 2> "$CASE_ROOT/diagnostics.log" || status=$?
    if [[ "$status" -ne "$expected" ]]; then
        cat "$CASE_ROOT/diagnostics.log" >&2
        printf 'Expected status %s; got %s\n' "$expected" "$status" >&2
        return 1
    fi
}

unchanged() {
    cmp -s "$RUN_DIR/output.md" "$CASE_ROOT/original-output.md"
    cmp -s ".apr/rounds/$workflow/round_2.md" "$CASE_ROOT/original-output.md"
    cmp -s "$RUN_DIR/terminal.meta.json" "$CASE_ROOT/original-terminal.json"
}

no_harvest() { [[ ! -e "$CASE_ROOT/calls.jsonl" && ! -e "$RUN_DIR/recovery.json" ]]; }

success() {
    invoke 0
    jq -se --arg session "$SESSION_ID" 'length==1 and (.[0]|.ok and .data.session_id==$session and (.data.already_recovered|not))' "$CASE_ROOT/result.json" >/dev/null
    local recovered receipt parent
    recovered=$(jq -r .data.output_file "$CASE_ROOT/result.json")
    receipt=$(jq -r .data.receipt_file "$CASE_ROOT/result.json")
    cmp -s "$recovered" "$CASE_ROOT/expected.md"
    parent="${recovered%/*}"
    [[ ! "$recovered" -ef "$parent/harvest.md" ]]
    grep -q "Session: $SESSION_ID" "$parent/oracle.stdout.log"
    grep -q 'Capture identity: matched' "$parent/oracle.stdout.log"
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 1 ]]
    jq -e --arg session "$SESSION_ID" '.[0]=="session" and .[1]==$session and .[2]=="--harvest"' "$CASE_ROOT/calls.jsonl" >/dev/null
    jq -e --arg dest "$RUN_DIR/output.md" '.session.writeOutputPath==$dest and .round==2 and .output.bytes>2048' "$receipt" >/dev/null
    unchanged
}

idempotent() {
    success
    # Simulate Oracle pruning without deleting any fixture/evidence.
    mv "$ORACLE_HOME_DIR/sessions" "$ORACLE_HOME_DIR/sessions.pruned"
    invoke 0
    jq -e '.data.already_recovered' "$CASE_ROOT/result.json" >/dev/null
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 1 ]]
    unchanged
}

ambiguous() {
    local other=apr-site-overview-independen-round-4
    mkdir -p "$ORACLE_HOME_DIR/sessions/$other"
    jq --arg id "$other" '.id=$id' "$SESSION_META" > "$ORACLE_HOME_DIR/sessions/$other/meta.json"
    invoke 4
    no_harvest
    unchanged
}

stale() {
    printf '%s\n' "$SESSION_ID" >> "$RUN_DIR/oracle-session-start"
    invoke 4
    no_harvest
    unchanged
}

unbound() {
    jq '.options.writeOutputPath="/another/round.md"' "$SESSION_META" > "$CASE_ROOT/other.json"
    cp "$CASE_ROOT/other.json" "$SESSION_META"
    invoke 4
    no_harvest
    unchanged
}

invalid_created() {
    jq '.createdAt="2026-10-15T12:00:01.000Z"' "$SESSION_META" > "$CASE_ROOT/future.json"
    cp "$CASE_ROOT/future.json" "$SESSION_META"
    invoke 4
    no_harvest
    unchanged
}

partial() {
    export HARVEST_MODE=partial
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    [[ $(find "$RUN_DIR" -name harvest.md | wc -l) -eq 1 ]]
    unchanged
}

failed() {
    export HARVEST_MODE=failed
    invoke 7
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    local diagnostic
    diagnostic=$(find "$RUN_DIR" -name oracle.stderr.log)
    grep -q 'Browser transport interrupted' "$diagnostic"
    unchanged
    # A failed harvest may be retried deliberately without creating a review.
    export HARVEST_MODE=complete
    invoke 0
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 2 ]]
    unchanged
}

rebound() {
    export HARVEST_MODE=rebound
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

recreated() {
    export HARVEST_MODE=recreated
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

conversation_changed() {
    export HARVEST_MODE=conversation_changed
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

new_target() {
    export HARVEST_MODE=new_target
    success
}

conversationless() {
    jq 'del(.browser.runtime.conversationId)' "$SESSION_META" > "$CASE_ROOT/no-conversation.json"
    cp "$CASE_ROOT/no-conversation.json" "$SESSION_META"
    invoke 4
    no_harvest
    unchanged
}

url_only() {
    jq 'del(.browser.runtime.conversationId) | .browser.runtime.tabUrl="https://chatgpt.com/c/conversation-bound-to-this-run"' \
        "$SESSION_META" > "$CASE_ROOT/url-only.json"
    cp "$CASE_ROOT/url-only.json" "$SESSION_META"
    success
}

conflicting_conversation() {
    jq '.browser.harvest.url="https://chatgpt.com/c/a-different-conversation"' "$SESSION_META" > "$CASE_ROOT/conflict.json"
    cp "$CASE_ROOT/conflict.json" "$SESSION_META"
    invoke 4
    no_harvest
    unchanged
}

running() {
    export HARVEST_MODE=running
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

unverified() {
    export HARVEST_MODE=unverified
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

wrong_banner() {
    export HARVEST_MODE=wrong_banner
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

missing_banner() {
    export HARVEST_MODE=missing_banner
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

body_banner() {
    printf '\nSession: quoted-other-session\nState: running\nCapture identity: mismatch\nThese are quoted examples, not the harvest summary.\n' >> "$CASE_ROOT/expected.md"
    success
}

marker_changed() {
    export HARVEST_MODE=marker_changed
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

terminal_changed() {
    export HARVEST_MODE=terminal_changed
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    cmp -s "$RUN_DIR/output.md" "$CASE_ROOT/original-output.md"
}

symlink() {
    export HARVEST_MODE=symlink
    invoke 4
    [[ ! -e "$RUN_DIR/recovery.json" ]]
    unchanged
}

corrupt_receipt() {
    success
    local recovered
    recovered=$(jq -r .data.output_file "$CASE_ROOT/result.json")
    chmod 600 "$recovered"
    # Same byte count and still structurally valid: only hash verification
    # distinguishes this from the accepted answer.
    { printf '!'; tail -c +2 "$recovered"; } > "$CASE_ROOT/tampered.md"
    cp "$CASE_ROOT/tampered.md" "$recovered"
    invoke 4
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 1 ]]
    unchanged
}

unsafe_reference() {
    invoke 2 'run:../../escape:round_2.ABC123'
    invoke 2 "run:$workflow:round_02.ABC123"
    invoke 2 'run:round_2.ABC123'
    no_harvest
    unchanged
}

redirected_run() {
    mv "$RUN_DIR" "$RUN_DIR.saved"
    ln -s "$RUN_DIR.saved" "$RUN_DIR"
    invoke 4
    no_harvest
}

active_lock() {
    command -v flock >/dev/null 2>&1 || { printf 'flock required for lock contention case\n' >&2; return 77; }
    mkdir -p .apr/.locks
    exec 8>>".apr/.locks/${workflow}_round_2.lock"
    flock -x 8
    invoke 12
    no_harvest
    exec 8>&-
    success
}

concurrent() {
    command -v flock >/dev/null 2>&1 || { printf 'flock required for concurrent case\n' >&2; return 77; }
    export HARVEST_MODE=blocked
    "$recover" "$target" > "$CASE_ROOT/first.json" 2> "$CASE_ROOT/first.log" &
    local pid=$! n
    trap ': > "$CASE_ROOT/release-harvest"; wait "$pid" || true' EXIT
    for n in {1..500}; do
        [[ ! -e "$CASE_ROOT/harvest-entered" ]] || break
        sleep 0.01
    done
    [[ -e "$CASE_ROOT/harvest-entered" ]]
    invoke 12
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 1 ]]
    : > "$CASE_ROOT/release-harvest"
    wait "$pid"
    trap - EXIT
    jq -e '.ok' "$CASE_ROOT/first.json" >/dev/null
    invoke 0
    jq -e '.data.already_recovered' "$CASE_ROOT/result.json" >/dev/null
    [[ $(wc -l < "$CASE_ROOT/calls.jsonl") -eq 1 ]]
    unchanged
}

cases=(success idempotent ambiguous stale unbound invalid_created partial failed rebound recreated marker_changed terminal_changed symlink corrupt_receipt unsafe_reference redirected_run active_lock concurrent conversation_changed new_target conversationless url_only conflicting_conversation running unverified wrong_banner missing_banner body_banner)
if [[ "$#" -gt 0 ]]; then cases=("$@"); fi
printf '1..%s\n' "${#cases[@]}"
failures=0 index=0
for case_name in "${cases[@]}"; do
    index=$((index+1))
    status=0
    # A separate Bash process keeps errexit active inside every assertion.
    # Running a test function as an if-condition would disable it recursively.
    if [[ ! "$case_name" =~ ^[a-z_]+$ ]] || ! declare -F "$case_name" >/dev/null; then
        printf 'not ok %s - invalid case\n' "$index"; failures=$((failures+1)); continue
    fi
    (
        set -e
        setup_case "$case_name"
        "$case_name"
    ) > "$work/$case_name.stdout" 2> "$work/$case_name.stderr" &
    test_pid=$!
    wait "$test_pid" || status=$?
    if [[ "$status" -eq 0 ]]; then
        printf 'ok %s - %s\n' "$index" "$case_name"
    elif [[ "$status" -eq 77 ]]; then
        printf 'ok %s - %s # SKIP requires flock\n' "$index" "$case_name"
    else
        printf 'not ok %s - %s\n' "$index" "$case_name"
        cat "$work/$case_name.stderr" >&2
        failures=$((failures+1))
    fi
done
printf 'Retained regression evidence: %s\n' "$work" >&2
[[ "$failures" -eq 0 ]]
