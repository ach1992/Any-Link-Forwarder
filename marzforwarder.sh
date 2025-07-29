#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
RENEW_SERVICE_PATH="/etc/systemd/system/marzforwarder-renew.service"
RENEW_TIMER_PATH="/etc/systemd/system/marzforwarder-renew.timer"

SCRIPT_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh"
RENEW_SERVICE_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.service"
RENEW_TIMER_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.timer"

function install {
  echo "📦 Installing dependencies..."
  apt update && apt install -y nginx curl certbot python3-certbot-nginx unzip

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

  echo "➕ Adding new forwarder for $DOMAIN -> $PANEL:$PORT on port $LISTEN_PORT"
  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "listen_port": $LISTEN_PORT
}
EOF

  echo "📝 Creating temporary Nginx config to pass certbot challenge..."
  TEMP_CONF="/etc/nginx/sites-available/$DOMAIN-temp"
  ln -s "$TEMP_CONF" "/etc/nginx/sites-enabled/$DOMAIN-temp"

  cat > "$TEMP_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF

  mkdir -p /var/www/html
  nginx -t && systemctl reload nginx

  echo "🔐 Obtaining SSL certificate with certbot..."
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN"
    rm -f "/etc/nginx/sites-enabled/$DOMAIN-temp" "$TEMP_CONF"
    return 1
  }

  echo "📝 Creating final Nginx configuration..."
  NGINX_CONF_PATH="/etc/nginx/sites-available/$DOMAIN"
  NGINX_ENABLED_PATH="/etc/nginx/sites-enabled/$DOMAIN"

  cat > "$NGINX_CONF_PATH" <<EOF
server {
    listen $LISTEN_PORT ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass https://$PANEL:$PORT;
        proxy_ssl_verify off;
        proxy_set_header Host $PANEL;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

  ln -s "$NGINX_CONF_PATH" "$NGINX_ENABLED_PATH"
  rm -f "/etc/nginx/sites-enabled/$DOMAIN-temp" "$TEMP_CONF"
  nginx -t && systemctl reload nginx

  echo "✅ Forwarder created and running on https://$DOMAIN:$LISTEN_PORT"
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
  rm -f "/etc/nginx/sites-available/$DOMAIN"
  rm -f "/etc/nginx/sites-enabled/$DOMAIN"
  nginx -t && systemctl reload nginx

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
      rm -f "/etc/nginx/sites-available/$DOMAIN"
      rm -f "/etc/nginx/sites-enabled/$DOMAIN"
      certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
    done
  fi

  systemctl reload nginx

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
  echo "🔐 Running certbot renew..."
  certbot renew

  echo "🔁 Reloading Nginx..."
  systemctl reload nginx
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
