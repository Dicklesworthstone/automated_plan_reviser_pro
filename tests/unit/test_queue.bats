#!/usr/bin/env bats
# Queue validation/state/execution is a distinct product domain. Fixtures are
# local processes/files; no browser/model/provider correctness is implied.
load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    load_apr_functions
    cd "$TEST_PROJECT" || return
    export APR_NO_ORACLE_PATCH=1 APR_NO_NPX=1
}

teardown() {
    teardown_test_environment
}

queue_test_workflow() {
    setup_test_workflow default
    mkdir -p "$TEST_DIR/probe-bin"
    cat > "$TEST_DIR/probe-bin/oracle" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$APR_QUEUE_PROBES"
exit 99
EOF
    cat > "$TEST_DIR/probe-bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$APR_QUEUE_NETWORK"
exit 99
EOF
    chmod +x "$TEST_DIR/probe-bin/oracle" "$TEST_DIR/probe-bin/curl"
    export APR_QUEUE_PROBES="$TEST_DIR/oracle-probes" APR_QUEUE_NETWORK="$TEST_DIR/network-probes"
    export PATH="$TEST_DIR/probe-bin:$PATH"
}

@test "queue lint: human and robot lint stay offline even with opt-in updates and leading robot flags" {
    queue_test_workflow
    export APR_CHECK_UPDATES=1
    capture_streams bash "$APR_SCRIPT" lint 1 --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.valid and .code=="ok" and (.errors|length)==0 and (.resolved.manifest.files|length)==3' <<< "$CAPTURED_STDOUT"
    capture_streams bash "$APR_SCRIPT" robot --compact lint 1
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    assert_json_value "$CAPTURED_STDOUT" .data.valid true
    [[ ! -f "$APR_QUEUE_PROBES" && ! -f "$APR_QUEUE_NETWORK" ]]
    [[ ! -d .apr/runs && ! -d .apr/.locks && ! -d .apr/logs ]]
}

@test "queue lint: typed findings expose source and observed hashes without prompt text" {
    queue_test_workflow
    capture_streams validate_workflow_local default 1 false
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.valid and .resolved.include_impl_requested==false and .resolved.include_impl_effective==false and (.resolved.prompt_hash|test("^[a-f0-9]{64}$")) and (has("prompt")|not)' <<< "$CAPTURED_STDOUT"
    local result="$CAPTURED_STDOUT" prompt
    prompt=$(build_revision_prompt false .apr/workflows/default.yaml "$(jq -c .resolved.manifest <<< "$result")")
    [[ $(jq -r .resolved.prompt_hash <<< "$result") == "$(printf '%s' "$prompt" | document_sha256_stdin)" ]]
    [[ "$result" != *'Please analyze and provide feedback'* ]]
}

@test "queue lint: both variants are checked before any producer can run" {
    queue_test_workflow
    cp .apr/workflows/default.yaml "$TEST_DIR/valid-workflow.yaml"
    cat > .apr/workflows/default.yaml <<'EOF'
documents:
  readme: README.md
  spec: SPECIFICATION.md
oracle:
  model: "5.2 Thinking"
rounds:
  output_dir: .apr/rounds/default
template: |
  A valid base review prompt.
template_with_impl: |
  {{UNEXPANDED}}
EOF
    capture_streams bash "$APR_SCRIPT" robot lint 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    assert_json_value "$CAPTURED_STDOUT" .code validation_failed
    jq -e 'any(.data.errors[]; .source.label=="template_with_impl" and .source.line==null and .code=="validation_failed")' <<< "$CAPTURED_STDOUT"
    [[ ! -f "$APR_QUEUE_PROBES" ]]
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_QUEUE_PROBES" ]]
    jq -e '.state=="failed" and .outcome.code=="validation_failed" and .execution.attempts_count==0' .apr/rounds/default/round_1.meta.json
}

