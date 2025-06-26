#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
CONFIG_FILE="$INSTALL_DIR/config.json"
FORWARD_PHP_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl curl socat certbot unzip

  echo "📁 Creating install directory..."
  mkdir -p "$INSTALL_DIR"

  echo "⬇️ Downloading forward.php..."
  curl -sSL "$FORWARD_PHP_URL" -o "$INSTALL_DIR/forward.php"

  echo "🔗 Creating CLI command 'marzforwarder'..."
  chmod +x "$0"
  ln -sf "$(realpath "$0")" /usr/local/bin/marzforwarder

  echo "✅ Installation complete!"
  echo "👉 Next: run 'marzforwarder configure'"
}

function configure {
  echo "🔧 Configure Marzban destination:"
  read -p "Enter Marzban domain (e.g. panel.domain.com): " DOMAIN
  read -p "Enter Marzban port (default: 8443): " PORT
  PORT=${PORT:-8443}

  cat > "$CONFIG_FILE" <<EOF
{
  "target_domain": "$DOMAIN",
  "target_port": $PORT
}
EOF

  echo "✅ Configuration saved to $CONFIG_FILE"
}

function reconfigure {
  echo "🔁 Reconfigure forwarder & reissue SSL"

  read -p "Enter forwarder domain (e.g. sub.domain.ir): " FORWARD_DOMAIN
  read -p "Enter Marzban domain (e.g. panel.domain.com): " TARGET_DOMAIN
  read -p "Enter Marzban port (default: 8443): " PORT
  PORT=${PORT:-8443}

  echo "🧼 Cleaning old certificate if exists..."
  certbot delete --cert-name "$FORWARD_DOMAIN" 2>/dev/null

  echo "🔐 Issuing SSL certificate for $FORWARD_DOMAIN..."
  certbot certonly --standalone --preferred-challenges http -d "$FORWARD_DOMAIN" \
    --agree-tos --email "admin@$FORWARD_DOMAIN" --non-interactive

  if [ ! -f "/etc/letsencrypt/live/$FORWARD_DOMAIN/fullchain.pem" ]; then
    echo "❌ SSL certificate failed. Aborting."
    exit 1
  fi

  cat > "$CONFIG_FILE" <<EOF
{
  "target_domain": "$TARGET_DOMAIN",
  "target_port": $PORT
}
EOF

  echo "✅ Reconfiguration complete."
  echo "👉 Run: marzforwarder start $FORWARD_DOMAIN"
}

function start {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "❗ Usage: marzforwarder start yourdomain.ir"
    exit 1
  fi

  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

  if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "❌ SSL certificate not found for $DOMAIN"
    exit 1
  fi

  echo "🚀 Starting forwarder on https://$DOMAIN (port 443)"

  echo "▶ Launching PHP server..."
  php -S 127.0.0.1:8080 -t "$INSTALL_DIR" "$INSTALL_DIR/forward.php" &
  PHP_PID=$!

  echo "▶ Launching socat HTTPS listener..."
  socat OPENSSL-LISTEN:443,cert=$CERT_PATH,key=$KEY_PATH,reuseaddr,fork TCP:127.0.0.1:8080 &
  SOCAT_PID=$!

  trap "kill $PHP_PID $SOCAT_PID" SIGINT SIGTERM
  wait
}

function uninstall {
  read -p "Are you sure you want to uninstall everything? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Aborted."
    exit 0
  fi

  echo "🗑 Removing project directory..."
  rm -rf "$INSTALL_DIR"

  echo "🗑 Removing CLI command 'marzforwarder'..."
  rm -f /usr/local/bin/marzforwarder

  echo "🧹 Removing certbot renewal cronjobs (if any)..."
  crontab -l | grep -v 'certbot renew' | crontab -

  echo "✅ Uninstallation complete."
}

# Dispatcher
case "$1" in
  install) install ;;
  configure) configure ;;
  reconfigure) reconfigure ;;
  start) start "$2" ;;
  uninstall) uninstall ;;
  *)
    echo "Usage: marzforwarder {install|configure|reconfigure|start <domain>|uninstall}"
    exit 1
    ;;
esac
