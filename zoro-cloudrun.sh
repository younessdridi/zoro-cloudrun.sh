#!/bin/bash
set -euo pipefail

# ===============================
# ZORO Cloud Run VLESS Deployer
# ===============================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# -------------------------------
# Functions for validation
# -------------------------------
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    [[ $1 =~ $uuid_pattern ]]
}

validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    [[ $1 =~ $token_pattern ]]
}

validate_chat_id() {
    [[ $1 =~ ^-?[0-9]+$ ]]
}

validate_channel_id() {
    [[ $1 =~ ^-?[0-9]+$ ]]
}

# -------------------------------
# CPU Selection
# -------------------------------
select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    while true; do
        read -p "Select CPU cores (1-4): " cpu_choice
        case $cpu_choice in
            1) CPU=1; break ;;
            2) CPU=2; break ;;
            3) CPU=4; break ;;
            4) CPU=8; break ;;
            *) echo "Invalid selection";;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

# -------------------------------
# Memory Selection
# -------------------------------
select_memory() {
    echo
    info "=== Memory Configuration ==="
    echo "1. 512Mi"
    echo "2. 1Gi"
    echo "3. 2Gi"
    echo "4. 4Gi"
    echo "5. 8Gi"
    echo "6. 16Gi"
    while true; do
        read -p "Select memory (1-6): " mem_choice
        case $mem_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection";;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# -------------------------------
# Region Selection
# -------------------------------
select_region() {
    echo
    info "=== Region Selection ==="
    echo "1. us-central1 (Iowa, USA)"
    echo "2. us-west1 (Oregon, USA)"
    echo "3. us-east1 (South Carolina, USA)"
    echo "4. europe-west1 (Belgium)"
    echo "5. asia-southeast1 (Singapore)"
    echo "6. asia-northeast1 (Tokyo, Japan)"
    echo "7. asia-east1 (Taiwan)"
    while true; do
        read -p "Select region (1-7): " region_choice
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-northeast1"; break ;;
            7) REGION="asia-east1"; break ;;
            *) echo "Invalid selection";;
        esac
    done
    info "Selected region: $REGION"
}

# -------------------------------
# Telegram Destination
# -------------------------------
select_telegram_destination() {
    echo
    info "=== Telegram Destination ==="
    echo "1. Channel only"
    echo "2. Bot private message only"
    echo "3. Both Channel & Bot"
    echo "4. Don't send"
    while true; do
        read -p "Select (1-4): " t_choice
        case $t_choice in
            1) TELE_DEST="channel"; read -p "Channel ID: " TELE_CHANNEL; break ;;
            2) TELE_DEST="bot"; read -p "Chat ID: " TELE_CHAT; break ;;
            3) TELE_DEST="both"; read -p "Channel ID: " TELE_CHANNEL; read -p "Chat ID: " TELE_CHAT; break ;;
            4) TELE_DEST="none"; break ;;
            *) echo "Invalid selection";;
        esac
    done
}

# -------------------------------
# User input
# -------------------------------
get_user_input() {
    read -p "Enter service name: " SERVICE_NAME
    read -p "Enter UUID (leave blank to generate): " UUID
    UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
    if [[ "$TELE_DEST" != "none" ]]; then
        read -p "Enter Telegram Bot Token: " BOT_TOKEN
    fi
    read -p "Enter Host Domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
}

# -------------------------------
# Summary
# -------------------------------
show_summary() {
    echo
    info "=== Configuration Summary ==="
    echo "Service: $SERVICE_NAME"
    echo "UUID: $UUID"
    echo "CPU: $CPU"
    echo "Memory: $MEMORY"
    echo "Region: $REGION"
    echo "Host: $HOST_DOMAIN"
    echo "Telegram: $TELE_DEST"
    [[ "$TELE_DEST" == "channel" || "$TELE_DEST" == "both" ]] && echo "Channel ID: $TELE_CHANNEL"
    [[ "$TELE_DEST" == "bot" || "$TELE_DEST" == "both" ]] && echo "Chat ID: $TELE_CHAT"
    echo
    read -p "Proceed with deployment? (y/n): " confirm
    [[ ! $confirm =~ [Yy] ]] && echo "Cancelled" && exit 0
}

# -------------------------------
# Validate prerequisites
# -------------------------------
validate_prerequisites() {
    command -v gcloud >/dev/null 2>&1 || { error "gcloud CLI required"; exit 1; }
    command -v git >/dev/null 2>&1 || { error "git required"; exit 1; }
}

# -------------------------------
# Telegram send function
# -------------------------------
send_telegram() {
    local chat="$1"
    local msg="$2"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$chat" -d text="$msg" -d parse_mode=Markdown >/dev/null
}

send_notification() {
    local link="$1"
    case $TELE_DEST in
        "channel") send_telegram "$TELE_CHANNEL" "$link" ;;
        "bot") send_telegram "$TELE_CHAT" "$link" ;;
        "both") send_telegram "$TELE_CHANNEL" "$link"; send_telegram "$TELE_CHAT" "$link" ;;
        "none") ;;
    esac
}

# -------------------------------
# Main
# -------------------------------
main() {
    select_region
    select_cpu
    select_memory
    select_telegram_destination
    get_user_input
    show_summary
    validate_prerequisites

    log "Cloning gcp-v2ray repo..."
    rm -rf gcp-v2ray
    git clone https://github.com/nyeinkokoaung404/gcp-v2ray.git
    cd gcp-v2ray

    log "Building container..."
    gcloud builds submit --tag gcr.io/$(gcloud config get-value project)/$SERVICE_NAME --quiet

    log "Deploying Cloud Run..."
    gcloud run deploy $SERVICE_NAME \
        --image gcr.io/$(gcloud config get-value project)/$SERVICE_NAME \
        --platform managed \
        --region $REGION \
        --allow-unauthenticated \
        --cpu $CPU \
        --memory $MEMORY \
        --quiet

    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)')
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')

    VLESS_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Fzoro&security=tls&encryption=none&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"

    echo "Deployment finished!"
    echo "Service URL: $SERVICE_URL"
    echo "VLESS Link: $VLESS_LINK"

    send_notification "$VLESS_LINK"

    log "All done!"
}

main "$@"


