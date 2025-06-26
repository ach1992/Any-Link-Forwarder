#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
CONFIG_FILE="$INSTALL_DIR/config.json"
FORWARD_PHP_URL="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/marzban-forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl certbot curl socat unzip

  mkdir -p $INSTALL_DIR

  echo "⬇️ Downloading forward.php..."
  curl -sSL $FORWARD_PHP_URL -o "$INSTALL_DIR/forward.php"

  echo "✅ Base installed. Now run:"
  echo "👉 ./marzforwarder.sh configure"
}

function configure {
  echo "🔧 Configure Marzban destination"
  read -p "Enter Marzban domain (e.g. panel.example.com): " DOMAIN
  read -p "Enter Marzban port (default 8443): " PORT
  [ -z "$PORT" ] && PORT=8443

  cat > "$CONFIG_FILE" <<EOF
{
  "target_domain": "$DOMAIN",
  "target_port": $PORT
}
EOF

  echo "✅ Destination saved to config.json"
}

function reconfigure {
  echo "🔁 Full reconfiguration (forwarder domain, SSL & destination)"

  read -p "Enter NEW forwarder domain (e.g. proxy.domain.ir): " NEW_DOMAIN
  read -p "Enter Marzban panel domain: " TARGET
  read -p "Enter target port (default 8443): " PORT
  [ -z "$PORT" ] && PORT=8443

  echo "🔐 Requesting SSL cert for $NEW_DOMAIN..."
  certbot delete --cert-name "$NEW_DOMAIN" 2>/dev/null
  certbot certonly --standalone --preferred-challenges http -d $NEW_DOMAIN \
    --agree-tos --email admin@$NEW_DOMAIN --non-interactive

  if [ ! -f "/etc/letsencrypt/live/$NEW_DOMAIN/fullchain.pem" ]; then
    echo "❌ SSL failed."
    exit 1
  fi

  cat > "$CONFIG_FILE" <<EOF
{
  "target_domain": "$TARGET",
  "target_port": $PORT
}
EOF

  echo "✅ Reconfiguration done."
  echo "👉 Run: ./marzforwarder.sh start $NEW_DOMAIN"
}

function start {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "Usage: ./marzforwarder.sh start yourdomain.com"
    exit 1
  fi

  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

  if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "❌ SSL certs not found for $DOMAIN"
    exit 1
  fi

  echo "🚀 Starting forwarder on https://$DOMAIN:443"
  php -S 127.0.0.1:8080 -t $INSTALL_DIR $INSTALL_DIR/forward.php &
  PHP_PID=$!

  socat OPENSSL-LISTEN:443,cert=$CERT_PATH,key=$KEY_PATH,reuseaddr,fork TCP:127.0.0.1:8080 &
  SOCAT_PID=$!

  trap "kill $PHP_PID $SOCAT_PID" SIGINT SIGTERM
  wait
}

function uninstall {
  read -p "Are you sure you want to uninstall everything? (yes/no): " CONFIRM
  [ "$CONFIRM" != "yes" ] && exit 0

  echo "🧹 Removing project files"
  rm -rf $INSTALL_DIR

  echo "🧹 Removing certbot crontab"
  crontab -l | grep -v 'certbot renew' | crontab -

  echo "✅ Uninstalled"
}

case "$1" in
  install) install ;;
  configure) configure ;;
  reconfigure) reconfigure ;;
  start) start "$2" ;;
  uninstall) uninstall ;;
  *)
    echo "Usage: $0 {install|configure|reconfigure|start <domain>|uninstall}"
    exit 1
    ;;
esac
