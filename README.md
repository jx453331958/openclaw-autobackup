# OpenClaw Auto Backup

English | [简体中文](README_CN.md)

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

## Configuration

### Environment Variables (.env)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WORKSPACES` | Yes | - | Format: `name1:/path1,name2:/path2` |
| `BACKUP_REPO` | Yes | - | Local git repository path for backups |
| `GIT_REMOTE` | Yes | - | Remote git URL (e.g. `git@github.com:user/repo.git`) |
| `SSH_KEY_PATH` | Yes | - | SSH private key path for git push |
| `PORT` | No | `3458` | Web server port |
| `DATABASE_URL` | No | `./data/backup.db` | SQLite database path |
| `TELEGRAM_BOT_TOKEN` | No | - | Telegram bot token for notifications |
| `TELEGRAM_CHAT_ID` | No | - | Telegram chat ID for notifications |

### Volume Mounts (docker-compose.yml)

Edit `docker-compose.yml` to mount your directories into the container:

```yaml
volumes:
  - ./data:/app/data
  - /path/to/backup-repo:/path/to/backup-repo
  - /home/user/.ssh/id_rsa:/home/user/.ssh/id_rsa:ro
  - /path/to/workspace1:/path/to/workspace1:ro
  - /path/to/workspace2:/path/to/workspace2:ro
```

**Important**: The paths in `.env` must match the container-side mount paths.

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

## From Source (Alternative)

```bash
git clone https://github.com/jx453331958/openclaw-autobackup.git
cd openclaw-autobackup
cp .env.example .env && vim .env
chmod +x setup.sh && ./setup.sh
```

Requires: Go 1.25+, Git, rsync, SSH key.

## Security Notes

- Never commit `.env` to version control
- Keep SSH keys with proper permissions (`chmod 600`)
- Use read-only SSH keys when possible

## License

MIT License
