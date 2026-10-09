You are implementing changes from a specification.

## Specification
{{if .Spec}}
{{.Spec.Content}}
{{end}}

## Repository Structure

{{range .RepoTree}}- {{.}}
{{end}}

## Existing Files
{{range .TargetFiles}}
### {{.Path}}
```{{.Language}}
{{.Content}}
```
{{end}}

## Instructions

Implement the specification above. Output ONLY a unified diff in a fenced diff block.

Rules:
- Output a single ```diff block containing the complete unified diff
- No explanation, commentary, or text outside the diff block
- Include all necessary file changes in one diff
- Use proper unified diff format with file headers
