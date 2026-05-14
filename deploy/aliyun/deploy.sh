#!/bin/bash
# deploy.sh — Nanobot 版本更新脚本
# 在 /opt/nanobot/deploy/aliyun/ 目录下运行：bash deploy.sh
set -euo pipefail

REPO_DIR="/opt/nanobot"
COMPOSE_DIR="${REPO_DIR}/deploy/aliyun"

echo "=== 拉取最新代码 ==="
cd "${REPO_DIR}"
git pull origin main

echo "=== 重新构建镜像 ==="
cd "${COMPOSE_DIR}"
docker compose build --no-cache

echo "=== 滚动重启 gateway ==="
docker compose up -d --no-deps nanobot-gateway

echo "=== 清理旧镜像 ==="
docker image prune -f

echo "=== 当前容器状态 ==="
docker compose ps

echo ""
echo "更新完成。查看日志：docker compose logs -f nanobot-gateway"
