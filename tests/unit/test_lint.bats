#!/usr/bin/env bats
# Public local validation/policy journeys; fixture processes are not providers.
load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    load_apr_functions
    cd "$TEST_PROJECT" || return
    export APR_NO_ORACLE_PATCH=1 APR_NO_NPX=1
}
teardown() { teardown_test_environment; }

lint_fixture() {
    mkdir -p .apr/workflows "$TEST_DIR/bin"
    printf 'Useful complete source context.\n%.0s' {1..8} > README.md
    cp README.md SPEC.md
    cp README.md IMPL.md
    cat > .apr/workflows/default.yaml <<'EOF'
documents:
  readme: README.md
  spec: SPEC.md
  implementation: IMPL.md
oracle:
  model: "5.2 Thinking"
  thinking_time: heavy
rounds:
  output_dir: .apr/rounds/default
template: |
  Review the attached complete source documents carefully.
EOF
    printf 'default_workflow: default\n' > .apr/config.yaml
    cat > "$TEST_DIR/bin/oracle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
 --version) printf 'oracle 1.0.0\n';exit 0;;
 --help) printf '%s\n' '--notify --browser-attachments --write-output';exit 0;;
 status) exit 0;;
esac
for argument in "$@";do [[ "$argument" != --render ]] || exit 0;done
printf 'producer\n' >> "$APR_LINT_PRODUCERS"
while [[ "$#" -gt 0 ]];do
 if [[ "$1" == --write-output ]];then output="$2";shift;fi
 shift
done
printf 'A useful complete local review answer.\n%.0s' {1..180} > "$output"
EOF
    chmod +x "$TEST_DIR/bin/oracle"
    export PATH="$TEST_DIR/bin:$PATH" APR_LINT_PRODUCERS="$TEST_DIR/producers"
}

@test "lint policies: fenced examples pass and outside placeholders retain precise failures" {
    local prompt=$'A useful review.\n```bash\n${EXAMPLE} {{README}} TODO: example\n```\nDone.'
    capture_streams prompt_quality_check "$prompt" '' example
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams prompt_quality_check "$prompt"$'\n{{SPEC}}' '' example
    [[ "$CAPTURED_STATUS" -eq 1 && "$PROMPT_QC_DETAILS" == *'example:6:'* ]]
    export APR_FAIL_ON_WARN=1
    capture_streams prompt_quality_check "$prompt" '' example
    [[ "$CAPTURED_STATUS" -eq 1 ]]
}

@test "lint policies: additional unfilled markers fail while shell examples can be configured" {
    local token
    for token in '${UNFILLED}' '$UNFILLED' '<REPLACE_ME>' '<INSERT>' 'TODO: fill this' 'TODO:fill' 'TBD'; do
        capture_streams prompt_quality_check "Review carefully. $token" '' prompt
        [[ "$CAPTURED_STATUS" -eq 1 && "$PROMPT_QC_DETAILS" == *'prompt:1:'* ]]
    done
    export APR_QC_SHELL_PLACEHOLDERS=0
    capture_streams prompt_quality_check 'Discuss $VALUE and ${VALUE} as literal shell syntax.' '' prompt
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams prompt_quality_check '<REPLACE_ME>' '' prompt
    [[ "$CAPTURED_STATUS" -eq 1 ]]
}

@test "lint policies: exact allowlisted tokens cannot hide a different placeholder on the same line" {
    export APR_QC_ALLOW_TOKENS='{{README}}'
    capture_streams prompt_quality_check 'Discuss {{README}} literally.' '' prompt
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams prompt_quality_check '{{README}} {{SPEC}}' '' prompt
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    export APR_QC_ALLOW_TOKENS='$FOO'
    capture_streams prompt_quality_check '$FOO' '' prompt
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams prompt_quality_check '$FOOBAR' '' prompt
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    capture_streams prompt_quality_check $'~~~~bash\n{{SPEC}}\n```\n{{SPEC}}\n~~~~\nUseful review.' '' prompt
    [[ "$CAPTURED_STATUS" -eq 0 ]]
}

@test "lint policies: authored metadata-shaped lines never hide placeholders" {
    capture_streams prompt_quality_check 'readme: path="{{README}}"; basename="README.md"' '' template
    [[ "$CAPTURED_STATUS" -eq 1 ]]
    lint_fixture
    local name='TBD ${NAME} <INSERT> {{README}}.md'
    cp README.md "$name"
    cat > .apr/workflows/default.yaml <<'EOF'
readme: 'TBD ${NAME} <INSERT> {{README}}.md'
spec: SPEC.md
model: "5.2 Thinking"
thinking_time: heavy
output_dir: .apr/rounds/default
template: |
  Carefully review the attached useful source files.
EOF
    capture_streams bash "$APR_SCRIPT" lint 1 --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.valid and any(.resolved.manifest.files[];.path=="TBD ${NAME} <INSERT> {{README}}.md" and .included and .bytes>64)' <<< "$CAPTURED_STDOUT"
}

