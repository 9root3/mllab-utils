# OpenClaw Command: experiment-run

## Purpose
Trigger official or precheck experiment run through Harness.

## Internal Invocation
`harness run --config <path> --mode <dev|exp> [--set k=v]`

## Input Example
```json
{
  "action": "experiment-run",
  "project": "example-project",
  "config": "experiments/configs/baseline.yaml",
  "mode": "exp",
  "overrides": {
    "params.lr": 0.0005,
    "params.seed": 42
  }
}
```

## Runtime Contract
1. config schema validation
2. run_id issuance
3. mode=exp uses experiment container path
4. artifacts and logs collection
5. summary response for OpenClaw
