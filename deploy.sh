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
            print_error "此项为必填项"
        fi
    done
}

# Check if docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "未检测到 Docker，请先安装 Docker"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请先启动 Docker"
        exit 1
    fi

    print_info "Docker 环境就绪"
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
    echo -e "${BOLD}  OpenClaw AutoBackup 配置向导${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    # --- Workspaces ---
    echo -e "${BOLD}1/5 工作区配置${NC}"
    echo "  添加需要备份的目录，每个工作区需要一个名称和绝对路径。"
    echo ""

    local workspaces_str=""
    local workspace_volumes=""
    local ws_index=1

    while true; do
        echo -e "  ${BOLD}工作区 #${ws_index}${NC}"
        prompt "    名称（如 my-project）"
        local ws_name="$REPLY"
        if [ -z "$ws_name" ]; then
            if [ -z "$workspaces_str" ]; then
                print_error "  至少需要配置一个工作区"
                continue
            fi
            break
        fi

        prompt_required "    路径（绝对路径，如 /home/user/projects/my-project）"
        local ws_path="$REPLY"

        # Validate path format
        if [[ "$ws_path" != /* ]]; then
            print_error "  路径必须是绝对路径（以 / 开头）"
            continue
        fi

        if [ -n "$workspaces_str" ]; then
            workspaces_str="${workspaces_str},"
        fi
        workspaces_str="${workspaces_str}${ws_name}:${ws_path}"
        workspace_volumes="${workspace_volumes}      - ${ws_path}:${ws_path}:ro\n"
        print_info "  已添加: ${ws_name} -> ${ws_path}"
        echo ""

        ws_index=$((ws_index + 1))
        prompt "  继续添加工作区？(y/N)"
        if [[ ! "$REPLY" =~ ^[Yy] ]]; then
            break
        fi
        echo ""
    done

    # --- Backup Repo ---
    echo ""
    echo -e "${BOLD}2/5 备份仓库${NC}"
    echo "  备份文件存储的本地 Git 仓库路径，不存在会自动创建。"
    echo ""
    prompt_required "  备份仓库路径（如 /home/user/backup-repo）"
    local backup_repo="$REPLY"

    # --- Git Remote ---
    echo ""
    echo -e "${BOLD}3/5 Git 远程仓库${NC}"
    echo "  备份推送的远程仓库地址（可选，直接回车跳过）。"
    echo ""
    prompt "  远程仓库地址（如 git@github.com:user/backup.git）"
    local git_remote="$REPLY"

    # --- SSH Key ---
    local ssh_key_path=""
    if [ -n "$git_remote" ]; then
        echo ""
        echo -e "${BOLD}4/5 SSH 密钥${NC}"
        echo "  用于推送到远程仓库的 SSH 私钥。"
        echo ""
        local default_key="$HOME/.ssh/id_rsa"
        # Try to find an existing key
        if [ ! -f "$default_key" ] && [ -f "$HOME/.ssh/id_ed25519" ]; then
            default_key="$HOME/.ssh/id_ed25519"
        fi
        prompt "  SSH 密钥路径" "$default_key"
        ssh_key_path="$REPLY"
    else
        echo ""
        echo -e "${BOLD}4/5 SSH 密钥${NC}（已跳过，未配置远程仓库）"
    fi

    # --- Optional Settings ---
    echo ""
    echo -e "${BOLD}5/5 可选配置${NC}"
    echo ""
    prompt "  Web 面板端口" "3458"
    local port="$REPLY"

    echo ""
    echo "  Telegram 通知（直接回车跳过）："
    prompt "    Bot Token"
    local tg_token="$REPLY"
    local tg_chat_id=""
    if [ -n "$tg_token" ]; then
        prompt "    Chat ID"
        tg_chat_id="$REPLY"
    fi

    # --- Init backup repo ---
    if [ ! -d "$backup_repo" ]; then
        print_info "正在创建备份仓库: $backup_repo"
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
    print_info "正在生成 .env..."
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
    print_info "正在生成 docker-compose.yml..."

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
    echo -e "${BOLD}  配置摘要${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo -e "  工作区:     ${GREEN}${workspaces_str}${NC}"
    echo -e "  备份仓库:   ${GREEN}${backup_repo}${NC}"
    echo -e "  远程仓库:   ${GREEN}${git_remote:-未配置}${NC}"
    echo -e "  SSH 密钥:   ${GREEN}${ssh_key_path:-未配置}${NC}"
    echo -e "  端口:       ${GREEN}${port}${NC}"
    echo -e "  Telegram:   ${GREEN}${tg_token:+已配置}${tg_token:-未配置}${NC}"
    echo ""

    read -p "$(echo -e "确认部署？(Y/n): ")" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        print_info "配置已保存到 .env 和 docker-compose.yml"
        print_info "准备好后运行 '$0 deploy' 即可部署"
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
    print_info "开始部署..."

    check_docker

    if [ -f .env ] && [ -f docker-compose.yml ]; then
        print_info "检测到已有配置"
        read -p "$(echo -e "${CYAN}是否重新配置？(y/N)${NC}: ")" reconfigure
        if [[ "$reconfigure" =~ ^[Yy] ]]; then
            interactive_setup
        fi
    else
        interactive_setup
    fi

    load_env
    init_data_dir

    print_info "正在拉取最新镜像..."
    docker compose pull

    print_info "正在启动容器..."
    docker compose up -d

    print_info "等待服务就绪..."
    sleep 3

    if docker compose ps | grep -q "Up"; then
        local host_ip=$(get_host_ip)
        local port="${PORT:-3458}"
        echo ""
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}  OpenClaw AutoBackup 已成功运行！${NC}"
        echo -e "${GREEN}  监控面板: http://${host_ip}:${port}${NC}"
        echo -e "${GREEN}============================================${NC}"
    else
        print_error "部署失败，请查看日志: $0 logs"
        exit 1
    fi
}

# Update (pull latest image and restart)
update() {
    print_info "开始更新..."

    check_docker

    print_info "正在拉取最新镜像..."
    docker compose pull

    print_info "正在使用新镜像重启..."
    docker compose up -d

    print_info "等待服务就绪..."
    sleep 3

    if docker compose ps | grep -q "Up"; then
        print_info "更新成功！"
    else
        print_error "更新失败，请查看日志: $0 logs"
        exit 1
    fi
}

# Stop service
stop() {
    print_info "正在停止服务..."
    docker compose down
    print_info "服务已停止"
}

# Restart service
restart() {
    print_info "正在重启服务..."
    docker compose restart
    print_info "服务已重启"
}

# Show logs
logs() {
    docker compose logs -f --tail=100
}

# Show status
status() {
    echo ""
    print_info "容器状态:"
    docker compose ps
    echo ""
    print_info "最近日志:"
    docker compose logs --tail=20
}

# Backup database
backup() {
    BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).db"
    if [ -f data/backup.db ]; then
        if cp data/backup.db "data/$BACKUP_FILE" 2>/dev/null; then
            print_info "数据库已备份到: data/$BACKUP_FILE"
        elif docker run --rm -v "$(pwd)/data:/data" alpine cp /data/backup.db "/data/$BACKUP_FILE"; then
            print_info "数据库已备份到: data/$BACKUP_FILE（通过 docker）"
        else
            print_error "数据库备份失败"
            exit 1
        fi
    else
        print_warn "未找到数据库文件"
    fi
}

# Clean up (remove containers and images)
clean() {
    print_warn "此操作将删除容器和镜像，./data 目录中的数据会保留。"
    read -p "确认删除？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down --rmi all
        print_info "清理完成"
    else
        print_info "已取消"
    fi
}

# Show help
show_help() {
    echo "OpenClaw AutoBackup 管理脚本"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "命令:"
    echo "  deploy   - 交互式配置并部署"
    echo "  update   - 拉取最新镜像并重启"
    echo "  start    - 启动服务"
    echo "  stop     - 停止服务"
    echo "  restart  - 重启服务"
    echo "  status   - 查看服务状态和最近日志"
    echo "  logs     - 实时查看日志"
    echo "  backup   - 备份数据库"
    echo "  clean    - 删除容器和镜像（保留数据）"
    echo "  help     - 显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 deploy    # 首次部署"
    echo "  $0 update    # 更新到最新版本"
    echo "  $0 logs      # 查看日志"
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
        print_info "服务已启动"
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
            print_error "未知命令: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
