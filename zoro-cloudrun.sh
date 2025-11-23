#!/bin/bash
set -e

echo "----------------------------------------"
echo "         ZORO Cloud Run Deployer"
echo "----------------------------------------"

read -p "أدخل توكن البوت: " BOT_TOKEN
read -p "أدخل آيدي التليغرام الذي يستقبل الرابط: " CHAT_ID
read -p "أدخل UUID (اضغط Enter لتوليد واحد تلقائياً): " UUID

if [[ -z "$UUID" ]]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
fi

read -p "اختر المنطقة (مثال: us-central1): " REGION
read -p "اختر اسم الخدمة (مثال: zoro-vless): " SERVICE

# إنشاء فولدر
mkdir -p zoro
cd zoro

# إنشاء Dockerfile
cat > Dockerfile <<EOF
FROM teddysun/v2ray:latest
EXPOSE 8080
COPY config.json /etc/v2ray/config.json
COPY index.html /www/index.html

CMD ["sh", "-c", "cp -r /www /usr/share/nginx/html 2>/dev/null || true; v2ray run -config /etc/v2ray/config.json"]
EOF

# إنشاء config.json
cat > config.json <<EOF
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
          "path": "/zoro"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# إنشاء صفحة ترحيب
cat > index.html <<EOF
<!DOCTYPE html>
<html lang="ar">
<head>
<meta charset="UTF-8">
<title>ZORO SERVER</title>
<style>
body {
  background: #000;
  color: #00eaff;
  font-family: 'Tahoma';
  text-align: center;
  padding-top: 100px;
}
h1 {
  font-size: 45px;
  text-shadow: 0 0 20px #00eaff;
}
p {
  font-size: 22px;
  opacity: .8;
}
.logo {
  font-size: 80px;
  margin-bottom: 20px;
  text-shadow: 0 0 35px #ff0000;
}
</style>
</head>
<body>
<div class="logo">⚔️</div>
<h1>مرحباً بك في سيرفر ZORO</h1>
<p>السيرفر يعمل الآن بنجاح ✔️</p>
<p>WebSocket Path: /zoro</p>
</body>
</html>
EOF

# بناء الصورة
gcloud builds submit --tag gcr.io/\$(gcloud config get-value project)/$SERVICE

# نشر Cloud Run
URL=$(gcloud run deploy $SERVICE \
  --image gcr.io/\$(gcloud config get-value project)/$SERVICE \
  --region $REGION \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --format="value(status.url)")

# تكوين VLESS النهائي
VLESS="vless://$UUID@$URL:443?encryption=none&security=none&type=ws&path=/zoro#ZORO"

# إرسال الرسالة إلى البوت
curl -s -X POST https://api.telegram.org/bot$BOT_TOKEN/sendMessage \
    -d chat_id=$CHAT_ID \
    -d text="🔥 *تم إنشاء سيرفر ZORO VLESS بنجاح!* 🔥\n\n🌐 *الرابط:*\n\`\`\`\n$VLESS\n\`\`\`\n⚔️ استعمله الآن." \
    -d parse_mode=Markdown

echo "----------------------------------------"
echo "تم إرسال رابط السيرفر إلى تليغرام ✔️"
echo "----------------------------------------"

