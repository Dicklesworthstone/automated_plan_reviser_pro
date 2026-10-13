#!/usr/bin/env bats
# Run provenance is a distinct runtime domain; these cases exercise real JSON
# and filesystem/CLI records, without model/browser/provider proof claims.
load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    load_apr_functions
    log_test_start "${BATS_TEST_NAME}"
    cd "$TEST_PROJECT" || return
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

ledger_fixture() {
    jq -nc '{schema_version:"1.0.0",run_id:"run-unique",workflow:"default",round:1,
        slug:"apr-default-round-1",state:"started",started_at:"2026-10-13T04:00:00Z",
        finished_at:null,duration_ms:null,config:{path:".apr/workflows/default.yaml",sha256:null},
        inputs:{status:"pending",files:[],manifest:null,prompt_hash:null},
        invocation:{engine:"browser",model:null,thinking_time:null,remote_host:null,oracle_flags_used:[],oracle_args:[]},
        execution:{attempts_count:0,retries_count:0,busy_wait_count:0,busy_wait_total_ms:0,retry_reasons:[]},
        outcome:{ok:null,code:null,exit_code:null,oracle_exit_code:null,output_path:null}}'
}

ledger_complete_fixture() {
    ledger_fixture | jq -c --arg hash e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 '
        .config.sha256=$hash | .inputs.status="complete" | .inputs.prompt_hash=$hash |
        .inputs.files=[{role:"readme",path:"README.md",basename:"README.md",bytes:0,sha256:$hash,included:true,inclusion_reason:"required",skip_reason:null},
            {role:"spec",path:"SPEC.md",basename:"SPEC.md",bytes:0,sha256:$hash,included:true,inclusion_reason:"required",skip_reason:null},
            {role:"implementation",path:"IMPL.md",basename:"IMPL.md",bytes:null,sha256:null,included:false,inclusion_reason:"optional",skip_reason:"not_requested"}] |
        .inputs.manifest={v:1,files:(.inputs.files | map(.reason=.inclusion_reason | del(.inclusion_reason)))} | .invocation.model="5.2 Thinking"'
}

@test "ledger schema: started partial and complete observations are valid" {
    ledger_fixture | ledger_validate
    ledger_complete_fixture | ledger_validate
}

@test "ledger schema: finished fixture has complete inputs and successful outcome" {
    ledger_complete_fixture | jq -c '.state="finished" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .execution.attempts_count=1 | .outcome={ok:true,code:"ok",exit_code:0,oracle_exit_code:0,output_path:".apr/rounds/default/round_1.md"}' | ledger_validate
}

@test "ledger schema: failed early validation and native busy fixtures retain real status" {
    ledger_fixture | jq -c '.state="failed" | .inputs.status="failed" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .outcome={ok:false,code:"validation_failed",exit_code:4,oracle_exit_code:null,output_path:null}' | ledger_validate
    ledger_complete_fixture | jq -c '.state="failed" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .execution={attempts_count:2,retries_count:0,busy_wait_count:2,busy_wait_total_ms:1000,retry_reasons:[]} | .outcome={ok:false,code:"busy",exit_code:12,oracle_exit_code:7,output_path:null}' | ledger_validate
}

@test "ledger schema: canceled signal fixture and optional fields are valid" {
    ledger_fixture | jq -c '.state="canceled" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .outcome={ok:false,code:"internal_error",exit_code:130,oracle_exit_code:null,output_path:null} | .interruption_reason="SIGINT" | .warnings=[] | .overrides=[]' | ledger_validate
}

@test "ledger schema: unsupported versions malformed JSON and missing identity reject" {
    run ledger_validate <<< '{'
    [[ "$status" -ne 0 ]]
    run bash -c 'source "$1"; ledger_validate' _ "$TEST_DIR/apr_functions.bash" <<< "$(ledger_fixture | jq '.schema_version="2.0.0"')"
    [[ "$status" -ne 0 ]]
    run ledger_validate <<< "$(ledger_fixture | jq 'del(.run_id)')"
    [[ "$status" -ne 0 ]]
}

@test "ledger schema: success cannot have partial inputs failed code or nonzero exit" {
    local record
    record=$(ledger_fixture | jq '.state="finished" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .outcome.ok=true | .outcome.code="ok" | .outcome.exit_code=0')
    run ledger_validate <<< "$record"
    [[ "$status" -ne 0 ]]
    record=$(ledger_complete_fixture | jq '.state="finished" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .outcome.ok=true | .outcome.code="internal_error" | .outcome.exit_code=1')
    run ledger_validate <<< "$record"
    [[ "$status" -ne 0 ]]
}

