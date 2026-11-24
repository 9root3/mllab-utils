# OpenClaw Command: project-init

## Purpose
Create standard project structure by delegating to Harness init.

## Internal Invocation
`harness init --name <project> --runtime <python|node> --no-template`

## Input Example
```json
{
  "action": "project-init",
  "project": "example-project",
  "runtime": "python",
  "no_template": true
}
```

## Expected Output
- standard repo layout ready
- docs/workflow.md initialized
- template engine usage: prohibited
