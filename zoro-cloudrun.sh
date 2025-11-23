#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log(){ echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARNING]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; }
info(){ echo -e "${BLUE}[INFO]${NC} $1"; }

# ===== Validation =====
validate_uuid(){ [[ $1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; }
validate_bot_token(){ [[ $1 =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; }
validate_id(){ [[ $1 =~ ^-?[0-9]+$ ]]; }

# ===== Select Region =====
select_region(){
    echo
    echo "=== اختر الدولة ==="
    echo "1. us-central1 (Iowa, USA)"
    echo "2. us-west1 (Oregon, USA)"
    echo "3. us-east1 (South Carolina, USA)"
    echo "4. europe-west1 (Belgium)"
    echo "5. asia-southeast1 (Singapore)"
    echo "6. asia-northeast1 (Tokyo, Japan)"
    echo "7. asia-east1 (Taiwan)"
    echo
    read -p "اختيارك: " r
    case $r in
        1) REGION="us-central1" ;;
        2) REGION="us-west1" ;;
        3) REGION="us-east1" ;;
        4) REGION="europe-west1" ;;
        5) REGION="asia-southeast1" ;;
        6) REGION="asia-northeast1" ;;
        7) REGION="asia-east1" ;;
        *) error "اختيار خاطئ"; exit 1 ;;
    esac
}

# ===== Select CPU & Memory =====
select_cpu(){ echo; echo "1) 1 CPU"; echo "2) 2 CPU"; echo "3) 4 CPU"; read -p "اختر CPU: " c; case $c in 1) CPU="1";;2) CPU="2";;3) CPU="4";;*) CPU="1";;esac }
select_memory(){ echo; echo "1) 512Mi"; echo "2) 1Gi"; echo "3) 2Gi"; read -p "اختر Memory: " m; case $m in 1) MEMORY="512Mi";;2) MEMORY="1Gi";;3) MEMORY="2Gi";;*) MEMORY="1Gi";;esac }

# ===== Telegram =====
select_tg(){
    echo
    echo "1) إرسال للقناة"
    echo "2) إرسال للخاص"
    echo "3) القناة والخاص"
    echo "4) عدم الإرسال"
    read -p "اختيارك: " t
    case $t in
        1) TELEGRAM_DESTINATION="channel"; read -p "ادخل ID القناة: " TELEGRAM_CHANNEL_ID; validate_id "$TELEGRAM_CHANNEL_ID" || exit ;;
        2) TELEGRAM_DESTINATION="bot"; read -p "ادخل Chat ID: " TELEGRAM_CHAT_ID; validate_id "$TELEGRAM_CHAT_ID" || exit ;;
        3) TELEGRAM_DESTINATION="both"; read -p "ادخل ID القناة: " TELEGRAM_CHANNEL_ID; validate_id "$TELEGRAM_CHANNEL_ID" || exit; read -p "ادخل Chat ID: " TELEGRAM_CHAT_ID; validate_id "$TELEGRAM_CHAT_ID" || exit ;;
        4) TELEGRAM_DESTINATION="none" ;;
        *) TELEGRAM_DESTINATION="none" ;;
    esac
}

# ===== User Input =====
get_user_input(){
    read -p "اسم السرفر: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-"zoro-server"}
    read -p "UUID (Enter لاستخدام الافتراضي): " UUID
    UUID=${UUID:-"ba0e3984-ccc9-48a3-8074-b2f507f41ce8"}
    validate_uuid "$UUID" || { error "UUID غير صحيح"; exit 1; }
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        read -p "Bot Token: " TELEGRAM_BOT_TOKEN
        validate_bot_token "$TELEGRAM_BOT_TOKEN" || exit 1
    fi
    read -p "Host Domain (default m.googleapis.com): " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
}

send_tg(){ curl -s -X POST -H "Content-Type: application/json" -d "{\"chat_id\":\"$1\",\"text\":\"$2\",\"parse_mode\":\"Markdown\"}" https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage; }

# ===== Deploy =====
deploy(){
    PROJECT_ID=$(gcloud config get-value project)
    gcloud services enable cloudbuild.googleapis.com run.googleapis.com iam.googleapis.com --quiet
    rm -rf gcp-v2ray
    git clone https://github.com/nyeinkokoaung404/gcp-v2ray.git
    cd gcp-v2ray
    log "Building..."
    gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray --quiet
    log "Deploy..."
    gcloud run deploy ${SERVICE_NAME} --image gcr.io/${PROJECT_ID}/gcp-v2ray --region ${REGION} --platform managed --allow-unauthenticated --cpu ${CPU} --memory ${MEMORY} --quiet
    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} --region ${REGION} --format 'value(status.url)')
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')

    PATCH="/zoro"
    VLESS="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Fzoro&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"

    # ===== JSON CONFIG FILE =====
    cat > "${SERVICE_NAME}-config.json" <<EOF
{
  "v": "2",
  "ps": "${SERVICE_NAME}",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "${HOST_DOMAIN}",
  "path": "${PATCH}",
  "tls": "tls"
}
EOF

    MSG="*تم إنشاء سرفر ZORO بنجاح ✅*
• Project: \`${PROJECT_ID}\`
• Service: \`${SERVICE_NAME}\`
• Region: ${REGION}
• CPU: ${CPU}
• RAM: ${MEMORY}
• URL: ${DOMAIN}

🔗 VLESS:
\`${VLESS}\`

📄 JSON config saved: \`${SERVICE_NAME}-config.json\`"

    echo "$MSG"

    # Send to Telegram
    [[ "$TELEGRAM_DESTINATION" == "channel" ]] && send_tg "$TELEGRAM_CHANNEL_ID" "$MSG"
    [[ "$TELEGRAM_DESTINATION" == "bot" ]] && send_tg "$TELEGRAM_CHAT_ID" "$MSG"
    [[ "$TELEGRAM_DESTINATION" == "both" ]] && { send_tg "$TELEGRAM_CHANNEL_ID" "$MSG"; send_tg "$TELEGRAM_CHAT_ID" "$MSG"; }

    log "تم نشر السرفر بنجاح 🎉"
}

# ===== RUN =====
select_region
select_cpu
select_memory
select_tg
get_user_input
deploy