@test "ledger schema: failed cannot pretend success and started cannot pretend completion" {
    run ledger_validate <<< "$(ledger_fixture | jq '.state="failed" | .finished_at="2026-10-13T04:00:01Z" | .duration_ms=1000 | .outcome.ok=true | .outcome.code="ok" | .outcome.exit_code=0')"
    [[ "$status" -ne 0 ]]
    run ledger_validate <<< "$(ledger_fixture | jq '.outcome.ok=true | .outcome.code="ok" | .outcome.exit_code=0')"
    [[ "$status" -ne 0 ]]
}

@test "ledger schema: invalid counters digests secret host and duplicate roles reject" {
    local mutation
    for mutation in '.execution.retries_count=-1' '.execution.busy_wait_total_ms=0.5' '.inputs.prompt_hash="fake"' '.invocation.remote_host="user:secret@host?token=secret"' '.inputs.files[1]=.inputs.files[0]' 'del(.invocation.model)' 'del(.outcome.exit_code)' '.started_at="2026-99-99T04:00:00Z"'; do
        run ledger_validate <<< "$(ledger_complete_fixture | jq "$mutation")"
        [[ "$status" -ne 0 ]]
    done
}

@test "ledger schema: complete file manifest binding rejects extra missing or contradictory rows" {
    local mutation
    for mutation in '.inputs.files += [.inputs.files[2] | .role="readme"]' 'del(.inputs.files[2].bytes)' 'del(.inputs.files[0].skip_reason)' '.inputs.manifest.files={a:1,b:2,c:3}' '.inputs.manifest.files[0].sha256=("0"*64)' '.inputs.manifest.files[0].reason="optional"' '.inputs.files[0].display_path=7 | .inputs.manifest.files[0].path=7'; do
        run ledger_validate <<< "$(ledger_complete_fixture | jq "$mutation")"
        [[ "$status" -ne 0 ]]
    done
    ledger_complete_fixture | jq '.inputs.files[0].display_path=.inputs.files[0].path | .inputs.files[0].path="/configured/project/README.md"' | ledger_validate
}

@test "ledger schema: one valid document cannot hide another invalid or duplicate document" {
    local valid invalid
    valid=$(ledger_fixture)
    invalid=$(ledger_fixture | jq '.schema_version="2.0.0"')
    run ledger_validate <<< "$invalid"$'\n'"$valid"
    [[ "$status" -ne 0 ]]
    run ledger_validate <<< "$valid"$'\n'"$invalid"
    [[ "$status" -ne 0 ]]
    run ledger_validate <<< "$valid"$'\n'"$valid"
    [[ "$status" -ne 0 ]]
    ledger_validate <<< "$valid"
}

start_runtime_ledger() {
    setup_test_workflow default
    ledger_write_start default 1 apr-default-round-1 .apr/workflows/default.yaml .apr/rounds/default/round_1.md
}

bind_runtime_ledger() {
    local manifest prompt
    manifest=$(build_document_manifest README.md SPECIFICATION.md IMPLEMENTATION.md false optional)
    prompt=$(build_revision_prompt false .apr/workflows/default.yaml "$manifest")
    ledger_bind_inputs "$manifest" "$prompt" README.md SPECIFICATION.md IMPLEMENTATION.md "5.2 Thinking" heavy \
        --engine browser -m "5.2 Thinking" --file README.md --file SPECIFICATION.md \
        --slug apr-default-round-1 --write-output .apr/rounds/default/round_1.md -p "$prompt"
}

@test "ledger writer: crash before input binding retains valid private started record" {
    setup_test_workflow default
    run bash -c 'source "$1"; ledger_write_start default 1 apr-default-round-1 .apr/workflows/default.yaml; exit 47' _ "$TEST_DIR/apr_functions.bash"
    [[ "$status" -eq 47 ]]
    APR_LEDGER_FILE=.apr/rounds/default/round_1.meta.json
    ledger_validate < "$APR_LEDGER_FILE"
    [[ $(jq -r .state "$APR_LEDGER_FILE") == started ]]
    [[ $(jq -r .inputs.status "$APR_LEDGER_FILE") == pending ]]
    [[ $(jq -r .outcome.oracle_exit_code "$APR_LEDGER_FILE") == null ]]
    [[ -f "$APR_LEDGER_FILE.lock" ]]
    [[ $(stat -f '%Lp' "$APR_LEDGER_FILE" 2>/dev/null || stat -c '%a' "$APR_LEDGER_FILE") == 600 ]]
}

