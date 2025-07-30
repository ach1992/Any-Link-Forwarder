#!/bin/bash

INSTALL_DIR="/var/www/any-forward"
BIN_PATH="/usr/local/bin/anyforwarder"
RENEW_SERVICE_PATH="/etc/systemd/system/anyforwarder-renew.service"
RENEW_TIMER_PATH="/etc/systemd/system/anyforwarder-renew.timer"

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

# Function to validate yes/no input
function validate_yes_no {
  local input
  while true; do
    read -p "$1" -n 1 -r input
    echo
    if [[ $input =~ ^[YyNn]$ ]]; then
      REPLY=$input
      return 0
    else
      echo "Invalid input. Please enter 'y' or 'n'."
    fi
  done
}

# Function to validate domain input
function validate_domain {
  local input
  while true; do
    read -p "$1" input
    if [[ -z "$input" ]]; then
      echo "Domain cannot be empty. Please try again."
    elif [[ ! "$input" =~ \. ]]; then
      echo "Invalid domain format. Please include at least one dot (e.g., sub.domain.com)."
    else
      REPLY=$input
      return 0
    fi
  done
}

# Function to validate port input
function validate_port {
  local input
  while true; do
    read -p "$1" input
    if [[ -z "$input" ]]; then
      echo "Port cannot be empty. Please try again."
    elif ! [[ "$input" =~ ^[0-9]+$ ]]; then
      echo "Invalid port. Please enter a number."
    elif (( input < 1 || input > 65535 )); then
      echo "Port must be between 1 and 65535. Please try again."
    else
      REPLY=$input
      return 0
    fi
  done
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
  curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/forward.php -o "$TMP_DIR/forward.php"
  curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/anyforwarder-renew.service -o "$TMP_DIR/anyforwarder-renew.service"
  curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/anyforwarder-renew.timer -o "$TMP_DIR/anyforwarder-renew.timer"

  echo "🔗 Setting up CLI shortcut..."
  # When executed via curl | bash, the script is read from stdin. We need to download it again.
  curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/anyforwarder.sh -o "$BIN_PATH"
  sudo chmod +x "$BIN_PATH"

  echo "📅 Setting up automatic SSL renewal..."
  sudo cp "$TMP_DIR/anyforwarder-renew.service" "$RENEW_SERVICE_PATH"
  sudo cp "$TMP_DIR/anyforwarder-renew.timer" "$RENEW_TIMER_PATH"
  sudo systemctl daemon-reload
  sudo systemctl enable --now anyforwarder-renew.timer

  echo "🗑 Cleaning up temporary files..."
  rm -rf "$TMP_DIR"

  echo "✅ Installation completed."

  validate_yes_no "Would you like to add your first forwarder now? (y/n): "
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    add
  fi
}

function add {
  if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This command requires root privileges. Please run with sudo: sudo anyforwarder add"
    return 1
  fi

  validate_domain "🌐 Enter domain to listen (e.g., forward.domain.com): "
  DOMAIN=$REPLY

  if [ -d "$INSTALL_DIR/instances/$DOMAIN" ]; then
    echo "⚠️ Forwarder for $DOMAIN already exists."
    return 1
  fi

  validate_port "🔊 Enter local listen port (e.g., 443, 8443, 2096...): "
  LISTEN_PORT=$REPLY

  validate_domain "📍 Enter target panel domain (e.g., panel.domain.com): "
  PANEL=$REPLY

  validate_port "🚪 Enter target panel port (e.g., 443, 8443, 2096...): "
  PORT=$REPLY

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
  curl -sSL https://raw.githubusercontent.com/ach1992/Any-Link-Forwarder/main/forward.php -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"

  # Create Nginx configuration for webroot challenge
  sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

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

    location ~ /\.well-known/acme-challenge/ {
        allow all;
        root /var/www/html;
    }
}
EOF

  sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

  # Test Nginx configuration before attempting SSL
  if ! sudo nginx -t; then
    echo "❌ Nginx configuration test failed for $DOMAIN. Please check your inputs and Nginx setup."
    sudo rm /etc/nginx/sites-enabled/$DOMAIN
    sudo rm /etc/nginx/sites-available/$DOMAIN
    return 1
  fi
  sudo systemctl reload nginx

  echo "🔐 Obtaining SSL certificate for $DOMAIN..."
  # Use webroot plugin for Certbot
  sudo certbot certonly --webroot -w /var/www/html -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || {
    echo "❌ SSL generation failed for $DOMAIN. Please check your DNS settings and try again."
    sudo rm /etc/nginx/sites-enabled/$DOMAIN
    sudo rm /etc/nginx/sites-available/$DOMAIN
    return 1
  }

  # Update Nginx configuration with SSL paths after successful certificate generation
  sudo cat > "/etc/nginx/sites-available/$DOMAIN" <<EOF
server {
    listen $LISTEN_PORT ssl;
    listen [::]:$LISTEN_PORT ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;

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
    echo "❌ Usage: anyforwarder remove <domain>"
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
  sudo systemctl status anyforwarder-renew.timer | grep Active
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
    echo "🛠 Available anyforwarder commands:"
    echo ""
    echo "  cleanup             🧹 Clean up previous installations"
    echo "  install             🔧 Install all dependencies and setup the tool"
    echo "  add                 ➕ Add a new domain forwarder"
    echo "  list                📋 List all configured forwarders"
    echo "  remove <domain>     ❌ Remove a forwarder"
    echo "  uninstall           🧨 Fully uninstall anyforwarder and clean all files"
    echo "  status              📊 Show status of Marzban Forwarder services"
    echo "  renew-cert          🔁 Manually renew SSL certificates for all domains"
    echo ""
    echo "ℹ️  Example: anyforwarder add"
    ;;
  *)
    echo "❌ Unknown command: \'$1\'"
    echo "Type \'anyforwarder help\' to see available commands."
    ;;
esac
