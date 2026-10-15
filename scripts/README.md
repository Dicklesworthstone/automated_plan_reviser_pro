# Recovering retained Oracle runs

`scripts/recover_oracle_run.sh` is an explicit, checkout-based recovery command
for a robot or background APR run that has already exited. It harvests the
existing Oracle conversation; it does not start another model review.

Run it from the **project directory containing `.apr/`**, using the
`attach_target` returned by `apr robot run`:

```bash
/path/to/automated_plan_reviser_pro/scripts/recover_oracle_run.sh \
  'run:site-overview-independent:round_2.ABC123'
```

Use the real run reference from your launch response, not the illustrative
`ABC123` above. The command returns JSON containing `data.session_id`,
`data.output_file`, `data.receipt_file`, `data.output_sha256`, and
`data.already_recovered`. Read `data.output_file` to use the recovered answer.

## What it verifies

The command reuses the sibling `apr` executable's session resolver, output
validator, ledger validator, Oracle discovery and lock implementation. It does
not maintain a second copy of those policies. Its small function loader refuses
unsupported core layouts instead of silently falling back to weaker checks.

Before contacting Oracle, recovery verifies the run's terminal record and takes
the same workflow/round lock used by normal execution. The actual session must
match the absolute private output destination, the retained creation evidence
and the pre-launch inventory. Requested slugs, collision suffixes and metadata
modification times are not sufficient evidence. Missing or ambiguous identity
is refused; an active producer is not interrupted.

A concrete logical browser conversation must also be recorded. Recovery pins
that conversation, the session ID, creation timestamp, output destination and
available submitted-prompt fingerprint. It permits a new Chrome target for the
same conversation, but not a different conversation or conflicting bindings.

After the harvest, the captured Oracle summary must report the expected session,
`State: completed` and `Capture identity: matched` before the answer separator.
A zero exit code, a long answer, or a quoted `Session:` line inside the answer
cannot substitute for that confirmation. This summary contract follows Oracle
0.21.5's `src/cli/browserTabs.ts`; an unsupported summary is refused. The original
run evidence and session binding are checked again before accepting output.

## Retention and repeat invocations

The original round output, partial producer answer and terminal ledger remain
unchanged. A successful recovery writes an independent answer copy and a
`recovery.json` receipt under `.apr/runs/<workflow>/<run_id>/`. The receipt binds
the answer, captured transcript and original terminal record with SHA-256
hashes. It is published only after the accepted answer and evidence exist.

Repeated calls verify the retained receipt and bytes, then return the same
answer without another Oracle call—even after Oracle prunes its session.
Corrupted receipts or answers are retained and refused. Failed, unfinished or
identity-mismatched harvests retain their output and diagnostics without
publishing a success receipt; a later explicit retry can attempt harvest again.

Success returns zero. Invalid references return 2; missing dependencies return
3; invalid or incomplete evidence/output returns 4; lock contention returns 12.
An Oracle harvest failure preserves Oracle's native nonzero exit code.

This command is not installed by `install.sh` and is not automatically invoked
by background/robot workers. It does not rewrite a failed queue or run outcome
as if the original producer had succeeded. Consume the separate recovered
artifact explicitly. It requires the checkout's `apr`, Bash 4+, jq, Oracle and
the same `flock`/BSD `lockf` support as APR.

## Offline checks

```bash
bash tests/regression/recover_oracle_run.sh
```

The driver uses production APR helper definitions, real filesystem locks,
realistic Oracle metadata and a deterministic Oracle process fixture. It is also
included in the normal BATS unit suite through `test_recovery_cli.bats`. It does
not require Chrome, credentials, network access or a paid model invocation.
