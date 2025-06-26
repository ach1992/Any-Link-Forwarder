#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
FORWARD_PHP_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl curl socat certbot unzip

  echo "📁 Creating install directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Creating CLI command 'marzforwarder'..."
  chmod +x "$0"
  ln -sf "$(realpath "$0")" /usr/local/bin/marzforwarder

  echo "✅ Installation complete!"
}

function add {
  DOMAIN=$1
  TARGET_DOMAIN=$2
  TARGET_PORT=$3

  if [ -z "$DOMAIN" ] || [ -z "$TARGET_DOMAIN" ] || [ -z "$TARGET_PORT" ]; then
    echo "❌ Usage: marzforwarder add <yourdomain.ir> <panel.domain.com> <port>"
    exit 1
  fi

  INST_PATH="$INSTALL_DIR/instances/$DOMAIN"
  mkdir -p "$INST_PATH"

  echo "\2b07️ Downloading forward.php..."
  curl -sSL "$FORWARD_PHP_URL" -o "$INST_PATH/forward.php"

  echo "🗘 Writing config.json..."
  cat > "$INST_PATH/config.json" <<EOF
{
  "target_domain": "$TARGET_DOMAIN",
  "target_port": $TARGET_PORT
}
EOF

  echo "🔐 Issuing SSL certificate for $DOMAIN..."
  certbot certonly --standalone --preferred-challenges http -d "$DOMAIN" \
    --agree-tos --email "admin@$DOMAIN" --non-interactive

  if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "❌ SSL certificate failed. Aborting."
    exit 1
  fi

  echo "⚙️ Creating systemd service marzforwarder-$DOMAIN..."
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=/usr/local/bin/marzforwarder instance-start $DOMAIN
Restart=always
RestartSec=5
User=root
WorkingDirectory=$INST_PATH

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable marzforwarder-$DOMAIN
  systemctl start marzforwarder-$DOMAIN

  echo "✅ Forwarder for $DOMAIN is now active."
}

function instance-start {
  DOMAIN=$1
  INST_PATH="$INSTALL_DIR/instances/$DOMAIN"
  CONFIG="$INST_PATH/config.json"
  PHP_FILE="$INST_PATH/forward.php"

  if [ ! -f "$CONFIG" ]; then
    echo "❌ Configuration not found for $DOMAIN"
    exit 1
  fi

  CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
  PORT=443

  echo "🔄 Starting PHP server for $DOMAIN"
  php -S 127.0.0.1:8${RANDOM:0:3} -t "$INST_PATH" "$PHP_FILE" &
  PHP_PID=$!

  sleep 1

  socat OPENSSL-LISTEN:$PORT,cert=$CERT_PATH,key=$KEY_PATH,reuseaddr,fork TCP:127.0.0.1:8${RANDOM:0:3} &
  SOCAT_PID=$!

  trap "kill $PHP_PID $SOCAT_PID" SIGINT SIGTERM
  wait
}

function list {
  echo "📋 Active Forwarders:"
  for dir in $INSTALL_DIR/instances/*; do
    [ -d "$dir" ] && basename "$dir"
  done
}

function remove {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "Usage: marzforwarder remove <yourdomain.ir>"
    exit 1
  fi

  systemctl stop marzforwarder-$DOMAIN
  systemctl disable marzforwarder-$DOMAIN
  rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive

  systemctl daemon-reload
  echo "✅ Removed $DOMAIN and all associated files."
}

function uninstall {
  echo "🤨 Uninstalling all Marzban forwarders..."

  for dir in "$INSTALL_DIR/instances/"*; do
    DOMAIN=$(basename "$dir")
    echo "🛋 Removing forwarder: $DOMAIN"

    systemctl stop marzforwarder-$DOMAIN 2>/dev/null
    systemctl disable marzforwarder-$DOMAIN 2>/dev/null
    rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service

    certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
  done

  echo "🗑 Removing install directory..."
  rm -rf "$INSTALL_DIR"

  echo "🗑 Removing CLI command..."
  rm -f /usr/local/bin/marzforwarder

  systemctl daemon-reload

  echo "✅ Fully uninstalled!"
}

case "$1" in
  install) install ;;
  add) add "$2" "$3" "$4" ;;
  instance-start) instance-start "$2" ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  *)
    echo "Usage:"
    echo "  marzforwarder install"
    echo "  marzforwarder add <yourdomain.ir> <panel.domain.com> <port>"
    echo "  marzforwarder list"
    echo "  marzforwarder remove <yourdomain.ir>"
    echo "  marzforwarder uninstall"
    ;;
esac
