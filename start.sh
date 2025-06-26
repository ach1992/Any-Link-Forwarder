#!/bin/bash

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
  echo "❗ Usage: bash start.sh yourdomain.com"
  exit 1
fi

# Check and install socat if missing
if ! command -v socat &> /dev/null; then
  echo "📦 Installing socat..."
  apt update && apt install -y socat
fi

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
INSTALL_DIR="/var/www/marzban-forward"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "❌ SSL certificate files not found for $DOMAIN"
  exit 1
fi

echo "🚀 Starting Marzban forwarder for https://$DOMAIN:443"

# Start PHP server on local port 8080
php -S 127.0.0.1:8080 -t $INSTALL_DIR $INSTALL_DIR/forward.php &
PHP_PID=$!

# Forward SSL traffic from :443 to PHP :8080 via socat
socat OPENSSL-LISTEN:443,cert=$CERT_PATH,key=$KEY_PATH,reuseaddr,fork TCP:127.0.0.1:8080 &
SOCAT_PID=$!

# Graceful shutdown on CTRL+C
trap "kill $PHP_PID $SOCAT_PID" SIGINT SIGTERM
wait
