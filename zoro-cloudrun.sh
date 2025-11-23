#!/bin/bash

set -euo pipefail

echo "====== ZORO CLOUD RUN FINAL PREMIUM ======"

# UUID
read -p "🧬 UUID (اتركه فارغ لتوليد UUID تلقائياً): " UUID
if [ -z "$UUID" ]; then
  UUID=$(cat /proc/sys/kernel/random/uuid)
  echo "✅ UUID Generated: $UUID"
fi

# CPU
echo ""
echo "====== CPU Options ======"
echo "1) 1 vCPU"
echo "2) 2 vCPU"
echo "3) 4 vCPU"
read -p "اختر رقم CPU: " CPU_CHOICE
case $CPU_CHOICE in
  1) CPU="1";;
  2) CPU="2";;
  3) CPU="4";;
  *) echo "❌ خطأ"; exit 1;;
esac

# RAM
echo ""
echo "====== RAM Options ======"
echo "1) 256Mi"
echo "2) 512Mi"
echo "3) 1Gi"
echo "4) 2Gi"
echo "5) 4Gi"
read -p "اختر رقم RAM: " RAM_CHOICE
case $RAM_CHOICE in
  1) RAM="256Mi";;
  2) RAM="512Mi";;
  3) RAM="1Gi";;
  4) RAM="2Gi";;
  5) RAM="4Gi";;
  *) echo "❌ خطأ"; exit 1;;
esac

# Region
echo ""
echo "====== Region Options ======"
echo "1) us-central1 🇺🇸"
echo "2) europe-west1 🇪🇺"
echo "3) europe-north1 🇫🇮"
echo "4) asia-east1 🇭🇰"
read -p "اختر رقم Region: " R_CHOICE
case $R_CHOICE in
  1) REGION="us-central1";;
  2) REGION="europe-west1";;
  3) REGION="europe-north1";;
  4) REGION="asia-east1";;
  *) echo "❌ خطأ"; exit 1;;
esac

# Bot Info
read -p "🤖 أدخل توكن البوت: " TOKEN
read -p "👤 أدخل ID الخاص بك: " ADMIN_ID

SERVICE_NAME="zoro-$(tr -dc a-z0-9 </dev/urandom | head -c 5)"

mkdir -p zoro-cloudrun
cd zoro-cloudrun

# config.json
cat <<EOF > config.json
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/@zoro_40"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

# index.html (صفحة ترحيبية)
cat <<EOF > index.html
<!DOCTYPE html>
<html>
<head>
<title>ZORO SERVER</title>
<style>
body {
  background: black;
  color: #fff;
  text-align: center;
  font-family: Arial;
  padding-top: 90px;
}
h1 {
  font-size: 45px;
  color: #ff0000;
  text-shadow: 0 0 20px #ff0000;
}
p {
  font-size: 20px;
  opacity: 0.8;
}
</style>
</head>
<body>
<h1>🔥 ZORO SERVER ACTIVE 🔥</h1>
<p>Welcome to your Cloud Run VLESS Server</p>
</body>
</html>
EOF

# Dockerfile
cat <<EOF > Dockerfile
FROM teddysun/v2ray:latest
EXPOSE 8080
COPY config.json /etc/v2ray/config.json
COPY index.html /usr/share/nginx/html/index.html
CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF

# Build & Deploy
gcloud builds submit --tag gcr.io/\$(gcloud config get-value project)/$SERVICE_NAME
gcloud run deploy $SERVICE_NAME \
  --image gcr.io/\$(gcloud config get-value project)/$SERVICE_NAME \
  --platform managed \
  --region $REGION \
  --cpu $CPU \
  --memory $RAM \
  --allow-unauthenticated

URL=$(gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)')

CONFIG="vless://$UUID@$URL:443?type=ws&path=/@zoro_40&security=none#ZORO"

# Send to Telegram
curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
-d chat_id="$ADMIN_ID" \
-d parse_mode="Markdown" \
-d text="🔥 *ZORO CLOUD RUN SERVER CREATED*\n
🧬 UUID: \`$UUID\`
⚙ CPU: *$CPU vCPU*
💾 RAM: *$RAM*
🌍 Region: *$REGION*
🔧 Service: *$SERVICE_NAME*
🌐 URL: $URL

🔗 *VLESS CONFIG:*
\`\`\`
$CONFIG
\`\`\`

✅ صفحة ترحيبية مضافة
"

echo "تم إرسال كل شيء للبوت ✔"
