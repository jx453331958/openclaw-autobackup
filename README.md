# OpenClaw Auto Backup

简体中文 | [English](README_EN.md)

轻量级多工作区自动备份工具，支持定时同步到 Git 仓库，带 Web 监控面板和 Telegram 通知。

## 快速开始

```bash
mkdir openclaw-autobackup && cd openclaw-autobackup
curl -sL https://raw.githubusercontent.com/jx453331958/openclaw-autobackup/main/deploy.sh -o deploy.sh
chmod +x deploy.sh
./deploy.sh deploy
```

脚本会引导你完成配置并启动服务。

## 功能特性

- **多工作区备份**：通过环境变量灵活配置多个工作区
- **选择性同步**：只备份关键文件（*.md、memory/、skills/、.clawhub/、canvas/）
- **自动 Git 同步**：定时 commit 并 push 到远程仓库（默认每小时）
- **Web 监控面板**：实时查看备份状态、历史记录、手动触发
- **Telegram 通知**：备份成功/失败时可选通知
- **REST API**：通过 HTTP 接口触发备份和查询状态

## 配置说明

### 环境变量 (.env)

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `WORKSPACES` | 是 | - | 格式：`名称1:路径1,名称2:路径2` |
| `BACKUP_REPO` | 是 | - | 本地 Git 备份仓库路径 |
| `GIT_REMOTE` | 是 | - | Git 远程地址（如 `git@github.com:user/repo.git`） |
| `SSH_KEY_PATH` | 是 | - | SSH 私钥路径，用于 git push |
| `PORT` | 否 | `3458` | Web 服务端口 |
| `DATABASE_URL` | 否 | `./data/backup.db` | SQLite 数据库路径 |
| `TELEGRAM_BOT_TOKEN` | 否 | - | Telegram Bot Token |
| `TELEGRAM_CHAT_ID` | 否 | - | Telegram Chat ID |

### 目录挂载 (docker-compose.yml)

编辑 `docker-compose.yml` 将你的目录挂载到容器中：

```yaml
volumes:
  - ./data:/app/data
  - /path/to/backup-repo:/path/to/backup-repo
  - /home/user/.ssh/id_rsa:/home/user/.ssh/id_rsa:ro
  - /path/to/workspace1:/path/to/workspace1:ro
  - /path/to/workspace2:/path/to/workspace2:ro
```

**注意**：`.env` 中的路径必须与容器内的挂载路径一致。

## 服务管理

```bash
./deploy.sh deploy    # 首次部署（下载文件 + 初始化 + 拉取镜像 + 启动）
./deploy.sh update    # 拉取最新镜像并重启
./deploy.sh start     # 启动服务
./deploy.sh stop      # 停止服务
./deploy.sh restart   # 重启服务
./deploy.sh status    # 查看状态和最近日志
./deploy.sh logs      # 实时查看日志
./deploy.sh backup    # 备份数据库
./deploy.sh clean     # 删除容器和镜像（保留数据）
```

## API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/` | GET | Web 面板 |
| `/api/status` | GET | 获取备份状态和工作区信息 |
| `/api/backups` | GET | 获取备份历史（支持分页） |
| `/api/backups/trigger` | POST | 触发手动备份 |

## 从源码安装（可选）

```bash
git clone https://github.com/jx453331958/openclaw-autobackup.git
cd openclaw-autobackup
cp .env.example .env && vim .env
chmod +x setup.sh && ./setup.sh
```

需要：Go 1.25+、Git、rsync、SSH 密钥。

## 安全提示

- 不要将 `.env` 文件提交到版本控制
- SSH 密钥保持适当权限（`chmod 600`）
- 尽可能使用只读 SSH 密钥

## 许可证

MIT License