@test "queue lint: empty included documents fail while small real documents only warn" {
    queue_test_workflow
    cp README.md "$TEST_DIR/README.before"
    printf '' > README.md
    capture_streams validate_workflow_local default 1 false
    jq -e '.valid==false and any(.errors[]; .details.role=="readme" and .details.bytes==0)' <<< "$CAPTURED_STDOUT"
    printf 'Useful.\n' > README.md
    capture_streams validate_workflow_local default 1 false
    jq -e '.valid and any(.warnings[]; .details.role=="readme" and .details.bytes==8 and .details.threshold==64)' <<< "$CAPTURED_STDOUT"
}

@test "queue lint: invalid identity and oversized rounds cannot enter cadence or read arbitrary paths" {
    queue_test_workflow
    capture_streams validate_workflow_local ../../elsewhere 999999999999999999999999 true
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.valid==false and .code=="usage_error" and (.errors|length)==2 and .resolved=={}' <<< "$CAPTURED_STDOUT"
    capture_streams validate_workflow_local default 00000000000000000008 false
    jq -e '.valid and .resolved.round==8' <<< "$CAPTURED_STDOUT"
}

@test "queue lint: cadence and absent optional inputs preserve requested versus effective selection" {
    queue_test_workflow
    cp .apr/workflows/default.yaml "$TEST_DIR/valid-workflow.yaml"
    cat > .apr/workflows/default.yaml <<'EOF'
documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: IMPLEMENTATION.md
oracle:
  model: "5.2 Thinking"
rounds:
  output_dir: .apr/rounds/default
  impl_every_n: 4
template: |
  A valid base review prompt.
EOF
    capture_streams validate_workflow_local default 4 false
    jq -e '.valid and .resolved.include_impl_requested==false and .resolved.include_impl_effective==true and .resolved.impl_reason=="impl_every_n" and any(.resolved.manifest.files[]; .role=="implementation" and .included)' <<< "$CAPTURED_STDOUT"
    cp .apr/workflows/default.yaml "$TEST_DIR/cadence-workflow.yaml"
    # A top-level scalar is supported by the existing configuration reader;
    # put this missing-path observation in its own real workflow.
    cat > .apr/workflows/missing.yaml <<'EOF'
readme: README.md
spec: SPECIFICATION.md
implementation: absent-implementation.md
model: "5.2 Thinking"
output_dir: .apr/rounds/missing
impl_every_n: 4
template: |
  A valid review prompt.
EOF
    capture_streams validate_workflow_local missing 4 false
    jq -e '.valid and .resolved.include_impl_effective==false and .resolved.impl_reason=="impl_every_n" and any(.resolved.manifest.files[]; .role=="implementation" and .included==false and .skip_reason=="missing_optional")' <<< "$CAPTURED_STDOUT"
}

@test "queue lint: actual unreadable config and failed reader cannot become default-template success" {
    queue_test_workflow
    chmod 000 .apr/workflows/default.yaml
    capture_streams validate_workflow_local default 1 false
    jq -e '.valid==false and .code=="config_error" and .resolved=={}' <<< "$CAPTURED_STDOUT"
    chmod 600 .apr/workflows/default.yaml
    get_config_value() { printf 'fixture reader failed\n' >&2; return 9; }
    capture_streams validate_workflow_local default 1 false
    [[ "$CAPTURED_STDERR" == *'fixture reader failed'* ]]
    jq -e '.valid==false and any(.errors[]; .message=="Cannot read workflow configuration")' <<< "$CAPTURED_STDOUT"
}

@test "queue events: enqueue start finish and cancel retain exact history and FIFO identities" {
    queue_test_workflow
    queue_append_event default enqueue entry-one '{"round":1,"include_impl":false}'
    cp .apr/queue/default.events.jsonl "$TEST_DIR/enqueue-prefix"
    queue_append_event default enqueue entry-two '{"round":2,"include_impl":true}'
    queue_append_event default start entry-one "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"runner-one",started_at:$stamp}')"
    queue_append_event default finish entry-one "$(jq -nc --arg stamp "$(iso_timestamp)" '{ok:true,code:"ok",exit_code:0,output_path:".apr/rounds/default/round_1.md",slug:"apr-default-round-1",finished_at:$stamp}')"
    queue_append_event default cancel entry-two "$(jq -nc --arg stamp "$(iso_timestamp)" '{canceled_at:$stamp,reason:"retain history"}')"
    [[ $(head -n 1 .apr/queue/default.events.jsonl) == "$(cat "$TEST_DIR/enqueue-prefix")" ]]
    capture_streams queue_status_data default
    jq -e '.counts=={queued:0,running:0,done:1,failed:0,canceled:1} and [.entries[].entry_id]==["entry-one","entry-two"]' <<< "$CAPTURED_STDOUT"
    [[ $(wc -l < .apr/queue/default.events.jsonl) -eq 5 && ! -f "$APR_QUEUE_PROBES" ]]
}

