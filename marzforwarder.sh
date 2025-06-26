#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl curl certbot unzip

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Setting up CLI shortcut..."
  cp "$0" "$BIN_PATH"
  chmod +x "$BIN_PATH"

  echo "📅 Setting up automatic SSL renewal..."
  if [[ -f marzforwarder-renew.service && -f marzforwarder-renew.timer ]]; then
    cp marzforwarder-renew.service /etc/systemd/system/
    cp marzforwarder-renew.timer /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now marzforwarder-renew.timer
  else
    echo "❌ Missing marzforwarder-renew.service or marzforwarder-renew.timer"
  fi

  echo "✅ Installation completed."
}

function add {
  read -p "🌐 Enter domain name (e.g., sub.example.com): " DOMAIN
  read -p "🎯 Enter target panel domain (e.g., panel.example.com): " PANEL
  read -p "📡 Enter target panel port (e.g., 8443): " PORT

  if [ -z "$DOMAIN" ] || [ -z "$PANEL" ] || [ -z "$PORT" ]; then
    echo "❌ Invalid input. All fields are required."
    exit 1
  fi

  echo "➕ Creating forwarder for $DOMAIN -> $PANEL:$PORT"
  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  # Generate random local PHP port
  LOCAL_PORT=$((10000 + RANDOM % 10000))

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "local_php_port": $LOCAL_PORT
}
EOF

  curl -sSL "https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php" \
    -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  echo "🔐 Generating SSL certificate for $DOMAIN..."
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
  if [ $? -ne 0 ]; then
    echo "❌ SSL generation failed for $DOMAIN"
    exit 1
  fi

  create_service "$DOMAIN" "$LOCAL_PORT"
  systemctl enable --now marzforwarder-$DOMAIN
  echo "✅ Forwarder for $DOMAIN is created and running."
}

function create_service {
  DOMAIN=$1
  PORT=$2
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"

  cat > "$INSTALL_DIR/instances/$DOMAIN/run.sh" <<EOF
#!/bin/bash
cd "$INSTALL_DIR/instances/$DOMAIN"
php -S 127.0.0.1:$PORT forward.php
EOF

  chmod +x "$INSTALL_DIR/instances/$DOMAIN/run.sh"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=/bin/bash $INSTALL_DIR/instances/$DOMAIN/run.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
}

function list {
  echo "📋 Active forwarders:"
  ls "$INSTALL_DIR/instances"
}

function remove {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "❌ Usage: marzforwarder remove <domain>"
    exit 1
  fi

  echo "🧹 Removing forwarder $DOMAIN..."
  systemctl stop marzforwarder-$DOMAIN
  systemctl disable marzforwarder-$DOMAIN
  rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive

  echo "✅ Removed $DOMAIN."
}

function uninstall {
  echo "🧨 Uninstalling all Marzban forwarders..."

  for dir in "$INSTALL_DIR/instances/"*; do
    DOMAIN=$(basename "$dir")
    echo "🧹 Removing forwarder: $DOMAIN"
    systemctl stop marzforwarder-$DOMAIN 2>/dev/null
    systemctl disable marzforwarder-$DOMAIN 2>/dev/null
    rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service
    certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
  done

  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_PATH"
  rm -f /etc/systemd/system/marzforwarder-renew.service
  rm -f /etc/systemd/system/marzforwarder-renew.timer
  systemctl daemon-reload

  echo "✅ Fully uninstalled."
}

function renew-cert {
  echo "🔁 Stopping all forwarders before SSL renewal..."
  for svc in $(systemctl list-units --type=service --no-legend | grep 'marzforwarder-.*\.service' | awk '{print $1}'); do
    systemctl stop "$svc"
  done

  echo "🔐 Running certbot renew..."
  certbot renew

  echo "🚀 Restarting forwarders..."
  for svc in $(systemctl list-units --type=service --no-legend | grep 'marzforwarder-.*\.service' | awk '{print $1}'); do
    systemctl start "$svc"
  done

  echo "✅ SSL renewal completed."
}

case "$1" in
  install) install ;;
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  renew-cert) renew-cert ;;
  *) echo "❌ Unknown command. Use: install | add | list | remove | uninstall | renew-cert" ;;
esac
