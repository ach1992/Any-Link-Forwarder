#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
RENEW_SERVICE_PATH="/etc/systemd/system/marzforwarder-renew.service"
RENEW_TIMER_PATH="/etc/systemd/system/marzforwarder-renew.timer"

SCRIPT_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh"
RENEW_SERVICE_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.service"
RENEW_TIMER_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.timer"
FORWARD_PHP_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y php php-curl curl certbot unzip socat netcat

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Setting up CLI shortcut..."
  curl -sSL "$SCRIPT_URL" -o "$BIN_PATH"
  chmod +x "$BIN_PATH"

  echo "📅 Setting up automatic SSL renewal..."
  curl -sSL "$RENEW_SERVICE_URL" -o "$RENEW_SERVICE_PATH"
  curl -sSL "$RENEW_TIMER_URL" -o "$RENEW_TIMER_PATH"
  systemctl daemon-reload
  systemctl enable --now marzforwarder-renew.timer

  echo "✅ Installation completed."
  add
}

function add {
  read -p "🌐 Enter domain to listen (e.g., sub.domain.com): " DOMAIN
  if [ -d "$INSTALL_DIR/instances/$DOMAIN" ]; then
    echo "⚠️ Forwarder for $DOMAIN already exists."
    return 1
  fi

  read -p "📍 Enter target panel domain (e.g., panel.domain.ir): " PANEL
  read -p "🚪 Enter target panel port (e.g., 443): " PORT
  read -p "🔊 Enter local listen port (e.g., 443, 8443, 2096...): " LISTEN_PORT
  RANDOM_PORT=$((10000 + RANDOM % 1000))

  echo "➕ Adding new forwarder for $DOMAIN -> $PANEL:$PORT on port $LISTEN_PORT"
  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "listen_port": $LISTEN_PORT
}
EOF

  curl -sSL "$FORWARD_PHP_URL" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN"
    return 1
  }

  create_service "$DOMAIN" "$RANDOM_PORT" "$LISTEN_PORT"
  systemctl enable --now "marzforwarder-$DOMAIN"

  echo "✅ Forwarder created and running."
}

function create_service {
  DOMAIN=$1
  LOCAL_PORT=$2
  LISTEN_PORT=$3
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"

  cat > "$INSTALL_DIR/instances/$DOMAIN/run.sh" <<EOF
#!/bin/bash
cd "$INSTALL_DIR/instances/$DOMAIN"
php -S 127.0.0.1:$LOCAL_PORT forward.php &
while ! nc -z 127.0.0.1 $LOCAL_PORT; do sleep 0.5; done
exec socat openssl-listen:$LISTEN_PORT,reuseaddr,fork,verify=1,cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem,key=/etc/letsencrypt/live/$DOMAIN/privkey.pem,cafile=/etc/ssl/certs/ca-certificates.crt TCP:127.0.0.1:$LOCAL_PORT

EOF

  chmod +x "$INSTALL_DIR/instances/$DOMAIN/run.sh"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Sub Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=$INSTALL_DIR/instances/$DOMAIN/run.sh
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

  echo "❌ Removing forwarder $DOMAIN..."
  systemctl stop "marzforwarder-$DOMAIN"
  systemctl disable "marzforwarder-$DOMAIN"
  rm -f "/etc/systemd/system/marzforwarder-$DOMAIN.service"
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive

  echo "✅ Removed $DOMAIN."
}

function uninstall {
  echo "🧨 Uninstalling all Marzban forwarders..."

  if [ -d "$INSTALL_DIR/instances" ]; then
    for dir in "$INSTALL_DIR/instances/"*; do
      DOMAIN=$(basename "$dir")
      echo "🧹 Removing forwarder: $DOMAIN"
      systemctl stop "marzforwarder-$DOMAIN" 2>/dev/null
      systemctl disable "marzforwarder-$DOMAIN" 2>/dev/null
      rm -f "/etc/systemd/system/marzforwarder-$DOMAIN.service"
      certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
    done
  fi

  echo "🗑 Removing install directory..."
  rm -rf "$INSTALL_DIR"

  echo "🗑 Removing CLI command..."
  rm -f "$BIN_PATH"

  echo "🧹 Removing auto-renew services..."
  rm -f "$RENEW_SERVICE_PATH"
  rm -f "$RENEW_TIMER_PATH"
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
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  renew-cert) renew-cert ;;
  "" | help | -h | --help)
    echo "🛠 Available marzforwarder commands:"
    echo ""
    echo "  install             🔧 Install all dependencies and setup the tool"
    echo "  add                 ➕ Add a new domain forwarder"
    echo "  list                📋 List all configured forwarders"
    echo "  remove <domain>     ❌ Remove a forwarder"
    echo "  uninstall           🧨 Fully uninstall marzforwarder and clean all files"
    echo "  renew-cert          🔁 Manually renew SSL certificates for all domains"
    echo ""
    echo "ℹ️  Example: marzforwarder add"
    ;;
  *)
    echo "❌ Unknown command: '$1'"
    echo "Type 'marzforwarder help' to see available commands."
    ;;
esac
