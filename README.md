# Ralph Gemini -- Agentic Coding System for Gemini CLI

Ralph Gemini is an autonomous agentic coding system that runs **Gemini CLI in a loop** with **clean context every iteration**. Each iteration is a fresh `gemini` process that picks one user story from `prd.json`, implements it, gets reviewed by a QA Auditor, and commits.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## How It Works

```
                          ┌─────────────────────────────┐
                          │   ralph-gemini [iterations]  │
                          └──────────────┬──────────────┘
                                         │
                          ┌──────────────▼──────────────┐
                          │  Phase 0: Architect Persona  │
                          │  Generates architecture_spec │
                          │  (runs once, then skipped)   │
                          └──────────────┬──────────────┘
                                         │
                 ┌───────────────────────▼───────────────────────┐
                 │              For Each Iteration                │
                 │                                               │
                 │  1. Context Sniffer (inject error logs)       │
                 │  2. Coding Agent (implement one story)        │
                 │  3. QA Auditor (review changes)               │
                 │     ├─ PASS → commit with semantic message    │
                 │     └─ FAIL → send feedback, retry (max 2x)  │
                 │  4. Learning Log (if retries >= 2)            │
                 │  5. All done? → exit : next iteration         │
                 │                                               │
                 └───────────────────────────────────────────────┘
```

### Phase 0: Architect Persona

Before the coding loop starts, a dedicated Gemini call analyzes `prd.json` and the codebase to generate `architecture_spec.md`. This file contains:

- Implementation plan per story
- File dependency map (which stories touch which files)
- Breaking changes and risks
- Recommended execution order

Runs once. If `architecture_spec.md` already exists, this phase is skipped.

### Coding Agent (per iteration)

Each iteration spawns a **new** `gemini -y` process with clean context. The agent:

1. Reads `prd.json`, `progress.txt`, `learning_log.md`, and `architecture_spec.md`
2. Picks the highest-priority story where `passes: false`
3. Scopes work using the story's `dependencies` array
4. Implements the story
5. Runs the story's `verification_steps` commands
6. Commits with conventional format: `feat(US-001): description`
7. Updates `prd.json` and appends to `progress.txt`

### QA Auditor (per iteration)

After the coding agent finishes, a separate Gemini call reviews the changes:

- Checks acceptance criteria are met
- Looks for logic errors, security issues, missing edge cases
- Runs `verification_steps` independently
- Outputs `<verdict>PASS</verdict>` or `<verdict>FAIL</verdict>` with detailed feedback

If FAIL, the feedback is injected into a correction prompt and the coding agent is re-invoked (up to 2 retries per iteration).

### Context Sniffer

If the `RALPH_LOG_PATHS` environment variable is set, the script reads the last 50 lines of each listed log file and injects them into the prompt. This gives the agent real-time error context from your dev server, build logs, etc.

```bash
RALPH_LOG_PATHS="logs/server.log,.next/error.log" ralph-gemini 15
```

### Learning Log

When a story takes 2 or more QA correction attempts, an entry is automatically appended to `learning_log.md` in the project root. Future iterations read this file to avoid repeating the same mistakes.

## Prerequisites

