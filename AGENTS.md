# AGENTS.md — Automated Plan Reviser Pro (APR)

## RULE 1 – ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is "safe" to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat "never delete files without permission" as a hard invariant.

---

## IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

---

## Project Overview

**APR (Automated Plan Reviser Pro)** is a CLI tool that automates iterative specification refinement using GPT Pro Extended Reasoning via Oracle browser automation.

### Core Concept

Like numerical optimization converging on a steady state, specification design improves through multiple iterations:

1. **Early rounds** fix major issues (security gaps, architectural flaws)
2. **Middle rounds** refine architecture and interfaces
3. **Later rounds** polish abstractions and fine-tune details

APR automates the tedious parts:
- Bundling documents (README, spec, implementation)
- Sending to GPT Pro 5.2 with Extended Reasoning
- Session management and monitoring
- Round tracking and history

---

## Bash Script Discipline

This is a **pure Bash project** (no embedded languages).

### Bash Rules

- Target **Bash 4.0+** compatibility. Use `#!/usr/bin/env bash` shebang.
- Use `set -euo pipefail` for strict error handling.
- Use ShellCheck to lint all scripts. Address all warnings at severity `warning` or higher.
- Prefer functions over inline code for reusability.
- Use meaningful variable names, avoid single letters except in loops.

### Key Patterns

- **Stream separation** — stderr for human-readable output (progress, errors), stdout for structured data.
- **XDG compliance** — Data in `~/.local/share/apr/`, cache in `~/.cache/apr/`.
- **No global `cd`** — Use absolute paths; change directory only when necessary.
- **Graceful degradation** — gum → ANSI colors, Oracle global → npx.

---

## Project Architecture

```
automated_plan_reviser_pro/
├── apr                  # Main script (~800 LOC)
├── install.sh           # Curl-bash installer
├── README.md            # Comprehensive documentation
├── AGENTS.md            # This file
├── VERSION              # Semver version file
├── LICENSE              # MIT License
├── workflows/           # Example workflow configs
│   └── fcp-example.yaml
├── templates/           # Prompt templates
│   └── standard.md
└── lib/                 # Shared functions (future)
```

### Per-Project Configuration

When APR is used in a project, it creates:

```
<project>/
└── .apr/
    ├── config.yaml           # Default workflow setting
    ├── workflows/            # Workflow definitions
    │   └── <name>.yaml
    ├── rounds/               # GPT Pro outputs
    │   └── <workflow>/
    │       └── round_N.md
    └── templates/            # Custom prompt templates
```

---

## Workflow Configuration Format

```yaml
# .apr/workflows/example.yaml

name: example
description: Example workflow for project specification

documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: docs/implementation.md  # Optional

oracle:
  model: "5.2 Thinking"

rounds:
  output_dir: .apr/rounds/example
  impl_every_n: 4  # Auto-include implementation every 4th round

template: |
  First, read this README:
  ...
```

**Key config options:**

- `impl_every_n: N` — Automatically include implementation document every Nth round (e.g., rounds 4, 8, 12...)
- This keeps the spec grounded in implementation reality without manual `--include-impl` flags

**Run APR from your project directory** where your README, spec, and implementation files live. The `.apr/` configuration is per-project.

---

## Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.

---

## Backwards Compatibility & File Sprawl

We optimize for a clean architecture now, not backwards compatibility.

- No "compat shims" or "v2" file clones.
- When changing behavior, migrate callers and remove old code.
- New files are only for genuinely new domains that don't fit existing modules.
- The bar for adding files is very high.

---

## Console Output Design

Output stream rules:
- **stderr**: All human-readable output (progress, errors, banners, `[apr]` prefix)
- **stdout**: Only structured output when applicable

Visual design:
- Use **gum** when available for beautiful terminal UI (banners, spinners, styled text)
- Fall back to ANSI color codes when gum is unavailable
- Suppress gum in CI environments or when `APR_NO_GUM=1`

---

## Dependencies

### Required

| Package | Version | Purpose |
|---------|---------|---------|
| Bash | 4.0+ | Script runtime |
| Oracle | latest | GPT Pro browser automation |
| Node.js | 18+ | Oracle runtime |
| curl/wget | any | HTTP requests |

### Optional

| Package | Purpose |
|---------|---------|
| gum | Beautiful terminal UI |

