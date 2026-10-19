#!/usr/bin/env bats
# Exact local input custody/replay; deterministic CLI fixtures are not live
# provider/model acknowledgement or response reproducibility evidence.
load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    load_apr_functions
    cd "$TEST_PROJECT" || return
    export APR_NO_NPX=1
}

teardown() { teardown_test_environment; }

replay_fixture() {
    mkdir -p .apr/workflows docs/readme docs/spec docs/implementation "$TEST_DIR/bin" "$TEST_DIR/seeds" "$TEST_DIR/capture"
    printf '\000\377Original README bytes\r\n\n' > docs/readme/source.md
    printf 'Useful specification with a distinct original byte stream.\n%.0s' {1..8} > docs/spec/source.md
    printf 'Useful implementation with a distinct original byte stream.\n%.0s' {1..8} > docs/implementation/source.md
    cp docs/readme/source.md "$TEST_DIR/seeds/readme"
    cp docs/spec/source.md "$TEST_DIR/seeds/spec"
    cp docs/implementation/source.md "$TEST_DIR/seeds/implementation"
    cat > .apr/workflows/default.yaml <<'EOF'
documents:
  readme: docs/readme/source.md
  spec: docs/spec/source.md
  implementation: docs/implementation/source.md
oracle:
  model: "5.2 Thinking" # SECRET_REPLAY_CONFIG_MARKER
  thinking_time: heavy
rounds:
  output_dir: .apr/rounds/default
  impl_every_n: 4
remote_token: SECRET_REPLAY_CONFIG_MARKER
template: |
  Keep this exact original custom review instruction.
template_with_impl: |
  Keep this exact original implementation review instruction.
credentials:
  model: SECRET_REPLAY_CONFIG_MARKER
  template: |
    SECRET_REPLAY_CONFIG_MARKER
EOF
    cp .apr/workflows/default.yaml "$TEST_DIR/seeds/config.yaml"
    printf 'default_workflow: default\n' > .apr/config.yaml
    cat > "$TEST_DIR/bin/oracle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    --version) printf 'oracle 1.0.0\n'; exit 0 ;;
    --help) printf '%s\n' '--notify --browser-attachments --write-output'; exit 0 ;;
    status) exit 0 ;;
    session) exit 19 ;;
esac
for argument in "$@"; do [[ "$argument" != --render ]] || exit 0; done
count=0
[[ ! -f "$APR_REPLAY_CAPTURE/count" ]] || count=$(cat "$APR_REPLAY_CAPTURE/count")
count=$((count+1)); printf '%s\n' "$count" > "$APR_REPLAY_CAPTURE/count"
if [[ "$APR_REPLAY_MODE" == mutate || "$APR_REPLAY_MODE" == retry ]]; then
    printf 'Edited live README after capture.\n' > docs/readme/source.md
    printf 'Edited live configuration after capture.\n' > .apr/workflows/default.yaml
fi
output='' file_index=0
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --file)
            file_index=$((file_index+1)); printf '%s\0' "$2" >> "$APR_REPLAY_CAPTURE/files-$count"
            cp "$2" "$APR_REPLAY_CAPTURE/input-$count-$file_index"; shift ;;
        -p) printf '%s' "$2" > "$APR_REPLAY_CAPTURE/prompt-$count"; shift ;;
        --write-output) output="$2"; shift ;;
    esac
    shift
done
if [[ "$APR_REPLAY_MODE" == retry && "$count" -eq 1 ]]; then printf 'Temporary network failure\n' >&2; exit 19; fi
for ((i=0;i<100;i++)); do printf 'A complete useful retained-input local review answer.\n'; done > "$output"
EOF
    chmod +x "$TEST_DIR/bin/oracle"
    export PATH="$TEST_DIR/bin:$PATH" APR_REPLAY_CAPTURE="$TEST_DIR/capture" APR_REPLAY_MODE="${1:-clean}"
    export APR_MAX_RETRIES=2 APR_INITIAL_BACKOFF=0 APR_RECOVERY_WAIT_SECS=0 APR_BUSY_WAIT_SECONDS=0
}