@test "queue events: real concurrent writers serialize whole events without lost requests" {
    queue_test_workflow
    local id pid pids=()
    for id in one two three four; do
        (
            local attempt=0 result=12
            while [[ "$result" -eq 12 && "$attempt" -lt 50 ]]; do
                result=0
                queue_append_event default enqueue "$id" '{"round":1,"include_impl":false}' > "$TEST_DIR/event-$id" || result=$?
                attempt=$((attempt+1))
                [[ "$result" -ne 12 ]] || sleep 0.05
            done
            exit "$result"
        ) &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    capture_streams queue_status_data default
    jq -e '.counts.queued==4 and ([.entries[].entry_id]|sort)==["four","one","three","two"]' <<< "$CAPTURED_STDOUT"
    queue_validate_events <<< "$(queue_load default)"
    [[ $(wc -l < .apr/queue/default.events.jsonl) -eq 4 ]]
}

@test "queue events: an exact retained pending prefix recovers by appending only its missing bytes" {
    queue_test_workflow
    queue_append_event default enqueue entry-one '{"round":1,"include_impl":false}'
    local pending partial before
    mkdir -p .apr/queue/.pending/default
    pending=.apr/queue/.pending/default/retained-second
    jq -nc --arg stamp "$(iso_timestamp)" '{schema_version:"1.0.0",ts:$stamp,sequence:2,event:"enqueue",event_id:"retained-second",entry_id:"entry-two",workflow:"default",round:2,include_impl:false}' > "$pending"
    partial=$(head -c 43 "$pending")
    printf '%s' "$partial" >> .apr/queue/default.events.jsonl
    cp .apr/queue/default.events.jsonl "$TEST_DIR/partial-before"
    before=$(wc -c < "$TEST_DIR/partial-before")
    capture_streams queue_status_data default
    jq -e '.counts.queued==1 and (.warnings|length)==1' <<< "$CAPTURED_STDOUT"
    queue_append_event default enqueue entry-three '{"round":3,"include_impl":false}'
    head -c "$before" .apr/queue/default.events.jsonl > "$TEST_DIR/preserved-prefix"
    cmp "$TEST_DIR/partial-before" "$TEST_DIR/preserved-prefix"
    [[ -f "$pending" && $(wc -l < .apr/queue/default.events.jsonl) -eq 3 ]]
    capture_streams queue_status_data default
    jq -e '.counts.queued==3 and (.warnings|length)==0' <<< "$CAPTURED_STDOUT"
}

@test "queue events: unknown trailing bytes remain readable but block mutation without history rewrite" {
    queue_test_workflow
    queue_append_event default enqueue entry-one '{"round":1,"include_impl":false}'
    printf 'UNKNOWN USEFUL TRAILING BYTES' >> .apr/queue/default.events.jsonl
    cp .apr/queue/default.events.jsonl "$TEST_DIR/unknown-before"
    capture_streams queue_status_data default
    jq -e '.counts.queued==1 and (.warnings|length)==1' <<< "$CAPTURED_STDOUT"
    run queue_append_event default enqueue entry-two '{"round":2,"include_impl":false}'
    [[ "$status" -eq 4 ]]
    cmp "$TEST_DIR/unknown-before" .apr/queue/default.events.jsonl
}