@test "ledger writer: actual config manifest and exact prompt bytes are bound without secret values" {
    start_runtime_ledger
    local manifest prompt hash
    manifest=$(build_document_manifest README.md SPECIFICATION.md IMPLEMENTATION.md false optional)
    prompt=$'Useful review prompt.\nNo added final newline.'
    hash=$(printf '%s' "$prompt" | document_sha256_stdin)
    ORACLE_REMOTE_HOST='https://user:PRIVATE_TOKEN@host.example:444/path?token=PRIVATE_TOKEN'
    ledger_bind_inputs "$manifest" "$prompt" README.md SPECIFICATION.md IMPLEMENTATION.md "5.2 Thinking" heavy \
        --engine browser -p "$prompt" --remote-token PRIVATE_TOKEN --remote-host "$ORACLE_REMOTE_HOST" \
        '--secret=PRIVATE_TOKEN' PRIVATE_TOKEN --notify
    ledger_validate < "$APR_LEDGER_FILE"
    [[ $(jq -r .inputs.prompt_hash "$APR_LEDGER_FILE") == "$hash" ]]
    [[ $(jq -r .config.sha256 "$APR_LEDGER_FILE") == "$(document_sha256_stdin < .apr/workflows/default.yaml)" ]]
    [[ $(jq -r .invocation.remote_host "$APR_LEDGER_FILE") == host.example:444 ]]
    run rg -q 'PRIVATE_TOKEN|Useful review prompt|No added final newline' "$APR_LEDGER_FILE"
    [[ "$status" -eq 1 ]]
    jq -e '.invocation.oracle_args | index("[redacted]")!=null' "$APR_LEDGER_FILE"
}

@test "ledger writer: early failure preserves typed caller status without fabricated Oracle attempt" {
    start_runtime_ledger
    ledger_write_finish_error validation_failed 4
    ledger_validate < "$APR_LEDGER_FILE"
    jq -e '.state=="failed" and .inputs.status=="failed" and .execution.attempts_count==0 and .outcome=={ok:false,code:"validation_failed",exit_code:4,oracle_exit_code:null,output_path:null}' "$APR_LEDGER_FILE"
}

@test "ledger writer: next generation preserves terminal history and rejects old owner update" {
    start_runtime_ledger
    ledger_write_finish_error config_error 4
    local prior="$APR_LEDGER_RECORD" old_id="$APR_LEDGER_RUN_ID" new_id new_dir new_record
    ledger_write_start default 1 apr-default-round-1 .apr/workflows/default.yaml
    new_id="$APR_LEDGER_RUN_ID"; new_dir="$APR_LEDGER_DIR"; new_record="$APR_LEDGER_RECORD"
    [[ "$new_id" != "$old_id" ]]
    cmp "$prior" "$new_dir/prior.meta.json"
    APR_LEDGER_RUN_ID="$old_id"; APR_LEDGER_RECORD="$prior"
    run ledger_write_finish_error internal_error 1
    [[ "$status" -eq 12 ]]
    cmp "$new_record" "$APR_LEDGER_FILE"
}

@test "ledger writer: live started owner and stale same-run candidate cannot be overwritten" {
    start_runtime_ledger
    local prior="$APR_LEDGER_RECORD" current
    run ledger_write_start default 1 apr-default-round-1 .apr/workflows/default.yaml
    [[ "$status" -eq 12 ]]
    cmp "$prior" "$APR_LEDGER_FILE"
    bind_runtime_ledger
    current="$APR_LEDGER_RECORD"
    APR_LEDGER_RECORD="$prior"
    run ledger_write_finish_error config_error 4
    [[ "$status" -eq 12 ]]
    cmp "$current" "$APR_LEDGER_FILE"
}

@test "ledger writer: invalid candidate and rename failure leave canonical JSON unchanged" {
    start_runtime_ledger
    local prior="$APR_LEDGER_RECORD" invalid="$TEST_DIR/invalid.json"
    printf '{' > "$invalid"
    run ledger_publish "$invalid"
    [[ "$status" -ne 0 ]]
    cmp "$prior" "$APR_LEDGER_FILE"
    mv() { return 74; }
    run ledger_write_finish_error config_error 4
    [[ "$status" -eq 4 ]]
    cmp "$prior" "$APR_LEDGER_FILE"
    ledger_validate < "$APR_LEDGER_FILE"
}