@test "replay: a real producer consumes original retained binary bytes after live sources change" {
    replay_fixture mutate
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    # This first assertion is a genuine old-source negative: the old producer
    # reads the edited live source, before any new replay helper is consulted.
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-1-1"
    cmp "$TEST_DIR/seeds/spec" "$APR_REPLAY_CAPTURE/input-1-2"
    local record=.apr/rounds/default/round_1.meta.json root
    root=".apr/runs/default/$(jq -r .run_id "$record")/inputs"
    [[ $(jq -r .config.sha256 "$record") == "$(document_sha256_stdin < "$TEST_DIR/seeds/config.yaml")" ]]
    [[ $(yaml_unquote "$(get_config_value model "$root/config.yaml")") == '5.2 Thinking' ]]
    [[ $(jq -r .config.sha256 "$root/bundle.json") == "$(document_sha256_stdin < "$root/config.yaml")" ]]
    [[ $(jq -r .config.source_sha256 "$root/bundle.json") == "$(document_sha256_stdin < "$TEST_DIR/seeds/config.yaml")" ]]
    cmp "$APR_REPLAY_CAPTURE/prompt-1" "$root/prompt.txt"
    [[ ! -w "$root/readme/source.md" && ! -w "$root/config.yaml" ]]
    [[ "$record" != *SECRET_REPLAY_CONFIG_MARKER* ]]
    run rg SECRET_REPLAY_CONFIG_MARKER "$record" "$root/bundle.json" "$root/config.yaml"
    [[ "$status" -eq 1 ]]
    jq -e '.state=="finished" and .inputs.files[0].path=="docs/implementation/source.md" and .replay.schema_version=="1.0.0"' "$record"
}

@test "replay: a stable producer keeps the earlier useful byte-selection control" {
    replay_fixture
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-1-1"
    cmp "$TEST_DIR/seeds/spec" "$APR_REPLAY_CAPTURE/input-1-2"
    [[ $(wc -c < .apr/rounds/default/round_1.md) -gt 2000 ]]
}

@test "replay: offline export survives missing live files and another working directory" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    local record="$TEST_PROJECT/.apr/rounds/default/round_1.meta.json"
    mkdir "$TEST_DIR/originals-retained"
    mv -n docs "$TEST_DIR/originals-retained/docs"
    mv -n .apr/workflows "$TEST_DIR/originals-retained/workflows"
    cat > "$TEST_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'UNEXPECTED NETWORK PROBE\n' >> "$APR_REPLAY_CAPTURE/network"
exit 99
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export APR_CHECK_UPDATES=1
    cd "$TEST_DIR" || return
    capture_streams bash "$APR_SCRIPT" replay "$record" --json --include-bytes
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 && ! -f "$APR_REPLAY_CAPTURE/network" ]]
    jq -e '(.files|length)==2 and (.prompt.base64|length)>0 and .resolved_config.model=="5.2 Thinking" and (has("raw_config")|not)' <<< "$CAPTURED_STDOUT"
    jq -r '.files[]|select(.role=="readme")|.base64' <<< "$CAPTURED_STDOUT" | base64 --decode > "$TEST_DIR/exported-readme"
    jq -r '.prompt.base64' <<< "$CAPTURED_STDOUT" | base64 --decode > "$TEST_DIR/exported-prompt"
    cmp "$TEST_DIR/seeds/readme" "$TEST_DIR/exported-readme"
    cmp "$APR_REPLAY_CAPTURE/prompt-1" "$TEST_DIR/exported-prompt"
    capture_streams bash "$APR_SCRIPT" robot replay "$record" --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.ok and (.data.prompt|has("base64")|not) and all(.data.files[];has("base64")|not)' <<< "$CAPTURED_STDOUT"
}

