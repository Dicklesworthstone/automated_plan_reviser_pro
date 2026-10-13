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
