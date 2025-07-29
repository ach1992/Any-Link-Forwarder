#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
NGINX_SITES_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
FORWARD_PHP_URL="https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php"

function install {
  echo "📦 Installing dependencies..."
  apt update
  apt install -y php php-cli php-curl curl certbot nginx unzip netcat

  echo "📁 Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  echo "🔧 Enabling NGINX to start on boot..."
  systemctl enable nginx
  systemctl restart nginx

  echo "✅ Installation complete."
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
  read -p "🔊 Enter public port (e.g., 443, 8443): " LISTEN_PORT

  LOCAL_PORT=$((10000 + RANDOM % 1000))
  echo "➕ Adding forwarder for $DOMAIN (local port: $LOCAL_PORT, public port: $LISTEN_PORT)"

  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "listen_port": $LISTEN_PORT
}
EOF

  curl -sSL "$FORWARD_PHP_URL" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  echo "🔐 Getting SSL certificate..."
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed."
    return 1
  }

  echo "⚙️  Starting local PHP server..."
  cat > "$INSTALL_DIR/instances/$DOMAIN/run.sh" <<EOF
#!/bin/bash
cd "$INSTALL_DIR/instances/$DOMAIN"
php -S 127.0.0.1:$LOCAL_PORT forward.php
EOF
  chmod +x "$INSTALL_DIR/instances/$DOMAIN/run.sh"

  # systemd service
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=$INSTALL_DIR/instances/$DOMAIN/run.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "marzforwarder-$DOMAIN"

  echo "🌐 Creating NGINX config..."
  NGINX_CONF="$NGINX_SITES_DIR/$DOMAIN"
  cat > "$NGINX_CONF" <<EOF
server {
    listen $LISTEN_PORT ssl;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:$LOCAL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

  ln -sf "$NGINX_CONF" "$NGINX_ENABLED_DIR/$DOMAIN"
  nginx -t && systemctl reload nginx

  echo "✅ Forwarder for $DOMAIN is active at https://$DOMAIN:$LISTEN_PORT/"
}

function list {
  echo "📋 Active forwarders:"
  ls "$INSTALL_DIR/instances"
}

function remove {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    echo "❌ Usage: marzforwarder remove <domain>"
    return 1
  fi

  echo "🧹 Removing forwarder $DOMAIN..."
  systemctl stop "marzforwarder-$DOMAIN"
  systemctl disable "marzforwarder-$DOMAIN"
  rm -f "/etc/systemd/system/marzforwarder-$DOMAIN.service"
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"

  rm -f "$NGINX_SITES_DIR/$DOMAIN"
  rm -f "$NGINX_ENABLED_DIR/$DOMAIN"
  systemctl reload nginx

  certbot delete --cert-name "$DOMAIN" --non-interactive

  echo "✅ Removed $DOMAIN."
}

function uninstall {
  echo "🧨 Uninstalling all forwarders..."
  for dir in "$INSTALL_DIR/instances/"*; do
    DOMAIN=$(basename "$dir")
    remove "$DOMAIN"
  done
  rm -rf "$INSTALL_DIR"
  echo "✅ Uninstalled all."
}

case "$1" in
  install) install ;;
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  *)
    echo "🛠 Usage: marzforwarder {install|add|list|remove|uninstall}"
    ;;
esac