@test "lint policies: explicit bypass is noisy recorded and still guards round arithmetic" {
    lint_fixture
    cp .apr/workflows/default.yaml "$TEST_DIR/valid-config"
    cat > .apr/workflows/default.yaml <<'EOF'
readme: README.md
spec: SPEC.md
model: "5.2 Thinking"
thinking_time: heavy
output_dir: .apr/rounds/default
template: |
  <INSERT>
EOF
    capture_streams bash "$APR_SCRIPT" run 1 --no-lint --wait --no-retry
    [[ "$CAPTURED_STATUS" -eq 0 && $(wc -l < "$APR_LINT_PRODUCERS") -eq 1 && "$CAPTURED_STDERR" == *'lint explicitly bypassed'* ]]
    jq -e '.validation.bypassed and .state=="finished" and .execution.attempts_count==1' .apr/rounds/default/round_1.meta.json
    capture_streams bash "$APR_SCRIPT" robot run 999999999999999999999 --no-lint --compact
    [[ "$CAPTURED_STATUS" -eq 2 && $(wc -l < "$APR_LINT_PRODUCERS") -eq 1 ]]
}

@test "lint policies: configured small-doc exception stays quiet in real human preflight" {
    lint_fixture
    printf 'Useful.\n' > README.md
    printf '\nreadme_warn_bytes: 0\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" run 1 --wait --no-retry
    [[ "$CAPTURED_STATUS" -eq 0 && "$CAPTURED_STDERR" != *'suspiciously small'* && $(wc -l < "$APR_LINT_PRODUCERS") -eq 1 ]]
}

@test "lint policies: strict refused runs retain policy audit and queue ignores direct bypass" {
    lint_fixture
    cp .apr/workflows/default.yaml "$TEST_DIR/valid-config"
    cat > .apr/workflows/default.yaml <<'EOF'
readme: README.md
spec: SPEC.md
model: gpt-5.2-instant
thinking_time: light
output_dir: .apr/rounds/default
template: |
  Carefully review the attached useful source files.
EOF
    export APR_FAIL_ON_WARN=1
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
    jq -e '.validation.strict and (.validation.policy_warnings|length)==2 and (.validation.policy_overrides|length)==0 and .execution.attempts_count==0 and .state=="failed"' .apr/rounds/default/round_1.meta.json
    export APR_NO_LINT=1
    bash "$APR_SCRIPT" queue add 2 --json > "$TEST_DIR/queued.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
    jq -e '.validation.bypassed==false and .validation.strict and .execution.attempts_count==0' .apr/rounds/default/round_2.meta.json
}

@test "lint policies: strict-only minima and unselected policy values are validated" {
    lint_fixture
    printf '\nreadme_warn_bytes: 0\nreadme_strict_bytes: 999\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" lint 1 --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    capture_streams bash "$APR_SCRIPT" lint 1 --json --fail-on-warn
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    jq -e 'any(.errors[];.details.role=="readme" and .details.threshold==999 and .details.bytes>64)' <<< "$CAPTURED_STDOUT"
    printf '\nimplementation_warn_bytes: nope\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" lint 1 --json
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    jq -e 'any(.errors[];.source.label=="implementation_warn_bytes" and .code=="config_error")' <<< "$CAPTURED_STDOUT"
    [[ ! -f "$APR_LINT_PRODUCERS" ]]
}

@test "lint policies: post-validation configuration drift never silently changes the paid model" {
    lint_fixture
    cp .apr/workflows/default.yaml "$TEST_DIR/accepted-config"
    check_oracle() {
        cat > .apr/workflows/default.yaml <<'EOF'
readme: README.md
spec: SPEC.md
model: gpt-5.2-instant
thinking_time: light
output_dir: .apr/rounds/default
template: |
  Review the attached complete source documents carefully.
EOF
        ORACLE_CMD=(oracle)
        [[ "${ORACLE_CMD[0]}" == oracle ]]
    }
    WAIT_MODE=true;SKIP_PREFLIGHT=true;ENABLE_RETRY=false
    [[ "$WAIT_MODE" == true && "$SKIP_PREFLIGHT" == true && "$ENABLE_RETRY" == false ]]
    capture_streams run_round 1
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
    [[ $(get_config_value model .apr/workflows/default.yaml) == gpt-5.2-instant ]]
    jq -e '.state=="failed" and .outcome.code=="attachment_mismatch" and .execution.attempts_count==0' .apr/rounds/default/round_1.meta.json
}

