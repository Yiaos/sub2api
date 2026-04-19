#!/usr/bin/env bash
# Build patched image from local source and restart app container with docker compose.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_TAG="${IMAGE_TAG:-weishaw/sub2api:latest}"
SERVICE_NAME="${SERVICE_NAME:-sub2api}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

echo "[1/4] Building image: ${IMAGE_TAG}"
docker build \
  -t "${IMAGE_TAG}" \
  --build-arg GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
  --build-arg GOSUMDB="${GOSUMDB:-sum.golang.google.cn}" \
  -f "${REPO_ROOT}/Dockerfile" \
  "${REPO_ROOT}"

echo "[2/4] Recreating service: ${SERVICE_NAME}"
cd "${SCRIPT_DIR}"
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate --no-deps "${SERVICE_NAME}"

CONTAINER_NAME="$(docker compose -f "${COMPOSE_FILE}" ps -q "${SERVICE_NAME}")"
if [[ -z "${CONTAINER_NAME}" ]]; then
  echo "[3/4] Failed to find container ID for service ${SERVICE_NAME}" >&2
  exit 1
fi

echo "[3/4] Waiting for service to become healthy"
for _ in $(seq 1 60); do
  HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${CONTAINER_NAME}")"
  if [[ "${HEALTH}" == "healthy" || "${HEALTH}" == "running" ]]; then
    break
  fi
  sleep 2
done

FINAL_HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${CONTAINER_NAME}")"
if [[ "${FINAL_HEALTH}" != "healthy" && "${FINAL_HEALTH}" != "running" ]]; then
  echo "Service ${SERVICE_NAME} is not healthy (status=${FINAL_HEALTH})" >&2
  docker compose -f "${COMPOSE_FILE}" ps
  exit 1
fi

echo "[4/4] Done. Service status:"
docker compose -f "${COMPOSE_FILE}" ps "${SERVICE_NAME}"
