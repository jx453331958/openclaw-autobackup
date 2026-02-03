# OpenClaw Auto Backup

[English](README.md) | 简体中文

一个通用的自动备份工具，支持多工作区文件自动同步到 Git 仓库，带 Web 监控面板。

## 功能特性

- **动态工作区配置**：通过环境变量灵活配置多个工作区
- **选择性文件备份**：只备份重要的 agent 文件（*.md、memory/、skills/、.clawhub/、canvas/）
- **自动 Git 同步**：自动 commit 和 push 到远程仓库
- **Web 监控面板**：实时查看备份状态和历史记录
- **定时备份**：可配置的自动备份（默认每小时）
- **Telegram 通知**：备份成功/失败时可选通知
- **REST API**：通过 HTTP 接口触发备份和查询状态

## 技术栈

- **后端**：Go + Gin + GORM + SQLite
- **前端**：Tailwind CSS (CDN) + Alpine.js
- **调度器**：robfig/cron
- **默认端口**：3458

## 前置要求

- Go 1.21 或更高版本
- Git
- rsync
- 用于 Git push 的 SSH 密钥

## 快速开始

### 一键安装

```bash
git clone https://github.com/jx453331958/openclaw-autobackup.git
cd openclaw-autobackup

# 复制并编辑配置
cp .env.example .env
vim .env  # 编辑你的配置

# 一键安装（自动检测 macOS/Linux，设置开机启动）
chmod +x setup.sh
./setup.sh
```

脚本会自动：
- 编译项目
- 检测操作系统（macOS 用 launchd，Linux 用 systemd）
- 配置开机自启动
- 启动服务

### 手动安装

```bash
# 编译
go build -o openclaw-autobackup

# 运行
./start.sh
```

## 配置说明

编辑 `.env` 文件：

### 必填配置

```bash
# 工作区配置
# 格式：'名称1:路径1,名称2:路径2'
# 每个工作区会备份到 {名称}-backup/ 目录
WORKSPACES=workspace1:/path/to/workspace1,workspace2:/path/to/workspace2

# 备份仓库路径（本地 Git 仓库）
BACKUP_REPO=/path/to/backup/repository

# Git 远程地址
GIT_REMOTE=git@github.com:username/backup-repo.git

# Git push 用的 SSH 密钥路径
SSH_KEY_PATH=/path/to/.ssh/id_rsa
```

### 可选配置

```bash
# 服务端口（默认 3458）
PORT=3458

# 数据库路径（默认 ./data/backup.db）
DATABASE_URL=./data/backup.db

# Telegram 通知（可选）
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

## 使用方法

### Web 面板

启动后访问 `http://localhost:3458` 查看：
- 备份状态
- 历史记录
- 手动触发备份

### API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| `/` | GET | Web 面板 |
| `/api/status` | GET | 获取备份状态和工作区信息 |
| `/api/backups` | GET | 获取备份历史（支持分页） |
| `/api/backup` | POST | 触发手动备份 |

### 手动触发备份

```bash
curl -X POST http://localhost:3458/api/backup
```

## 备份流程

对于每个配置的工作区，工具会：

1. 同步工作区文件到 `{BACKUP_REPO}/{工作区名称}-backup/`
2. 只包含以下内容：
   - `*.md` 文件
   - `memory/` 目录
   - `skills/` 目录
   - `.clawhub/` 目录
   - `canvas/` 目录
3. 提交更改到本地 Git 仓库
4. 使用指定的 SSH 密钥 push 到远程仓库

## 服务管理

### macOS (launchd)

```bash
# 停止
launchctl unload ~/Library/LaunchAgents/com.openclaw-autobackup.plist

# 启动
launchctl load ~/Library/LaunchAgents/com.openclaw-autobackup.plist

# 查看日志
tail -f logs/launchd.log
```

### Linux (systemd)

```bash
# 状态
sudo systemctl status openclaw-autobackup

# 停止
sudo systemctl stop openclaw-autobackup

# 启动
sudo systemctl start openclaw-autobackup

# 日志
journalctl -u openclaw-autobackup -f
```

### 卸载

```bash
./setup.sh uninstall
```

## 项目结构

```
openclaw-autobackup/
├── config/          # 配置加载
├── handlers/        # HTTP 请求处理
├── models/          # 数据库模型
├── services/        # 业务逻辑（备份执行、调度）
├── templates/       # HTML 模板（嵌入）
├── static/          # 静态资源
├── data/            # SQLite 数据库（运行时创建）
├── logs/            # 日志文件（运行时创建）
├── main.go          # 程序入口
├── setup.sh         # 一键安装脚本
├── start.sh         # 启动脚本
└── .env             # 环境配置（不提交到 git）
```

## 安全提示

- 不要将 `.env` 文件提交到版本控制
- SSH 密钥保持适当权限（chmod 600）
- 如果可能，使用只读 SSH 密钥
- 定期轮换 Telegram bot token

## 故障排除

### SSH 错误导致备份失败

检查：
- SSH 密钥路径正确且可访问
- SSH 密钥权限正确（chmod 600）
- SSH 密钥已添加到 Git 服务商（GitHub、GitLab 等）
- Git 远程地址使用 SSH 格式（git@...）

### "未配置工作区"错误

检查：
- `.env` 中设置了 `WORKSPACES` 环境变量
- 格式正确：`名称1:路径1,名称2:路径2`
- 工作区路径存在且可访问

### 权限拒绝错误

确保应用程序有：
- 工作区目录的读取权限
- 备份仓库的写入权限
- SSH 密钥文件的读取权限

## 许可证

MIT License

## 贡献

欢迎贡献代码。请提交 Issue 或 Pull Request。
