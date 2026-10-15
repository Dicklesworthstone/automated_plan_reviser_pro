# Automated Plan Reviser Pro (apr)

<div align="center">
  <img src="apr_illustration.webp" alt="Automated Plan Reviser Pro - Iterative specification refinement with AI">
</div>

<div align="center">

[![Version](https://img.shields.io/badge/version-1.3.1-blue?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blueviolet?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro)
[![Runtime](https://img.shields.io/badge/runtime-Bash%204+-purple?style=for-the-badge)](https://github.com/Dicklesworthstone/automated_plan_reviser_pro)
[![License: MIT](https://img.shields.io/badge/License-MIT%2BOpenAI%2FAnthropic%20Rider-blue-the-badge)](./LICENSE)

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

**The Problem**: Complex specifications, especially security-sensitive protocols, need multiple rounds of review. A single pass by even the best AI misses architectural issues, edge cases, and subtle flaws. Manually running 15-20 review cycles is tedious and error-prone.

**The Solution**: apr automates iterative specification refinement using GPT Pro 5.2 Extended Reasoning via [Oracle](https://github.com/steipete/oracle). Each round builds on the last, converging toward optimal architecture like a numerical optimizer.

### Why Use apr?

| Feature | What It Does |
|---------|--------------|
| **One-Command Iterations** | `apr run 5` kicks off round 5 without manual copy-paste |
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

Each round, GPT Pro focuses on finer details because major issues were already addressed, similar to gradient descent settling into a minimum.

---

## Prepared Blurb for AGENTS.md Files

Include this in your AGENTS.md file for any projects where you want to have access to APR:

```markdown
# APR (Automated Plan Reviser Pro) - Agent Reference

Iterative spec refinement via GPT Pro Extended Reasoning. Multi-round AI review
with structured outputs for Claude Code integration.

## Commands

# Workflow
apr setup                      # Interactive wizard (first time)
apr run <N>                    # Run revision round N
apr run <N> -i                 # Include implementation doc
apr run <N> -d                 # Dry-run preview
apr show <N>                   # View round output

# Analysis
apr diff <N> [M]               # Compare rounds (N vs M, or N vs N-1)
apr stats                      # Convergence analytics + remaining rounds estimate
apr integrate <N> -c           # Claude Code prompt → clipboard (KEY COMMAND)

# Management
apr status [--hours 24]        # Oracle session status
apr attach <slug>              # Reattach to session
apr list                       # List workflows
apr history                    # Round history
apr backfill                   # Generate metrics from existing rounds
apr update                     # Self-update

## Robot Mode (JSON API)

Robot mode defaults to JSON, and can also emit TOON (token-optimized) when
`tru` (toon_rust) is installed:

```bash
apr robot status --format toon
```

Format precedence:
`--format` > `APR_OUTPUT_FORMAT` > `TOON_DEFAULT_FORMAT` > `json`.

apr robot status               # {configured, workflows, oracle_available}
apr robot workflows            # [{name, description}, ...]
apr robot init                 # Create .apr/
apr robot validate <N>         # Pre-flight → {valid, errors[], warnings[]}
apr robot run <N>              # Execute → {slug, pid, output_file, log_file, status}
apr robot history              # List completed rounds
apr robot help                 # API docs

Response: {ok, code, data, hint?, meta: {v, ts}}
Codes: ok | usage_error | not_configured | config_error | validation_failed | dependency_missing | busy | internal_error

## Key Paths

.apr/rounds/<workflow>/round_N.md   # ← GPT output (INTEGRATE THIS)
.apr/analytics/<workflow>/metrics.json  # Round analytics data
.apr/logs/oracle_<slug>.log             # Oracle output log (robot mode)
.apr/workflows/<name>.yaml          # Workflow definition
.apr/config.yaml                    # Default workflow

## Agent Workflow

# 1. Validate (saves 30+ min on failures)
apr robot validate 5 -w myspec | jq -e '.data.valid' || exit 1

# 2. Run
result=$(apr robot run 5 -w myspec -i)

# 3. After completion, use integrate command or read file directly
apr integrate 5 -w myspec --copy
# File: .apr/rounds/myspec/round_5.md

# 4. Check convergence to know when to stop
apr stats -w myspec  # Score ≥0.75 = approaching stability

## Reliability Features

- Pre-flight validation before expensive Oracle runs
- Auto-retry with exponential backoff (10s → 30s → 90s)
- Session locking prevents concurrent runs
- Configurable via APR_MAX_RETRIES, APR_INITIAL_BACKOFF

## Options

-w, --workflow NAME   Workflow (default: from config)
-i, --include-impl    Include implementation doc
-d, --dry-run         Preview oracle command
-c, --copy            Copy to clipboard
-o, --output FILE     Output to file
-v, --verbose         Debug output
--wait                Block until completion
--login               Browser login (first time)
--no-preflight        Skip validation
--hours NUM           Status window (default: 72)
--compact             Minified JSON (robot mode)
--json                JSON output for stats command
--detailed            Detailed metrics for stats command

## Dependencies

Required: bash 4+, node 18+, oracle (or npx @steipete/oracle)
Optional: gum (TUI), jq (robot mode), delta (prettier diffs)
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
- [Analysis Commands](#-analysis-commands)
  - [View Round Output](#view-round-output-apr-show)
  - [Compare Rounds](#compare-rounds-apr-diff)
  - [Claude Code Integration](#claude-code-integration-apr-integrate)
- [Convergence Analytics](#-convergence-analytics)
  - [The Stats Command](#the-stats-command)
  - [Convergence Algorithm](#convergence-algorithm)
  - [Backfill Historical Data](#backfill-historical-data)
- [Reliability Features](#-reliability-features)
  - [Pre-Flight Validation](#pre-flight-validation)
  - [Auto-Retry with Backoff](#auto-retry-with-exponential-backoff)
  - [Session Locking](#session-locking)
- [Robot Mode](#-robot-mode-automation-api)
- [Self-Update](#-self-update)
- [The Inspiration](#-the-inspiration-flywheel-connector-protocol)
- [Design Principles](#-design-principles)
- [Architecture](#-architecture)
- [Testing Framework](#-testing-framework)
- [Terminal Styling](#-terminal-styling)
- [Dependencies](#-dependencies)
- [Environment Variables](#-environment-variables)
- [Oracle Remote Setup](#-oracle-remote-setup-headlessssh-environments)
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

**Important: Run APR from your project directory** (where your README, spec, and implementation files live). The `.apr/` configuration directory will be created there.

```bash
# Navigate to your project
cd /path/to/your/project

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
| **Core Workflow** | |
| `run <round>` | Run a revision round (default if number given) |
| `setup` | Interactive workflow setup wizard |
| `status` | Check Oracle session status |
| `attach <session>` | Attach to a running/completed session |
| **Management** | |
| `list` | List all configured workflows |
| `history` | Show revision history for current workflow |
| `backfill` | Generate metrics from existing rounds |
| `update` | Check for and install updates |
| `help` | Show help message |
| **Analysis** | |
| `show <round>` | View round output with pager support |
| `diff <N> [M]` | Compare round outputs (N vs M, or N vs N-1) |
| `integrate <round>` | Generate Claude Code integration prompt |
| `stats` | Show round analytics and convergence signals |
| **Automation** | |
| `robot <cmd>` | Machine-friendly JSON interface for coding agents |

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

### Automatic Implementation Inclusion

Instead of manually adding `--include-impl` every few rounds, you can configure automatic periodic inclusion in your workflow:

```yaml
# .apr/workflows/fcp.yaml
rounds:
  output_dir: .apr/rounds/fcp
  impl_every_n: 4  # Include implementation every 4th round (4, 8, 12, ...)
```

With `impl_every_n: 4`:
- Rounds 1, 2, 3: README + spec only
- Round 4: README + **impl** + spec (automatic)
- Rounds 5, 6, 7: README + spec only
- Round 8: README + **impl** + spec (automatic)
- ...and so on

This ensures implementation-grounded feedback at regular intervals without manual intervention. You can still override with `--include-impl` for any specific round.

---

## 🧙 Interactive Setup

Run `apr setup` to launch the interactive wizard:

```
╔════════════════════════════════════════════════════════════╗
║    Automated Plan Reviser Pro v1.2.0                       ║
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
Select model for reviews:
  > 5.2 Thinking (Extended Reasoning)
    gpt-5.2-pro
    gpt-5.2
    Custom / Other (any Oracle model id)

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

## 🔍 Analysis Commands

Once you've accumulated rounds of feedback, APR provides powerful tools to navigate, compare, and integrate the outputs. These commands transform raw GPT Pro output into actionable insights.

### View Round Output (`apr show`)

View any round's output with intelligent paging:

```bash
# View a specific round
apr show 5

# View from a specific workflow
apr show 3 -w my-protocol
```

The `show` command:
- Automatically uses your preferred pager (`$PAGER`, falling back to `less` or `more`)
- Supports all standard pager navigation (search with `/`, page up/down, etc.)
- Falls back to direct output when piped or in non-interactive mode

### Compare Rounds (`apr diff`)

Track how the specification evolves across iterations:

```bash
# Compare round 3 to round 4
apr diff 3 4

# Compare round 5 to its predecessor (round 4)
apr diff 5

# Use a specific diff tool
apr diff 3 5 --tool delta
```

The diff command intelligently selects the best available diff tool:
1. **delta**: Beautiful syntax-highlighted diffs with line numbers
2. **diff**: Standard UNIX diff as fallback

**Why diffs help:** Seeing what changed between rounds reveals the convergence pattern. Early diffs show major structural changes; later diffs show increasingly subtle refinements, confirming you're approaching a stable design.

### Claude Code Integration (`apr integrate`)

The `integrate` command generates prompts optimized for handing GPT Pro's feedback to Claude Code:

```bash
# Generate integration prompt
apr integrate 5

# Copy directly to clipboard
apr integrate 5 --copy

# Output to file for later use
apr integrate 5 --output round5_prompt.md
```

The generated prompt:
- Includes context priming (instructs Claude to read AGENTS.md, README, spec)
- Wraps the GPT Pro output in appropriate delimiters
- Adds integration instructions for applying changes

**Workflow tip:** Run `apr integrate 5 -c`, then paste directly into Claude Code. The prompt is structured to maximize Claude's understanding of the context and desired changes.

---

## 📊 Convergence Analytics

APR tracks metrics over time alongside running rounds, so you can see when your specification is converging toward a stable design. This turns the subjective "are we done yet?" into quantifiable signals.

### The Stats Command

```bash
# Show analytics for current workflow
apr stats

# Detailed metrics with document statistics
apr stats --detailed

# JSON output for programmatic use
apr stats --json
```

Example output:

```
╭────────────────────────────────────────────────────────────╮
│  CONVERGENCE ANALYTICS                                      │
│  Workflow: fcp-spec                                         │
├────────────────────────────────────────────────────────────┤
│  Rounds completed: 12                                       │
│  Convergence score: 0.82 (HIGH - approaching stability)    │
│  Estimated remaining: 2-3 rounds                            │
│                                                             │
│  Signal Analysis:                                           │
│    Output size trend:  ↓ decreasing (0.89)                 │
│    Change velocity:    ↓ slowing (0.78)                    │
│    Content similarity: ↑ increasing (0.79)                 │
╰────────────────────────────────────────────────────────────╯
```

### Convergence Algorithm

The convergence detector uses a weighted combination of three signals:

```
Score = (0.35 × output_trend) + (0.35 × change_velocity) + (0.30 × similarity_trend)
```

| Signal | Weight | What It Measures |
|--------|--------|------------------|
| **Output Size Trend** | 35% | Are GPT Pro's responses getting shorter? Early rounds produce lengthy analyses; convergence shows as more focused, briefer feedback. |
| **Change Velocity** | 35% | Is the rate of change slowing? Measured by comparing delta sizes between consecutive rounds. |
| **Content Similarity** | 30% | Are successive rounds becoming more similar? Uses word-level overlap to detect stabilization. |

**Interpretation:**
- **Score ≥ 0.75**: High confidence of convergence. The specification is stabilizing.
- **Score 0.50-0.74**: Moderate convergence. Significant work remains but progress is visible.
- **Score < 0.50**: Low convergence. Still in early iteration phase with major changes likely.

The algorithm also estimates remaining rounds based on the current convergence trajectory, helping you plan your workflow.

### Backfill Historical Data

If you've been running rounds before metrics collection was added, the `backfill` command generates metrics retroactively:

```bash
# Backfill metrics for all rounds
apr backfill

# Backfill for a specific workflow
apr backfill -w my-protocol

# Force regeneration even if metrics exist
apr backfill --force
```

Backfill analyzes each round's output file and generates:
- Character, word, and line counts
- Heading and section counts
- Timestamps from file metadata
- Baseline data for convergence calculations

### Interactive Dashboard

For a full-screen analytics experience:

```bash
apr dashboard
```

The dashboard provides:
- Real-time convergence gauge visualization
- Round-by-round output size trends
- Navigation with keyboard shortcuts (↑↓ navigate, Enter view details, d diff, q quit)
- Summary statistics at a glance

### Data Export

Export metrics for external analysis or reporting:

```bash
# JSON format (full metrics structure)
apr stats --export json > metrics.json

# CSV format (tabular data for spreadsheets)
apr stats --export csv > metrics.csv

# Markdown report (human-readable summary)
apr stats --export md > report.md

# Export specific round range
apr stats --export json --rounds 3-5

# Export to file directly
apr stats --export csv -o metrics.csv
```

Example JSON export structure:

```json
{
  "schema_version": "1.0.0",
  "workflow": "my-project",
  "rounds": [
    {
      "round": 1,
      "timestamp": "2026-01-10T14:30:00Z",
      "output": {
        "char_count": 15200,
        "word_count": 2500,
        "line_count": 320
      }
    }
  ],
  "convergence": {
    "detected": false,
    "confidence": 0.78,
    "signals": {
      "output_trend": 0.85,
      "change_velocity": 0.75,
      "similarity_trend": 0.72
    }
  }
}
```

Example CSV export:

```csv
"round","timestamp","output_chars","output_words","output_lines","similarity","convergence_score"
1,"2026-01-10T14:30:00Z",15200,2500,320,"",0.0
2,"2026-01-10T16:45:00Z",14100,2350,298,0.72,0.45
3,"2026-01-11T09:15:00Z",12800,2150,275,0.81,0.68
```

---

## 🛡️ Reliability Features

Extended reasoning sessions can take 30-60 minutes. APR includes multiple features to ensure these expensive operations succeed reliably.

### Pre-Flight Validation

Before sending anything to Oracle, APR validates that all preconditions are met:

```bash
# Run with explicit pre-flight (default behavior)
apr run 5

# Skip pre-flight for faster startup
apr run 5 --no-preflight
```

Pre-flight checks verify:

| Check | What It Validates |
|-------|-------------------|
| **Oracle availability** | Oracle is installed and accessible (global or npx) |
| **Workflow exists** | The specified workflow configuration is readable |
| **README exists** | The project README file is present |
| **Spec exists** | The specification document is accessible |
| **Implementation exists** | If `--include-impl`, verifies the implementation doc |
| **Previous round** | For round N > 1, verifies round N-1 exists |

**Why this matters:** Discovering a missing file 30 minutes into a GPT Pro session is frustrating. Pre-flight catches these issues in under a second.

### Auto-Retry with Exponential Backoff

Network issues, rate limits, and transient failures shouldn't require manual intervention. APR automatically retries failed Oracle operations:

```
Attempt 1 → fail → wait 10s
Attempt 2 → fail → wait 30s  (10s × 3)
Attempt 3 → success (or final failure)
```

Configuration via environment variables:

```bash
# Maximum retry attempts (default: 3)
export APR_MAX_RETRIES=5

# Initial backoff in seconds (default: 10)
export APR_INITIAL_BACKOFF=15
```

The exponential backoff (multiplier of 3) prevents hammering the service while giving transient issues time to resolve.

APR recognizes Oracle's failing stderr diagnostics `ERROR: busy` and
`User error (browser-automation): busy` as single-flight contention. Foreground
runs that exhaust their busy budget return exit 12 with `APR_ERROR_CODE=busy`;
a robot worker that exhausts its configured policy before the launch check
returns the JSON `busy` code with `data.busy: true` and `data.policy`. A worker still
retrying remains `running`. The final attempt determines the result, so an
earlier busy response cannot relabel a later authentication or network error.
Successful output, stdout prose and unrelated errors such as “device busy” are
not busy signals. Other failures retain the ordinary retry settings above.

Human runs wait for busy Oracle operations for up to **300 seconds**, independently
of `APR_MAX_RETRIES`. Busy responses do not consume ordinary retries while this
wait policy is enabled. Delays double from 5 seconds up to a 30-second cap.
Each update includes elapsed time, the next delay and single-flight guidance.
`--no-retry` remains one-shot, including when a busy wait is configured.

```bash
# Finite busy budget; min/max delays and advisory status timeout (seconds)
APR_BUSY_WAIT_SECONDS=600 APR_BUSY_MIN_SLEEP=5 APR_BUSY_MAX_SLEEP=30 apr run 5 --wait

# Explicit unbounded wait; useful when another long review must finish first
APR_BUSY_WAIT_SECONDS=infinite apr run 5 --wait

# Disable the separate busy wait and use the ordinary retry policy
APR_BUSY_WAIT_SECONDS=0 apr run 5 --wait

# Robot workers opt into waiting explicitly; default remains ordinary retries
APR_BUSY_WAIT_SECONDS=600 apr robot run 5 --compact
```

Finite values are decimal whole seconds from 0 through 86400; invalid or oversized
values use the documented defaults. Min/max delays must be positive; zero min
uses 5, and a max below the min is raised to the min. `APR_BUSY_STATUS_TIMEOUT`
defaults to 2 seconds (zero uses the default). Status probes and sleeps consume
the same busy budget, and APR does not start a new review at/after its deadline.
A review already started is allowed to finish normally.

When `timeout` or `gtimeout` is available, APR runs a bounded **no-ID** `oracle status`
diagnostic. It lists local sessions and cannot establish remote availability;
only a successful review attempt ends contention. Probe errors/timeouts cannot
replace the producer's error. Without a bounded timeout utility, APR skips this
optional diagnostic and continues its bounded retry policy. APR never attaches
to another session while polling. Robot launch JSON includes `data.busy_policy`
(`retry` or `wait`); an active waiting worker remains `running`, with progress in
its retained log and final classification in its result file. Persistent queue
integration remains pending; these options do not create or enqueue work.

If the worker has already completed successfully at the launch check, APR
validates and retains its output instead of reporting a startup failure; robot
mode returns `status: "completed"`. An incomplete or missing output is never
reported as completed. Diagnostic-capture failures stop without launching a
duplicate review.

### Preview Document Metadata Without Oracle

Inspect the documents selected by a workflow without starting a review or even
probing Oracle:

```bash
apr run 4 --show-manifest                 # Human text on stderr
apr run 4 --show-manifest --json          # Deterministic JSON on stdout
apr run 3 --show-manifest --include-impl  # Explicit implementation selection
```

The preview records each document's role, path, basename, exact observed byte
count, SHA256 and inclusion reason (`required`, `optional`, or `impl_every_n`).
It applies the existing workflow cadence and records skipped implementation
documents explicitly, with no invented hash or size. Duplicate basenames remain
distinct by role/path. Paths are safely quoted, JSON keys/rows have stable
ordering, and binary file contents are hashed as bytes. Invalid UTF-8 paths are
rejected rather than silently replaced.

Hash and size come from the same byte stream. They describe the **current local
observation**; a later writer or Oracle read may see different bytes. This
preview does not send documents, acquire a run lock, create output/log artifacts,
or assemble a review prompt. Required-file, unreadable-file and hashing failures return a
configuration error with no partial JSON manifest. `--show-manifest` takes
precedence over review/render flags.

Normal human and robot runs automatically prepend this observed metadata to
their review prompt, using the same selected files and inclusion reasons as the
Oracle file arguments. Templates need no metadata placeholders. Dry-run prints
the complete assembled prompt on stderr; render passes that same prompt to
Oracle's renderer and preserves its stdout. `apr robot validate` checks both
template variants and the selected assembled prompt, including document read
and hashing failures. Literal braces in generated JSON-quoted filenames are
escaped reversibly; unresolved template placeholders still fail prompt QC.

This binding describes local observations before Oracle reads the files. It does
not establish immutable transmitted bytes or model acknowledgement. Human,
robot and queue execution record these observations and the final prompt hash
in the persistent run ledger.

### Run Ledger Contract

The ledger contract is version `1.0.0`. Its canonical path is
`.apr/rounds/<workflow>/round_<N>.meta.json`, independently of a custom output
directory. A run has an immutable `run_id`; its workflow, round and slug identify
the selected review. A later run must preserve the earlier ledger as a separate
run record before publishing the new canonical record. Optional fields may be
added within version 1; removing or renaming fields requires a major version
change. Readers reject unsupported versions and contradictory outcomes.

The writer retains each private record candidate, atomically renames a hard-link
alias in the canonical directory, and retains the previous terminal record in
the next run's private `.apr/runs/<workflow>/round_<N>.*` directory. A stable lock
file is never unlinked. A new run refuses to replace a started record; updates
compare both run identity and the entire previous record to reject stale writers.
Malformed candidates and failed publication leave the canonical bytes intact.
This protects whole JSON records against process interruption; it does not claim
power-loss durability or a transaction spanning multiple files. Kernel locking
requires `flock` or BSD `lockf` and fails closed if neither is available.

The required fields are:

| Field | Meaning |
|---|---|
| `schema_version`, `run_id`, `workflow`, `round`, `slug` | Version and run identity; round is a nonnegative integer |
| `state` | `started`, `finished`, `failed`, or `canceled` |
| `started_at`, `finished_at`, `duration_ms` | UTC RFC3339 timestamps; finish and duration are null until terminal |
| `config.path`, `config.sha256` | Configured workflow path and observed config bytes digest; null until available |
| `inputs.status` | `pending`, `complete`, or `failed`; unavailable metadata never receives an invented hash |
| `inputs.files[]` | Role, configured path, basename, observed bytes/SHA256, included boolean, `inclusion_reason`, and `skip_reason` |
| `inputs.manifest`, `inputs.prompt_hash` | Original observed manifest and SHA256 of the exact final `-p` argument bytes, with no added newline |
| `invocation` | Browser engine, model, thinking time, sanitized remote host, flag names and redacted Oracle args |
| `execution` | `attempts_count`, ordinary `retries_count`, `busy_wait_count`, `busy_wait_total_ms`, `retry_reasons[]` |
| `outcome` | `ok`, canonical `code`, actual caller `exit_code`, native `oracle_exit_code`, and output path |

Included files have nonnegative byte sizes and lowercase SHA256; skipped optional
files have null sizes/hashes and an explicit reason. A complete observation has
one README, one specification and one implementation row (possibly skipped),
the manifest and the final prompt hash. Metadata failures may retain partial
observations with `inputs.status: "failed"`; they never claim a complete bundle.
Input hashes remain local observations rather than immutable sent bytes.
The inline manifest retains the shared helper's `reason` and display path;
ledger file rows use `inclusion_reason` and the configured path. An optional
`display_path` records a differing normalized display name. After that explicit
mapping, all three rows must agree on role, basename, bytes, hash, inclusion and
skip reason; an unrelated three-row manifest is invalid.

Started records have null finish/duration and null outcome `ok/code/exit_code`.
Successful records require `state: "finished"`, complete observed inputs,
`ok: true`, `code: "ok"` and exit 0. Failed/canceled records require a finish
timestamp, duration, `ok: false`, a non-`ok` code from APR's existing taxonomy and
a nonzero exit. Cancellation uses `internal_error` with the actual signal exit
(for example 130), with a separate interruption reason when available. Native
Oracle status is retained separately from the caller exit; legacy human and
robot exits may differ until the broader error-contract work is complete.

Remote hosts contain only host/port authority, never user information, URLs,
query parameters or tokens. Ledger metadata embeds no environment dump, raw
configuration, cookies or prompt body. Oracle arguments redact authentication values
and the prompt body; the prompt hash binds the latter. Attempt counts include
every actual producer launch; retry counts exclude busy-policy retries. Busy
wait duration measures status-probe/sleep time, not useful model execution, at
the available clock resolution. Optional `warnings`, `overrides`, `trim` and
`redaction` fields may extend the record without changing these meanings.

The executable `ledger_validate` check and state fixtures exercise this contract.
`ledger_write_start`, `ledger_bind_inputs`, `ledger_write_finish_success` and
`ledger_write_finish_error` provide the shared writer API. Writer tests exercise
real files, separate-process interruption, both kernel lock backends, publication
failure and concurrent readers. Human and robot execution now write started
observations before the producer and terminal records after validating its own
fresh output. Detached launch acknowledgement is separate from terminal success;
robot launch data includes `ledger_path`, `run_id` and `run_record_path`. The last
path names the immutable terminal record once the worker finishes. A worker owns finalization
after its parent exits. Early refused runs retain partial failed records, and a
busy contender retains a private `attempt.meta.json` without replacing the active
run. Manifest previews, dry runs and renders create no execution ledger.

Each run writes to its own private output sink. An earlier public answer is copied
into the new run directory before execution; a producer that writes nothing cannot
reuse that answer as its own successful result. Useful prior answers and new partial
answers are retained, including when automatic recovery fails. A successful human
rerun saves a distinct `round_<N>.<run_id>.md` result while retaining the earlier
public answer. Publication uses an atomic non-overwriting hard link: an arriving
peer file blocks publication, and a failed producer cannot replace a good answer. A native
Oracle success with incomplete output is a failed APR result. Robot diagnostics
use unique private log files rather than replacing an earlier run's log. These
checks use APR's existing output-completeness heuristic; they do not establish
that a live model answered correctly or acknowledged immutable attachments.

Producer stderr, the session marker, harvested answers and harvest diagnostics
remain in the private run directory. Successful recovery retains the initial
producer partial and the harvested answer before selecting the latter. Failed
recovery retains both partial answers. Raw Oracle diagnostics may contain
sensitive console output; they are private local artifacts and are not embedded
in the redacted ledger or public JSON.

Successful runs also retain `output_observation.sha256` and `bytes`. Queue
execution adds `queue_entry_id`, binding the actual run to its durable request.
New executions retain a private input bundle for deterministic local replay
after original files or templates change or disappear. This pins local producer
input bytes; it does not establish live model acknowledgement.

### Exact Input Replay

```bash
apr replay 4 --json                    # Validate saved bundle; metadata only
apr replay 4 --json --include-bytes    # Export exact prompt/doc bytes as base64
apr robot replay 4 --compact
apr replay .apr/runs/default/<run-id>/terminal.meta.json --json
```

Each real human/robot/queue execution captures selected independent document
copies under `.apr/runs/<workflow>/<run-id>/inputs/<role>/<original-basename>`.
Role directories distinguish duplicate basenames. Every producer and retry uses
those saved paths and the same final prompt, preserving configured/display
identity, inclusion reason and file order in metadata. Capture verifies the
accepted document hashes and resolved routing/selection; conflicting concurrent
changes fail before a producer. Previews still create no execution bundle.

The private `prompt.txt` preserves the exact `-p` bytes. A safe `config.yaml`
retains APR-applied scalars and template blocks, excluding unknown authentication
keys and unrelated comments. Its digest is distinct from the digest of the
single observed original configuration stream. `bundle.json` binds run identity,
the manifest, saved file sizes/hashes, safe resolved configuration and prompt
digest. Ledger `replay` references that completed descriptor by path and SHA256;
public metadata contains no raw input/configuration/prompt body or credentials.
Saved files have private, read-only modes. Partial failed captures are retained.

Replay resolves the bundle relative to the retained canonical/private record,
including historical generations and invocation from another working directory.
It validates every saved file/hash and run/manifest binding, refuses symlinks,
and never rebuilds with current templates or falls back to changed live files.
Legacy hash-only records, missing snapshots and changed saved bytes fail clearly.
No Oracle, package fallback, update probe, network call or paid review occurs.

`--include-bytes` explicitly exports private document and prompt contents; keep
that export private. Without it, both human and robot JSON report verified
metadata only. Original raw configuration is not exported. This reproduces
local producer inputs, including binary bytes and trailing newlines, rather
than promising identical future model responses, browser/model ACK, authenticated
custody against an owner rewriting hashes, or power-loss durability.

### Persistent Queue and Local Lint

```bash
apr lint 1 --json                   # Local checks; no Oracle or update probes
apr queue add 1                    # Prints the stable request ID on stderr
apr queue add 2 --include-impl
apr queue status
apr queue run                      # FIFO until empty; waits for each result
apr queue run --once                # Process one request
apr queue run --max 5               # Bound the number processed
apr queue cancel <entry-id>         # Retain history and any active worker
apr queue doctor --json             # Inspect state and trailing-record warnings
apr robot queue add 3 --compact     # Same operations in the robot JSON envelope
apr robot queue run --until-empty --compact
```

All commands accept `--workflow NAME`. Human `--json` emits raw data; robot
commands use `ok/code/data/hint/meta`. Local lint returns typed `errors[]` and
`warnings[]`, source paths, resolved document selection and observed hashes.
It checks both template variants, selected files and the assembled prompt.
The queue uses the same locally validated robot execution path and shared
ledger/output/busy helpers. `robot validate` uses the same offline decision and
canonical codes. It preserves legacy message arrays and exposes the identical
typed core result in `data.findings`. Oracle readiness is checked when execution
starts, rather than making offline validity depend on an installed provider.
Queue commands reject preview/render/copy flags before executing or changing
requests; use `lint` or `run --show-manifest` for an offline preview.

#### Local validation policies

```bash
apr lint --round 1 --json
apr robot validate 1 --compact
apr run 1 --fail-on-warn --wait
APR_FAIL_ON_WARN=1 apr robot run 1 --compact
```

Human/robot execution and dry/render previews use the shared local validator
before provider discovery. Errors identify files, best-effort YAML lines,
prompt line hits and remediation. Required selected documents must be nonempty.
By default, selected documents below64 bytes warn; customize per-role scalars
`readme_warn_bytes`, `spec_warn_bytes`, `implementation_warn_bytes` (for example
under `lint:`). A zero warning threshold permits intentionally tiny nonempty
documents. Optional `readme_strict_bytes`, `spec_strict_bytes`, and
`implementation_strict_bytes` add fatal minimums in strict mode. Thresholds and
normalized round/cadence values must be nonnegative integers of at most nine
digits. Invalid policy values are errors even for an unselected document role.
`--fail-on-warn` or `APR_FAIL_ON_WARN=1` promotes every remaining warning to a
fatal finding, including a missing prior review.

QC rejects unfilled mustache markers, `${VAR}`/uppercase `$VAR`, high-signal
`<REPLACE_ME>`/`<INSERT>`/`<FILL_ME>`/`<YOUR_NAME>` markers, `TODO:` and `TBD`.
Default QC ignores actual backtick/tilde fenced examples; strict mode scans
their contents. Closing fences must match their opening type and width.
`APR_QC_SCAN_FENCES=1` enables that scan independently. Explicitly set
`APR_QC_SHELL_PLACEHOLDERS=0` for literal shell-variable discussions, or
`APR_QC_IGNORE_QUOTES=1` to skip blockquote examples. For isolated literal
tokens use newline-separated `APR_QC_ALLOW_TOKENS`; allowing `$FOO` does not
allow `$FOOBAR`. Legacy `APR_ALLOW_CURLY_PLACEHOLDERS=1` permits curly syntax
only. Template variants and final generated prompts are checked. JSON-quoted
manifest filenames escape marker characters without altering actual names;
authored lines resembling metadata are still checked.

Models outside `5.2 Thinking`/`gpt-5.2-pro` and missing or lighter thinking time
produce concrete policy warnings. Setup's strong/heavy defaults remain quiet.
Intentional experiments can set `APR_ALLOW_NONPRO_MODELS=1` and/or
`APR_ALLOW_LIGHT_THINKING=1`. Run ledgers retain fired policy warnings, override
categories and strictness, including refused attempts; no environment dump or
raw prompt is added. These are local quality heuristics, not model-quality proof.

`--no-preflight` skips legacy readiness extras while retaining local lint.
Direct `run --no-lint` explicitly bypasses local policy, warns, and records
`validation.bypassed`; required attachment custody and round bounds still apply.
Queue entries always apply lint, even if the caller set `APR_NO_LINT=1`.

History is `.apr/queue/<workflow>.events.jsonl`: version `1.0.0`, UTC timestamp,
monotonic sequence, event ID, workflow and entry ID on every whole-line event.
`enqueue` records round and implementation selection; `start` records controller
identity/time; `bind` pins run identity and private terminal record; `finish`
and `fail` retain observed outcome, execution counters and diagnostic digest.
`cancel` preserves scheduling precedence; a started worker may finish and its
useful result is still audited with `execution_status`. Canceling queued work
prevents execution. Canceling started work never kills or replays it.

Short mutations serialize on the stable `.apr/.locks/queue.<workflow>.lock`.
One controller owns `.apr/.locks/queue-runner.<workflow>.lock`; its detached
worker inherits that ownership through completion. Stable lock files and private
pending events are retained. Reads tolerate a trailing partial/invalid record
and warn; writes repair only an exact raw-byte prefix of one retained valid
next event. Unknown or ambiguous tails, invalid earlier records, symlink logs
and conflicting run bindings are held without truncating history.

The runner waits for a validated private terminal record, not launch
acknowledgement. Restart reconciles the same completed queue-bound run and
checks successful output bytes against its digest without another producer.
Unresolved started executions or altered completed output block later work
and preserve useful files. A new request for an already occupied output fails
before producer execution, preserving the earlier answer.

Queue busy waits default to `infinite`; ordinary human/robot defaults remain
unchanged. An explicit finite `APR_BUSY_WAIT_SECONDS` exhaustion records a
`wait` event and keeps the request pending (`running`, `waiting_code: "busy"`),
stopping later jobs with exit 12. It never silently replays that attempt. Inspect
its ledger and cancel the held entry before intentionally adding another
request. An output-publication conflict is a terminal failure rather than an
Oracle-busy deferral. Batch failures are audited and processing continues; the
batch returns the first failed exit/code. These are local filesystem/process
guarantees, not model correctness, live-service or power-loss qualification.

### GPT Pro Extended Thinking Stability

GPT Pro Extended Thinking can pause for 10-30+ seconds during its reasoning phase. Without adjustment, Oracle's browser automation might interpret these pauses as "response complete" and capture truncated output.

APR automatically patches Oracle's stability detection thresholds at runtime to tolerate these long pauses:

| Parameter | Oracle Default | APR Default | Purpose |
|-----------|---------------|-------------|---------|
| `minStableMs` | 1.2s | 30s | Time text must stop changing |
| `settleWindowMs` | 5s | 30s | Completion detection window |
| `stableCycles` | 6 | 12 | Polling cycles required |

The patch is applied during pre-flight checks and persists until Oracle is updated. A backup of the original file is preserved for restoration.

**Automatic recovery:** If truncation is detected despite patching (output ends mid-word), APR waits 30 seconds (`APR_RECOVERY_WAIT_SECS`) and harvests the Oracle session (`oracle session <slug> --harvest --write-output ...`) to capture the complete response. If that fails, Oracle's own error is shown.

### Session Locking

Concurrent runs of the same workflow can cause data corruption or wasted Oracle sessions. APR uses file-based locking:

```
.apr/rounds/<workflow>/.lock
```

When a run starts:
1. APR attempts to acquire the lock
2. If locked, it displays who holds it and when it was acquired
3. Stale locks (from crashed processes) are automatically cleaned after 2 hours

```
╭────────────────────────────────────────────────────────────╮
│  ⚠ WORKFLOW LOCKED                                          │
│                                                             │
│  Workflow 'fcp-spec' is currently in use.                  │
│  Locked by: PID 12345 at 2026-01-12 14:30:00               │
│                                                             │
│  Use 'apr status' to check the running session.            │
╰────────────────────────────────────────────────────────────╯
```

---

## 🤖 Robot Mode: Automation API

APR's human-friendly terminal output is beautiful for interactive use, but coding agents and automation pipelines need structured, machine-readable data. Robot mode provides a complete JSON API that makes APR a first-class citizen in automated workflows.

### Why Robot Mode Matters

The iterative refinement workflow APR enables is exactly the kind of repetitive, multi-step process that benefits from automation. A coding agent like Claude Code can:

1. **Validate before running**: Check that all preconditions are met before kicking off an expensive 30-minute GPT Pro review
2. **Run rounds programmatically**: Execute `apr robot run 5` and parse the structured response
3. **Monitor progress**: Query status and workflow information in a parseable format
4. **Handle errors gracefully**: Semantic error codes and structured error messages enable intelligent retry logic

### Response Format

All robot mode commands return a consistent JSON envelope:

```json
{
  "ok": true,
  "code": "ok",
  "data": { ... },
  "hint": "Optional helpful message for debugging",
  "meta": {
    "v": "1.2.0",
    "ts": "2026-01-12T19:14:00Z"
  }
}
```

On failure, `ok` becomes `false` and `code` contains a stable, semantic failure class. For grep-friendly automation, fatal failures also emit a single-line stderr tag:

`APR_ERROR_CODE=<code>`

| Code | Meaning |
|------|---------|
| `ok` | Success |
| `usage_error` | Bad arguments (missing/invalid round/workflow/option) |
| `not_configured` | No `.apr/` directory / not initialized |
| `config_error` | Workflow/config invalid (missing fields/files, cannot create dirs) |
| `validation_failed` | Preconditions not met (prompt QC, output exists, metrics missing) |
| `dependency_missing` | Required dependency missing (e.g. oracle/jq) |
| `busy` | Single-flight/busy (lock held / cannot proceed without waiting) |
| `network_error` | Network/remote unreachable (when remote mode is used) |
| `update_error` | Self-update failed |
| `not_implemented` | Feature unsupported in this install |
| `internal_error` | Unexpected failure (bug/unknown state) |

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

Initializes the `.apr/` directory structure. It is idempotent and safe to call multiple times:

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

Pre-flight validation before running a round. This is the key command for automation; it checks all preconditions without actually running anything:

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
    "slug": "apr-fcp-spec-round-5",
    "session_id": "apr-fcp-spec-round-5",
    "requested_slug": "apr-fcp-spec-round-5-with-impl",
    "pid": 12345,
    "output_file": ".apr/rounds/fcp-spec/round_5.md",
    "log_file": ".apr/logs/oracle_round_5.ABC123.log.XYZ789",
    "workflow": "fcp-spec",
    "round": 5,
    "include_impl": true,
    "status": "running"
  }
}
```

The `session_id` (also returned as `slug`) is Oracle's actual session identifier and can be used with `apr attach`. `requested_slug` retains APR's original label; Oracle may shorten it or add a collision suffix. If identity cannot yet be verified, `session_id` and `slug` are `null`. The `attach_target` is a stable APR run reference (`run:<workflow>:<run_id>`): pass it to `apr attach` to resolve the actual session after startup or a retry. APR verifies identity using the private output destination, Oracle's creation timestamp, and a fresh session inventory for each producer attempt; ambiguous or stale candidates are never automatically attached or harvested. The `output_file` will contain the GPT Pro response once complete, and `log_file` captures Oracle output.

#### `apr robot help`

Returns complete API documentation in JSON format, useful for coding agents to discover capabilities:

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

1. **Semantic error codes**: Machine-parseable error types enable intelligent error handling, not just string matching
2. **Pre-flight validation**: Expensive Oracle runs (10-60 minutes) shouldn't fail due to missing files; validate first
3. **Consistent envelope**: Every response has the same structure, making parsing trivial
4. **Self-documenting**: The `help` command returns structured documentation
5. **Minimal dependencies**: Only requires `jq` for JSON output formatting

---

## 🔄 Self-Update

APR includes a secure self-update mechanism that keeps your installation current without requiring manual downloads or reinstallation.

### How It Works

```bash
apr update
```

The update command:

1. **Fetches the latest version** from GitHub with a 5-second timeout
2. **Compares versions** using semantic versioning (e.g., `1.2.0 → 1.2.1`)
3. **Shows what's available** and asks for confirmation
4. **Downloads the new version** to a temporary location
5. **Verifies the download** with multiple security checks
6. **Installs atomically**: the old version is only replaced after verification succeeds

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
│  Current version: 1.2.0                                     │
│  Latest version:  1.2.1                                     │
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

1. **Low friction**: No need to re-run the installer or remember download URLs
2. **Security**: Checksum verification prevents tampering
3. **Reliability**: Atomic updates mean no corrupted installations
4. **User control**: Updates are never automatic; you always confirm

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

Two output formats exist because iterative refinement workflows benefit from automation; a tool that only works interactively leaves value on the table.

### 6. Secure by Default

Security considerations are woven throughout:
- **No credential storage**: APR never touches your ChatGPT credentials; Oracle uses browser cookies
- **Checksum verification**: Downloads are verified against published SHA-256 checksums
- **Atomic operations**: Updates either complete fully or don't happen at all
- **User consent**: Nothing destructive happens without explicit confirmation

---

## 🏗️ Architecture

### Component Overview

```
apr (bash script, ~5000 LOC)
├── Core Commands
│   ├── run           # Execute revision rounds with retry logic
│   ├── setup         # Interactive workflow wizard
│   ├── status        # Oracle session status
│   ├── attach        # Reattach to sessions
│   ├── list          # List workflows
│   ├── history       # Round history
│   ├── show          # View round output
│   ├── diff          # Compare rounds
│   ├── integrate     # Claude Code prompts
│   ├── stats         # Convergence analytics
│   └── backfill      # Retroactive metrics
├── Robot Mode        # JSON API for automation
│   ├── status        # Environment introspection
│   ├── workflows     # List workflows
│   ├── init          # Initialize .apr/
│   ├── validate      # Pre-flight checks
│   ├── run           # Execute rounds
│   ├── history       # Round history (JSON)
│   └── help          # API documentation
├── Reliability Layer
│   ├── Pre-flight validation
│   ├── Auto-retry with exponential backoff
│   ├── Session locking
│   └── Graceful error handling
├── Analytics Engine
│   ├── Metrics collection
│   ├── Convergence detection
│   └── Round comparison
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
├── analytics/            # Convergence + metrics data
│   └── <workflow>/
│       └── metrics.json
├── rounds/               # Round outputs
│   └── <workflow>/
│       └── round_N.md
├── logs/                 # Oracle logs (robot mode)
│   └── oracle_<slug>.log
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
| `.apr/analytics/<workflow>/metrics.json` | Round analytics data |
| `.apr/logs/oracle_<slug>.log` | Oracle output log (robot mode) |

---

## 🧪 Testing Framework

APR includes a comprehensive test suite built on [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System). The test infrastructure validates everything from individual functions to complete end-to-end workflows.

### Test Structure

```
tests/
├── helpers/
│   └── test_helper.bash      # Shared fixtures and assertions
├── unit/
│   ├── test_yaml_parser.bats # YAML parsing edge cases
│   ├── test_exit_codes.bats  # Exit code contract verification
│   └── ...                   # Function-level tests
├── e2e/
│   └── test_full_workflow.bats  # Complete workflow tests
└── logs/
    └── test_run_*.log        # Test execution logs
```

### Running Tests

```bash
# Run all tests
./tests/run_tests.sh

# Run only unit tests
bats tests/unit/

# Run only e2e tests
bats tests/e2e/

# Run with verbose output
bats --verbose-run tests/
```

### Test Categories

| Category | Purpose | Count |
|----------|---------|-------|
| **Unit Tests** | Individual function validation | ~160 |
| **Exit Code Tests** | Verify semantic exit codes | ~30 |
| **YAML Parser Tests** | Edge cases in config parsing | ~25 |
| **E2E Tests** | Complete workflow journeys | ~20 |

### Key Testing Principles

1. **No Oracle dependency**: Tests use mocked Oracle responses to run quickly and offline
2. **Isolated environments**: Each test creates a fresh project directory in `/tmp`
3. **Semantic exit codes**: Tests verify that specific error conditions produce specific exit codes
4. **Stream separation**: Tests validate that JSON goes to stdout, errors to stderr
5. **Robot mode coverage**: Full JSON API contract validation

### Custom Assertions

The test helper provides domain-specific assertions:

```bash
# File and directory assertions
assert_file_exists ".apr/config.yaml"
assert_dir_exists ".apr/workflows"

# Exit code verification
assert_exit_code 0   # Success
assert_exit_code 2   # Usage error
assert_exit_code 4   # Config error

# JSON validation
assert_valid_json "$output"
assert_json_value "$output" ".ok" "true"
assert_json_value "$output" ".code" "ok"

# Stream capture
capture_streams "$APR_SCRIPT" robot status
assert_valid_json "$CAPTURED_STDOUT"
```

---

## 🎨 Terminal Styling

APR uses [gum](https://github.com/charmbracelet/gum) for beautiful terminal output:

```
╔════════════════════════════════════════════════════════════╗
║    Automated Plan Reviser Pro v1.2.0                       ║
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

### Core Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_HOME` | Data directory | `~/.local/share/apr` |
| `APR_CACHE` | Cache directory | `~/.cache/apr` |
| `APR_CHECK_UPDATES` | Enable daily update checking | unset (set to `1` to enable) |
| `APR_NO_NPX` | Disable npx fallback for Oracle (require global `oracle`) | unset |

### Reliability Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_MAX_RETRIES` | Maximum Oracle retry attempts | `3` |
| `APR_INITIAL_BACKOFF` | Initial retry delay (seconds) | `10` |

### Oracle Stability Thresholds

These control how APR patches Oracle to tolerate GPT Pro Extended Thinking pauses:

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_ORACLE_MIN_STABLE_MS` | Time text must stop changing before considered complete | `30000` |
| `APR_ORACLE_SHORT_STABLE_MS` | Shorter threshold for non-extended responses | `15000` |
| `APR_ORACLE_SETTLE_WINDOW_MS` | Completion detection window | `30000` |
| `APR_ORACLE_STABLE_CYCLES` | Polling cycles required for stability | `12` |
| `APR_RECOVERY_WAIT_SECS` | Seconds to wait before reattaching to recover a truncated answer (`0` skips the wait) | `30` |

### Status & Monitoring

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_STATUS_HOURS` | Time window for status checks (hours) | `72` |
| `APR_VERBOSE` | Enable verbose/debug output | unset |

### Display Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `APR_NO_GUM` | Disable gum even if available | unset |
| `NO_COLOR` | Disable colored output (accessibility) | unset |
| `CI` | Detected CI environment (disables gum) | unset |
| `PAGER` | Pager for `apr show` output | `less` or `more` |

---

## 🌐 Oracle Remote Setup (Headless/SSH Environments)

If you're running APR on a headless server (SSH session, remote VM, CI runner), Oracle can't open a browser locally. The solution is **Oracle's serve mode**: run the browser automation on a local machine with a GUI, and have the remote server connect to it.

### Why This Is Needed

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  THE PROBLEM                                                                  │
│                                                                               │
│  [Remote Server]                      [ChatGPT]                              │
│       SSH ───────→ No browser ──────✕──→ Can't authenticate                  │
│                                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  THE SOLUTION: Oracle Serve Mode                                              │
│                                                                               │
│  [Remote Server]     [Local Machine]      [ChatGPT]                          │
│       APR ──────────→ Oracle Serve ──────→ Browser ──────→ ✓                 │
│              TCP/9333        ▲                                                │
│              (Tailscale)     └── Has GUI, can run Chrome                     │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Step 1: Start Oracle Serve on Your Local Machine

On the machine with a browser (your laptop, desktop, Mac Mini, etc.):

```bash
# Install Oracle if needed
npm install -g @steipete/oracle

# Start the server (keep this terminal open)
oracle serve --port 9333 --token "your-secret-token"
```

**Important: Use port 9333, not 9222.** Port 9222 is used internally by Chrome for the DevTools Protocol. Using 9333 for Oracle's server avoids the conflict.

You'll see output like:
```
Oracle remote server started on port 9333
Waiting for connections...
```

### Step 2: Configure the Remote Server

On your remote machine (the one running APR via SSH):

```bash
# Set environment variables (add to ~/.zshrc or ~/.bashrc for persistence)
export ORACLE_REMOTE_HOST="192.168.1.100:9333"  # Your local machine's IP
export ORACLE_REMOTE_TOKEN="your-secret-token"  # Must match --token above

# Or for Tailscale (recommended for remote servers)
export ORACLE_REMOTE_HOST="100.x.x.x:9333"      # Tailscale IP of local machine
```

### Step 3: Test the Connection

```bash
oracle -p "Say exactly: Connection successful" -e browser -m "5.2 Thinking"
```

If successful, you'll see GPT Pro's response. APR will now work normally:

```bash
apr run 1  # Works over the remote connection
```

### Tailscale Setup (Recommended)

If your local and remote machines are both on a Tailscale network, use Tailscale IPs for reliable connectivity:

```bash
# Find your local machine's Tailscale IP
tailscale ip -4  # Run this on your local machine

# On the remote server
export ORACLE_REMOTE_HOST="100.x.x.x:9333"  # Use the Tailscale IP
export ORACLE_REMOTE_TOKEN="your-secret-token"

# Verify connectivity
tailscale ping 100.x.x.x  # Should succeed
```

Tailscale provides:
- **NAT traversal**: Works even when your local machine is behind a firewall
- **Encryption**: Traffic is encrypted via WireGuard
- **Stable IPs**: Tailscale IPs don't change when you move networks

### Session Persistence

Once authenticated, Oracle maintains the ChatGPT session in the browser. You can:

1. Leave `oracle serve` running on your local machine
2. Run multiple APR rounds from the remote server
3. Reattach to sessions: `apr attach <slug>`

If the session expires, you may need to re-authenticate by visiting ChatGPT in the browser on your local machine.

### How Documents Are Sent (Inline Pasting)

APR uses Oracle's `--browser-attachments never` mode, which **pastes document contents directly into the chat** rather than uploading them as file attachments. This is more reliable because:

- **No upload failures**: File uploads to ChatGPT can fail silently or trigger "duplicate file" errors
- **Consistent formatting**: Pasted content appears exactly as intended
- **No attachment limits**: Works regardless of ChatGPT's file upload restrictions

The documents are combined with the prompt template and pasted as a single message. For typical workflows (README + spec + impl ~200KB), this works reliably within GPT's context limits.

### Security Considerations

- **Token secrecy**: The `--token` value is like a password. Use a strong, unique value.
- **Network exposure**: Only expose `oracle serve` on trusted networks (Tailscale, local LAN).
- **Don't use over public internet**: Without Tailscale, you'd need firewall rules and the connection isn't encrypted.

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
If you set `APR_NO_NPX=1`, APR will not use the npx fallback.

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
<summary><strong>Response appears truncated or incomplete</strong></summary>

**Cause:** GPT Pro Extended Thinking can pause for 10-30+ seconds during reasoning. If Oracle's stability thresholds are too low, it may capture output prematurely.

**Fix:**

APR automatically patches Oracle's stability thresholds to tolerate extended thinking pauses. If you still experience truncation:

```bash
# Increase the stability wait time (milliseconds)
export APR_ORACLE_MIN_STABLE_MS=45000
export APR_ORACLE_SETTLE_WINDOW_MS=45000

# Then re-run
apr run 5
```

If output was captured mid-response, try reattaching:
```bash
apr attach apr-default-round-5
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

MIT License (with OpenAI/Anthropic Rider). See [LICENSE](LICENSE) for details.

---

<div align="center">

**[Report Bug](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/issues) · [Request Feature](https://github.com/Dicklesworthstone/automated_plan_reviser_pro/issues)**

---

<sub>Built with [Oracle](https://github.com/steipete/oracle), [gum](https://github.com/charmbracelet/gum), and a healthy appreciation for iterative refinement.</sub>

<sub>Special thanks to [Peter Steinberger](https://github.com/steipete) for creating Oracle, the excellent browser automation tool that makes APR possible.</sub>

</div>
