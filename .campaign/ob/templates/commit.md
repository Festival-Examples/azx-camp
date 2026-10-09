---
model: qwen3:8b
---
You are generating a git commit message.

## Staged Changes

{{.GitDiff}}

## Instructions

Write a single commit message for these changes following Conventional Commits format.

Rules:
- Output ONLY the commit message, nothing else
- No markdown, no explanation, no fencing
- Format: type(scope): description
- Keep under 72 characters
