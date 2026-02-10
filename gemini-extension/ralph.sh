#!/bin/bash
# Ralph loop for Gemini CLI - each iteration is a fresh Gemini process (clean context).
# Run from your project root: cd /path/to/project && /path/to/ralph.sh [max_iterations]
# Requires: gemini CLI, jq

set -e

MAX_ITERATIONS=10
[[ -n "$1" && "$1" =~ ^[0-9]+$ ]] && MAX_ITERATIONS="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo "Ralph (Gemini CLI) - max iterations: $MAX_ITERATIONS"
echo "Project: $PROJECT_DIR"
echo ""

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "==============================================================="
  echo "  Ralph iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  OUTPUT=$(cd "$PROJECT_DIR" && gemini -y --prompt "$(cat "$PROMPT_FILE")" 2>&1 | tee /dev/stderr) || true

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks at iteration $i of $MAX_ITERATIONS."
    exit 0
  fi

  echo "Iteration $i done. Continuing..."
  sleep 3
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE and prd.json for status."
exit 1