@test "ledger writer: retained kernel lock rejects a separate process until descriptor closes" {
    start_runtime_ledger
    exec 8>>"$APR_LEDGER_FILE.lock"
    apr_kernel_lock 8
    local inode
    inode=$(stat -f '%i' "$APR_LEDGER_FILE.lock" 2>/dev/null || stat -c '%i' "$APR_LEDGER_FILE.lock")
    run bash -c 'source "$1"; exec 8>>"$2"; apr_kernel_lock 8' _ "$TEST_DIR/apr_functions.bash" "$APR_LEDGER_FILE.lock"
    [[ "$status" -eq 12 ]]
    exec 8>&-
    run bash -c 'source "$1"; exec 8>>"$2"; apr_kernel_lock 8' _ "$TEST_DIR/apr_functions.bash" "$APR_LEDGER_FILE.lock"
    [[ "$status" -eq 0 ]]
    [[ "$inode" == "$(stat -f '%i' "$APR_LEDGER_FILE.lock" 2>/dev/null || stat -c '%i' "$APR_LEDGER_FILE.lock")" ]]
}

@test "ledger writer: real retrying producer counters native exit and useful output reach terminal record" {
    start_runtime_ledger
    bind_runtime_ledger
    cat > "$TEST_DIR/producer" <<'EOF'
#!/usr/bin/env bash
count=0
[[ ! -f "$APR_TEST_COUNT" ]] || count=$(cat "$APR_TEST_COUNT")
count=$((count+1)); printf '%s\n' "$count" > "$APR_TEST_COUNT"
[[ "$count" -ne 1 ]] || { printf 'temporary failure\n' >&2; exit 19; }
for ((i=0; i<100; i++)); do printf 'A complete useful local review response.\n'; done > "$1"
EOF
    chmod +x "$TEST_DIR/producer"
    export APR_TEST_COUNT="$TEST_DIR/producer-count"
    ORACLE_CMD=("$TEST_DIR/producer")
    MAX_RETRY_ATTEMPTS=2; INITIAL_BACKOFF=0; ORACLE_BUSY_WAIT_SECONDS=0
    run_oracle_with_retry .apr/rounds/default/round_1.md
    ledger_write_finish_success .apr/rounds/default/round_1.md
    ledger_validate < "$APR_LEDGER_FILE"
    [[ $(cat "$APR_TEST_COUNT") -eq 2 ]]
    jq -e '.state=="finished" and .execution.attempts_count==2 and .execution.retries_count==1 and .execution.retry_reasons==["oracle_error"] and .execution.busy_wait_count==0 and .outcome.oracle_exit_code==0' "$APR_LEDGER_FILE"
}

@test "ledger writer: BSD lockf numeric descriptor retains contention after utility exits" {
    [[ -x /usr/bin/lockf ]] || skip "BSD lockf is not installed on this host"
    start_runtime_ledger
    # Exercise the real fallback with Homebrew flock out of the search path.
    run bash -c 'source "$1"; PATH=/usr/bin:/bin; apr_kernel_lock 8' _ "$TEST_DIR/apr_functions.bash"
    [[ "$status" -eq 4 ]]
    exec 8>>"$APR_LEDGER_FILE.lock"
    PATH=/usr/bin:/bin apr_kernel_lock 8
    run bash -c 'source "$1"; PATH=/usr/bin:/bin; exec 8>>"$2"; apr_kernel_lock 8' _ "$TEST_DIR/apr_functions.bash" "$APR_LEDGER_FILE.lock"
    [[ "$status" -eq 12 ]]
    exec 8>&-
    run bash -c 'source "$1"; PATH=/usr/bin:/bin; exec 8>>"$2"; apr_kernel_lock 8' _ "$TEST_DIR/apr_functions.bash" "$APR_LEDGER_FILE.lock"
    [[ "$status" -eq 0 ]]
}

@test "ledger writer: concurrent readers observe only whole valid published records" {
    start_runtime_ledger
    local observed="$TEST_DIR/reader.jsonl"
    (
        for ((i=0;i<40;i++)); do
            local snapshot
            snapshot=$(cat "$APR_LEDGER_FILE") || exit 90
            ledger_validate <<< "$snapshot" || exit 91
            printf '%s\n' "$snapshot" >> "$observed"
        done
    ) &
    local reader=$!
    bind_runtime_ledger
    ledger_write_finish_error busy 12 "" 7
    wait "$reader"
    [[ $(wc -l < "$observed") -eq 40 ]]
    jq -se 'all(.[]; .state=="started" or .state=="failed")' "$observed"
}

