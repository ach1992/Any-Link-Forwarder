#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
NGINX_DIR="/etc/nginx/sites-enabled"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y nginx php php-curl curl certbot unzip python3-certbot-nginx

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Setting up CLI shortcut..."
  curl -sSL "https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh" -o "$BIN_PATH"
  chmod +x "$BIN_PATH"

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
  "target_port": $PORT
}
EOF

  curl -sSL "https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  echo "🔐 Requesting SSL certificate via certbot..."
  certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN"
    return 1
  }

  echo "📝 Creating Nginx config for $DOMAIN"
  cat > "$NGINX_DIR/$DOMAIN.conf" <<EOF
server {
  listen 443 ssl;
  server_name $DOMAIN;

  ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

  location / {
    root $INSTALL_DIR/instances/$DOMAIN;
    index forward.php;
  }
}
EOF

  nginx -t && systemctl reload nginx

  echo "✅ Forwarder created and running at https://$DOMAIN"
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

  read -p "❓ Are you sure you want to delete forwarder for $DOMAIN? (y/n): " CONFIRM
  [[ "$CONFIRM" != "y" ]] && echo "❌ Cancelled." && return

  echo "🧹 Removing forwarder: $DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  rm -f "$NGINX_DIR/$DOMAIN.conf"

  nginx -t && systemctl reload nginx
  echo "✅ $DOMAIN removed."
}

function uninstall {
  read -p "⚠️ This will uninstall ALL forwarders. Are you sure? (y/n): " CONFIRM
  [[ "$CONFIRM" != "y" ]] && echo "❌ Cancelled." && return

  echo "🧨 Uninstalling everything..."
  if [ -d "$INSTALL_DIR/instances" ]; then
    for dir in "$INSTALL_DIR/instances/"*; do
      DOMAIN=$(basename "$dir")
      echo "🧹 Removing forwarder: $DOMAIN"
      rm -rf "$INSTALL_DIR/instances/$DOMAIN"
      rm -f "$NGINX_DIR/$DOMAIN.conf"
      certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
    done
  fi

  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_PATH"

  echo "🔄 Reloading nginx..."
  nginx -t && systemctl reload nginx

  echo "✅ Fully uninstalled!"
}

function status {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "❌ Usage: marzforwarder status <domain>"
    exit 1
  fi

  echo "📊 Checking status for $DOMAIN..."
  if [ ! -f "$NGINX_DIR/$DOMAIN.conf" ]; then
    echo "❌ Nginx config not found."
    return 1
  fi

  echo "🔍 Nginx status: $(systemctl is-active nginx)"
  echo "🔐 SSL info:"
  openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -text -noout | grep -E 'Subject:|Not Before:|Not After :'
}

case "$1" in
  install) install ;;
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  renew-cert) certbot renew && systemctl reload nginx ;;
  status) status "$2" ;;
  "" | help | -h | --help)
    echo "🛠 Available marzforwarder commands:"
    echo ""
    echo "  install             🔧 Install dependencies and set up"
    echo "  add                 ➕ Add a new domain forwarder"
    echo "  list                📋 List all forwarders"
    echo "  remove <domain>     ❌ Remove a forwarder"
    echo "  uninstall           🧨 Uninstall everything"
    echo "  status <domain>     📊 Check forwarder and cert status"
    echo "  renew-cert          🔁 Manually renew all SSL certs"
    ;;
  *)
    echo "❌ Unknown command: '$1'"
    echo "Type 'marzforwarder help' to see available commands."
    ;;
esac