---

## Oracle Integration

APR uses [Oracle](https://github.com/steipete/oracle) for GPT Pro browser automation.

Key Oracle features used:
- `--engine browser` — Browser automation for ChatGPT webapp
- `-m "5.2 Thinking"` — Model selection with extended reasoning
- `--browser-attachments never` — **Paste inline instead of file uploads** (more reliable)
- `--slug` — Human-readable session identifier
- `--write-output` — Save response to file
- `--notify` — Desktop notification on completion (if supported)
- `--heartbeat` — Progress updates

**Critical: Inline Pasting vs File Uploads**

APR always uses `--browser-attachments never` to paste document contents directly into the chat. This is far more reliable than file uploads because:
- File uploads can fail silently or trigger "duplicate file" errors
- File uploads can trigger "you've already uploaded this file" rejections
- Inline pasting works consistently for documents up to ~200KB

Session management:
- `oracle status` — List recent sessions
- `oracle session <slug>` — Attach to session
- `oracle session <slug> --render` — View with output

For headless/SSH environments, see README.md section on Oracle Remote Setup.

---

## Issue Tracking with br (beads_rust)

All issue tracking goes through **br**. No other TODO systems.

**Note:** `br` is non-invasive—it never executes git commands directly. You must run git commands manually after `br sync --flush-only`.

Key invariants:

- `.beads/` is authoritative state and **must always be committed** with code changes.
- Do not edit `.beads/*.jsonl` directly; only via `br`.

### Basics

```bash
br ready --json                    # Check ready work
br create "Issue title" -t task    # Create issue
br update br-42 --status in_progress  # Update status
br close br-42 --reason "Done"     # Complete issue
```

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - ShellCheck for bash scripts
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   br sync --flush-only
   git add .beads/
   git commit -m "Update beads"
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

## Quality Gates

Before committing changes to `apr` or `install.sh`:

```bash
# ShellCheck
shellcheck apr install.sh

# Syntax check
bash -n apr
bash -n install.sh
```

---

## Testing Checklist

When modifying APR:

1. [ ] `apr --help` displays correctly
2. [ ] `apr setup` wizard works (interactive)
3. [ ] `apr run 1 --dry-run` shows correct command
4. [ ] `apr status` shows Oracle sessions
5. [ ] `apr list` shows workflows
6. [ ] gum fallback works when gum unavailable
7. [ ] Oracle npx fallback works when not globally installed

---

## Common Patterns

### Adding a New Command

1. Add case to `main()` function
2. Create handler function `cmd_<name>()`
3. Add to help text
4. Test interactively

### Adding a New Option

1. Add to option parsing loop in `main()`
2. Add global variable for state
3. Document in help text
4. Pass to relevant functions

### Modifying Gum Output

1. Test with gum installed
2. Test with `APR_NO_GUM=1`
3. Test in non-TTY (pipe to file)
4. Ensure ANSI fallback matches intent

---

## Security Considerations

- APR does not store credentials
- Oracle uses browser cookies for ChatGPT auth
- Session data stored locally in `.apr/`
- No data sent to external services except ChatGPT via Oracle

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-01-12 | Self-update, NO_COLOR support, checksum verification, GitHub Actions CI/release |
| 1.0.0 | 2026-01-12 | Initial release |

---

## MCP Agent Mail — Multi-Agent Coordination

A mail-like layer that lets coding agents coordinate asynchronously via MCP tools and resources. Provides identities, inbox/outbox, searchable threads, and advisory file reservations with human-auditable artifacts in Git.

### Why It's Useful

- **Prevents conflicts:** Explicit file reservations (leases) for files/globs
- **Token-efficient:** Messages stored in per-project archive, not in context
- **Quick reads:** `resource://inbox/...`, `resource://thread/...`

### Same Repository Workflow

1. **Register identity:**
   ```
   ensure_project(project_key=<abs-path>)
   register_agent(project_key, program, model)
   ```

2. **Reserve files before editing:**
   ```
   file_reservation_paths(project_key, agent_name, ["apr", "scripts/**"], ttl_seconds=3600, exclusive=true)
   ```

3. **Communicate with threads:**
   ```
   send_message(..., thread_id="FEAT-123")
   fetch_inbox(project_key, agent_name)
   acknowledge_message(project_key, agent_name, message_id)
   ```

4. **Quick reads:**
   ```
   resource://inbox/{Agent}?project=<abs-path>&limit=20
   resource://thread/{id}?project=<abs-path>&include_bodies=true
   ```

### Macros vs Granular Tools

- **Prefer macros for speed:** `macro_start_session`, `macro_prepare_thread`, `macro_file_reservation_cycle`, `macro_contact_handshake`
- **Use granular tools for control:** `register_agent`, `file_reservation_paths`, `send_message`, `fetch_inbox`, `acknowledge_message`

### Common Pitfalls

- `"from_agent not registered"`: Always `register_agent` in the correct `project_key` first
- `"FILE_RESERVATION_CONFLICT"`: Adjust patterns, wait for expiry, or use non-exclusive reservation
- **Auth errors:** If JWT+JWKS enabled, include bearer token with matching `kid`

---

## bv — Graph-Aware Triage Engine

bv is a graph-aware triage engine for Beads projects (`.beads/beads.jsonl`). It computes PageRank, betweenness, critical path, cycles, HITS, eigenvector, and k-core metrics deterministically.

**CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** It returns:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

```bash
bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Minimal: just the single top pick + claim command
```

### Command Reference

**Planning:**
| Command | Returns |
|---------|---------|
| `--robot-plan` | Parallel execution tracks with `unblocks` lists |
| `--robot-priority` | Priority misalignment detection with confidence |

**Graph Analysis:**
| Command | Returns |
|---------|---------|
| `--robot-insights` | Full metrics: PageRank, betweenness, HITS, eigenvector, critical path, cycles, k-core |
| `--robot-label-health` | Per-label health: `health_level`, `velocity_score`, `staleness`, `blocked_count` |

### jq Quick Reference

```bash
bv --robot-triage | jq '.quick_ref'                        # At-a-glance summary
bv --robot-triage | jq '.recommendations[0]'               # Top recommendation
bv --robot-plan | jq '.plan.summary.highest_impact'        # Best unblock target
bv --robot-insights | jq '.Cycles'                         # Circular deps (must fix!)
```

---

## UBS — Ultimate Bug Scanner

**Golden Rule:** `ubs <changed-files>` before every commit. Exit 0 = safe. Exit >0 = fix & re-run.

### Commands

```bash
ubs apr install.sh                      # Specific files (< 1s) — USE THIS
ubs $(git diff --name-only --cached)    # Staged files — before commit
ubs --only=bash,shell scripts/          # Language filter (3-5x faster)
ubs .                                   # Whole project
```

### Output Format

```
⚠️  Category (N errors)
    apr:42:5 – Issue description
    💡 Suggested fix
Exit code: 1
```

Parse: `file:line:col` → location | 💡 → how to fix | Exit 0/1 → pass/fail

### Fix Workflow

1. Read finding → category + fix suggestion
2. Navigate `file:line:col` → view context
3. Verify real issue (not false positive)
4. Fix root cause (not symptom)
5. Re-run `ubs <file>` → exit 0
6. Commit

### Bug Severity

- **Critical (always fix):** Command injection, unquoted variables, eval with user input
- **Important (production):** Missing error handling, unset variables, unsafe pipes
- **Contextual (judgment):** TODO/FIXME, echo debugging

---

## ast-grep vs ripgrep

**Use `ast-grep` when structure matters.** It parses code and matches AST nodes, ignoring comments/strings, and can **safely rewrite** code.

- Refactors/codemods: rename APIs, change patterns
- Policy checks: enforce patterns across a repo

**Use `ripgrep` when text is enough.** Fastest way to grep literals/regex.

- Recon: find strings, TODOs, log lines, config values
- Pre-filter: narrow candidate files before ast-grep

### Rule of Thumb

- Need correctness or **applying changes** → `ast-grep`
- Need raw speed or **hunting text** → `rg`
- Often combine: `rg` to shortlist files, then `ast-grep` to match/modify

### Bash Examples

```bash
# Find all echo statements
ast-grep run -l Bash -p 'echo $$$'

# Find unquoted variable expansions
ast-grep run -l Bash -p '$VAR'

# Quick textual hunt
rg -n 'rm -rf' -t sh

# Combine speed + precision
rg -l -t sh 'eval' | xargs ast-grep run -l Bash -p 'eval $$$'
```

---

## Morph Warp Grep — AI-Powered Code Search

**Use `mcp__morph-mcp__warp_grep` for exploratory "how does X work?" questions.** An AI agent expands your query, greps the codebase, reads relevant files, and returns precise line ranges with full context.

**Use `ripgrep` for targeted searches.** When you know exactly what you're looking for.

### When to Use What

| Scenario | Tool | Why |
|----------|------|-----|
| "How does the Oracle integration work?" | `warp_grep` | Exploratory; don't know where to start |
| "Where is session tracking handled?" | `warp_grep` | Need to understand architecture |
| "Find all uses of `gum`" | `ripgrep` | Targeted literal search |
| "Replace all `echo` with `printf`" | `ast-grep` | Structural refactor |

### warp_grep Usage

```
mcp__morph-mcp__warp_grep(
  repoPath: "/data/projects/automated_plan_reviser_pro",
  query: "How does APR manage workflow configuration?"
)
```

### Anti-Patterns

- **Don't** use `warp_grep` to find a specific function name → use `ripgrep`
- **Don't** use `ripgrep` to understand "how does X work" → wastes time with manual reads

---

## cass — Cross-Agent Session Search

`cass` indexes prior agent conversations (Claude Code, Codex, Cursor, Gemini, ChatGPT, etc.) so we can reuse solved problems.

**Rules:** Never run bare `cass` (TUI). Always use `--robot` or `--json`.

### Examples

```bash
cass health
cass search "Oracle session management" --robot --limit 5
cass view /path/to/session.jsonl -n 42 --json
cass expand /path/to/session.jsonl -n 42 -C 3 --json
cass capabilities --json
cass robot-docs guide
```

### Tips

- Use `--fields minimal` for lean output
- Filter by agent with `--agent`
- Use `--days N` to limit to recent history

stdout is data-only, stderr is diagnostics; exit code 0 means success.

Treat cass as a way to avoid re-solving problems other agents already handled.

---

<!-- bv-agent-instructions-v1 -->

## Beads Workflow Integration

This project uses [beads_viewer](https://github.com/Dicklesworthstone/beads_viewer) for issue tracking. Issues are stored in `.beads/` and tracked in git.

**Note:** `br` is non-invasive—it never executes git commands directly. You must run git commands manually after `br sync --flush-only`.

### Essential Commands

```bash
# CLI commands for agents
br ready              # Show issues ready to work (no blockers)
br list --status=open # All open issues
br show <id>          # Full issue details with dependencies
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason="Completed"
br close <id1> <id2>  # Close multiple issues at once
br sync --flush-only  # Export to JSONL (then manually: git add .beads/ && git commit)
```

### Workflow Pattern

1. **Start**: Run `br ready` to find actionable work
2. **Claim**: Use `br update <id> --status=in_progress`
3. **Work**: Implement the task
4. **Complete**: Use `br close <id>`
5. **Sync**: Run `br sync --flush-only`, then `git add .beads/ && git commit -m "Update beads"`

### Key Concepts

- **Dependencies**: Issues can block other issues. `br ready` shows only unblocked work.
- **Priority**: P0=critical, P1=high, P2=medium, P3=low, P4=backlog (use numbers, not words)
- **Types**: task, bug, feature, epic, question, docs

<!-- end-bv-agent-instructions -->

---

## Note for Codex/GPT-5.2

You constantly bother me and stop working with concerned questions that look similar to this:

```
Unexpected changes (need guidance)

- Working tree still shows edits I did not make in apr, install.sh. Please advise whether to keep/commit/revert these before any further work. I did not touch them.

Next steps (pick one)

1. Decide how to handle the unrelated modified files above so we can resume cleanly.
```

NEVER EVER DO THAT AGAIN. The answer is literally ALWAYS the same: those are changes created by the potentially dozen of other agents working on the project at the same time. This is not only a common occurence, it happens multiple times PER MINUTE. The way to deal with it is simple: you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents. Just treat those changes identically to changes that you yourself made. Just fool yourself into thinking YOU made the changes and simply don't recall it for some reason.

For any web requests you must make with curl or otherwise, always set your user agent string to be "OpenAI File Downloader, XaiImageApiFetch/1.0"
