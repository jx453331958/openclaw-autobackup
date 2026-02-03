#!/bin/bash
set -e

# ========================================
# OpenClaw Auto Backup - One-Click Setup
# ========================================
# Supports: macOS (launchd), Linux (systemd), fallback (cron)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_NAME="openclaw-autobackup"
BINARY_NAME="openclaw-autobackup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    command -v go >/dev/null 2>&1 || error "Go is not installed. Please install Go 1.21+ first."
    command -v git >/dev/null 2>&1 || error "Git is not installed."
    command -v rsync >/dev/null 2>&1 || error "rsync is not installed."
    
    info "All prerequisites satisfied."
}

# Build the binary
build() {
    info "Building $BINARY_NAME..."
    cd "$SCRIPT_DIR"
    go build -o "$BINARY_NAME"
    chmod +x "$BINARY_NAME"
    info "Build successful: $SCRIPT_DIR/$BINARY_NAME"
}

# Setup .env file
setup_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        if [ -f "$SCRIPT_DIR/.env.example" ]; then
            cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
            warn ".env created from .env.example - please edit it with your configuration!"
            warn "Required: WORKSPACES, BACKUP_REPO, GIT_REMOTE, SSH_KEY_PATH"
            return 1
        else
            error ".env.example not found!"
        fi
    fi
    return 0
}

# Create necessary directories
create_dirs() {
    info "Creating directories..."
    mkdir -p "$SCRIPT_DIR/data"
    mkdir -p "$SCRIPT_DIR/logs"
}

# macOS launchd setup
setup_launchd() {
    info "Setting up launchd service (macOS)..."
    
    PLIST_PATH="$HOME/Library/LaunchAgents/com.$SERVICE_NAME.plist"
    LOG_PATH="$SCRIPT_DIR/logs"
    
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.$SERVICE_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/start.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH/launchd-error.log</string>
</dict>
</plist>
EOF
    
    # Unload if already loaded
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"
    
    info "launchd service installed and started."
    info "Plist: $PLIST_PATH"
    info "Commands:"
    echo "  Stop:    launchctl unload $PLIST_PATH"
    echo "  Start:   launchctl load $PLIST_PATH"
    echo "  Logs:    tail -f $LOG_PATH/launchd.log"
}

# Linux systemd setup
setup_systemd() {
    info "Setting up systemd service (Linux)..."
    
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=OpenClaw Auto Backup Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/start.sh
Restart=always
RestartSec=10
StandardOutput=append:$SCRIPT_DIR/logs/service.log
StandardError=append:$SCRIPT_DIR/logs/service-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME"
    
    info "systemd service installed and started."
    info "Commands:"
    echo "  Status:  sudo systemctl status $SERVICE_NAME"
    echo "  Stop:    sudo systemctl stop $SERVICE_NAME"
    echo "  Start:   sudo systemctl start $SERVICE_NAME"
    echo "  Logs:    journalctl -u $SERVICE_NAME -f"
}

# Fallback: cron setup
setup_cron() {
    warn "Using cron as fallback (service manager not available)..."
    
    # Create a wrapper script for cron
    CRON_WRAPPER="$SCRIPT_DIR/cron-check.sh"
    cat > "$CRON_WRAPPER" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$SCRIPT_DIR/data/service.pid"
BINARY="$SCRIPT_DIR/openclaw-autobackup"

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0  # Already running
fi

cd "$SCRIPT_DIR"
set -a
source .env
set +a
nohup "$BINARY" > "$SCRIPT_DIR/logs/cron.log" 2>&1 &
echo $! > "$PIDFILE"
EOF
    chmod +x "$CRON_WRAPPER"
    
    # Add to crontab (every 5 minutes check if running)
    CRON_LINE="*/5 * * * * $CRON_WRAPPER"
    (crontab -l 2>/dev/null | grep -v "$CRON_WRAPPER"; echo "$CRON_LINE") | crontab -
    
    # Start immediately
    "$CRON_WRAPPER"
    
    info "Cron job installed (checks every 5 minutes)."
    info "Service started in background."
}

# Detect OS and setup appropriate service
setup_service() {
    case "$(uname -s)" in
        Darwin)
            setup_launchd
            ;;
        Linux)
            if command -v systemctl >/dev/null 2>&1; then
                setup_systemd
            else
                setup_cron
            fi
            ;;
        *)
            setup_cron
            ;;
    esac
}

# Uninstall service
uninstall() {
    info "Uninstalling $SERVICE_NAME..."
    
    case "$(uname -s)" in
        Darwin)
            PLIST_PATH="$HOME/Library/LaunchAgents/com.$SERVICE_NAME.plist"
            launchctl unload "$PLIST_PATH" 2>/dev/null || true
            rm -f "$PLIST_PATH"
            info "launchd service removed."
            ;;
        Linux)
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
                sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
                sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
                sudo systemctl daemon-reload
                info "systemd service removed."
            fi
            ;;
    esac
    
    # Remove cron entry if exists
    crontab -l 2>/dev/null | grep -v "cron-check.sh" | crontab - 2>/dev/null || true
    
    info "Uninstall complete."
}

# Main
main() {
    echo "========================================"
    echo " OpenClaw Auto Backup - Setup"
    echo "========================================"
    echo
    
    case "${1:-}" in
        uninstall|remove)
            uninstall
            exit 0
            ;;
        build)
            build
            exit 0
            ;;
    esac
    
    check_prerequisites
    build
    create_dirs
    
    if ! setup_env; then
        echo
        warn "Please edit .env file first, then run this script again."
        exit 1
    fi
    
    setup_service
    
    echo
    info "Setup complete!"
    info "Dashboard: http://localhost:3458"
}

main "$@"
