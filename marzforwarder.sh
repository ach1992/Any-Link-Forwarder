#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
NGINX_SITES="/etc/nginx/sites-enabled"
FORWARD_PHP_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y nginx php php-curl curl certbot unzip

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔗 Setting up CLI shortcut..."
  curl -sSL "https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh" -o "$BIN_PATH"
  chmod +x "$BIN_PATH"

  echo "🔄 Restarting Nginx..."
  systemctl enable nginx
  systemctl restart nginx

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

  curl -sSL "$FORWARD_PHP_URL" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  echo "🔐 Requesting SSL certificate via certbot..."
  certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN"
    return 1
  }

  echo "🧾 Creating Nginx config for $DOMAIN..."
  cat > "$NGINX_SITES/$DOMAIN.conf" <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    root $INSTALL_DIR/instances/$DOMAIN;
    index forward.php;

    location / {
        try_files \$uri /forward.php\$is_args\$args;
    }
}
EOF

  systemctl reload nginx
  echo "✅ Forwarder for $DOMAIN has been created and is now active."
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

  echo "🧹 Removing forwarder for $DOMAIN..."
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  rm -f "$NGINX_SITES/$DOMAIN.conf"
  certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
  systemctl reload nginx

  echo "✅ $DOMAIN removed."
}

function uninstall {
  echo "🧨 Uninstalling MarzForwarder..."
  for dir in "$INSTALL_DIR/instances/"*; do
    DOMAIN=$(basename "$dir")
    echo "🧹 Removing: $DOMAIN"
    remove "$DOMAIN"
  done

  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_PATH"
  echo "✅ Fully uninstalled."
}

function status {
  DOMAIN=$2
  if [ -z "$DOMAIN" ]; then
    echo "❌ Usage: marzforwarder status <domain>"
    exit 1
  fi

  echo "🔍 Checking status for $DOMAIN"
  systemctl is-active --quiet nginx && echo "✅ Nginx is running." || echo "❌ Nginx is NOT running."
  test -f "$INSTALL_DIR/instances/$DOMAIN/forward.php" && echo "✅ Forward.php exists." || echo "❌ forward.php missing."
  test -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" && echo "✅ SSL certificate is present." || echo "❌ SSL certificate not found."
}

case "$1" in
  install) install ;;
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  status) status "$@" ;;
  "" | help | -h | --help)
    echo "🛠 Available marzforwarder commands:"
    echo ""
    echo "  install              🔧 Install and setup the tool"
    echo "  add                  ➕ Add a new forwarder"
    echo "  list                 📋 List all forwarders"
    echo "  remove <domain>      ❌ Remove a forwarder"
    echo "  uninstall            🧨 Remove everything"
    echo "  status <domain>      📡 Show status of a domain forwarder"
    echo ""
    echo "ℹ️ Example: marzforwarder add"
    ;;
  *)
    echo "❌ Unknown command: '$1'"
    echo "Type 'marzforwarder help' to see available commands."
    ;;
esac
