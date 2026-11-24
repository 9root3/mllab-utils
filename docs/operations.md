# Operations

## Logging
- level default: INFO
- format: JSON Lines
- required fields: timestamp, run_id, phase, message, duration_ms

## Failure Handling
- return explicit error codes `[Exxx]`
- include failed stage (plan/run/eval) in log message
- OpenClaw response includes root-cause summary (`stderr` and code)

## Reproducibility
- pin runtime deps in experiment image
- run with same config + seed to validate tolerance-bound consistency

## Remote SSH + Home Bind Pattern
- create each project under `/home/gglee/<project>`
- bind project root into dev container workspace
- keep official experiment execution in separate experiment container path
