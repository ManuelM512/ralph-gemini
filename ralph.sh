#!/bin/bash
# Ralph loop for Gemini CLI - each iteration is a fresh Gemini process (clean context).
# Run from your project root: cd /path/to/project && /path/to/ralph.sh [max_iterations]
# Requires: gemini CLI, jq

set -e

MAX_ITERATIONS=10
[[ -n "$1" && "$1" =~ ^[0-9]+$ ]] && MAX_ITERATIONS="$1"

# Resolve symlinks to find the real script directory
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
[[ -f "$PROMPT_FILE" ]] || PROMPT_FILE="${RALPH_EXTENSION_DIR:-$HOME/.gemini/extensions/ralph-gemini}/prompt.md"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: prompt.md not found. Set RALPH_EXTENSION_DIR or run from extension directory."
  exit 1
fi

# Project dir = current directory when script is invoked
PROJECT_DIR="${PWD}"
PRD_FILE="$PROJECT_DIR/prd.json"
PROGRESS_FILE="$PROJECT_DIR/progress.txt"
ARCHIVE_DIR="$PROJECT_DIR/archive"
LAST_BRANCH_FILE="$PROJECT_DIR/.ralph-last-branch"

# Archive previous run if branch changed
if [[ -f "$PRD_FILE" && -f "$LAST_BRANCH_FILE" ]]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  if [[ -n "$CURRENT_BRANCH" && -n "$LAST_BRANCH" && "$CURRENT_BRANCH" != "$LAST_BRANCH" ]]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [[ -f "$PRD_FILE" ]] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [[ -f "$PROGRESS_FILE" ]] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

if [[ -f "$PRD_FILE" ]]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  [[ -n "$CURRENT_BRANCH" ]] && echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
fi

if [[ ! -f "$PROGRESS_FILE" ]]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "Error: prd.json not found in $PROJECT_DIR. Create one (e.g. use the ralph skill to convert a PRD)."
  exit 1
fi

ARCHITECT_PROMPT_FILE="$SCRIPT_DIR/architect_prompt.md"
ARCHITECTURE_SPEC="$PROJECT_DIR/architecture_spec.md"

echo "Ralph (Gemini CLI) - max iterations: $MAX_ITERATIONS"
echo "Project: $PROJECT_DIR"
echo ""

# Phase 0: Architect Persona - generate architecture_spec.md if it doesn't exist
if [[ -f "$ARCHITECT_PROMPT_FILE" && ! -f "$ARCHITECTURE_SPEC" ]]; then
  echo "==============================================================="
  echo "  Phase 0: Architect Persona (generating architecture_spec.md)"
  echo "==============================================================="
  ARCH_OUTPUT=$(cd "$PROJECT_DIR" && gemini -y --prompt "$(cat "$ARCHITECT_PROMPT_FILE")" 2>&1 | tee /dev/stderr) || true

  if echo "$ARCH_OUTPUT" | grep -q "<promise>ARCHITECT_DONE</promise>"; then
    echo "Architect phase complete. architecture_spec.md generated."
  else
    echo "Warning: Architect phase did not signal completion. Continuing anyway..."
  fi
  echo ""
  sleep 2
elif [[ -f "$ARCHITECTURE_SPEC" ]]; then
  echo "architecture_spec.md already exists - skipping Architect phase."
  echo ""
fi

QA_PROMPT_FILE="$SCRIPT_DIR/qa_auditor_prompt.md"
MAX_QA_RETRIES=2
LEARNING_LOG="$PROJECT_DIR/learning_log.md"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "==============================================================="
  echo "  Ralph iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # --- Context Sniffer: inject recent error logs if available ---
  EXTRA_CONTEXT=""
  if [[ -n "$RALPH_LOG_PATHS" ]]; then
    IFS=',' read -ra LOG_PATHS <<< "$RALPH_LOG_PATHS"
    for log_path in "${LOG_PATHS[@]}"; do
      log_path=$(echo "$log_path" | xargs)  # trim whitespace
      if [[ -f "$PROJECT_DIR/$log_path" ]]; then
        EXTRA_CONTEXT="${EXTRA_CONTEXT}

