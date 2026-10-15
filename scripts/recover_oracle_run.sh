#!/usr/bin/env bash
# Recover a retained APR run without launching another model review.
# Run from the project directory: /path/to/APR/scripts/recover_oracle_run.sh
#   run:<workflow>:<run_id>
# Recovered bytes and their receipt stay under the private run directory;
# neither the original round output nor its terminal ledger is rewritten.
set -euo pipefail

# shellcheck disable=SC2034 # Used by the imported APR lock implementation.
readonly EXIT_DEPENDENCY_ERROR=3 EXIT_CONFIG_ERROR=4 EXIT_BUSY_ERROR=12
ORACLE_CMD=()
print_error() { printf '%s\n' "$*" >&2; }

fail() {
    local code="$1" message="$2"
    print_error "$message"
    return "$code"
}

# Reuse the installed checkout's actual validation/identity rules. APR is a
# single-file executable with an unconditional main call, not a sourceable
# library. Load only these named, top-level function definitions, never main.
# Refuse a changed/missing layout rather than silently using a copied policy.
load_apr_recovery_functions() {
    local core="$1" definitions minimum
    [[ -f "$core" && -r "$core" ]] || { fail 3 "Cannot read APR core: $core"; return $?; }
    definitions=$(awk '
        BEGIN {
            split("resolve_oracle_session_id validate_output_file document_sha256_stdin check_oracle apr_kernel_lock ledger_validate", names, " ")
            for (i in names) required[names[i]]=1
        }
        /^[a-z_][a-z_0-9]*\(\) \{$/ {
            name=$0; sub(/\(\) \{$/, "", name)
            copying=(name in required)
            if (copying && seen[name]++) exit 1
        }
        copying {print}
        copying && /^}$/ {copying=0; count++}
        END {if (copying || count!=6) exit 1}
    ' "$core") || { fail 3 "APR recovery helper layout is unsupported"; return $?; }
    minimum=$(awk '/^readonly MIN_OUTPUT_SIZE_BYTES=[0-9]+$/ {sub(/^.*=/, ""); print}' "$core")
    [[ "$minimum" =~ ^[0-9]+$ ]] || { fail 3 "APR output validation threshold is unavailable"; return $?; }
    # shellcheck disable=SC2034 # Used by the imported APR output validator.
    readonly MIN_OUTPUT_SIZE_BYTES="$minimum"
    # Only trusted function definitions from the sibling APR executable enter
    # eval. No run metadata, paths supplied by the caller, or Oracle output do.
    eval "$definitions"
}

file_digest() { document_sha256_stdin < "$1"; }

# Snapshot only identity-bearing fields, not prompts, cookies or browser
# credentials. Exactly one metadata object must describe this exact directory.
recovery_session_evidence() {
    local metadata="$1" id="$2" destination="$3"
    [[ -f "$metadata" && -r "$metadata" && ! -L "$metadata" ]] || return 1
    jq -sce --arg id "$id" --arg destination "$destination" '
        select(length==1) | .[0] |
        select(type=="object" and .id==$id and .options.writeOutputPath==$destination and
            (.createdAt|type=="string") and (.mode // .options.mode)=="browser") |
        # Pin the logical conversation, not a Chrome target that legitimate
        # recovery may replace. Never allow Oracle to fall back to "current".
        ([.browser.runtime.conversationId, .browser.harvest.conversationId,
         ((.browser.runtime.tabUrl // "") | try capture("/c/(?<id>[^/?#]+)").id catch null),
         ((.browser.harvest.url // "") | try capture("/c/(?<id>[^/?#]+)").id catch null)] |
         map(select(.!=null and .!="")) | unique) as $conversations |
        select(($conversations|length)==1 and all($conversations[];type=="string")) |
        {id,createdAt,writeOutputPath:.options.writeOutputPath,conversation_id:$conversations[0],
         submitted_prompt_hash:(.browser.runtime.submittedPromptHash // null)}
    ' "$metadata"
}

# Oracle 0.21.5 prints this summary before the separator and answer. A zero
# exit and a long, punctuated answer do not establish completed generation.
# Ignore answer-body text: it may quote other Session/State lines verbatim.
recovery_harvest_confirmed() {
    local transcript="$1" expected="$2"
    [[ -f "$transcript" && ! -L "$transcript" ]] || return 1
    LC_ALL=C awk -v expected="$expected" '
        {
            gsub(/\033\[[0-9;]*m/, "")
            sub(/\r$/, "")
            if ($0=="---") {separator=1; exit}
            if ($0 ~ /^Session:/) {
                if (NF!=2 || $2!=expected) bad=1
                sessions++
            }
            if ($0 ~ /^State:/) {
                if (NF!=2 || $2!="completed") bad=1
                states++
            }
            if ($0 ~ /^Capture identity:/) {
                if (NF!=3 || $3!="matched") bad=1
                identities++
            }
        }
        END {exit !(separator && sessions==1 && states==1 && identities==1 && !bad)}
    ' "$transcript"
}

recovery_report() {
    local receipt="$1" reused="$2"
    jq -c --argjson reused "$reused" '
        {ok:true,code:"ok",data:{run_id,workflow,round,session_id:.session.id,
            output_file,receipt_file,output_sha256:.output.sha256,output_bytes:.output.bytes,
            already_recovered:$reused}}
    ' "$receipt"
}

# Idempotence depends on retained bytes and the same immutable terminal record,
# not on whether Oracle still retains the browser session days later.
recovery_receipt_valid() {
    local receipt="$1" directory="$2" workflow="$3" run_id="$4" terminal_hash="$5"
    local output_path parent expected round session
    round="${run_id#round_}"; round="${round%%.*}"
    [[ -f "$receipt" && ! -L "$receipt" ]] || return 1
    jq -se --arg workflow "$workflow" --arg id "$run_id" --arg terminal "$terminal_hash" --arg receipt "$receipt" --argjson round "$round" '
        length==1 and (.[0] | .schema_version=="1.0.0" and .workflow==$workflow and .run_id==$id and
            .round==$round and .terminal_sha256==$terminal and .receipt_file==$receipt and
            (.session.id|type=="string" and test("^[a-zA-Z0-9][a-zA-Z0-9_-]*$")) and
            (.harvest_transcript_sha256|type=="string" and test("^[a-f0-9]{64}$")) and
            (.output.sha256|type=="string" and test("^[a-f0-9]{64}$")) and
            (.output.bytes|type=="number" and .>=0 and .==floor))
    ' "$receipt" >/dev/null || return 1
    output_path=$(jq -r .output_file "$receipt") || return 1
    parent="${output_path%/output.md}"
    [[ "$output_path" == "$parent/output.md" && "$parent" == "$directory"/recovery.* &&
       "${parent#"$directory"/}" != */* && -d "$parent" && ! -L "$parent" &&
       -f "$output_path" && ! -L "$output_path" ]] || return 1
    [[ -f "$parent/session.before.json" && ! -L "$parent/session.before.json" ]] || return 1
    jq -se --slurpfile receipt "$receipt" 'length==1 and .[0]==$receipt[0].session' \
        "$parent/session.before.json" >/dev/null || return 1
    session=$(jq -r .session.id "$receipt") || return 1
    recovery_harvest_confirmed "$parent/oracle.stdout.log" "$session" || return 1
    [[ $(file_digest "$parent/oracle.stdout.log") == "$(jq -r .harvest_transcript_sha256 "$receipt")" ]] || return 1
    validate_output_file "$output_path" || return 1
    expected=$(jq -r .output.sha256 "$receipt") || return 1
    [[ $(file_digest "$output_path") == "$expected" ]] || return 1
    [[ $(LC_ALL=C wc -c < "$output_path" | tr -d '[:space:]') == "$(jq -r .output.bytes "$receipt")" ]]
}

recover_run() (
    local reference="$1" workflow run_id round directory component terminal record terminal_hash
    local marker marker_hash destination session metadata evidence attempt receipt result=0 after output_hash bytes snapshot transcript_hash
    [[ "$reference" =~ ^run:[A-Za-z0-9_][A-Za-z0-9._-]*:round_(0|[1-9][0-9]{0,8})\.[A-Za-z0-9]+$ ]] ||
        { fail 2 "Expected run:<workflow>:<run_id>, as returned by apr robot run"; return $?; }
    reference="${reference#run:}"
    workflow="${reference%%:*}"
    run_id="${reference#*:}"
    [[ "$workflow" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ && "$run_id" =~ ^round_[0-9]+\.[A-Za-z0-9]+$ ]] ||
        { fail 2 "Expected run:<workflow>:<run_id>, as returned by apr robot run"; return $?; }
    round="${run_id#round_}"; round="${round%%.*}"
    umask 077
    # A run reference is project-local. Refuse symlink redirection at every
    # project-owned directory component before consulting session metadata.
    for component in .apr .apr/runs ".apr/runs/$workflow" ".apr/runs/$workflow/$run_id"; do
        [[ -d "$component" && ! -L "$component" ]] || { fail 4 "APR run directory is missing or redirected: $component"; return $?; }
    done
    directory=$(cd ".apr/runs/$workflow/$run_id" && pwd -P) || return 4
    terminal="$directory/terminal.meta.json"
    [[ -f "$terminal" && -r "$terminal" && ! -L "$terminal" ]] ||
        { fail 4 "This run has no retained terminal record; an active or uncertain producer must not be recovered here"; return $?; }
    [[ ! -L .apr/.locks ]] || { fail 4 "APR lock directory is redirected"; return $?; }
    mkdir -p .apr/.locks || return 4
    component=".apr/.locks/${workflow}_round_${round}.lock"
    [[ ! -L "$component" && ( ! -e "$component" || -f "$component" ) ]] || return 4
    exec 9>>"$component" || return 4
    apr_kernel_lock 9 || result=$?
    [[ "$result" -eq 0 ]] || { fail "$result" "Cannot own this workflow/round for recovery"; return $?; }
    # Observe the complete ledger once, then validate and hash those same bytes.
    # A private snapshot also preserves evidence when validation fails.
    snapshot=$(mktemp "$directory/recovery-terminal.XXXXXX") || return 4
    cat "$terminal" > "$snapshot" || return 4
    ledger_validate < "$snapshot" || { fail 4 "Invalid terminal run record"; return $?; }
    record=$(cat "$snapshot") || return 4
    jq -e --arg workflow "$workflow" --arg id "$run_id" --arg round "$round" '
        .workflow==$workflow and .run_id==$id and .round==($round|tonumber) and
        (.state=="failed" or .state=="finished") and .execution.attempts_count>0
    ' <<< "$record" >/dev/null || { fail 4 "Terminal record does not describe a completed producer for this run"; return $?; }
    terminal_hash=$(file_digest "$snapshot") || return 4
    cmp -s "$terminal" "$snapshot" || return 4
    receipt="$directory/recovery.json"
    if [[ -e "$receipt" || -L "$receipt" ]]; then
        recovery_receipt_valid "$receipt" "$directory" "$workflow" "$run_id" "$terminal_hash" ||
            { fail 4 "Existing recovery receipt or recovered bytes failed verification; retained them unchanged"; return $?; }
        recovery_report "$receipt" true
        return 0
    fi

    marker="$directory/oracle-session-start"
    [[ -f "$marker" && -r "$marker" && ! -L "$marker" ]] ||
        { fail 4 "Retained creation evidence is missing; refusing to guess a session"; return $?; }
    marker_hash=$(file_digest "$marker") || return 4
    destination="$directory/output.md"
    session=$(resolve_oracle_session_id "$destination" "$marker") || return 4
    [[ "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] ||
        { fail 4 "No unique Oracle session is bound to this run's output and creation evidence"; return $?; }
    metadata="${ORACLE_HOME_DIR:-$HOME/.oracle}/sessions/$session/meta.json"
    evidence=$(recovery_session_evidence "$metadata" "$session" "$destination") || return 4
    [[ $(file_digest "$marker") == "$marker_hash" ]] || return 4
    check_oracle || { fail 3 "Oracle is required to harvest the bound session"; return $?; }
    attempt=$(mktemp -d "$directory/recovery.XXXXXX") || return 4
    printf '%s\n' "$evidence" > "$attempt/session.before.json" || return 4
    print_error "Harvesting verified Oracle session $session (no new review)."
    "${ORACLE_CMD[@]}" session "$session" --harvest --write-output "$attempt/harvest.md" \
        > "$attempt/oracle.stdout.log" 2> "$attempt/oracle.stderr.log" || result=$?
    if [[ "$result" -ne 0 ]]; then
        print_error "Oracle harvest failed (exit $result); evidence retained in $attempt"
        return "$result"
    fi
    recovery_harvest_confirmed "$attempt/oracle.stdout.log" "$session" ||
        { fail 4 "Oracle did not confirm completed, identity-matched output; inspect $attempt/oracle.stdout.log"; return $?; }
    # Recheck both the immutable run binding and live Oracle identity before
    # accepting any harvested bytes. Never repair/mutate the original ledger.
    [[ $(file_digest "$terminal") == "$terminal_hash" && $(file_digest "$marker") == "$marker_hash" ]] ||
        { fail 4 "Run creation evidence changed during recovery; harvested bytes retained but not accepted"; return $?; }
    [[ $(resolve_oracle_session_id "$destination" "$marker") == "$session" ]] ||
        { fail 4 "Oracle session binding changed during recovery; not accepting the answer"; return $?; }
    after=$(recovery_session_evidence "$metadata" "$session" "$destination") || return 4
    [[ "$after" == "$evidence" ]] || { fail 4 "Oracle session identity changed during recovery"; return $?; }
    [[ -f "$attempt/harvest.md" && ! -L "$attempt/harvest.md" ]] ||
        { fail 4 "Oracle did not produce a regular harvest file; retained diagnostics in $attempt"; return $?; }
    # Accept an independent inode, not a sink that an Oracle process may still
    # hold open. Validation and the receipt observe this same retained copy.
    cp "$attempt/harvest.md" "$attempt/output.md" || return 4
    chmod 400 "$attempt/output.md" || return 4
    validate_output_file "$attempt/output.md" ||
        { fail 4 "Harvested answer is incomplete; retained diagnostics in $attempt"; return $?; }
    output_hash=$(file_digest "$attempt/output.md") || return 4
    bytes=$(LC_ALL=C wc -c < "$attempt/output.md" | tr -d '[:space:]') || return 4
    transcript_hash=$(file_digest "$attempt/oracle.stdout.log") || return 4
    jq -nc --arg workflow "$workflow" --arg id "$run_id" --arg round "$round" \
        --arg terminal "$terminal_hash" --arg marker "$marker_hash" --argjson session "$evidence" \
        --arg output "$attempt/output.md" --arg receipt "$receipt" --arg sha "$output_hash" --argjson bytes "$bytes" --arg transcript "$transcript_hash" \
        --arg stamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{schema_version:"1.0.0",workflow:$workflow,run_id:$id,round:($round|tonumber),
          recovered_at:$stamp,terminal_sha256:$terminal,creation_evidence_sha256:$marker,
          session:$session,harvest_transcript_sha256:$transcript,output_file:$output,receipt_file:$receipt,output:{sha256:$sha,bytes:$bytes}}' \
        > "$attempt/receipt.json" || return 4
    chmod 400 "$attempt/receipt.json" "$attempt/session.before.json" "$attempt/oracle.stdout.log" "$snapshot" || return 4
    # Hard-link publication cannot overwrite a prior receipt. The answer and
    # evidence already exist before the only authoritative pointer appears.
    ln -n "$attempt/receipt.json" "$receipt" || return 12
    [[ -f "$receipt" && ! -L "$receipt" && "$receipt" -ef "$attempt/receipt.json" ]] || return 12
    recovery_report "$receipt" false
)

main() {
    if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
        printf '%s\n' 'Usage: scripts/recover_oracle_run.sh run:<workflow>:<run_id>' \
            'Run from the APR project directory. Harvests a verified retained session without a new review.' \
            'Returns JSON with the recovered output and receipt paths. Original outputs and ledgers are preserved.'
        return 0
    fi
    [[ "$#" -eq 1 && "$1" == run:* ]] || { fail 2 "Expected one APR run reference; see --help"; return $?; }
    command -v jq >/dev/null 2>&1 || { fail 3 "Recovery requires jq"; return $?; }
    local core
    core="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/apr"
    load_apr_recovery_functions "$core" || return $?
    recover_run "$1"
}

main "$@"
