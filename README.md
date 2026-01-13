# Automated Plan Reviser Pro (apr)

<div align="center">
  <img src="apr_illustration.webp" alt="Automated Plan Reviser Pro - Iterative specification refinement with AI">
</div>

<div align="center">

[![Version](https://img.shields.io/badge/version-1.1.0-blue?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blueviolet?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro)
[![Runtime](https://img.shields.io/badge/runtime-Bash%204+-purple?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](https://opensource.org/licenses/MIT)

</div>

Iterative specification refinement with GPT Pro Extended Reasoning via Oracle. The missing link between your specification documents and production-ready designs.

<div align="center">
<h3>Quick Install</h3>

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/install.sh?$(date +%s)" | bash
```

<p><em>Works on Linux and macOS. Auto-installs to ~/.local/bin with PATH detection.</em></p>
</div>

---

## TL;DR

**The Problem**: Complex specifications—especially security-sensitive protocols—need multiple rounds of review. A single pass by even the best AI misses architectural issues, edge cases, and subtle flaws. Manually running 15-20 review cycles is tedious and error-prone.

**The Solution**: apr automates iterative specification refinement using GPT Pro 5.2 Extended Reasoning via [Oracle](https://github.com/steipete/oracle). Each round builds on the last, converging toward optimal architecture like a numerical optimizer.

### Why Use apr?

| Feature | What It Does |
|---------|--------------|
| **One-Command Iterations** | `apr run 5` kicks off round 5—no manual copy-paste |
| **Document Bundling** | Automatically combines README, spec, and implementation docs |
| **Background Processing** | 10-60 minute reviews run in background with notifications |
| **Session Management** | Attach/detach from running sessions, check status anytime |
| **Round History** | All outputs saved to `.apr/rounds/` with git integration |
| **Beautiful TUI** | Gum-powered interface with graceful ANSI fallback |
| **Robot Mode** | JSON API for coding agents (`apr robot run 5`) |

### Quick Example

```bash
# Set up your workflow once
$ apr setup
# → Interactive wizard: select README, spec, and implementation files

# Run iterative reviews
$ apr run 1 --login --wait    # First time: manual ChatGPT login
$ apr run 2                    # Background execution
$ apr run 3 --include-impl     # Include implementation every few rounds

# Monitor progress
$ apr status                   # Check all sessions
$ apr attach apr-default-round-3   # Attach to specific session
```

### The Convergence Pattern

```
Round 1-3:   Major architectural fixes, security gaps identified
Round 4-7:   Architecture refinements, interface improvements
Round 8-12:  Nuanced optimizations, edge case handling
Round 13+:   Polishing abstractions, converging on steady state
```

Each round, GPT Pro focuses on finer details because major issues were already addressed—like gradient descent settling into a minimum.

---

## Prepared Blurb for AGENTS.md Files

Include this in your AGENTS.md file for any projects where you want to have access to APR:

```markdown
# APR (Automated Plan Reviser Pro) — Agent Reference

Iterative specification refinement via GPT Pro Extended Reasoning. Automates
multi-round AI review of specs, saving outputs for integration.

## Quick Commands

apr setup                      # Interactive workflow wizard (first time)
apr run <N>                    # Run revision round N
apr run <N> --include-impl     # Include implementation doc
apr run <N> --dry-run          # Preview without executing
apr status                     # Check Oracle session status
apr attach <slug>              # Reattach to session
apr list                       # List configured workflows
apr history                    # Show round outputs for workflow
apr update                     # Self-update to latest version

## Robot Mode (JSON API for automation)

apr robot status               # Environment & config info
apr robot workflows            # List workflows with descriptions
apr robot init                 # Initialize .apr/ directory
apr robot validate <N>         # Pre-flight checks (run before expensive rounds!)
apr robot run <N>              # Execute round, returns {slug, pid, output_file}
apr robot help                 # Full API documentation

All robot commands return: {ok, code, data, hint?, meta: {v, ts}}
Error codes: ok | not_configured | not_found | validation_failed | oracle_error

## Key Paths

.apr/                          # Per-project config directory
.apr/config.yaml               # Default workflow setting
.apr/workflows/<name>.yaml     # Workflow definitions
.apr/rounds/<workflow>/round_N.md  # GPT Pro outputs (this is what you integrate!)

## Typical Agent Workflow

1. Validate before running (saves 30+ min on failures):
   result=$(apr robot validate 5 --workflow myspec)

2. Run the round:
   result=$(apr robot run 5 --workflow myspec)
   slug=$(echo "$result" | jq -r '.data.slug')

3. After completion, integrate .apr/rounds/<workflow>/round_N.md

## Options

-w, --workflow NAME    # Specify workflow (default: from config)
-i, --include-impl     # Include implementation document
-d, --dry-run          # Preview oracle command
--wait                 # Block until completion
--login                # Manual browser login (first time)

## Dependencies

Required: bash 4+, oracle (or npx @steipete/oracle), node 18+
Optional: gum (TUI), jq (robot mode)
```

---

## The Core Insight: Iterative Convergence

When you're designing a complex protocol specification, especially when security is involved, just one iteration of review by GPT Pro 5.2 with Extended Reasoning doesn't cut it.

**APR automates the multi-round revision workflow:**

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Round 1       │────▶│   Round 2       │────▶│   Round 3       │────▶ ...
│   Major fixes   │     │  Architecture   │     │  Refinements    │
│   Security gaps │     │  improvements   │     │  Optimizations  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
   Wild swings            Dampening              Converging
   in design              oscillations           on optimal
```

**It very much reminds me of a numerical optimizer gradually converging on a steady state after wild swings in the initial iterations.**

With each round, the specification becomes "less wrong." Not only is this a good thing because the protocol improves, but it also means that in the next round of review, GPT Pro can focus its considerable intellectual energies on the nuanced particulars and in finding just the right abstractions and interfaces because it doesn't need to put out fires in terms of outright mistakes or security problems that preoccupy it in earlier rounds.

---

## Table of Contents

- [For Coding Agents](#for-coding-agents)
- [The Core Insight](#the-core-insight-iterative-convergence)
- [Why APR Exists](#-why-apr-exists)
- [Highlights](#-highlights)
- [Quickstart](#-quickstart)
- [Usage](#-usage)
  - [Commands](#commands)
  - [Options](#options)
- [The Workflow](#-the-workflow)
- [Interactive Setup](#-interactive-setup)
- [Session Monitoring](#-session-monitoring)
- [Robot Mode](#-robot-mode-automation-api)
- [Self-Update](#-self-update)
- [The Inspiration](#-the-inspiration-flywheel-connector-protocol)
- [Design Principles](#-design-principles)
- [Architecture](#-architecture)
- [Terminal Styling](#-terminal-styling)
- [Dependencies](#-dependencies)
- [Environment Variables](#-environment-variables)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

---

## 💡 Why APR Exists

Specification review is an iterative process, not a single pass:

| Problem | Why It's Hard | How APR Solves It |
|---------|---------------|-------------------|
| **Context loss** | Each new GPT session starts fresh | Structured prompts carry full context |
| **Manual bundling** | Copying README + spec + impl is tedious | Automatic document bundling |
| **No tracking** | Easy to lose track of which round you're on | Round history with git integration |
| **Slow feedback loop** | Extended reasoning takes 10-60 minutes | Background execution with monitoring |
| **Authentication friction** | ChatGPT login expires, cookies fail | Manual login mode with persistent profile |
| **Integration gaps** | GPT output sits in a chat window | Saved to files for Claude Code integration |

APR lets you set up a workflow once, then iterate with a single command per round.

---

## ✨ Highlights

<table>
<tr>
<td width="50%">

### Beautiful Terminal UI
Powered by [gum](https://github.com/charmbracelet/gum):
- Styled banners and headers
- Interactive file picker
- Confirmation dialogs
- Graceful ANSI fallback

</td>
<td width="50%">

### Interactive Setup Wizard
Configure your workflow once:
- Select README, spec, implementation files
- Choose GPT model and reasoning level
- Automatic round output management
- Multiple workflow support

</td>
</tr>
<tr>
<td width="50%">

### Session Management
Never lose a review:
- Background execution with PID tracking
- Session status checking
- Reattachment to running sessions
- Desktop notifications on completion

</td>
<td width="50%">

### Round Tracking
Full revision history:
- Numbered round outputs
- Git-integrated workflow
- History command for review
- Multiple workflow support

</td>
</tr>
<tr>
<td width="50%">

### Robot Mode for Automation
JSON API for coding agents:
- Structured output for machine parsing
- Pre-flight validation before expensive runs
- Full status and workflow introspection
- Seamless CI/CD integration

</td>
<td width="50%">

### Secure Self-Update
Keep APR current effortlessly:
- One-command updates with `apr update`
- SHA-256 checksum verification
- Atomic installation (no partial updates)
- Optional daily update checking

</td>
</tr>
</table>

---

## ⚡ Quickstart

### Installation

**One-liner (recommended):**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/install.sh" | bash
```

<details>
<summary><strong>Manual installation</strong></summary>

```bash
# Download script
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/apr -o ~/.local/bin/apr
chmod +x ~/.local/bin/apr

# Ensure ~/.local/bin is in PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc

# Install Oracle (required)
npm install -g @steipete/oracle
```

</details>

### First Run

```bash
# 1. Run the setup wizard
apr setup

# 2. First round with manual login (required first time)
apr run 1 --login --wait

# 3. Subsequent rounds
apr run 2
apr run 3 --include-impl  # Include implementation doc every few rounds
```

---

## 🚀 Usage

```
apr [command] [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `run <round>` | Run a revision round (default if number given) |
| `setup` | Interactive workflow setup wizard |
| `status` | Check Oracle session status |
| `attach <session>` | Attach to a running/completed session |
| `list` | List all configured workflows |
| `history` | Show revision history for current workflow |
| `update` | Check for and install updates |
| `robot <cmd>` | Machine-friendly JSON interface for coding agents |
| `help` | Show help message |

### Options

| Flag | Description |
|------|-------------|
| `-w, --workflow NAME` | Workflow to use (default: from config) |
| `-i, --include-impl` | Include implementation document |
| `-d, --dry-run` | Preview without sending to GPT Pro |
| `-r, --render` | Render bundle for manual paste |
| `-c, --copy` | Copy rendered bundle to clipboard |
| `--wait` | Wait for completion (blocking) |
| `--login` | Manual login mode (first-time setup) |
| `--keep-browser` | Keep browser open after completion |
| `-q, --quiet` | Minimal output (errors only) |
| `--version` | Show version |

### Examples

```bash
# First-time setup
apr setup

# Run revision round 1 (first time requires --login)
apr run 1 --login --wait

# Run round 2 in background
apr run 2

# Run round 3 with implementation doc
apr run 3 --include-impl

# Check session status
apr status

# Attach to a running session
apr attach apr-default-round-3

# Preview what will be sent
apr run 4 --dry-run

# Render for manual paste into ChatGPT
apr run 4 --render --copy

# Use a different workflow
apr run 1 -w my-other-project
```

---

## 🔄 The Workflow

APR automates this workflow:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        APR REVISION WORKFLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐     ┌──────────────────────────────────────────────────┐   │
│  │   START     │────▶│  1. BUNDLE: Collect docs for GPT Pro review      │   │
│  │  Round N    │     │     - README (project overview)                  │   │
│  └─────────────┘     │     - Specification (the design)                 │   │
│                      │     - Implementation (optional, every 3-4 rounds)│   │
│                      └──────────────────────────────────────────────────┘   │
│                                          │                                   │
│                                          ▼                                   │
│                      ┌──────────────────────────────────────────────────┐   │
│                      │  2. ORACLE: Send to GPT Pro 5.2 Extended         │   │
│                      │     - Browser automation mode                    │   │
│                      │     - 10-60 minute processing time               │   │
│                      │     - Desktop notification on completion         │   │
│                      └──────────────────────────────────────────────────┘   │
│                                          │                                   │
│                                          ▼                                   │
│                      ┌──────────────────────────────────────────────────┐   │
│                      │  3. CAPTURE: Save GPT Pro output                 │   │
│                      │     → .apr/rounds/<workflow>/round_N.md          │   │
│                      └──────────────────────────────────────────────────┘   │
│                                          │                                   │
│                                          ▼                                   │
│                      ┌──────────────────────────────────────────────────┐   │
│                      │  4. INTEGRATE: (Manual) Paste into Claude Code   │   │
│                      │     - Prime CC with AGENTS.md, README, spec      │   │
│                      │     - Apply revisions to specification           │   │
│                      │     - Update README to match                     │   │
│                      │     - Harmonize implementation doc               │   │
│                      └──────────────────────────────────────────────────┘   │
│                                          │                                   │
│                                          ▼                                   │
│                      ┌──────────────────────────────────────────────────┐   │
│                      │  5. COMMIT: Push to git                          │   │
│                      │     - Logical commit groupings                   │   │
│                      │     - Detailed commit messages                   │   │
│                      │     - Audit trail in git history                 │   │
│                      └──────────────────────────────────────────────────┘   │
│                                          │                                   │
│                                          ▼                                   │
│                      ┌─────────────┐                                        │
│                      │    READY    │  → Start Round N+1                     │
│                      │  for next   │                                        │
│                      └─────────────┘                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why Include Implementation Every Few Rounds?

You might object that it's pointless to update the README and implementation document if we know already that we are going to make many more revisions to the specification document. But when you start thinking of each round of iteration as a sort of perturbation in an optimization process, you want these changes mirrored in the implementation as you go.

**This reduces the shock of trying to apply N revisions all at once and helps to surface problems better.** After all, when you start turning ideas into code, the faulty assumptions get surfaced earlier and can feed back into your specification revisions.

---

## 🧙 Interactive Setup

Run `apr setup` to launch the interactive wizard:

```
╔════════════════════════════════════════════════════════════╗
║    Automated Plan Reviser Pro v1.1.0                       ║
║    Iterative AI-Powered Spec Refinement                    ║
╚════════════════════════════════════════════════════════════╝

╭────────────────────────────────────────────────────────────╮
│  Welcome to the APR Setup Wizard!                          │
│                                                            │
│  This will help you configure a new revision workflow.     │
│  You'll specify your documents and review preferences.     │
╰────────────────────────────────────────────────────────────╯

[1/6] Workflow name
Workflow name: fcp-spec

[2/6] Project description
Brief description: Flywheel Connector Protocol specification

[3/6] README/Overview document
Select README file: README.md
✓ README: README.md

[4/6] Specification document
Select specification file: FCP_Specification_V2.md
✓ Specification: FCP_Specification_V2.md

[5/6] Implementation document (optional)
Do you have an implementation/reference document? [y/N] y
Select implementation file: docs/fcp_model_connectors_rust.md
✓ Implementation: docs/fcp_model_connectors_rust.md

[6/6] Review preferences
Select GPT model for reviews:
  > 5.2 Thinking (Extended Reasoning)
    gpt-5.2-pro
    gpt-5.2

╭────────────────────────────────────────────────────────────╮
│  ✓ Workflow 'fcp-spec' created successfully!               │
│                                                            │
│  To run your first revision round:                         │
│    apr run 1                                               │
│                                                            │
│  To run with implementation doc:                           │
│    apr run 1 --include-impl                                │
╰────────────────────────────────────────────────────────────╯
```

---

## 📡 Session Monitoring

APR provides multiple ways to monitor long-running reviews:

### Check All Sessions
```bash
apr status
```

### Attach to a Specific Session
```bash
apr attach apr-fcp-spec-round-5
```

### Oracle Direct Commands
```bash
# Check status
npx -y @steipete/oracle status --hours 24

# Attach with rendered output
npx -y @steipete/oracle session apr-fcp-spec-round-5 --render
```

### Desktop Notifications
APR automatically enables desktop notifications (via Oracle's `--notify` flag) so you'll be alerted when a review completes.

---

## 🤖 Robot Mode: Automation API

APR's human-friendly terminal output is beautiful for interactive use, but coding agents and automation pipelines need structured, machine-readable data. Robot mode provides a complete JSON API that makes APR a first-class citizen in automated workflows.

### Why Robot Mode Matters

The iterative refinement workflow APR enables is exactly the kind of repetitive, multi-step process that benefits from automation. A coding agent like Claude Code can:

1. **Validate before running** — Check that all preconditions are met before kicking off an expensive 30-minute GPT Pro review
2. **Run rounds programmatically** — Execute `apr robot run 5` and parse the structured response
3. **Monitor progress** — Query status and workflow information in a parseable format
4. **Handle errors gracefully** — Semantic error codes and structured error messages enable intelligent retry logic

### Response Format

All robot mode commands return a consistent JSON envelope:

```json
{
  "ok": true,
  "code": "ok",
  "data": { ... },
  "hint": "Optional helpful message for debugging",
  "meta": {
    "v": "1.1.0",
    "ts": "2026-01-12T19:14:00Z"
  }
}
```

When errors occur, `ok` becomes `false` and `code` contains a semantic error identifier:

| Code | Meaning |
|------|---------|
| `ok` | Success |
| `not_configured` | No `.apr/` directory found |
| `not_found` | Requested resource doesn't exist |
| `validation_failed` | Preconditions not met |
| `oracle_error` | Oracle invocation failed |
| `missing_argument` | Required argument not provided |
| `dependency_missing` | jq or Oracle not available |

### Commands

#### `apr robot status`

Returns complete configuration and environment status:

```bash
apr robot status
```

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "configured": true,
    "default_workflow": "fcp-spec",
    "workflow_count": 2,
    "workflows": ["fcp-spec", "auth-protocol"],
    "oracle_available": true,
    "oracle_method": "global",
    "config_dir": "/home/user/project/.apr",
    "apr_home": "/home/user/.local/share/apr"
  }
}
```

#### `apr robot workflows`

Lists all configured workflows with their descriptions:

```bash
apr robot workflows
```

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "workflows": [
      {"name": "fcp-spec", "description": "Flywheel Connector Protocol specification"},
      {"name": "auth-protocol", "description": "Authentication protocol design"}
    ]
  }
}
```

#### `apr robot init`

Initializes the `.apr/` directory structure. Idempotent—safe to call multiple times:

```bash
apr robot init
```

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "created": true,
    "existed": false
  }
}
```

#### `apr robot validate <round>`

Pre-flight validation before running a round. This is the key command for automation—it checks all preconditions without actually running anything:

```bash
apr robot validate 5 --workflow fcp-spec
```

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "valid": true,
    "errors": [],
    "warnings": [],
    "workflow": "fcp-spec",
    "round": "5"
  }
}
```

If validation fails:

```json
{
  "ok": false,
  "code": "validation_failed",
  "data": {
    "valid": false,
    "errors": [
      "Previous round output not found: .apr/rounds/fcp-spec/round_4.md",
      "Specification file not found: SPEC.md"
    ],
    "warnings": ["Implementation file not configured"],
    "workflow": "fcp-spec",
    "round": "5"
  }
}
```

**Validation checks:**
- Round number is valid and numeric
- Configuration directory exists
- Workflow exists and is readable
- README and spec files exist
- Oracle is available
- Previous round exists (if round > 1)

#### `apr robot run <round>`

Executes a revision round and returns structured status:

```bash
apr robot run 5 --workflow fcp-spec --include-impl
```

```json
{
  "ok": true,
  "code": "ok",
  "data": {
    "slug": "apr-fcp-spec-round-5-with-impl",
    "pid": 12345,
    "output_file": ".apr/rounds/fcp-spec/round_5.md",
    "workflow": "fcp-spec",
    "round": 5,
    "include_impl": true,
    "status": "running"
  }
}
```

The `slug` can be used with `apr attach` to monitor the session. The `output_file` will contain the GPT Pro response once complete.

#### `apr robot help`

Returns complete API documentation in JSON format—useful for coding agents to discover capabilities:

```bash
apr robot help
```

### Options

| Flag | Description |
|------|-------------|
| `--workflow NAME` | Specify workflow (default: from config) |
| `--include-impl`, `-i` | Include implementation document |
| `--compact` | Minified JSON output (no pretty-printing) |

### Integration Example

Here's how a coding agent might use robot mode:

```bash
# 1. Check environment
status=$(apr robot status)
if ! echo "$status" | jq -e '.data.oracle_available' > /dev/null; then
    echo "Oracle not available"
    exit 1
fi

# 2. Validate before running
validation=$(apr robot validate 5 --workflow fcp-spec)
if ! echo "$validation" | jq -e '.data.valid' > /dev/null; then
    echo "Validation failed:"
    echo "$validation" | jq '.data.errors[]'
    exit 1
fi

# 3. Run the round
result=$(apr robot run 5 --workflow fcp-spec)
slug=$(echo "$result" | jq -r '.data.slug')
output_file=$(echo "$result" | jq -r '.data.output_file')

echo "Started session: $slug"
echo "Output will be at: $output_file"
```

### Why This Design?

Robot mode follows these principles:

1. **Semantic error codes** — Machine-parseable error types enable intelligent error handling, not just string matching
2. **Pre-flight validation** — Expensive Oracle runs (10-60 minutes) shouldn't fail due to missing files; validate first
3. **Consistent envelope** — Every response has the same structure, making parsing trivial
4. **Self-documenting** — The `help` command returns structured documentation
5. **Minimal dependencies** — Only requires `jq` for JSON output formatting

---

## 🔄 Self-Update

APR includes a secure self-update mechanism that keeps your installation current without requiring manual downloads or reinstallation.

### How It Works

```bash
apr update
```

The update command:

1. **Fetches the latest version** from GitHub with a 5-second timeout
2. **Compares versions** using semantic versioning (e.g., `1.1.0 → 1.2.0`)
3. **Shows what's available** and asks for confirmation
4. **Downloads the new version** to a temporary location
5. **Verifies the download** with multiple security checks
6. **Installs atomically** — the old version is only replaced after verification succeeds

### Security Features

Self-update is designed with security as a priority:

| Feature | Purpose |
|---------|---------|
| **SHA-256 checksums** | Verifies download integrity against published checksums |
| **Script validation** | Confirms downloaded file is a valid bash script (has shebang) |
| **Syntax checking** | Runs `bash -n` to verify script parses correctly |
| **Atomic installation** | Uses temp file + move to prevent partial updates |
| **Sudo detection** | Automatically elevates privileges for system directories |

### Interactive Confirmation

Updates always require confirmation:

```
╭────────────────────────────────────────────────────────────╮
│  UPDATE AVAILABLE                                           │
│                                                             │
│  Current version: 1.1.0                                     │
│  Latest version:  1.2.0                                     │
│                                                             │
│  Install update? [y/N]                                      │
╰────────────────────────────────────────────────────────────╯
```

### Daily Update Checking

For users who want to stay current, APR supports opt-in daily update notifications:

```bash
export APR_CHECK_UPDATES=1
```

With this enabled, APR checks for updates once per day (tracked in `~/.local/share/apr/.last_update_check`) and displays a non-blocking notification if a new version is available. The check uses a 5-second timeout and never interrupts your workflow.

### Why Self-Update?

APR is a rapidly evolving tool. New features, bug fixes, and improvements are released frequently. Self-update ensures:

1. **Low friction** — No need to re-run the installer or remember download URLs
2. **Security** — Checksum verification prevents tampering
3. **Reliability** — Atomic updates mean no corrupted installations
4. **User control** — Updates are never automatic; you always confirm

---

## 📖 The Inspiration: Flywheel Connector Protocol

APR was built to automate the workflow used to develop the [Flywheel Connector Protocol](https://github.com/Dicklesworthstone/flywheel_connectors):

> The goal is to have security and isolation built in at the protocol level, and also extreme performance and reliability, with everything done in Rust in a uniform manner that conforms to the protocol specification.

### The Original Manual Workflow

This is the process APR automates:

#### Step 1: Send to GPT Pro 5.2 Extended Reasoning

```markdown
First, read this README:

\`\`\`
<paste contents of readme file>
\`\`\`

---

NOW: Carefully review this entire plan for me and come up with your best
revisions in terms of better architecture, new features, changed features,
etc. to make it better, more robust/reliable, more performant, more
compelling/useful, etc.

For each proposed change, give me your detailed analysis and
rationale/justification for why it would make the project better along
with the git-diff style change versus the original plan shown below:

\`\`\`
<paste contents of spec document>
\`\`\`
```

#### Step 2: Prime Claude Code

```
First read ALL of the AGENTS.md file and README.md file super carefully
and understand ALL of both! Then use your code investigation agent mode
to fully understand the code, and technical architecture and purpose of
the project. Read ALL of the V2 spec doc and the connector doc.
```

#### Step 3: Integrate Feedback

```
Now integrate all of this feedback (and let me know what you think of it,
whether you agree with each thing and how much) from gpt 5.2:
\`\`\`[Pasted GPT output]\`\`\`
Be meticulous and use ultrathink.
```

#### Step 4: Update README

```
We need to revise the README too for these changes (don't write about
these as "changes" however, make it read like it was always like that,
we don't have any users yet!) Use ultrathink.
```

#### Step 5: Harmonize Implementation

```
Now review docs/fcp_model_connectors_rust.md ultra carefully and ensure
it is 100% harmonized with the V2 spec and as optimized as possible
subject to those constraints.
```

#### Step 6: Commit and Push

```
Now, based on your knowledge of the project, commit all changed files
now in a series of logically connected groupings with super detailed
commit messages for each and then push. Take your time to do it right.
```

### Extended Template (Every 3-4 Rounds)

Once every few review sessions, include the implementation document:

```markdown
First, read this README:
\`\`\`<readme>\`\`\`

---

And here is a document detailing Rust implementations for the canonical
connector types that follow the specification document given below; you
should also keep the implementation in mind as you think about the
specification, since ultimately the specification needs to be translated
into the Rust code eventually!

\`\`\`<implementation>\`\`\`

---

NOW: Carefully review this entire plan...
\`\`\`<spec>\`\`\`
```

---

## 🧭 Design Principles

### 1. Iterative Convergence

Like numerical optimization, specification design converges over multiple iterations:
- Early rounds fix major issues (security gaps, architectural flaws)
- Middle rounds refine architecture
- Later rounds polish abstractions and interfaces

### 2. Grounded Abstraction

Every few rounds, including the implementation document keeps abstract specifications grounded in concrete reality. Faulty assumptions surface earlier when ideas meet code.

### 3. Audit Trail

Every round creates artifacts:
- GPT Pro output saved to `.apr/rounds/`
- Git commits capture evolution
- Both abstract "specification space" and concrete "implementation space" are tracked

### 4. Graceful Degradation

Everything has fallbacks:
- gum → ANSI colors
- Oracle global → npx
- Interactive → CLI flags

### 5. Dual Interface

APR serves two audiences with the same codebase:
- **Humans** get beautiful gum-styled output, interactive wizards, and progress indicators
- **Machines** get structured JSON via robot mode, semantic error codes, and pre-flight validation

This isn't just about having two output formats—it's about recognizing that iterative refinement workflows benefit immensely from automation, and a tool that only works interactively leaves value on the table.

### 6. Secure by Default

Security considerations are woven throughout:
- **No credential storage** — APR never touches your ChatGPT credentials; Oracle uses browser cookies
- **Checksum verification** — Downloads are verified against published SHA-256 checksums
- **Atomic operations** — Updates either complete fully or don't happen at all
- **User consent** — Nothing destructive happens without explicit confirmation

---

## 🏗️ Architecture

### Component Overview

```
apr (bash script, ~1950 LOC)
├── Core Commands
│   ├── run           # Execute revision rounds
│   ├── setup         # Interactive workflow wizard
│   ├── status        # Oracle session status
│   ├── attach        # Reattach to sessions
│   ├── list          # List workflows
│   └── history       # Round history
├── Robot Mode        # JSON API for automation
│   ├── status        # Environment introspection
│   ├── workflows     # List workflows
│   ├── init          # Initialize .apr/
│   ├── validate      # Pre-flight checks
│   ├── run           # Execute rounds
│   └── help          # API documentation
├── Self-Update       # Secure update mechanism
│   ├── Version comparison
│   ├── Checksum verification
│   └── Atomic installation
├── Gum Integration   # Beautiful TUI with ANSI fallback
└── Oracle Detection  # Global or npx fallback

.apr/ (per-project configuration)
├── config.yaml           # Global settings
├── workflows/            # Workflow definitions
│   └── <name>.yaml
├── rounds/               # Round outputs
│   └── <workflow>/
│       └── round_N.md
└── templates/            # Custom prompt templates

~/.local/share/apr/ (user data)
└── .last_update_check    # Daily update check timestamp
```

Workflow YAMLs can include `template` and `template_with_impl` block scalars to
override the Oracle prompt. If omitted, APR uses the built-in default prompt.

### File Locations

| Path | Purpose |
|------|---------|
| `~/.local/bin/apr` | Main script (default install) |
| `~/.local/share/apr/` | User data directory (XDG-compliant) |
| `~/.cache/apr/` | Cache directory (XDG-compliant) |
| `.apr/` | Per-project configuration directory |
| `.apr/config.yaml` | Global APR config for this project |
| `.apr/workflows/*.yaml` | Workflow definitions |
| `.apr/rounds/<workflow>/` | GPT Pro outputs per round |

---

## 🎨 Terminal Styling

APR uses [gum](https://github.com/charmbracelet/gum) for beautiful terminal output:

```
╔════════════════════════════════════════════════════════════╗
║    Automated Plan Reviser Pro v1.1.0                       ║
║    Iterative AI-Powered Spec Refinement                    ║
╚════════════════════════════════════════════════════════════╝

╭────────────────────────────────────────────────────────────╮
│  REVISION ROUND 5                                          │
│                                                            │
│  Workflow:     fcp-spec                                    │
│  Model:        5.2 Thinking                                │
│  Include impl: true                                        │
│  Output:       .apr/rounds/fcp-spec/round_5.md             │
╰────────────────────────────────────────────────────────────╯

✓ Oracle running in background (PID: 12345)

╭────────────────────────────────────────────────────────────╮
│  MONITORING COMMANDS                                       │
├────────────────────────────────────────────────────────────┤
│  Check status:      apr status                             │
│  Attach to session: apr attach apr-fcp-spec-round-5        │
╰────────────────────────────────────────────────────────────╯
```

### Styling Behavior

| Environment | Output Style |
|-------------|--------------|
| TTY with gum installed | Full gum styling |
| TTY without gum | ANSI color codes |
| Non-TTY (piped) | Plain text |
| CI environment (`$CI` set) | Plain text |
| `APR_NO_GUM=1` | Force ANSI fallback |
| `NO_COLOR=1` | Plain text (no colors) |

### Accessibility

APR respects the [NO_COLOR](https://no-color.org/) standard. When `NO_COLOR` is set (to any value), all colored output is disabled. This is useful for:

- Screen readers and assistive technologies
- Users with color vision deficiency
- Piping output to files or other tools
- Environments where ANSI codes cause issues

---

## 📦 Dependencies

### Required

| Package | Purpose |
|---------|---------|
| Bash 4+ | Script runtime |
| [Oracle](https://github.com/steipete/oracle) | GPT Pro browser automation (excellent tool by [Peter Steinberger](https://github.com/steipete)) |
| Node.js 18+ | Oracle runtime |
| curl or wget | Installation |

### Optional

| Package | Purpose |
|---------|---------|
| gum | Beautiful terminal UI |
| jq | Required for robot mode JSON output |

### Install Dependencies

```bash
# Node.js (if not installed)
# macOS
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# Oracle
npm install -g @steipete/oracle

# gum (optional, for beautiful UI)
# macOS
brew install gum

# Linux
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install gum

# jq (optional, for robot mode)
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

---

## 🌐 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_HOME` | Data directory | `~/.local/share/apr` |
| `APR_CACHE` | Cache directory | `~/.cache/apr` |
| `APR_CHECK_UPDATES` | Enable daily update checking | unset (set to `1` to enable) |
| `APR_NO_GUM` | Disable gum even if available | unset |
| `NO_COLOR` | Disable colored output (accessibility) | unset |
| `CI` | Detected CI environment (disables gum) | unset |

---

## 🧭 Troubleshooting

### Common Issues

<details>
<summary><strong>Oracle not found</strong></summary>

**Cause:** Node.js or Oracle not installed.

**Fix:**
```bash
# Install Node.js first, then:
npm install -g @steipete/oracle

# Or use npx (works without global install)
npx -y @steipete/oracle --version
```

</details>

<details>
<summary><strong>Browser doesn't open / cookies expired</strong></summary>

**Cause:** First run requires manual login, or session expired.

**Fix:**
```bash
apr run 1 --login --wait
# Browser opens - log into ChatGPT
# Session saved for future runs
```

</details>

<details>
<summary><strong>Session timeout</strong></summary>

**Cause:** Extended reasoning took longer than expected.

**Fix:**
```bash
# Don't re-run! Reattach to the session
apr attach apr-default-round-5

# Or use Oracle directly
npx -y @steipete/oracle session apr-default-round-5 --render
```

</details>

<details>
<summary><strong>Workflow not found</strong></summary>

**Cause:** No `.apr/` directory or workflow not set up.

**Fix:**
```bash
apr setup  # Run the setup wizard
```

</details>

<details>
<summary><strong>Robot mode returns "jq not found"</strong></summary>

**Cause:** Robot mode requires `jq` for JSON formatting.

**Fix:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora
sudo dnf install jq
```

</details>

<details>
<summary><strong>Update fails with checksum error</strong></summary>

**Cause:** Download was corrupted or tampered with.

**Fix:**
```bash
# Try again - network issues can cause incomplete downloads
apr update

# If it persists, reinstall from scratch
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/install.sh" | bash
```

</details>

<details>
<summary><strong>Permission denied during update</strong></summary>

**Cause:** APR is installed in a system directory requiring elevated privileges.

**Fix:**
APR automatically detects this and prompts for sudo. If it doesn't:
```bash
# Check where apr is installed
which apr

# If in /usr/local/bin, update will prompt for sudo
# If that fails, manually update:
sudo curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/apr -o /usr/local/bin/apr
sudo chmod +x /usr/local/bin/apr
```

</details>

---

> *About Contributions:* Please don't take this the wrong way, but I do not accept outside contributions for any of my projects. I simply don't have the mental bandwidth to review anything, and it's my name on the thing, so I'm responsible for any problems it causes; thus, the risk-reward is highly asymmetric from my perspective. I'd also have to worry about other "stakeholders," which seems unwise for tools I mostly make for myself for free. Feel free to submit issues, and even PRs if you want to illustrate a proposed fix, but know I won't merge them directly. Instead, I'll have Claude or Codex review submissions via `gh` and independently decide whether and how to address them. Bug reports in particular are welcome. Sorry if this offends, but I want to avoid wasted time and hurt feelings. I understand this isn't in sync with the prevailing open-source ethos that seeks community contributions, but it's the only way I can move at this velocity and keep my sanity.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

**[Report Bug](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/issues) · [Request Feature](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/issues)**

---

<sub>Built with [Oracle](https://github.com/steipete/oracle), [gum](https://github.com/charmbracelet/gum), and a healthy appreciation for iterative refinement.</sub>

<sub>Special thanks to [Peter Steinberger](https://github.com/steipete) for creating Oracle, the excellent browser automation tool that makes APR possible.</sub>

</div>
