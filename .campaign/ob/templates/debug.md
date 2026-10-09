You are debugging an error.

## Error Log

{{.ErrorLog}}

## Relevant Files
{{range .TargetFiles}}
### {{.Path}}
```{{.Language}}
{{.Content}}
```
{{end}}

## Instructions

Analyze the error above and provide a structured diagnosis.

### Root Cause
Identify the most likely root cause.

### Fix
Describe the specific code change needed.

### Prevention
How to prevent this class of error in the future.
