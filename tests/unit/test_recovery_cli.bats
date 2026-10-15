#!/usr/bin/env bats
# The standalone driver runs the complete recovery command and imports APR's
# production policies. Its isolated Oracle process never starts a model review.
@test "retained-run recovery CLI preserves identity and artifacts" {
    run bash "$BATS_TEST_DIRNAME/../regression/recover_oracle_run.sh"
    printf '%s\n' "$output"
    [[ "$status" -eq 0 ]]
}