@test "ledger writer: actual busy policy counts waiting separately from ordinary retries" {
    start_runtime_ledger
    bind_runtime_ledger
    cat > "$TEST_DIR/busy-producer" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" != status ]] || exit 0
count=0
[[ ! -f "$APR_TEST_COUNT" ]] || count=$(cat "$APR_TEST_COUNT")
count=$((count+1)); printf '%s\n' "$count" > "$APR_TEST_COUNT"
[[ "$count" -ne 1 ]] || { printf 'ERROR: busy: another review is active\n' >&2; exit 7; }
sleep 2
for ((i=0; i<100; i++)); do printf 'A complete useful local review response.\n'; done > "$1"
EOF
    chmod +x "$TEST_DIR/busy-producer"
    export APR_TEST_COUNT="$TEST_DIR/busy-count"
    ORACLE_CMD=("$TEST_DIR/busy-producer")
    MAX_RETRY_ATTEMPTS=1; INITIAL_BACKOFF=0; ORACLE_BUSY_WAIT_SECONDS=6
    ORACLE_BUSY_MIN_SLEEP=1; ORACLE_BUSY_MAX_SLEEP=1
    [[ "${ORACLE_CMD[0]}" == "$TEST_DIR/busy-producer" && "$MAX_RETRY_ATTEMPTS" -eq 1 && "$INITIAL_BACKOFF" -eq 0 && "$ORACLE_BUSY_WAIT_SECONDS" -eq 6 && "$ORACLE_BUSY_MIN_SLEEP" -eq 1 && "$ORACLE_BUSY_MAX_SLEEP" -eq 1 ]]
    run_oracle_with_retry .apr/rounds/default/round_1.md
    ledger_write_finish_success .apr/rounds/default/round_1.md
    ledger_validate < "$APR_LEDGER_FILE"
    [[ $(cat "$APR_TEST_COUNT") -eq 2 ]]
    jq -e '.execution.attempts_count==2 and .execution.retries_count==0 and .execution.busy_wait_count==1 and .execution.busy_wait_total_ms>=1000 and .execution.busy_wait_total_ms<2000 and .execution.retry_reasons==[]' "$APR_LEDGER_FILE"
}

@test "ledger writer: incomplete output cannot publish successful terminal state" {
    start_runtime_ledger
    bind_runtime_ledger
    local prior="$APR_LEDGER_RECORD"
    printf 'A partial answer.\n' > .apr/rounds/default/round_1.md
    run ledger_write_finish_success .apr/rounds/default/round_1.md
    [[ "$status" -eq 4 ]]
    cmp "$prior" "$APR_LEDGER_FILE"
    ledger_write_finish_error internal_error 1 .apr/rounds/default/round_1.md 0
    jq -e '.state=="failed" and .outcome.oracle_exit_code==0 and .outcome.ok==false' "$APR_LEDGER_FILE"
}

@test "ledger writer: failed retry capture is not counted as a producer retry" {
    start_runtime_ledger
    bind_runtime_ledger
    cat > "$TEST_DIR/failing-producer" <<'EOF'
#!/usr/bin/env bash
printf 'producer\n' >> "$APR_TEST_COUNT"
printf 'temporary failure\n' >&2
exit 19
EOF
    chmod +x "$TEST_DIR/failing-producer"
    export APR_TEST_COUNT="$TEST_DIR/failed-count"
    ORACLE_CMD=("$TEST_DIR/failing-producer")
    MAX_RETRY_ATTEMPTS=2; INITIAL_BACKOFF=0; ORACLE_BUSY_WAIT_SECONDS=0
    [[ "${ORACLE_CMD[0]}" == "$TEST_DIR/failing-producer" && "$MAX_RETRY_ATTEMPTS" -eq 2 && "$INITIAL_BACKOFF" -eq 0 && "$ORACLE_BUSY_WAIT_SECONDS" -eq 0 ]]
    mktemp() {
        local count=0
        if [[ "${1:-}" != *apr-oracle-stderr* ]]; then
            command mktemp "$@"
            return $?
        fi
        [[ ! -f "$TEST_DIR/capture-count" ]] || count=$(cat "$TEST_DIR/capture-count")
        count=$((count+1)); printf '%s\n' "$count" > "$TEST_DIR/capture-count"
        [[ "$count" -ne 2 ]] || return 73
        command mktemp "$@"
    }
    capture_streams run_oracle_with_retry
    [[ "$CAPTURED_STATUS" -eq 1 && "$ORACLE_FAILURE_KIND" == capture_error ]]
    [[ $(wc -l < "$APR_TEST_COUNT") -eq 1 ]]
    [[ "$APR_ATTEMPTS_COUNT" -eq 1 && "$APR_RETRIES_COUNT" -eq 0 && "$APR_RETRY_REASONS" == '[]' ]]
}