@test "replay: queued cadence preserves duplicate basenames and exact selected snapshots" {
    replay_fixture
    bash "$APR_SCRIPT" queue add 4 --json > "$TEST_DIR/enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-1-1"
    cmp "$TEST_DIR/seeds/implementation" "$APR_REPLAY_CAPTURE/input-1-2"
    cmp "$TEST_DIR/seeds/spec" "$APR_REPLAY_CAPTURE/input-1-3"
    capture_streams bash "$APR_SCRIPT" robot replay 4 --include-bytes --compact
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.ok and [.data.files[].role]==["readme","implementation","spec"] and all(.data.files[];.basename=="source.md") and any(.data.files[];.role=="implementation" and .reason=="impl_every_n")' <<< "$CAPTURED_STDOUT"
    [[ $(jq -r .data.prompt.sha256 <<< "$CAPTURED_STDOUT") == "$(document_sha256_stdin < "$APR_REPLAY_CAPTURE/prompt-1")" ]]
}

@test "replay: every transient retry uses the same captured files and exact prompt" {
    replay_fixture retry
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-preflight --retry
    [[ "$CAPTURED_STATUS" -eq 0 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 2 ]]
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-1-1"
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-2-1"
    cmp "$APR_REPLAY_CAPTURE/files-1" "$APR_REPLAY_CAPTURE/files-2"
    cmp "$APR_REPLAY_CAPTURE/prompt-1" "$APR_REPLAY_CAPTURE/prompt-2"
    jq -e '.execution.attempts_count==2 and .execution.retries_count==1 and .state=="finished"' .apr/rounds/default/round_1.meta.json
}

@test "replay: historical run bundle remains usable after a successful human rerun" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/first.stdout" 2> "$TEST_DIR/first.stderr"
    local first_id; first_id=$(jq -r .run_id .apr/rounds/default/round_1.meta.json)
    cp .apr/rounds/default/round_1.md "$TEST_DIR/first-answer"
    printf 'Useful incremental later source bytes.\n' >> docs/spec/source.md
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/second.stdout" 2> "$TEST_DIR/second.stderr"
    cmp "$TEST_DIR/first-answer" .apr/rounds/default/round_1.md
    capture_streams bash "$APR_SCRIPT" replay ".apr/runs/default/$first_id/terminal.meta.json" --include-bytes --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -r '.files[]|select(.role=="spec")|.base64' <<< "$CAPTURED_STDOUT" | base64 --decode > "$TEST_DIR/historical-spec"
    cmp "$TEST_DIR/seeds/spec" "$TEST_DIR/historical-spec"
    [[ $(jq -r .run_id <<< "$CAPTURED_STDOUT") == "$first_id" && $(jq -r .run_id .apr/rounds/default/round_1.meta.json) != "$first_id" ]]
}

