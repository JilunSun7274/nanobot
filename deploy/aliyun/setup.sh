#!/bin/bash
# setup.sh — Nanobot 阿里云香港服务器初始化脚本
# 以 root 身份运行：bash setup.sh
# 目标系统：Ubuntu 22.04 / 24.04
set -euo pipefail

NANOBOT_REPO="https://github.com/nanobot-xyz/nanobot.git"
DEPLOY_DIR="/opt/nanobot"
DATA_DIR="${DEPLOY_DIR}/deploy/aliyun/data/.nanobot"

echo "=== [1/6] 系统更新 ==="
apt-get update -qq && apt-get upgrade -y -qq

echo "=== [2/6] 安装 Docker ==="
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    echo "Docker 安装完成：$(docker --version)"
else
    echo "Docker 已存在，跳过：$(docker --version)"
fi

echo "=== [3/6] 安装辅助工具 ==="
apt-get install -y -qq fail2ban ufw git

echo "=== [4/6] 防火墙配置（仅开放 SSH） ==="
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw --force enable
ufw status verbose

echo "=== [5/6] 创建 1GB Swap（为 Dream 功能留安全网） ==="
if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap 已创建：$(free -h | grep Swap)"
else
    echo "Swap 已存在，跳过"
fi

echo "=== [6/6] 克隆 nanobot 仓库 ==="
if [ ! -d "${DEPLOY_DIR}/.git" ]; then
    git clone "${NANOBOT_REPO}" "${DEPLOY_DIR}"
else
    echo "仓库已存在，跳过克隆"
fi

# 创建数据目录
mkdir -p "${DATA_DIR}"
chmod 700 "${DATA_DIR}"

# 复制配置模板
COMPOSE_DIR="${DEPLOY_DIR}/deploy/aliyun"
if [ ! -f "${DATA_DIR}/config.json" ]; then
    cp "${COMPOSE_DIR}/config.example.json" "${DATA_DIR}/config.json"
    echo "已复制 config.example.json → ${DATA_DIR}/config.json"
fi
if [ ! -f "${COMPOSE_DIR}/.env" ]; then
    cp "${COMPOSE_DIR}/.env.example" "${COMPOSE_DIR}/.env"
    chmod 600 "${COMPOSE_DIR}/.env"
    echo "已复制 .env.example → ${COMPOSE_DIR}/.env"
fi

echo ""
echo "========================================"
echo " 初始化完成！请执行以下步骤："
echo "========================================"
echo ""
echo "  1. 编辑密钥：vim ${COMPOSE_DIR}/.env"
echo "  2. 编辑配置：vim ${DATA_DIR}/config.json"
echo "  3. 构建并启动："
echo "       cd ${COMPOSE_DIR}"
echo "       docker compose build"
echo "       docker compose up -d"
echo "  4. 微信登录（首次）："
echo "       docker compose run --rm nanobot-cli onboard"
echo "  5. 查看日志："
echo "       docker compose logs -f nanobot-gateway"
echo ""
