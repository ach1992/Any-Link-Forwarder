#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
RENEW_SERVICE_PATH="/etc/systemd/system/marzforwarder-renew.service"
RENEW_TIMER_PATH="/etc/systemd/system/marzforwarder-renew.timer"

function cleanup {
  echo "🧹 Cleaning up previous installations..."
  sudo rm -rf "$INSTALL_DIR"
  sudo rm -f "$BIN_PATH"
  sudo rm -f "$RENEW_SERVICE_PATH"
  sudo rm -f "$RENEW_TIMER_PATH"
  sudo systemctl daemon-reload
  sudo systemctl reset-failed
  echo "✅ Cleanup completed."
}

function install {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y nginx php php-fpm php-curl curl unzip certbot python3-certbot-nginx

  echo "📁 Creating base directory..."
  sudo mkdir -p "$INSTALL_DIR/instances"

  echo "⬇️ Downloading necessary files..."
  # Create a temporary directory for downloaded files
  TMP_DIR="$(mktemp -d)"
  curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php -o "$TMP_DIR/forward.php"
  curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.service -o "$TMP_DIR/marzforwarder-renew.service"
  curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder-renew.timer -o "$TMP_DIR/marzforwarder-renew.timer"

  echo "🔗 Setting up CLI shortcut..."
  # When executed via curl | bash, the script is read from stdin. We need to download it again.
  curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/marzforwarder.sh -o "$BIN_PATH"
  sudo chmod +x "$BIN_PATH"

  echo "📅 Setting up automatic SSL renewal..."
  sudo cp "$TMP_DIR/marzforwarder-renew.service" "$RENEW_SERVICE_PATH"
  sudo cp "$TMP_DIR/marzforwarder-renew.timer" "$RENEW_TIMER_PATH"
  sudo systemctl daemon-reload
  sudo systemctl enable --now marzforwarder-renew.timer

  echo "🗑 Cleaning up temporary files..."
  rm -rf "$TMP_DIR"

  echo "✅ Installation completed."
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
  sudo mkdir -p "$INSTALL_DIR/instances/$DOMAIN"

  sudo cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "listen_port": $LISTEN_PORT
}
EOF

  # Download forward.php directly to the instance directory
  curl -sSL https://raw.githubusercontent.com/ach1992/Marzban-Sub-Forwarder/main/forward.php -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  # Create Nginx configuration
  sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen $LISTEN_PORT ssl;
    listen [::]:$LISTEN_PORT ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    root $INSTALL_DIR/instances/$DOMAIN;
    index forward.php;

    location / {
        try_files \$uri \$uri/ /forward.php\$is_args\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

  sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

  echo "🔐 Obtaining SSL certificate for $DOMAIN..."
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN. Please check your DNS settings and try again."
    sudo rm /etc/nginx/sites-enabled/$DOMAIN
    sudo rm /etc/nginx/sites-available/$DOMAIN
    return 1
  }

  sudo nginx -t && sudo systemctl reload nginx

  echo "✅ Forwarder created and running."
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
  sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
  sudo rm -f "/etc/nginx/sites-available/$DOMAIN"
  sudo nginx -t && sudo systemctl reload nginx
  sudo rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  sudo certbot delete --cert-name "$DOMAIN" --non-interactive

  echo "✅ Removed $DOMAIN."
}

function uninstall {
  echo "🧨 Uninstalling all Marzban forwarders..."

  if [ -d "$INSTALL_DIR/instances" ]; then
    for dir in "$INSTALL_DIR/instances/"*; do
      DOMAIN=$(basename "$dir")
      echo "🧹 Removing forwarder: $DOMAIN"
      sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
      sudo rm -f "/etc/nginx/sites-available/$DOMAIN"
      sudo certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null
    done
  fi
  sudo nginx -t && sudo systemctl reload nginx

  echo "🗑 Removing install directory..."
  sudo rm -rf "$INSTALL_DIR"

  echo "🗑 Removing CLI command..."
  sudo rm -f "$BIN_PATH"

  echo "🧹 Removing auto-renew services..."
  sudo rm -f "$RENEW_SERVICE_PATH"
  sudo rm -f "$RENEW_TIMER_PATH"
  sudo systemctl daemon-reload

  echo "✅ Fully uninstalled!"
}

function status {
  echo "📊 Marzban Forwarder Status:"
  echo ""
  echo "Nginx Status:"
  sudo systemctl status nginx | grep Active
  echo ""
  echo "PHP-FPM Status:"
  sudo systemctl status php*-fpm | grep Active
  echo ""
  echo "Certbot Renewal Timer Status:"
  sudo systemctl status marzforwarder-renew.timer | grep Active
  echo ""
  echo "Active Forwarders:"
  if [ -d "$INSTALL_DIR/instances" ]; then
    for dir in "$INSTALL_DIR/instances/"*; do
      DOMAIN=$(basename "$dir")
      echo "  - $DOMAIN"
      # Check if Nginx config exists and is enabled for this domain
      if [ -f "/etc/nginx/sites-enabled/$DOMAIN" ]; then
        echo "    Status: Enabled (Nginx)"
      else
        echo "    Status: Disabled or Not Configured (Nginx)"
      fi
    done
  else
    echo "  No forwarders configured."
  fi
}

function renew-cert {
  echo "🔐 Running certbot renew..."
  sudo certbot renew
  sudo nginx -t && sudo systemctl reload nginx
  echo "✅ SSL renewal completed."
}

case "$1" in
  cleanup) cleanup ;;
  install) install ;;
  add) add ;;
  list) list ;;
  remove) remove "$2" ;;
  uninstall) uninstall ;;
  status) status ;;
  renew-cert) renew-cert ;;
  "" | help | -h | --help)
    echo "🛠 Available marzforwarder commands:"
    echo ""
    echo "  cleanup             🧹 Clean up previous installations"
    echo "  install             🔧 Install all dependencies and setup the tool"
    echo "  add                 ➕ Add a new domain forwarder"
    echo "  list                📋 List all configured forwarders"
    echo "  remove <domain>     ❌ Remove a forwarder"
    echo "  uninstall           🧨 Fully uninstall marzforwarder and clean all files"
    echo "  status              📊 Show status of Marzban Forwarder services"
    echo "  renew-cert          🔁 Manually renew SSL certificates for all domains"
    echo ""
    echo "ℹ️  Example: marzforwarder add"
    ;;
  *)
    echo "❌ Unknown command: \'$1\'"
    echo "Type \'marzforwarder help\' to see available commands."
    ;;
esac