- [Gemini CLI](https://geminicli.com/) installed and authenticated
- `jq` (`brew install jq` on macOS)
- A git repo for your project

## Install

From this repo (after clone):

```bash
gemini extensions link /path/to/ralph-gemini
```

### Single command setup

Create a symlink so you can run `ralph-gemini` from anywhere:

```bash
sudo ln -s /path/to/ralph-gemini/ralph.sh /usr/local/bin/ralph-gemini
```

Then from any project:

```bash
cd /path/to/your/project
ralph-gemini        # default 10 iterations
ralph-gemini 20     # 20 iterations
```

## Workflow

### 1. Create a PRD

In a Gemini CLI session, ask to create a PRD (the **prd** skill activates automatically):

- "Create a PRD for [feature]"
- "Write a PRD for [feature]"

The PRD includes **Dependencies** and **Verification** sections per story. Saved to `tasks/prd-[feature-name].md`.

### 2. Convert to Ralph format

Ask to convert the PRD to `prd.json` (the **ralph** skill activates automatically):

- "Convert tasks/prd-[feature-name].md to prd.json"
- "Turn this PRD into ralph format"

This creates `prd.json` with user stories including `dependencies`, `verification_steps`, and `passes: false`.

### 3. Run Ralph

```bash
cd /path/to/your/project
ralph-gemini [max_iterations]
```

Ralph will:

1. Generate `architecture_spec.md` (Architect phase, runs once)
2. Pick the highest-priority incomplete story
3. Implement it, scoped by the story's `dependencies`
4. Run the story's `verification_steps`
5. QA Auditor reviews; retries if FAIL (up to 2x)
6. Commit with semantic format: `feat(US-001): description`
7. Update `prd.json` and `progress.txt`
8. Log to `learning_log.md` if the story was difficult
9. Repeat until all stories pass or max iterations reached

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main loop script: architect phase, coding iterations, QA auditor, context sniffer, learning log |
| `prompt.md` | Instructions for each coding iteration (reads PRD, implements story, runs checks, commits) |
| `architect_prompt.md` | Instructions for the Architect phase (analyzes codebase, generates implementation plan) |
| `qa_auditor_prompt.md` | Instructions for the QA Auditor (reviews code changes, outputs PASS/FAIL verdict) |
| `skills/prd/` | Skill to generate PRDs with dependencies and verification steps |
| `skills/ralph/` | Skill to convert PRD markdown to `prd.json` with enhanced schema |
| `prd.json.example` | Example PRD format with `dependencies` and `verification_steps` |
| `GEMINI.md` | Context file loaded by Gemini CLI when extension is active |

### Files generated in project root (during a run)

| File | Purpose |
|------|---------|
| `prd.json` | User stories with status (created via ralph skill) |
| `progress.txt` | Append-only log with learnings and codebase patterns |
| `architecture_spec.md` | Implementation plan from Architect phase |
| `learning_log.md` | Auto-generated entries for bugs that took multiple attempts |

## PRD JSON Schema

Each user story in `prd.json` has:

```json
{
  "id": "US-001",
  "title": "Add priority field to database",
  "description": "As a developer, I need to store task priority.",
  "acceptanceCriteria": [
    "Add priority column to tasks table",
    "Typecheck passes"
  ],
  "dependencies": ["src/db/schema.ts", "src/db/migrations/"],
  "verification_steps": ["npx tsc --noEmit", "npm test"],
  "priority": 1,
  "passes": false,
  "notes": ""
}
```

- **`dependencies`** -- Files/directories the story touches. Helps the agent scope its work.
- **`verification_steps`** -- Shell commands to validate the story. Run by both the coding agent and the QA auditor.

## Clean Context Per Task

Each iteration is a **new** Gemini process. The only memory across iterations is:

- Git history (commits from previous runs)
- `progress.txt` (learnings and Codebase Patterns)
- `prd.json` (which stories are done)
- `architecture_spec.md` (implementation plan)
- `learning_log.md` (known pitfalls)

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName` in `prd.json`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## Debugging

```bash
# Stories and status
cat prd.json | jq '.userStories[] | {id, title, passes}'

# Progress log
cat progress.txt

# Learning log (difficult bugs)
cat learning_log.md

# Architecture spec
cat architecture_spec.md

# Recent commits
git log --oneline -10
```

## Customizing

- **`RALPH_EXTENSION_DIR`** -- Set this env var to override the extension directory (where `prompt.md` lives).
- **`RALPH_LOG_PATHS`** -- Comma-separated log files for the Context Sniffer.
- **Quality checks** -- The prompt is generic; your project's `verification_steps` in `prd.json` define the actual checks.
- **Max QA retries** -- Edit `MAX_QA_RETRIES` in `ralph.sh` (default: 2).
