# OpenClaw Auto Backup

English | [简体中文](README_CN.md)

A generic backup tool for automatically backing up multiple workspaces to a Git repository with scheduled synchronization and web monitoring.

## Quick Start

```bash
git clone https://github.com/jx453331958/openclaw-autobackup.git
cd openclaw-autobackup
cp .env.example .env && vim .env  # Edit configuration
chmod +x setup.sh && ./setup.sh   # One-click install
```

The setup script auto-detects your OS and configures:
- **macOS**: launchd service (auto-start on boot)
- **Linux**: systemd service (auto-start on boot)
- **Fallback**: cron-based watchdog

## Features

- **Dynamic Workspace Configuration**: Support multiple workspaces through simple environment variable configuration
- **Selective File Backup**: Only backs up important agent files (*.md, memory/, skills/, .clawhub/, canvas/)
- **Automated Git Sync**: Automatic commit and push to remote Git repository
- **Web Dashboard**: Real-time monitoring of backup status and history
- **Scheduled Backups**: Configurable cron-based automatic backups (default: hourly)
- **Telegram Notifications**: Optional notifications on backup success/failure
- **REST API**: Trigger backups and query status via HTTP endpoints

## Tech Stack

- **Backend**: Go + Gin + GORM + SQLite
- **Frontend**: Tailwind CSS (CDN) + Alpine.js
- **Scheduler**: robfig/cron for automated backups
- **Default Port**: 3458

## Prerequisites

- Go 1.25 or higher
- Git
- rsync
- SSH key for Git push authentication

## Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd openclaw-autobackup
```

2. Copy the example environment file and configure it:
```bash
cp .env.example .env
```

3. Edit `.env` with your configuration (see Configuration section below)

4. Build the application:
```bash
go build -o openclaw-autobackup
```

## Configuration

Edit the `.env` file with your settings:

### Required Configuration

```bash
# Workspace Configuration
# Format: 'name1:/path1,name2:/path2'
# Each workspace will be backed up to {name}-backup/ directory
WORKSPACES=workspace1:/path/to/workspace1,workspace2:/path/to/workspace2

# Backup Repository Path (local Git repository)
BACKUP_REPO=/path/to/backup/repository

# Git Remote URL
GIT_REMOTE=git@github.com:username/backup-repo.git

# SSH Key Path for Git Push
SSH_KEY_PATH=/path/to/.ssh/id_rsa
```

### Optional Configuration

```bash
# Server Port (default: 3458)
PORT=3458

# Database Path (default: ./data/backup.db)
DATABASE_URL=./data/backup.db

# Telegram Notifications (optional)
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_CHAT_ID=your_chat_id
```

## Usage

### Start the Service

```bash
./openclaw-autobackup
```

Or use the provided start script:
```bash
./start.sh
```

The service will:
- Start the web server on the configured port (default: 3458)
- Run automatic backups every hour
- Provide a web dashboard at `http://localhost:3458`

### API Endpoints

- `GET /` - Web dashboard
- `GET /api/status` - Get current backup status and workspace info
- `GET /api/backups` - Get backup history (supports pagination)
- `POST /api/backup` - Trigger a manual backup

### Manual Backup

Trigger a backup via API:
```bash
curl -X POST http://localhost:3458/api/backup
```

## Backup Process

For each configured workspace, the tool will:

1. Sync workspace files to `{BACKUP_REPO}/{workspace-name}-backup/`
2. Include only:
   - `*.md` files
   - `memory/` directory
   - `skills/` directory
   - `.clawhub/` directory
   - `canvas/` directory
3. Commit changes to the local Git repository
4. Push to the configured remote repository using the specified SSH key

## Deployment

### Systemd Service (Linux)

Create `/etc/systemd/system/openclaw-autobackup.service`:

```ini
[Unit]
Description=OpenClaw Auto Backup Service
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/openclaw-autobackup
ExecStart=/path/to/openclaw-autobackup/openclaw-autobackup
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable openclaw-autobackup
sudo systemctl start openclaw-autobackup
```

### Docker (Optional)

```dockerfile
FROM golang:1.25-alpine
WORKDIR /app
COPY . .
RUN go build -o openclaw-autobackup
CMD ["./openclaw-autobackup"]
```

## Project Structure

```
openclaw-autobackup/
├── config/          # Configuration loading
├── handlers/        # HTTP request handlers
├── models/          # Database models and migrations
├── services/        # Business logic (backup execution, scheduling)
├── templates/       # HTML templates (embedded)
├── static/          # Static assets
├── data/            # SQLite database (created at runtime)
├── logs/            # Log files (created at runtime)
├── main.go          # Application entry point
└── .env             # Environment configuration (not in git)
```

## Security Notes

- Never commit `.env` file to version control
- Keep SSH keys secure with appropriate permissions (chmod 600)
- Use read-only SSH keys if possible
- Regularly rotate Telegram bot tokens
- Consider using environment-specific configurations

## Troubleshooting

### Backup Fails with SSH Error

Ensure:
- SSH key path is correct and accessible
- SSH key has proper permissions (chmod 600)
- SSH key is added to your Git provider (GitHub, GitLab, etc.)
- Git remote URL uses SSH format (git@...)

### No Workspaces Configured Error

Check:
- `WORKSPACES` environment variable is set in `.env`
- Format is correct: `name1:/path1,name2:/path2`
- Workspace paths exist and are accessible

### Permission Denied Errors

Ensure the application has:
- Read access to workspace directories
- Write access to backup repository
- Read access to SSH key file

## License

MIT License

## Contributing

Contributions are welcome. Please open an issue or submit a pull request.