@test "queue events: invalid completed earlier event and duplicate terminal mutation are rejected" {
    queue_test_workflow
    queue_append_event default enqueue entry-one '{"round":1,"include_impl":false}'
    queue_append_event default cancel entry-one "$(jq -nc --arg stamp "$(iso_timestamp)" '{canceled_at:$stamp,reason:"cancel queued request"}')"
    cp .apr/queue/default.events.jsonl "$TEST_DIR/canceled-before"
    run queue_append_event default start entry-one "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"runner",started_at:$stamp}')"
    [[ "$status" -eq 12 ]]
    cmp "$TEST_DIR/canceled-before" .apr/queue/default.events.jsonl
    printf '{broken earlier line}\n' > .apr/queue/bad.events.jsonl
    cat .apr/queue/default.events.jsonl >> .apr/queue/bad.events.jsonl
    run queue_status_data bad
    [[ "$status" -eq 4 ]]
}

@test "queue events: omitted terminal fields preserve binding and conflicting identities cannot append" {
    queue_test_workflow
    queue_append_event default enqueue bound '{"round":1,"include_impl":false}'
    queue_append_event default start bound "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"runner",started_at:$stamp}')"
    queue_append_event default bind bound '{"run_id":"run-a","run_record_path":"private-a","ledger_path":"canonical-a"}'
    cp .apr/queue/default.events.jsonl "$TEST_DIR/bound-before"
    run queue_append_event default bind bound '{"run_id":"run-b","run_record_path":"private-b","ledger_path":"canonical-b"}'
    [[ "$status" -eq 4 ]]
    cmp "$TEST_DIR/bound-before" .apr/queue/default.events.jsonl
    run queue_append_event default finish bound "$(jq -nc --arg stamp "$(iso_timestamp)" '{ok:true,code:"ok",exit_code:0,output_path:"answer.md",slug:"slug",finished_at:$stamp,run_id:"other"}')"
    [[ "$status" -eq 4 ]]
    cmp "$TEST_DIR/bound-before" .apr/queue/default.events.jsonl
    queue_append_event default finish bound "$(jq -nc --arg stamp "$(iso_timestamp)" '{ok:true,code:"ok",exit_code:0,output_path:"answer.md",slug:"slug",finished_at:$stamp}')"
    queue_status_data default | jq -e '.entries[0]|.status=="done" and .run_id=="run-a" and .run_record_path=="private-a" and .ledger_path=="canonical-a"'
}

@test "queue events: cancellation retains a started execution binding and eventual useful outcome" {
    queue_test_workflow
    queue_append_event default enqueue canceled '{"round":1,"include_impl":false}'
    queue_append_event default start canceled "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"runner",started_at:$stamp}')"
    queue_append_event default cancel canceled "$(jq -nc --arg stamp "$(iso_timestamp)" '{canceled_at:$stamp,reason:"retain active work"}')"
    queue_append_event default bind canceled '{"run_id":"run-a","run_record_path":"private-a","ledger_path":"canonical-a"}'
    queue_append_event default finish canceled "$(jq -nc --arg stamp "$(iso_timestamp)" '{ok:true,code:"ok",exit_code:0,output_path:"answer.md",slug:"slug",finished_at:$stamp}')"
    queue_status_data default | jq -e '.counts.canceled==1 and .entries[0].status=="canceled" and .entries[0].execution_status=="done" and .entries[0].run_id=="run-a" and .entries[0].output_path=="answer.md"'
    run queue_append_event default start canceled "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"another",started_at:$stamp}')"
    [[ "$status" -eq 12 ]]
}

@test "queue events: dangling links and unknown blank tails are held without changing bytes" {
    queue_test_workflow
    mkdir -p .apr/queue
    ln -s "$TEST_DIR/absent-target" .apr/queue/default.events.jsonl
    run queue_append_event default enqueue linked '{"round":1,"include_impl":false}'
    [[ "$status" -eq 4 && -L .apr/queue/default.events.jsonl && ! -e "$TEST_DIR/absent-target" ]]
    queue_append_event blank enqueue entry-one '{"round":1,"include_impl":false}'
    printf '\n' >> .apr/queue/blank.events.jsonl
    cp .apr/queue/blank.events.jsonl "$TEST_DIR/blank-before"
    run queue_append_event blank enqueue entry-two '{"round":2,"include_impl":false}'
    [[ "$status" -eq 4 ]]
    cmp "$TEST_DIR/blank-before" .apr/queue/blank.events.jsonl
    queue_status_data blank | jq -e '.counts.queued==1 and (.warnings|length)==1'
}

