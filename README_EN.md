# OpenClaw Auto Backup

[简体中文](README.md) | English

A lightweight auto-backup tool with scheduled Git sync, web dashboard, and Telegram notifications.

Two backup modes:
- **Workspace Mode**: rsync multiple source directories to a dedicated backup repo (source untouched)
- **Direct Mode**: use an existing directory as-is, commit + push directly (no rsync)

## Quick Start

```bash
mkdir openclaw-autobackup && cd openclaw-autobackup
curl -sL https://raw.githubusercontent.com/jx453331958/openclaw-autobackup/main/deploy.sh -o deploy.sh
chmod +x deploy.sh
./deploy.sh deploy
```

The script will guide you through configuration and start the service.

## Features

- **Dual Backup Modes**: Workspace mode (rsync + git) or Direct mode (git only)
- **Multi-Workspace Support**: Configure multiple source directories in workspace mode
- **Auto Git Sync**: Scheduled commit and push to remote repository (default: hourly)
- **Web Dashboard**: Real-time backup status, history, and manual trigger
- **Telegram Notifications**: Optional alerts on backup success/failure
- **REST API**: Programmatic access to trigger backups and query status

## Configuration Reference

The deploy wizard generates config files automatically. This table is for later reference:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WORKSPACES` | No | - | Workspace mode: `name1:/path1,name2:/path2`; leave empty for direct mode |
| `BACKUP_REPO` | Yes | - | Local git repo path (in direct mode, this IS the target directory) |
| `GIT_REMOTE` | No | - | Remote git URL (e.g. `git@github.com:user/repo.git`) |
| `SSH_KEY_PATH` | No | - | SSH private key path for git push |
| `SSH_PORT` | No | `22` | SSH port (use 443 for GitHub via `ssh.github.com`) |
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
