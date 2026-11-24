# Workflow

1. User develops in dev container on lab server (bind-mounted workspace)
2. `harness plan --config ...` validates ExperimentSpec
3. `harness run --mode dev` performs precheck
4. OpenClaw runs on local machine
5. OpenClaw connects to lab server via SSH and calls wrapper shell
6. Wrapper triggers official `harness run --mode exp` in experiment container
7. `harness eval --run-id ...` compares outcomes and archives artifacts/logs

## Command Canon
- `harness init --name <project> --runtime <python|node> --no-template`
- `harness plan --config experiments/configs/<x>.yaml`
- `harness run --config experiments/configs/<x>.yaml --mode <dev|exp>`
- `harness eval --run-id <id>`
- `harness status --run-id <id>`
