# 阿里云 Docker 部署指南

本指南介绍如何在**阿里云香港轻量应用服务器**上，用 Docker 部署 nanobot 作为个人助手（微信 / 飞书 / 钉钉）。

> **为什么选 Docker？**
> Docker 提供可复现的运行环境——无论你的服务器是 Ubuntu 22.04 还是 24.04，部署步骤完全一致。容器隔离让回滚和版本切换变得简单，也方便他人参考这份文档在自己的服务器上复现。

---

## 前置条件

| 项目 | 要求 |
|------|------|
| 阿里云账号 | 已完成实名认证 |
| 服务器 | 香港轻量应用服务器，2 vCPU / 1 GB RAM / Ubuntu 22.04 |
| 本地工具 | SSH 客户端 |
| OpenRouter | 已注册并获取 API Key |

---

## Step 1：购买服务器

1. 登录 [阿里云控制台](https://ecs.console.aliyun.com/)
2. 选择 **轻量应用服务器** → **立即购买**
3. 配置：
   - **地域**：香港
   - **镜像**：Ubuntu 22.04
   - **套餐**：2 vCPU / 1 GB / 40 GB SSD / 200 Mbps（约 ¥25-34/月）
4. 设置 SSH 密钥对（推荐）或登录密码
5. 购买完成后记录**公网 IP**

> **为什么选香港？**
> 微信、飞书、钉钉的渠道连接均为出站请求，从香港服务器可直连这三个平台；同时 OpenRouter API 无需翻墙。香港服务器无需 ICP 备案。

---

## Step 2：连接服务器

```bash
# 本地执行
ssh root@<你的服务器IP>
```

首次连接会提示确认服务器指纹，输入 `yes` 继续。

---

## Step 3：运行初始化脚本

初始化脚本会自动完成：Docker 安装、防火墙配置（仅开放 SSH 22 端口）、创建 1GB Swap、克隆仓库、复制配置模板。

```bash
# 服务器上执行（以 root 身份）
curl -fsSL https://raw.githubusercontent.com/nanobot-xyz/nanobot/main/deploy/aliyun/setup.sh | bash
```

或者如果你已经克隆了仓库：

```bash
bash /opt/nanobot/deploy/aliyun/setup.sh
```

脚本完成后，目录结构如下：

```
/opt/nanobot/
├── deploy/aliyun/
│   ├── docker-compose.yml       # 容器编排配置
│   ├── .env                     # 密钥（已从 .env.example 复制）
│   └── data/.nanobot/
│       └── config.json          # nanobot 配置（已从模板复制）
└── ...（仓库其余文件）
```

---

## Step 4：填写密钥

```bash
vim /opt/nanobot/deploy/aliyun/.env
```

至少填写 `OPENROUTER_API_KEY`，其余渠道按需填写：

```
OPENROUTER_API_KEY=sk-or-v1-你的key
```

保护文件权限（已由 setup.sh 设置，可验证）：

```bash
ls -la /opt/nanobot/deploy/aliyun/.env   # 应显示 -rw------- (600)
```

---

## Step 5：配置 nanobot

```bash
vim /opt/nanobot/deploy/aliyun/data/.nanobot/config.json
```

**最简配置（仅微信）：**

```json
{
  "agents": {
    "defaults": {
      "model": "anthropic/claude-sonnet-4-6",
      "provider": "openrouter",
      "timezone": "Asia/Shanghai"
    }
  },
  "providers": {
    "openrouter": { "apiKey": "${OPENROUTER_API_KEY}" }
  },
  "channels": {
    "weixin": {
      "enabled": true,
      "allowFrom": ["你的微信ID"]
    }
  },
  "gateway": { "host": "0.0.0.0", "port": 18790 }
}
```

> **`allowFrom` 的作用**：只允许指定微信 ID 的消息触发 nanobot，防止陌生人使用。留空 `[]` 则接受所有消息（不推荐）。

---

## Step 6：构建并启动

```bash
cd /opt/nanobot/deploy/aliyun

# 首次构建镜像（需要几分钟，会下载依赖）
docker compose build

# 启动 gateway（后台运行）
docker compose up -d nanobot-gateway

# 查看启动日志
docker compose logs -f nanobot-gateway
```

> **构建原理**：`docker compose build` 读取仓库根目录的 `Dockerfile`，在服务器上本地构建镜像。这比拉取预构建镜像更透明——你可以看到每一步在做什么。

---

## Step 7：微信登录（首次）

微信需要扫描二维码登录，需要交互式操作：

```bash
cd /opt/nanobot/deploy/aliyun

# 运行 onboard（首次配置向导）
docker compose run --rm nanobot-cli onboard
```

按提示扫描终端中显示的二维码。登录状态会保存在 `data/.nanobot/` 目录（已挂载为数据卷），容器重启后不需要重新登录。

---

## Step 8：飞书 / 钉钉配置（选填）

### 飞书

1. 访问 [飞书开放平台](https://open.feishu.cn/app) → **创建企业自建应用**
2. 获取 **App ID** 和 **App Secret**
3. 在应用的「事件与回调」中添加 nanobot 的 Webhook 地址（如有需要）
4. 填入 `.env`：
   ```
   FEISHU_APP_ID=cli_xxxxx
   FEISHU_APP_SECRET=xxxxx
   ```
5. 在 `config.json` 中将 `feishu.enabled` 改为 `true`
6. 重启 gateway：`docker compose restart nanobot-gateway`

### 钉钉

1. 访问 [钉钉开放平台](https://open.dingtalk.com/) → **创建应用**
2. 获取 **Client ID** 和 **Client Secret**
3. 填入 `.env` 并修改 `config.json`，步骤同飞书
4. 重启 gateway

---

## Step 9：配置每日备份

```bash
# 编辑 root 的 crontab
crontab -e
```

添加以下内容（每日 3:00 备份到 OSS，香港 OSS 有 5GB 免费额度）：

```
0 3 * * * tar czf /tmp/nanobot-backup.tar.gz -C /opt/nanobot/deploy/aliyun/data .nanobot/ && ossutil cp /tmp/nanobot-backup.tar.gz oss://你的bucket名/$(date +\%Y\%m\%d).tar.gz && rm /tmp/nanobot-backup.tar.gz
```

> **前置条件**：需要先安装 [ossutil](https://help.aliyun.com/document_detail/120075.html) 并配置 AccessKey。

---

## 日常运维

```bash
cd /opt/nanobot/deploy/aliyun

# 查看容器状态
docker compose ps

# 查看实时日志
docker compose logs -f nanobot-gateway

# 重启 gateway
docker compose restart nanobot-gateway

# 停止所有容器
docker compose down

# 健康检查
curl http://127.0.0.1:18790/health
```

### 版本更新

```bash
bash /opt/nanobot/deploy/aliyun/deploy.sh
```

`deploy.sh` 会自动：拉取最新代码 → 重新构建镜像 → 滚动重启 gateway → 清理旧镜像。

---

## 验证清单

完成部署后逐项检查：

- [ ] 服务器购买完成，SSH 可正常连接
- [ ] `setup.sh` 执行成功，Docker 已安装
- [ ] `ufw status` 显示仅 22/tcp 开放
- [ ] `free -h` 显示 Swap 约 1GB
- [ ] `.env` 填写完毕，权限为 600
- [ ] `docker compose ps` 显示 nanobot-gateway 为 `running`
- [ ] 微信 onboard 扫码登录成功
- [ ] 从微信发送测试消息，收到 nanobot 回复
- [ ] `curl http://127.0.0.1:18790/health` 返回正常响应
- [ ] 备份 cron 添加完成

---

## 月度成本估算

| 项目 | 费用 |
|------|------|
| 香港轻量应用服务器（2C/1G） | ¥25–34/月 |
| OSS 备份（香港，≤5GB） | ¥0（免费额度） |
| OpenRouter API | 按用量计费 |
| **合计（基础设施）** | **~¥25–34/月** |

---

## 常见问题

**Q: 构建失败，npm install 超时？**
A: 服务器在香港，访问 npm registry 有时较慢。重试一次通常可解决：`docker compose build --no-cache`

**Q: 微信二维码扫描后很快过期？**
A: 在终端扫码后，onboard 命令会等待确认。请在二维码出现后 30 秒内完成扫描。

**Q: 容器内存不足，被 OOM Kill？**
A: `docker compose ps` 查看状态，如果是 OOM，增大 `docker-compose.yml` 中的 `memory` 限制，同时确认 Swap 已正确创建（`free -h`）。

**Q: 服务器重启后 nanobot 未自动启动？**
A: 检查 Docker daemon 是否设为开机自启：`systemctl is-enabled docker`。应返回 `enabled`。`restart: unless-stopped` 依赖 Docker daemon 已启动。
