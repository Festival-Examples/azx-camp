#!/usr/bin/env bash
# Approval-judge wrapper for judge-agent (fest approval_judge hook).
#
# judge-agent's built-in `claude` preset expects `claude --print --output-format
# json` to print one result object. With `"verbose": true` in the user's Claude
# Code settings it prints the whole event array, which judge-agent cannot parse.
# This wrapper runs the same call with verbose off for this invocation only.
#
# It also narrows the preset: the judge gets read-only tools (Read, Grep, Glob)
# and no permission bypass, so it can open evidence but cannot edit files or run
# commands.
#
# Usage (from judge-agent.json):
#   claude-judge.sh --prompt-file F --schema-file F [--campaign DIR] [--festival DIR] [--phase DIR]
set -euo pipefail

prompt_file="" schema_file=""
dirs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) prompt_file="$2"; shift 2 ;;
    --schema-file) schema_file="$2"; shift 2 ;;
    --campaign | --festival | --phase) dirs+=(--add-dir "$2"); shift 2 ;;
    *) echo "claude-judge.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -r "$prompt_file" ]] || { echo "claude-judge.sh: missing --prompt-file" >&2; exit 2; }
[[ -r "$schema_file" ]] || { echo "claude-judge.sh: missing --schema-file" >&2; exit 2; }

# The prompt goes on stdin: --tools and --allowedTools are variadic and would
# swallow a trailing prompt argument.
exec claude --print --output-format json \
  --settings '{"verbose":false}' \
  --json-schema "$(cat "$schema_file")" \
  "${dirs[@]}" \
  --tools Read,Grep,Glob \
  --allowedTools Read,Grep,Glob \
  < "$prompt_file"