## Recent Error Context (from $log_path)
\`\`\`
$(tail -n 50 "$PROJECT_DIR/$log_path")
\`\`\`
"
      fi
    done
  fi

  # Build the prompt (base + optional error context)
  FULL_PROMPT="$(cat "$PROMPT_FILE")"
  if [[ -n "$EXTRA_CONTEXT" ]]; then
    FULL_PROMPT="${FULL_PROMPT}
${EXTRA_CONTEXT}"
  fi

  # --- Main coding agent ---
  OUTPUT=$(cd "$PROJECT_DIR" && gemini -y --prompt "$FULL_PROMPT" 2>&1 | tee /dev/stderr) || true

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks at iteration $i of $MAX_ITERATIONS."
    exit 0
  fi

  # --- QA Auditor Loop ---
  if [[ -f "$QA_PROMPT_FILE" ]]; then
    RETRY_COUNT=0
    QA_PASSED=false

    while [[ $RETRY_COUNT -lt $MAX_QA_RETRIES ]]; do
      echo ""
      echo "  --- QA Auditor Review (attempt $((RETRY_COUNT + 1))) ---"
      QA_OUTPUT=$(cd "$PROJECT_DIR" && gemini -y --prompt "$(cat "$QA_PROMPT_FILE")" 2>&1 | tee /dev/stderr) || true

      if echo "$QA_OUTPUT" | grep -q "<verdict>PASS</verdict>"; then
        echo "  QA Auditor: PASS"
        QA_PASSED=true
        break
      else
        echo "  QA Auditor: FAIL - sending feedback to coding agent..."
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if [[ $RETRY_COUNT -lt $MAX_QA_RETRIES ]]; then
          # Extract feedback (everything between "## QA Verdict" and the verdict tag)
          QA_FEEDBACK=$(echo "$QA_OUTPUT" | sed -n '/## QA Verdict/,/<verdict>/p' | sed '$d')

          # Build correction prompt
          CORRECTION_PROMPT="$(cat "$PROMPT_FILE")

## QA Auditor Feedback (Fix Required)

The QA Auditor reviewed your previous changes and found issues. You MUST fix these issues before proceeding.

${QA_FEEDBACK}

Focus ONLY on fixing the issues listed above. Do NOT start a new story. Re-run verification steps after fixing."

          OUTPUT=$(cd "$PROJECT_DIR" && gemini -y --prompt "$CORRECTION_PROMPT" 2>&1 | tee /dev/stderr) || true
        fi
      fi
    done

    # --- Learning Log: record if it took multiple attempts ---
    if [[ $RETRY_COUNT -ge 2 ]]; then
      echo ""
      echo "  Recording difficult fix in learning_log.md..."
      if [[ ! -f "$LEARNING_LOG" ]]; then
        echo "# Ralph Learning Log" > "$LEARNING_LOG"
        echo "" >> "$LEARNING_LOG"
        echo "Auto-generated entries for bugs that required multiple QA correction attempts." >> "$LEARNING_LOG"
        echo "---" >> "$LEARNING_LOG"
      fi
      {
        echo ""
        echo "## $(date '+%Y-%m-%d %H:%M') - Iteration $i"
        echo "- **Attempts:** $((RETRY_COUNT + 1))"
        echo "- **QA Passed:** $QA_PASSED"
        echo "- **QA Feedback Summary:** (see progress.txt for details)"
        echo "---"
      } >> "$LEARNING_LOG"
    fi

    if [[ "$QA_PASSED" == "false" ]]; then
      echo "  Warning: QA Auditor did not pass after $MAX_QA_RETRIES retries. Continuing to next iteration..."
    fi
  fi

  echo "Iteration $i done. Continuing..."
  sleep 3
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE and prd.json for status."
exit 1