@test "lint policies: per-role thresholds warn by default and strict mode stops real execution" {
    lint_fixture
    printf 'Useful.\n' > README.md
    printf '\nreadme_warn_bytes: 16\nspec_warn_bytes: 0\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" lint --round 1 --json
    [[ "$CAPTURED_STATUS" -eq 0 ]]
    jq -e '.valid and any(.warnings[];.details.role=="readme" and .details.bytes==8 and .details.threshold==16)' <<< "$CAPTURED_STDOUT"
    export APR_FAIL_ON_WARN=1
    for command in 'run' 'robot run'; do
        # Intentional command splitting is confined to this fixed two-item list.
        read -r -a args <<< "$command"
        capture_streams bash "$APR_SCRIPT" "${args[@]}" 1
        [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
        [[ "$CAPTURED_STDERR" == *APR_ERROR_CODE=validation_failed* ]]
    done
    bash "$APR_SCRIPT" queue add 1 --json > "$TEST_DIR/enqueue.json"
    capture_streams bash "$APR_SCRIPT" robot queue run --once --compact
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
}

@test "lint policies: default strong settings are quiet weak settings and overrides are actionable" {
    lint_fixture
    capture_streams bash "$APR_SCRIPT" robot lint 1 --compact
    jq -e '.ok and (.data.warnings|length)==0' <<< "$CAPTURED_STDOUT"
    cp .apr/workflows/default.yaml "$TEST_DIR/strong.yaml"
    cat > .apr/workflows/default.yaml <<'EOF'
readme: README.md
spec: SPEC.md
model: gpt-5.2-instant
thinking_time: light
output_dir: .apr/rounds/default
template: |
  Carefully review the useful attached source documents.
EOF
    capture_streams bash "$APR_SCRIPT" robot lint 1 --compact
    jq -e '.ok and any(.data.warnings[];.details.policy=="model" and .source.line==3 and (.hint|contains("5.2 Thinking"))) and any(.data.warnings[];.details.policy=="thinking_time" and .source.line==4)' <<< "$CAPTURED_STDOUT"
    export APR_ALLOW_NONPRO_MODELS=1 APR_ALLOW_LIGHT_THINKING=1 APR_FAIL_ON_WARN=1
    capture_streams bash "$APR_SCRIPT" robot run 1 --compact
    [[ "$CAPTURED_STATUS" -eq 0 && $(wc -l < "$APR_LINT_PRODUCERS") -eq 1 ]]
    jq -e '.validation.policy_overrides==["nonpro_models","light_thinking"] and (.validation.policy_warnings|length)==2 and .state=="finished"' .apr/rounds/default/round_1.meta.json
}

@test "lint policies: malformed sizes and oversized round are typed before arithmetic or a producer" {
    lint_fixture
    printf '\nreadme_warn_bytes: 999999999999999999999999\n' >> .apr/workflows/default.yaml
    capture_streams bash "$APR_SCRIPT" lint 1 --json
    [[ "$CAPTURED_STATUS" -eq 4 && ! -f "$APR_LINT_PRODUCERS" ]]
    jq -e '.code=="config_error" and any(.errors[];.source.label=="readme_warn_bytes")' <<< "$CAPTURED_STDOUT"
    capture_streams bash "$APR_SCRIPT" run 99999999999999999999 --dry-run
    [[ "$CAPTURED_STATUS" -eq 2 && ! -f "$APR_LINT_PRODUCERS" ]]
}

@test "lint policies: lint and legacy validate agree offline on typed findings" {
    lint_fixture
    export APR_NO_NPX=1
    cat >> .apr/workflows/default.yaml <<'EOF'
template_with_impl: |
  <REPLACE_ME>
EOF
    capture_streams bash "$APR_SCRIPT" robot lint 1 --compact
    local lint="$CAPTURED_STDOUT"
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    capture_streams bash "$APR_SCRIPT" robot validate 1 --compact
    [[ "$CAPTURED_STATUS" -eq 4 ]]
    [[ $(jq -c .data.findings.errors <<< "$CAPTURED_STDOUT") == "$(jq -c .data.errors <<< "$lint")" ]]
    [[ $(jq -r .code <<< "$CAPTURED_STDOUT") == "$(jq -r .code <<< "$lint")" && ! -f "$APR_LINT_PRODUCERS" ]]
}

@test "lint policies: dry render and queue gates reject the same broken template without paid work" {
    lint_fixture
    printf '\ntemplate_with_impl: |\n  <INSERT>\n' >> .apr/workflows/default.yaml
    for flag in --dry-run --render; do
        capture_streams bash "$APR_SCRIPT" run 1 "$flag"
        [[ "$CAPTURED_STATUS" -eq 4 && "$CAPTURED_STDERR" == *'<INSERT>'* && ! -f "$APR_LINT_PRODUCERS" ]]
        [[ "$CAPTURED_STDERR" == *'.apr/workflows/default.yaml:'* ]]
    done
}