@test "queue events: a known pending prefix split inside UTF-8 recovers exact bytes" {
    queue_test_workflow
    queue_append_event default enqueue entry-one '{"round":1,"include_impl":false}'
    mkdir -p .apr/queue/.pending/default
    local pending=.apr/queue/.pending/default/utf8-pending bytes
    jq -nc --arg stamp "$(iso_timestamp)" '{schema_version:"1.0.0",ts:$stamp,sequence:2,event:"cancel",event_id:"utf8-pending",entry_id:"entry-one",workflow:"default",canceled_at:$stamp,reason:"café"}' > "$pending"
    # Trim the final é byte plus closing quote/brace/newline, leaving C3 alone.
    bytes=$(( $(wc -c < "$pending") - 4 ))
    head -c "$bytes" "$pending" >> .apr/queue/default.events.jsonl
    cp .apr/queue/default.events.jsonl "$TEST_DIR/utf8-before"
    local before; before=$(wc -c < "$TEST_DIR/utf8-before")
    queue_append_event default enqueue entry-two '{"round":2,"include_impl":false}'
    head -c "$before" .apr/queue/default.events.jsonl > "$TEST_DIR/utf8-preserved"
    cmp "$TEST_DIR/utf8-before" "$TEST_DIR/utf8-preserved"
    queue_status_data default | jq -e '.counts.canceled==1 and .counts.queued==1 and .entries[0].reason=="café" and (.warnings|length)==0'
}

queue_test_producer() {
    queue_test_workflow
    cat > "$TEST_DIR/probe-bin/oracle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    --version) printf 'oracle 1.0.0\n'; exit 0 ;;
    --help) printf '%s\n' '--notify --browser-attachments --write-output'; exit 0 ;;
    status) printf 'No active sessions\n'; exit 0 ;;
    session) exit 19 ;;
esac
for argument in "$@"; do [[ "$argument" != --render ]] || exit 0; done
output='' slug=''
while [[ "$#" -gt 0 ]]; do
    case "$1" in --write-output) output="$2"; shift ;; --slug) slug="$2"; shift ;; esac
    shift
done
count=0
[[ ! -f "$APR_QUEUE_COUNT" ]] || count=$(cat "$APR_QUEUE_COUNT")
count=$((count+1)); printf '%s\n' "$count" > "$APR_QUEUE_COUNT"
printf '%s\n' "$slug" >> "$APR_QUEUE_STARTS"
if [[ "$APR_QUEUE_MODE" == always_busy || ( "$APR_QUEUE_MODE" == busy && "$count" -eq 1 ) ]]; then printf 'ERROR: busy: another review is active\n' >&2; exit 7; fi
[[ "$APR_QUEUE_MODE" != slow ]] || sleep 2
for ((i=0;i<100;i++)); do printf 'A complete useful queue review for %s.\n' "$slug"; done > "$output"
EOF
    chmod +x "$TEST_DIR/probe-bin/oracle"
    export APR_QUEUE_COUNT="$TEST_DIR/paid-count" APR_QUEUE_STARTS="$TEST_DIR/paid-starts" APR_QUEUE_MODE="${1:-success}"
    export APR_MAX_RETRIES=1 APR_INITIAL_BACKOFF=0 APR_BUSY_MIN_SLEEP=1 APR_BUSY_MAX_SLEEP=1 APR_BUSY_WAIT_SECONDS=8 APR_RECOVERY_WAIT_SECS=0
}

@test "queue CLI: offline add status cancel and doctor share human and robot state" {
    queue_test_workflow
    export APR_CHECK_UPDATES=1
    capture_streams bash "$APR_SCRIPT" queue add 1 --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    local first; first=$(jq -r .entry_id <<< "$CAPTURED_STDOUT")
    capture_streams bash "$APR_SCRIPT" robot queue add 2 --include-impl --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.ok and .data.round==2 and .data.include_impl' <<< "$CAPTURED_STDOUT"
    capture_streams bash "$APR_SCRIPT" robot queue cancel "$first" --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams bash "$APR_SCRIPT" queue doctor --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.counts.queued==1 and .counts.canceled==1 and (.entries|length)==2' <<< "$CAPTURED_STDOUT"
    [[ ! -f "$APR_QUEUE_PROBES" && ! -f "$APR_QUEUE_NETWORK" && ! -d .apr/runs ]]
}

