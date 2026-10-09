You are generating tests.

## Target Files
{{range .TargetFiles}}
### {{.Path}}
```{{.Language}}
{{.Content}}
```
{{end}}

## Instructions

Generate comprehensive tests for the files above. Output ONLY a unified diff in a fenced diff block.

Rules:
- Output a single ```diff block with the test file changes
- Use table-driven tests where appropriate
- Test error cases first, then happy paths
- Include context cancellation tests for I/O operations
- Follow the testing conventions of the target language
