#!/usr/bin/env bash
set -x

# Resolve script directory and change to the project root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

GIT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD | tr A-Z a-z)

DOCKER_BUILDKIT=1 docker compose -p cms-$GIT_BRANCH_NAME -f docker/docker-compose.test.yml run --build --rm stresstestcms