@test "queue runner: actual public FIFO execution produces two bound useful answers and ledgers" {
    queue_test_producer
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/first-enqueue.json"
    bash "$APR_SCRIPT" robot queue add 2 --compact > "$TEST_DIR/second-enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --until-empty --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.ok and .data.processed==2 and .data.counts.done==2 and all(.data.entries[];.execution.attempts_count==1 and .run_id!=null and .run_record_path!=null)' <<< "$CAPTURED_STDOUT"
    [[ $(cat "$APR_QUEUE_COUNT") -eq 2 ]]
    [[ $(cat "$APR_QUEUE_STARTS") == $'apr-default-round-1\napr-default-round-2' ]]
    local round id output_record
    for round in 1 2; do
        ledger_validate < ".apr/rounds/default/round_$round.meta.json"
        id=$(jq -r .queue_entry_id ".apr/rounds/default/round_$round.meta.json")
        output_record=$(jq -c --arg id "$id" '.data.entries[]|select(.entry_id==$id)' <<< "$CAPTURED_STDOUT")
        [[ $(jq -r .run_id <<< "$output_record") == "$(jq -r .run_id ".apr/rounds/default/round_$round.meta.json")" ]]
        [[ $(jq -r .output_observation.sha256 ".apr/rounds/default/round_$round.meta.json") == "$(document_sha256_stdin < ".apr/rounds/default/round_$round.md")" ]]
        [[ $(wc -c < ".apr/rounds/default/round_$round.md") -gt 2000 ]]
    done
    capture_streams bash "$APR_SCRIPT" queue run --once --json
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 2 ]]
    jq -e '.processed==0 and .counts.done==2' <<< "$CAPTURED_STDOUT"
}

@test "queue runner: once max and canceled scheduling execute only selected FIFO work" {
    queue_test_producer
    local round first
    for round in 1 2 3; do bash "$APR_SCRIPT" queue add "$round" --json > "$TEST_DIR/enqueue-$round.json"; done
    first=$(jq -r .entry_id "$TEST_DIR/enqueue-1.json")
    bash "$APR_SCRIPT" queue cancel "$first"
    capture_streams bash "$APR_SCRIPT" queue run --once --json
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    jq -e '.processed==1 and .counts=={queued:1,running:0,done:1,failed:0,canceled:1}' <<< "$CAPTURED_STDOUT"
    capture_streams bash "$APR_SCRIPT" robot queue run --max 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 2 ]]
    jq -e '.data.processed==1 and .data.counts.queued==0' <<< "$CAPTURED_STDOUT"
    [[ ! -f .apr/rounds/default/round_1.md ]]
    run bash "$APR_SCRIPT" robot queue run --max 0 --compact
    [[ "$status" -eq 2 ]]
}

@test "queue runner: local lint failure records failed queue and early ledger without Oracle" {
    queue_test_workflow
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    cp SPECIFICATION.md "$TEST_DIR/spec-before"
    printf '' > SPECIFICATION.md
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_QUEUE_PROBES" ]]
    jq -e '.ok==false and .code=="validation_failed" and .data.counts.failed==1 and .data.entries[0].execution.attempts_count==0' <<< "$CAPTURED_STDOUT"
    jq -e '.state=="failed" and .outcome.code=="validation_failed" and .outcome.exit_code==4 and .queue_entry_id!=null and .execution.attempts_count==0' .apr/rounds/default/round_1.meta.json
}

@test "queue runner: actual busy producer waits then succeeds with matching wait counters" {
    queue_test_producer busy
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 2 ]]
    jq -e '.ok and .data.entries[0].execution.attempts_count==2 and .data.entries[0].execution.busy_wait_count>0' <<< "$CAPTURED_STDOUT"
    [[ $(jq -c .execution .apr/rounds/default/round_1.meta.json) == "$(jq -c .data.entries[0].execution <<< "$CAPTURED_STDOUT")" ]]
}

