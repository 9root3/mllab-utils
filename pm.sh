#!/usr/bin/env bash
set -e

# 이 스크립트가 있는 디렉토리 (즉, utils 폴더)
UTILS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- 하위 명령어 정의 ---
SUBCOMMAND=$1
shift # 첫 번째 인자(하위 명령어) 제거

# --- 도움말 ---
if [ "$SUBCOMMAND" == "help" ] || [ -z "$SUBCOMMAND" ]; then
    echo "Project Manager for MLLAB"
    echo "Usage: bash utils/pm.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init <proj_name> <git_url>   Initialize a new project from a Git repository."
    echo "  build <proj_name> [<tag>]      Build a Docker image for a project."
    echo "  start <proj_name> [options]    Create (if not exist) and start a project container."
    echo "  stop <proj_name>               Stop the project container."
    echo "  rm <proj_name>                 Remove the project container."
    exit 0
fi

# --- 하위 명령어에 따라 해당 스크립트 실행 ---
case $SUBCOMMAND in
    init)
        bash "${UTILS_DIR}/make_project.sh" "$@"
        ;;
    build)
        bash "${UTILS_DIR}/build_image.sh" "$@"
        ;;
    start)
        ARGS=("$@")
        CONTAINER_NAME=""
        for i in "${!ARGS[@]}"; do
            if [[ "${ARGS[$i]}" == "-n" ]]; then
                CONTAINER_NAME="${ARGS[$i+1]}"
                break
            fi
        done

        if [ -z "$CONTAINER_NAME" ]; then
            PROJ_NAME=${@: -1}
            CONTAINER_NAME="$(whoami)_${PROJ_NAME}" # 구분자 변경
        fi
        
        bash "${UTILS_DIR}/create_container.sh" "$@"
        docker start -ai "$CONTAINER_NAME"
        ;;
    stop)
        PROJ_NAME=$1
        CONTAINER_NAME="$(whoami)_${PROJ_NAME}" # 구분자 변경
        echo "Stopping container '$CONTAINER_NAME'..."
        docker stop "$CONTAINER_NAME"
        ;;
    rm)
        PROJ_NAME=$1
        CONTAINER_NAME="$(whoami)_${PROJ_NAME}" # 구분자 변경
        echo "Removing container '$CONTAINER_NAME'..."
        docker rm "$CONTAINER_NAME"
        ;;
    *)
        echo "Error: Unknown command '$SUBCOMMAND'"
        bash "${UTILS_DIR}/pm.sh" help
        exit 1
        ;;
esac