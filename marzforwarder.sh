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
  apt update && apt install -y php php-fpm php-curl curl certbot unzip nginx

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

  echo "➕ Adding new forwarder for $DOMAIN -> $PANEL:$PORT"
  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "listen_port": 443
}
EOF

  curl -sSL "$FORWARD_PHP_URL" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN"
    return 1
  }

  create_nginx_config "$DOMAIN"
  systemctl reload nginx

  echo "✅ Forwarder created and ready."
}

function create_nginx_config {
  DOMAIN=$1
  CONF_PATH="/etc/nginx/sites-available/$DOMAIN"
  cat > "$CONF_PATH" <<EOF
server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  location /sub/ {
    root $INSTALL_DIR/instances/$DOMAIN;
    index forward.php;
    try_files \$uri /forward.php;
    fastcgi_pass unix:/run/php/php-fpm.sock;
    fastcgi_index forward.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $INSTALL_DIR/instances/$DOMAIN/forward.php;
  }
}
EOF
  ln -s "$CONF_PATH" /etc/nginx/sites-enabled/ || true
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
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  rm -f "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive
  systemctl reload nginx
  echo "✅ Removed $DOMAIN."
}

function uninstall {
  echo "🧨 Uninstalling all Marzban forwarders..."
  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_PATH"
  rm -f "$RENEW_SERVICE_PATH" "$RENEW_TIMER_PATH"
  systemctl daemon-reload
  echo "✅ Fully uninstalled!"
}

function renew-cert {
  echo "🔐 Running certbot renew..."
  certbot renew
  echo "🔄 Reloading Nginx..."
  systemctl reload nginx
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