@test "queue runner: completed controller interruption reconciles same run without another producer" {
    queue_test_producer
    queue_append_event default enqueue interrupted '{"round":1,"include_impl":false}'
    queue_append_event default start interrupted "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"interrupted-controller",started_at:$stamp}')"
    export APR_QUEUE_ENTRY_ID=interrupted
    bash "$APR_SCRIPT" robot run 1 --compact > "$TEST_DIR/original-launch.json"
    local record; record=$(jq -r .data.run_record_path "$TEST_DIR/original-launch.json")
    for ((i=0;i<100;i++)); do [[ ! -f "$record" ]] || break; sleep 0.1; done
    [[ -f "$record" && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    jq -e '.data.counts.done==1 and .data.entries[0].run_id!=null' <<< "$CAPTURED_STDOUT"
    [[ $(jq -r .data.entries[0].run_id <<< "$CAPTURED_STDOUT") == "$(jq -r .run_id "$record")" ]]
}

@test "queue runner: unresolved started execution holds later work and never relaunches" {
    queue_test_producer
    queue_append_event default enqueue uncertain '{"round":1,"include_impl":false}'
    queue_append_event default start uncertain "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"unknown-controller",started_at:$stamp}')"
    bash "$APR_SCRIPT" queue add 2 --json > "$TEST_DIR/later-enqueue.json"
    cp .apr/queue/default.events.jsonl "$TEST_DIR/uncertain-before"
    capture_streams bash "$APR_SCRIPT" robot queue run --compact
    [[ "$CAPTURED_STATUS" -eq 12 && ! -f "$APR_QUEUE_COUNT" ]]
    assert_json_value "$CAPTURED_STDOUT" .code busy
    cmp "$TEST_DIR/uncertain-before" .apr/queue/default.events.jsonl
    queue_status_data default | jq -e '.counts.running==1 and .counts.queued==1'
}

@test "queue runner: a competing controller is refused while the actual slow worker is preserved" {
    queue_test_producer slow
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    bash "$APR_SCRIPT" robot queue run --once --compact > "$TEST_DIR/first-run.json" 2> "$TEST_DIR/first-run.stderr" &
    local runner_pid=$!
    for ((i=0;i<100;i++)); do [[ ! -f "$APR_QUEUE_COUNT" ]] || break; sleep 0.05; done
    [[ -f "$APR_QUEUE_COUNT" ]]
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 12 ]]
    assert_json_value "$CAPTURED_STDOUT" .code busy
    wait "$runner_pid"
    jq -e '.ok and .data.counts.done==1' "$TEST_DIR/first-run.json"
    [[ $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
}

@test "queue runner: explicit busy exhaustion retains pending work and blocks later producer launches" {
    queue_test_producer always_busy
    export APR_BUSY_WAIT_SECONDS=0
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/first-enqueue.json"
    bash "$APR_SCRIPT" queue add 2 --json > "$TEST_DIR/second-enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --compact
    [[ "$CAPTURED_STATUS" -eq 12 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    jq -e '.ok==false and .code=="busy" and .data.counts.running==1 and .data.counts.failed==0 and .data.counts.queued==1 and .data.entries[0].waiting_code=="busy" and .data.entries[0].execution.attempts_count==1' <<< "$CAPTURED_STDOUT"
    capture_streams bash "$APR_SCRIPT" robot queue run --compact
    [[ "$CAPTURED_STATUS" -eq 12 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    jq -e '.outcome.code=="busy" and .oracle_failure_kind=="busy" and .execution.attempts_count==1' .apr/rounds/default/round_1.meta.json
}

@test "queue runner: active cancellation preserves useful output and records its observed completion" {
    queue_test_producer slow
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    local id runner_pid
    id=$(jq -r .entry_id "$TEST_DIR/enqueue.json")
    bash "$APR_SCRIPT" robot queue run --once --compact > "$TEST_DIR/run.json" 2> "$TEST_DIR/run.stderr" &
    runner_pid=$!
    for ((i=0;i<100;i++)); do [[ ! -f "$APR_QUEUE_COUNT" ]] || break; sleep 0.05; done
    [[ -f "$APR_QUEUE_COUNT" ]]
    bash "$APR_SCRIPT" robot queue cancel "$id" --compact > "$TEST_DIR/cancel.json"
    wait "$runner_pid"
    jq -e '.ok and .data.counts.canceled==1 and .data.entries[0].status=="canceled" and .data.entries[0].execution_status=="done" and .data.entries[0].output_path!=null' "$TEST_DIR/run.json"
    [[ $(cat "$APR_QUEUE_COUNT") -eq 1 && $(wc -c < .apr/rounds/default/round_1.md) -gt 2000 ]]
    capture_streams bash "$APR_SCRIPT" queue run --once --json
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
}

@test "queue runner: existing useful answer is preserved and a duplicate request never pays" {
    queue_test_producer
    mkdir -p .apr/rounds/default
    for ((i=0;i<100;i++)); do printf 'Earlier useful answer that must survive.\n'; done > .apr/rounds/default/round_1.md
    cp .apr/rounds/default/round_1.md "$TEST_DIR/prior-answer"
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_QUEUE_COUNT" ]]
    jq -e '.code=="validation_failed" and .data.counts.failed==1 and .data.entries[0].execution.attempts_count==0' <<< "$CAPTURED_STDOUT"
    cmp "$TEST_DIR/prior-answer" .apr/rounds/default/round_1.md
}

@test "queue runner: recovery rejects changed output bytes without paying or overwriting them" {
    queue_test_producer
    queue_append_event default enqueue changed '{"round":1,"include_impl":false}'
    queue_append_event default start changed "$(jq -nc --arg stamp "$(iso_timestamp)" '{runner_id:"interrupted-controller",started_at:$stamp}')"
    export APR_QUEUE_ENTRY_ID=changed
    bash "$APR_SCRIPT" robot run 1 --compact > "$TEST_DIR/launch.json"
    local record; record=$(jq -r .data.run_record_path "$TEST_DIR/launch.json")
    for ((i=0;i<100;i++)); do [[ ! -f "$record" ]] || break; sleep 0.1; done
    [[ -f "$record" ]]
    printf 'Useful subsequent edits.\n' >> .apr/rounds/default/round_1.md
    cp .apr/rounds/default/round_1.md "$TEST_DIR/changed-answer"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 4 && $(cat "$APR_QUEUE_COUNT") -eq 1 ]]
    cmp "$TEST_DIR/changed-answer" .apr/rounds/default/round_1.md
    queue_status_data default | jq -e '.counts.running==1 and .counts.done==0'
}

@test "queue runner: twenty actual public requests drain in order with one execution each" {
    queue_test_producer
    local round expected=''
    for ((round=1;round<=20;round++)); do
        bash "$APR_SCRIPT" queue add "$round" --json > "$TEST_DIR/enqueue-$round.json"
        expected+="apr-default-round-$round"$'\n'
    done
    capture_streams bash "$APR_SCRIPT" robot queue run --until-empty --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_QUEUE_COUNT") -eq 20 ]]
    jq -e '.ok and .data.processed==20 and .data.counts.done==20 and .data.counts.queued==0 and all(.data.entries[];.execution.attempts_count==1 and .run_id!=null)' <<< "$CAPTURED_STDOUT"
    [[ $(cat "$APR_QUEUE_STARTS") == "${expected%$'\n'}" ]]
    for ((round=1;round<=20;round++)); do
        ledger_validate < ".apr/rounds/default/round_$round.meta.json"
        [[ $(wc -c < ".apr/rounds/default/round_$round.md") -gt 2000 ]]
    done
}

@test "queue CLI: incompatible preview flags cannot accidentally execute queued paid work" {
    queue_test_producer
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    cp .apr/queue/default.events.jsonl "$TEST_DIR/queued-before"
    local flag
    for flag in --dry-run --render --show-manifest --copy; do
        capture_streams bash "$APR_SCRIPT" queue run "$flag" --json
        [[ "$CAPTURED_STATUS" -eq 2 && ! -f "$APR_QUEUE_COUNT" ]]
        [[ "$CAPTURED_STDERR" == *'APR_ERROR_CODE=usage_error'* ]]
        cmp "$TEST_DIR/queued-before" .apr/queue/default.events.jsonl
    done
}
