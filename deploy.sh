#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Image name
IMAGE="ghcr.io/jx453331958/openclaw-autobackup:latest"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prompt with default value, result stored in REPLY
prompt() {
    local msg="$1"
    local default="$2"
    if [ -n "$default" ]; then
        read -p "$(echo -e "${CYAN}$msg${NC} [${default}]: ")" REPLY
        REPLY="${REPLY:-$default}"
    else
        read -p "$(echo -e "${CYAN}$msg${NC}: ")" REPLY
    fi
}

# Prompt for required value (loop until non-empty)
prompt_required() {
    local msg="$1"
    REPLY=""
    while [ -z "$REPLY" ]; do
        read -p "$(echo -e "${CYAN}$msg${NC}: ")" REPLY
        if [ -z "$REPLY" ]; then
            print_error "This field is required"
        fi
    done
}

# Check if docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    print_info "Docker is available"
}

# Load .env file variables
load_env() {
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    fi
}

# Get host IP address
get_host_ip() {
    local ip=""
    if command -v hostname &> /dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ] && command -v ip &> /dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    fi
    if [ -z "$ip" ]; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi
    echo "${ip:-localhost}"
}

# Interactive configuration wizard
interactive_setup() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  OpenClaw AutoBackup Setup Wizard${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # --- Workspaces ---
    echo -e "${BOLD}1/5 Workspace Configuration${NC}"
    echo "  Add the directories you want to back up."
    echo "  Each workspace needs a name and its absolute path."
    echo ""

    local workspaces_str=""
    local workspace_volumes=""
    local ws_index=1

    while true; do
        echo -e "  ${BOLD}Workspace #${ws_index}${NC}"
        prompt "    Name (e.g. my-project)"
        local ws_name="$REPLY"
        if [ -z "$ws_name" ]; then
            if [ -z "$workspaces_str" ]; then
                print_error "  At least one workspace is required"
                continue
            fi
            break
        fi

        prompt_required "    Path (absolute path, e.g. /home/user/projects/my-project)"
        local ws_path="$REPLY"

        # Validate path format
        if [[ "$ws_path" != /* ]]; then
            print_error "  Path must be absolute (start with /)"
            continue
        fi

        if [ -n "$workspaces_str" ]; then
            workspaces_str="${workspaces_str},"
        fi
        workspaces_str="${workspaces_str}${ws_name}:${ws_path}"
        workspace_volumes="${workspace_volumes}      - ${ws_path}:${ws_path}:ro\n"
        print_info "  Added: ${ws_name} -> ${ws_path}"
        echo ""

        ws_index=$((ws_index + 1))
        prompt "  Add another workspace? (y/N)"
        if [[ ! "$REPLY" =~ ^[Yy] ]]; then
            break
        fi
        echo ""
    done

    # --- Backup Repo ---
    echo ""
    echo -e "${BOLD}2/5 Backup Repository${NC}"
    echo "  Local git repository where backups will be stored."
    echo "  If it doesn't exist, it will be created automatically."
    echo ""
    prompt_required "  Backup repo path (e.g. /home/user/backup-repo)"
    local backup_repo="$REPLY"

    # --- Git Remote ---
    echo ""
    echo -e "${BOLD}3/5 Git Remote${NC}"
    echo "  Remote URL to push backups to (optional, press Enter to skip)."
    echo ""
    prompt "  Git remote URL (e.g. git@github.com:user/backup.git)"
    local git_remote="$REPLY"

    # --- SSH Key ---
    local ssh_key_path=""
    if [ -n "$git_remote" ]; then
        echo ""
        echo -e "${BOLD}4/5 SSH Key${NC}"
        echo "  SSH private key for pushing to the remote repository."
        echo ""
        local default_key="$HOME/.ssh/id_rsa"
        # Try to find an existing key
        if [ ! -f "$default_key" ] && [ -f "$HOME/.ssh/id_ed25519" ]; then
            default_key="$HOME/.ssh/id_ed25519"
        fi
        prompt "  SSH key path" "$default_key"
        ssh_key_path="$REPLY"
    else
        echo ""
        echo -e "${BOLD}4/5 SSH Key${NC} (skipped, no git remote configured)"
    fi

    # --- Optional Settings ---
    echo ""
    echo -e "${BOLD}5/5 Optional Settings${NC}"
    echo ""
    prompt "  Web dashboard port" "3458"
    local port="$REPLY"

    echo ""
    echo "  Telegram notifications (press Enter to skip):"
    prompt "    Bot token"
    local tg_token="$REPLY"
    local tg_chat_id=""
    if [ -n "$tg_token" ]; then
        prompt "    Chat ID"
        tg_chat_id="$REPLY"
    fi

    # --- Init backup repo ---
    if [ ! -d "$backup_repo" ]; then
        print_info "Creating backup repository: $backup_repo"
        mkdir -p "$backup_repo"
        git init "$backup_repo" > /dev/null 2>&1
        git -C "$backup_repo" commit --allow-empty -m "init" > /dev/null 2>&1
    fi
    if [ -n "$git_remote" ] && [ -d "$backup_repo/.git" ]; then
        if ! git -C "$backup_repo" remote get-url origin > /dev/null 2>&1; then
            git -C "$backup_repo" remote add origin "$git_remote" > /dev/null 2>&1
        fi
    fi

    # --- Generate .env ---
    print_info "Generating .env..."
    cat > .env << ENVEOF
# Server Configuration
PORT=${port}

# Database Configuration
DATABASE_URL=/app/data/backup.db

# Workspace Configuration
WORKSPACES=${workspaces_str}

# Backup Repository Configuration
BACKUP_REPO=${backup_repo}

# Git Remote URL
GIT_REMOTE=${git_remote}

# SSH Key Path for Git Push
SSH_KEY_PATH=${ssh_key_path}

# Telegram Notification Configuration (Optional)
TELEGRAM_BOT_TOKEN=${tg_token}
TELEGRAM_CHAT_ID=${tg_chat_id}
ENVEOF

    # --- Generate docker-compose.yml ---
    print_info "Generating docker-compose.yml..."

    local ssh_volume=""
    if [ -n "$ssh_key_path" ]; then
        ssh_volume="      - ${ssh_key_path}:${ssh_key_path}:ro"
    fi

    cat > docker-compose.yml << COMPOSEEOF
services:
  openclaw-autobackup:
    image: ${IMAGE}
    container_name: openclaw-autobackup
    restart: unless-stopped
    ports:
      - "${port}:3458"
    volumes:
      - ./data:/app/data
      - ${backup_repo}:${backup_repo}
$(echo -e "$workspace_volumes" | sed '/^$/d')
${ssh_volume}
    env_file:
      - .env
COMPOSEEOF

    # --- Summary ---
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  Configuration Summary${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo -e "  Workspaces:   ${GREEN}${workspaces_str}${NC}"
    echo -e "  Backup repo:  ${GREEN}${backup_repo}${NC}"
    echo -e "  Git remote:   ${GREEN}${git_remote:-not configured}${NC}"
    echo -e "  SSH key:      ${GREEN}${ssh_key_path:-not configured}${NC}"
    echo -e "  Port:         ${GREEN}${port}${NC}"
    echo -e "  Telegram:     ${GREEN}${tg_token:+configured}${tg_token:-not configured}${NC}"
    echo ""

    read -p "$(echo -e "Proceed with deployment? (Y/n): ")" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "Configuration saved to .env and docker-compose.yml"
        print_info "Run '$0 deploy' again when ready"
        exit 0
    fi
}

# Create data directory
init_data_dir() {
    if [ ! -d data ]; then
        mkdir -p data
    fi
}

# Deploy (first time)
deploy() {
    print_info "Starting deployment..."

    check_docker

    if [ -f .env ] && [ -f docker-compose.yml ]; then
        print_info "Existing configuration found"
        read -p "$(echo -e "${CYAN}Reconfigure? (y/N)${NC}: ")" reconfigure
        if [[ "$reconfigure" =~ ^[Yy] ]]; then
            interactive_setup
        fi
    else
        interactive_setup
    fi

    load_env
    init_data_dir

    print_info "Pulling latest image..."
    docker compose pull

    print_info "Starting containers..."
    docker compose up -d

    print_info "Waiting for service to be ready..."
    sleep 3

    if docker compose ps | grep -q "Up"; then
        local host_ip=$(get_host_ip)
        local port="${PORT:-3458}"
        echo ""
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}  OpenClaw AutoBackup is now running!${NC}"
        echo -e "${GREEN}  Dashboard: http://${host_ip}:${port}${NC}"
        echo -e "${GREEN}============================================${NC}"
    else
        print_error "Deployment failed. Check logs with: $0 logs"
        exit 1
    fi
}

# Update (pull latest image and restart)
update() {
    print_info "Starting update..."

    check_docker

    print_info "Pulling latest image..."
    docker compose pull

    print_info "Restarting containers with new image..."
    docker compose up -d

    print_info "Waiting for service to be ready..."
    sleep 3

    if docker compose ps | grep -q "Up"; then
        print_info "Update successful!"
    else
        print_error "Update failed. Check logs with: $0 logs"
        exit 1
    fi
}

# Stop service
stop() {
    print_info "Stopping service..."
    docker compose down
    print_info "Service stopped"
}

# Restart service
restart() {
    print_info "Restarting service..."
    docker compose restart
    print_info "Service restarted"
}

# Show logs
logs() {
    docker compose logs -f --tail=100
}

# Show status
status() {
    echo ""
    print_info "Container status:"
    docker compose ps
    echo ""
    print_info "Recent logs:"
    docker compose logs --tail=20
}

# Backup database
backup() {
    BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).db"
    if [ -f data/backup.db ]; then
        if cp data/backup.db "data/$BACKUP_FILE" 2>/dev/null; then
            print_info "Database backed up to: data/$BACKUP_FILE"
        elif docker run --rm -v "$(pwd)/data:/data" alpine cp /data/backup.db "/data/$BACKUP_FILE"; then
            print_info "Database backed up to: data/$BACKUP_FILE (via docker)"
        else
            print_error "Failed to backup database"
            exit 1
        fi
    else
        print_warn "No database file found to backup"
    fi
}

# Clean up (remove containers and images)
clean() {
    print_warn "This will remove containers and images. Data in ./data will be preserved."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down --rmi all
        print_info "Cleanup complete"
    else
        print_info "Cleanup cancelled"
    fi
}

# Show help
show_help() {
    echo "OpenClaw AutoBackup Management Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy   - Interactive setup and deployment"
    echo "  update   - Pull latest image and restart"
    echo "  start    - Start the service"
    echo "  stop     - Stop the service"
    echo "  restart  - Restart the service"
    echo "  status   - Show service status and recent logs"
    echo "  logs     - Follow container logs"
    echo "  backup   - Backup the database"
    echo "  clean    - Remove containers and images (preserves data)"
    echo "  help     - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy    # First-time interactive setup"
    echo "  $0 update    # Update to latest version"
    echo "  $0 logs      # View logs"
}

# Main
case "${1:-}" in
    deploy)
        deploy
        ;;
    update)
        update
        ;;
    start)
        docker compose up -d
        print_info "Service started"
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    backup)
        backup
        ;;
    clean)
        clean
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "${1:-}" ]; then
            show_help
        else
            print_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
