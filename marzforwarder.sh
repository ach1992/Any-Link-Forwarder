#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl socat curl certbot unzip

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Setting up CLI shortcut..."
  cp "$0" "$BIN_PATH"
  chmod +x "$BIN_PATH"

  echo "📅 Setting up automatic SSL renewal..."
  cp marzforwarder-renew.service /etc/systemd/system/
  cp marzforwarder-renew.timer /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now marzforwarder-renew.timer

  echo "✅ Installation completed."
}

function add {
  DOMAIN=$1
  PANEL=$2
  PORT=$3

  if [ -z "$DOMAIN" ] || [ -z "$PANEL" ] || [ -z "$PORT" ]; then
    echo "❌ Usage: marzforwarder add <domain> <panel> <port>"
    exit 1
  fi

  echo "➕ Adding new forwarder for $DOMAIN -> $PANEL:$PORT"

  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT
}
EOF

  curl -sSL "https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"

  create_service "$DOMAIN"
  systemctl enable --now marzforwarder-$DOMAIN

  echo "✅ Forwarder created and running."
}

function create_service {
  DOMAIN=$1
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Sub Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8443,reuseaddr,fork TCP:127.0.0.1:10443
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  cat > "$INSTALL_DIR/instances/$DOMAIN/run.sh" <<EOF
#!/bin/bash
cd "$INSTALL_DIR/instances/$DOMAIN"
php -S 127.0.0.1:10443 forward.php
EOF

  chmod +x "$INSTALL_DIR/instances/$DOMAIN/run.sh"
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

  echo "❌ Removing forwarder $DOMAIN..."
  systemctl stop marzforwarder-$DOMAIN
  systemctl disable marzforwarder-$DOMAIN
  rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive

  echo "✅ Removed $DOMAIN."
}

function instance-start {
  DOMAIN=$1
  bash "$INSTALL_DIR/instances/$DOMAIN/run.sh"
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

  echo "🗑 Removing install directory..."
  rm -rf "$INSTALL_DIR"

  echo "🗑 Removing CLI command..."
  rm -f "$BIN_PATH"

  rm -f /etc/systemd/system/marzforwarder-renew.service
  rm -f /etc/systemd/system/marzforwarder-renew.timer
  systemctl daemon-reload

  echo "✅ Fully uninstalled!"
}

function renew-cert {
  echo "🔁 Stopping all forwarders before renewal..."
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
  add) add "$2" "$3" "$4" ;;
  list) list ;;
  remove) remove "$2" ;;
  instance-start) instance-start "$2" ;;
  uninstall) uninstall ;;
  renew-cert) renew-cert ;;
  *) echo "❌ Unknown command. Use: install | add | list | remove | instance-start | uninstall | renew-cert" ;;
esac
