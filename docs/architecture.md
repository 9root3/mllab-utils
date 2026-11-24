# Architecture

## Planes
- Control Plane (Local): OpenClaw on user local machine
- Data Plane (Server): experiment container + wrapper shell + harness runner

## Trigger Flow
1. OpenClaw runs on local machine
2. OpenClaw connects to lab server via SSH
3. Server-side wrapper script runs experiment with config/overrides
4. Harness runner writes artifacts/logs on server

## Separation Contract
- Dev Container: coding, lint, unit/integration test, dry-run only
- Experiment Container: official runs only, locked deps, constrained write path

## Metadata Contract
Every run records:
- run_id
- git_commit
- image_digest
- start_ts / end_ts
- config_hash
- metric_summary

## Storage Contract
- `artifacts/<run_id>/metadata.json`
- `artifacts/<run_id>/result.json`
- `artifacts/<run_id>/run.log.jsonl`
