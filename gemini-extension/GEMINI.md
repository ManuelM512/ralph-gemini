# Ralph extension for Gemini CLI

You have the **Ralph** extension loaded. Ralph is an autonomous agentic coding system that runs Gemini CLI in a loop with **clean context each iteration** until all PRD items are complete.

Ralph goes beyond a simple loop: it includes an **Architect phase** (plans before coding), a **QA Auditor** (reviews code after each iteration), a **self-correction loop** (retries on QA failure), a **Context Sniffer** (injects error logs), and a **Learning Log** (tracks bugs that were hard to fix).

Memory persists via git history, `progress.txt`, `prd.json`, `architecture_spec.md`, and `learning_log.md`.

## When to use Ralph skills

- **Create a PRD:** Use the **prd** skill when the user wants to plan a feature, create a PRD, or spec out requirements. Output goes to `tasks/prd-[feature-name].md`. Each story should include **Dependencies** and **Verification** sections.
- **Convert to Ralph format:** Use the **ralph** skill when the user has a PRD (markdown) and wants to turn it into `prd.json` so they can run the Ralph loop. The JSON includes `dependencies` and `verification_steps` per story.

## Running the Ralph loop

The loop is **not** run inside this chat. Each iteration must be a **new Gemini process** so context stays clean. The user runs the loop from the terminal:

```bash
cd /path/to/project
ralph-gemini [max_iterations]
```

Or directly:

```bash
cd /path/to/project
~/.gemini/extensions/ralph-gemini/ralph.sh [max_iterations]
```

### What happens when the loop runs

1. **Phase 0 -- Architect:** A one-shot Gemini call analyzes `prd.json` and the codebase, then writes `architecture_spec.md` with implementation plans, file dependency maps, and breaking changes. Runs once; skipped if the file already exists.
2. **For each iteration:**
   - **Context Sniffer** checks for error logs (via `RALPH_LOG_PATHS` env var) and injects them into the prompt.
   - **Coding Agent** reads `prd.json`, `progress.txt`, `learning_log.md`, and `architecture_spec.md`, picks the highest-priority incomplete story, implements it, runs `verification_steps`, and commits.
   - **QA Auditor** reviews the changes with a separate Gemini call. If it returns FAIL, the feedback is sent back to the coding agent for correction (up to 2 retries).
   - **Learning Log** records an entry in `learning_log.md` if a story took 2+ QA correction attempts.
3. When all stories have `passes: true`, the model replies with `<promise>COMPLETE</promise>` and the script exits.

### Environment variables

- `RALPH_LOG_PATHS` -- Comma-separated list of log file paths (relative to project root) for the Context Sniffer. Example: `RALPH_LOG_PATHS="logs/server.log,.next/error.log" ralph-gemini 15`

## Key ideas

- **One story per iteration** -- each run does exactly one user story.
- **Small stories** -- each story must fit in one context window; the prd/ralph skills guide splitting.
- **Persistent memory** -- git, `progress.txt`, `prd.json`, `architecture_spec.md`, and `learning_log.md` carry information across iterations.
- **Dependencies & verification** -- each story declares which files it touches (`dependencies`) and how to validate it (`verification_steps`).
- **Semantic commits** -- commits use conventional format: `feat(US-001): description` with verification results in the body.

Do not run the full Ralph loop inside this session. You can create PRDs, convert them to `prd.json`, and remind the user to run `ralph-gemini` from their project for the autonomous loop.
