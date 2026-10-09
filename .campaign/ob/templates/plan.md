You are creating an implementation plan.

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

Create a structured implementation plan. Output as markdown:

### Overview
Brief summary of what will be built.

### Steps
Numbered list of implementation steps, each with:
- What to change
- Which files to modify/create
- Key design decisions

### Dependencies
External dependencies or prerequisites.

### Risks
Potential issues and mitigations.
