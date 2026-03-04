# OpenClaw Auto Backup

[简体中文](README.md) | English

A lightweight tool for automatically backing up multiple workspaces to a Git repository. Features scheduled sync, web dashboard, and Telegram notifications.

## Quick Start

```bash
mkdir openclaw-autobackup && cd openclaw-autobackup
curl -sL https://raw.githubusercontent.com/jx453331958/openclaw-autobackup/main/deploy.sh -o deploy.sh
chmod +x deploy.sh
./deploy.sh deploy
```

The script will guide you through configuration and start the service.

## Features

- **Multi-Workspace Backup**: Configure multiple workspaces via environment variable
- **Selective Sync**: Only backs up key files (*.md, memory/, skills/, .clawhub/, canvas/)
- **Auto Git Sync**: Scheduled commit and push to remote repository (default: hourly)
- **Web Dashboard**: Real-time backup status, history, and manual trigger
- **Telegram Notifications**: Optional alerts on backup success/failure
- **REST API**: Programmatic access to trigger backups and query status

## Configuration Reference

The deploy wizard generates config files automatically. This table is for later reference:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WORKSPACES` | Yes | - | Format: `name1:/path1,name2:/path2` |
| `BACKUP_REPO` | Yes | - | Local git repository path for backups |
| `GIT_REMOTE` | No | - | Remote git URL (e.g. `git@github.com:user/repo.git`) |
| `SSH_KEY_PATH` | No | - | SSH private key path for git push |
| `BACKUP_CRON` | No | `0 * * * *` | Backup schedule (cron expression, default: hourly) |
| `PORT` | No | `3458` | Web server port |
| `TELEGRAM_BOT_TOKEN` | No | - | Telegram bot token |
| `TELEGRAM_CHAT_ID` | No | - | Telegram chat ID |

## Management

```bash
./deploy.sh deploy    # First-time setup
./deploy.sh update    # Pull latest image and restart
./deploy.sh start     # Start the service
./deploy.sh stop      # Stop the service
./deploy.sh restart   # Restart the service
./deploy.sh status    # Show status and recent logs
./deploy.sh logs      # Follow container logs
./deploy.sh backup    # Backup the database
./deploy.sh clean     # Remove containers and images (preserves data)
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web dashboard |
| `/api/status` | GET | Current status and workspace info |
| `/api/backups` | GET | Backup history (paginated) |
| `/api/backups/trigger` | POST | Trigger manual backup |

## License

MIT License
