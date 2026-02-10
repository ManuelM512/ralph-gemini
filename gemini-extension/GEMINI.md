# Ralph extension for Gemini CLI

You have the **Ralph** extension loaded. Ralph is an autonomous agent loop that runs Gemini CLI repeatedly with **clean context each iteration** until all PRD items are complete. Memory persists via git history, `progress.txt`, and `prd.json`.

## When to use Ralph skills

- **Create a PRD:** Use the **prd** skill when the user wants to plan a feature, create a PRD, or spec out requirements. Output goes to `tasks/prd-[feature-name].md`.
- **Convert to Ralph format:** Use the **ralph** skill when the user has a PRD (markdown) and wants to turn it into `prd.json` so they can run the Ralph loop.

## Running the Ralph loop (clean context per task)

The loop is **not** run inside this chat. Each iteration must be a **new Gemini process** so context stays clean. The user runs the loop from the terminal:

1. **From project root** (where `prd.json` and `progress.txt` live), run the extension’s script:
   ```bash
   cd /path/to/project
   ~/.gemini/extensions/ralph-gemini/ralph.sh [max_iterations]
   ```
   Or if they linked from source: `path/to/ralph-gemini/gemini-extension/ralph.sh [max_iterations]`

2. **What the loop does:**
   - Each iteration starts a **new** `gemini -y --prompt "..."` process (fresh context).
   - The prompt instructs that process to: read `prd.json` and `progress.txt`, pick the highest-priority story with `passes: false`, implement it, run checks, commit, update `prd.json`, append to `progress.txt`.
   - When all stories have `passes: true`, the model replies with `<promise>COMPLETE</promise>` and the script exits.

3. **Prerequisites:** Project must have `prd.json` (create it via the ralph skill). `jq` must be installed. Gemini CLI must be installed and authenticated.

## Key ideas

- **One story per iteration** – each run does exactly one user story.
- **Small stories** – each story must fit in one context window; the prd/ralph skills guide splitting.
- **Persistent memory** – only git, `progress.txt`, and `prd.json` carry information across iterations.
- **AGENTS.md / GEMINI.md** – the per-iteration prompt tells the model to update these when it finds reusable patterns.

Do not run the full Ralph loop inside this session. You can create PRDs, convert them to `prd.json`, and remind the user to run `ralph.sh` from their project for the autonomous loop.
