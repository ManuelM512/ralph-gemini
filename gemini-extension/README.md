# Ralph extension for Gemini CLI

Ralph runs **Gemini CLI in a loop** with **clean context every iteration**. Each iteration is a new `gemini` process that reads `prd.json` and `progress.txt`, does one user story, commits, updates the PRD, and appends progress. Memory between runs is only git, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Prerequisites

- [Gemini CLI](https://geminicli.com/) installed and authenticated
- `jq` (e.g. `brew install jq` on macOS)
- A git repo for your project

## Install

From this repo (after clone):

```bash
gemini extensions link /path/to/ralph-gemini/gemini-extension
```

Or install from GitHub (if published):

```bash
gemini extensions install https://github.com/YOUR_ORG/ralph-gemini
```

Then restart Gemini CLI.

## Workflow

### 1. Create a PRD

In a Gemini CLI session, ask to create a PRD (the **prd** skill will be used):

- "Create a PRD for [feature]"
- "Write a PRD for [feature]"
- "Plan this feature"

Save output to `tasks/prd-[feature-name].md`.

### 2. Convert to Ralph format

Ask to convert the PRD to `prd.json` (the **ralph** skill will be used):

- "Convert tasks/prd-[feature-name].md to prd.json"
- "Turn this PRD into ralph format"

This creates `prd.json` in the project root with user stories and `passes: false`.

### 3. Run the Ralph loop

From your **project root** (where `prd.json` and `progress.txt` live):

```bash
# Default: ~/.gemini/extensions/ralph-gemini
~/.gemini/extensions/ralph-gemini/ralph.sh [max_iterations]
```

Or from the extension directory (e.g. after linking):

```bash
cd /path/to/your/project
/path/to/ralph-gemini/gemini-extension/ralph.sh 10
```

Or in Gemini CLI you can run the custom command (if extension is in default path):

```
/ralph:loop
```

**What the loop does:**

1. Ensures branch from `prd.json` `branchName` (create/checkout from main).
2. Each iteration: runs `gemini -y --prompt "$(cat prompt.md)"` in the project directory (one story per run).
3. When the model finishes a story it sets `passes: true` for that story and appends to `progress.txt`.
4. When all stories have `passes: true`, the model replies with `<promise>COMPLETE</promise>` and the script exits.

## Key files

| File | Purpose |
|------|--------|
| `prompt.md` | Instructions for each Gemini run (one story, read prd.json/progress.txt, commit, update PRD, append progress). |
| `ralph.sh` | Loop script: runs Gemini in headless mode per iteration, checks for COMPLETE. |
| `prd.json` | User stories with `passes` and `priority` (in project root). |
| `progress.txt` | Append-only log and "Codebase Patterns" (in project root). |
| `skills/prd/` | Skill to generate PRDs. |
| `skills/ralph/` | Skill to convert PRD markdown → `prd.json`. |

## Clean context per task

Each iteration is a **new** Gemini process. The only memory across iterations is:

- Git history (commits from previous runs)
- `progress.txt` (learnings and Codebase Patterns)
- `prd.json` (which stories are done)

So each task gets a clean context window; the model reads the PRD and progress each time.

## Customizing

- **Extension path:** Set `RALPH_EXTENSION_DIR` to the directory that contains `prompt.md` and `ralph.sh` if you don’t use the default path.
- **Quality checks:** The per-iteration prompt tells the model to run your project’s checks (typecheck, lint, test). Adjust those in your project; the prompt is generic.

## Debugging

```bash
# Stories and status
cat prd.json | jq '.userStories[] | {id, title, passes}'

# Progress log
cat progress.txt

# Recent commits
git log --oneline -10
```