@test "replay: tampered saved bytes refuse replay without consulting useful live sources" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    local file; file=".apr/runs/default/$(jq -r .run_id .apr/rounds/default/round_1.meta.json)/inputs/readme/source.md"
    cp "$file" "$TEST_DIR/untampered-snapshot"
    chmod 600 "$file"
    printf 'Tampered saved bytes\n' > "$file"
    capture_streams bash "$APR_SCRIPT" robot replay 1 --include-bytes --compact
    [[ "$CAPTURED_STATUS" -eq 4 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    assert_json_value "$CAPTURED_STDOUT" .code validation_failed
    cmp "$TEST_DIR/seeds/readme" docs/readme/source.md
}

@test "replay: a snapshot symlink is rejected with its original bytes retained" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    local file; file=".apr/runs/default/$(jq -r .run_id .apr/rounds/default/round_1.meta.json)/inputs/readme/source.md"
    mv -n "$file" "$TEST_DIR/retained-snapshot"
    ln -s "$TEST_PROJECT/docs/readme/source.md" "$file"
    capture_streams bash "$APR_SCRIPT" robot replay 1 --include-bytes --compact
    [[ "$CAPTURED_STATUS" -eq 4 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    cmp "$TEST_DIR/seeds/readme" "$TEST_DIR/retained-snapshot"
}

@test "replay: prelaunch copying detects real source drift and retains an unpaid failed attempt" {
    replay_fixture
    cat > "$TEST_DIR/bin/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == ./docs/readme/source.md && "${2:-}" == */inputs/readme/source.md ]]; then
    printf 'Concurrent useful source edit before capture.\n' > docs/readme/source.md
fi
exec /bin/cp "$@"
EOF
    chmod +x "$TEST_DIR/bin/cp"
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_REPLAY_CAPTURE/count" ]]
    assert_json_value "$CAPTURED_STDOUT" .code attachment_mismatch
    jq -e '.state=="failed" and .outcome.code=="attachment_mismatch" and .execution.attempts_count==0' .apr/rounds/default/round_1.meta.json
    [[ $(cat docs/readme/source.md) == 'Concurrent useful source edit before capture.' ]]
    local captured; captured=".apr/runs/default/$(jq -r .run_id .apr/rounds/default/round_1.meta.json)/inputs/readme/source.md"
    [[ -f "$captured" && -f "$TEST_DIR/seeds/readme" ]]
}

@test "replay: legacy hash-only records refuse fallback and malformed arguments cannot probe a provider" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    jq 'del(.replay)' .apr/rounds/default/round_1.meta.json > .apr/rounds/default/legacy.meta.json
    capture_streams bash "$APR_SCRIPT" robot replay .apr/rounds/default/legacy.meta.json --compact
    [[ "$CAPTURED_STATUS" -eq 4 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
    [[ "$CAPTURED_STDERR" == *'no retained input bundle'* ]]
    capture_streams bash "$APR_SCRIPT" replay 1 extra --json
    [[ "$CAPTURED_STATUS" -eq 2 && $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
}

@test "replay: a large binary bundle exports through human and robot without argv limits" {
    replay_fixture
    dd if=/dev/zero bs=1024 count=900 >> docs/readme/source.md 2> "$TEST_DIR/dd.stderr"
    cp docs/readme/source.md "$TEST_DIR/seeds/large-readme"
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    cmp "$TEST_DIR/seeds/large-readme" "$APR_REPLAY_CAPTURE/input-1-1"
    for mode in human robot; do
        if [[ "$mode" == human ]]; then
            bash "$APR_SCRIPT" replay 1 --include-bytes --json > "$TEST_DIR/$mode.json" 2> "$TEST_DIR/$mode.stderr"
            jq -r '.files[]|select(.role=="readme")|.base64' "$TEST_DIR/$mode.json"
        else
            bash "$APR_SCRIPT" robot replay 1 --include-bytes --compact > "$TEST_DIR/$mode.json" 2> "$TEST_DIR/$mode.stderr"
            jq -er '.data.files[]|select(.role=="readme")|.base64' "$TEST_DIR/$mode.json"
        fi | base64 --decode > "$TEST_DIR/$mode-readme"
        cmp "$TEST_DIR/seeds/large-readme" "$TEST_DIR/$mode-readme"
    done
    [[ $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
}

@test "replay: verification and export keep one captured stream when saved files change" {
    replay_fixture
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    local root; root="$TEST_PROJECT/.apr/runs/default/$(jq -r .run_id .apr/rounds/default/round_1.meta.json)/inputs"
    export APR_REPLAY_REAL_SHA
    APR_REPLAY_REAL_SHA=$(command -v sha256sum)
    cat > "$TEST_DIR/bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
report=$("$APR_REPLAY_REAL_SHA" "$@")
if [[ "$report" == "$APR_REPLAY_MUTATE_HASH "* && ! -f "$APR_REPLAY_CAPTURE/race-$APR_REPLAY_RACE_ROLE" ]]; then
    printf 'mutation\n' > "$APR_REPLAY_CAPTURE/race-$APR_REPLAY_RACE_ROLE"
    chmod 600 "$APR_REPLAY_MUTATE_FILE"
    printf 'Useful later saved-file bytes.\n' > "$APR_REPLAY_MUTATE_FILE"
fi
printf '%s\n' "$report"
EOF
    chmod +x "$TEST_DIR/bin/sha256sum"
    # A hash utility consumes the full captured bytes, then changes the source
    # before returning. Neither bundle parsing nor document export may reopen it.
    for role in readme bundle; do
        export APR_REPLAY_RACE_ROLE="$role"
        if [[ "$role" == readme ]]; then export APR_REPLAY_MUTATE_FILE="$root/readme/source.md"
        else export APR_REPLAY_MUTATE_FILE="$root/bundle.json"; fi
        export APR_REPLAY_MUTATE_HASH
        APR_REPLAY_MUTATE_HASH=$("$APR_REPLAY_REAL_SHA" < "$APR_REPLAY_MUTATE_FILE"); APR_REPLAY_MUTATE_HASH="${APR_REPLAY_MUTATE_HASH%% *}"
        bash "$APR_SCRIPT" replay 1 --include-bytes --json > "$TEST_DIR/$role-race.json" 2> "$TEST_DIR/$role-race.stderr"
        [[ -f "$APR_REPLAY_CAPTURE/race-$role" ]]
        jq -r '.files[]|select(.role=="readme")|.base64' "$TEST_DIR/$role-race.json" | base64 --decode > "$TEST_DIR/$role-race-readme"
        cmp "$TEST_DIR/seeds/readme" "$TEST_DIR/$role-race-readme"
        if [[ "$role" == readme ]]; then cp "$TEST_DIR/seeds/readme" "$APR_REPLAY_MUTATE_FILE"; chmod 400 "$APR_REPLAY_MUTATE_FILE"; fi
    done
    [[ $(cat "$APR_REPLAY_CAPTURE/count") -eq 1 ]]
}

@test "replay: a large unused credential block stays out of captured applied configuration" {
    replay_fixture
    printf '  unused_auth: |\n' >> .apr/workflows/default.yaml
    for ((i=0;i<2500;i++)); do printf '    SECRET_REPLAY_CONFIG_MARKER unused credential material\n'; done >> .apr/workflows/default.yaml
    cp .apr/workflows/default.yaml "$TEST_DIR/seeds/large-config.yaml"
    bash "$APR_SCRIPT" run 1 --wait --no-preflight --no-retry > "$TEST_DIR/run.stdout" 2> "$TEST_DIR/run.stderr"
    cmp "$TEST_DIR/seeds/readme" "$APR_REPLAY_CAPTURE/input-1-1"
    local root; root=".apr/runs/default/$(jq -r .run_id .apr/rounds/default/round_1.meta.json)/inputs"
    [[ $(wc -c < "$root/config.yaml") -lt 1000 ]]
    run rg SECRET_REPLAY_CONFIG_MARKER "$root/config.yaml" "$root/bundle.json" .apr/rounds/default/round_1.meta.json
    [[ "$status" -eq 1 ]]
    [[ $(jq -r .config.sha256 .apr/rounds/default/round_1.meta.json) == "$(document_sha256_stdin < "$TEST_DIR/seeds/large-config.yaml")" ]]
}

@test "replay: scalar comments respect plain apostrophes and quoted literal hashes" {
    local config="$TEST_DIR/scalars.yaml"
    cat > "$config" <<'EOF'
readme: docs/Bob's notes.md # unused comment
spec: "docs/a # literal.md" # unused comment
implementation: 'docs/Bob''s # literal.md' # unused comment
model: plain"literal # unused comment
EOF
    [[ $(get_config_value readme "$config") == "docs/Bob's notes.md" ]]
    [[ $(yaml_unquote "$(get_config_value spec "$config")") == 'docs/a # literal.md' ]]
    [[ $(yaml_unquote "$(get_config_value implementation "$config")") == "docs/Bob's # literal.md" ]]
    [[ $(get_config_value model "$config") == 'plain"literal' ]]
    apr_capture_config "$config" "$TEST_DIR/safe-config.yaml"
    [[ $(yaml_unquote "$(get_config_value readme "$TEST_DIR/safe-config.yaml")") == "docs/Bob's notes.md" ]]
    run rg 'unused comment' "$TEST_DIR/safe-config.yaml"
    [[ "$status" -eq 1 ]]
}
