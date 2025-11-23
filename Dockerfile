FROM teddysun/v2ray:latest
EXPOSE 8080
COPY config.json /etc/v2ray/config.json
COPY index.html /www/index.html

CMD ["sh", "-c", "cp -r /www /usr/share/nginx/html 2>/dev/null || true; v2ray run -config /etc/v2ray/config.json"]
