#!/bin/bash

INSTALL_DIR="/var/www/marzban-forward"
BIN_PATH="/usr/local/bin/marzforwarder"
GITHUB_BASE_URL="https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_error {
  echo -e "${RED}❌ $1${NC}"
}

function print_success {
  echo -e "${GREEN}✅ $1${NC}"
}

function print_info {
  echo -e "${YELLOW}🔸 $1${NC}"
}

function install {
  print_info "Installing dependencies..."
  apt update && apt install -y php php-curl socat curl certbot unzip || {
    print_error "Failed to install required packages."
    exit 1
  }

  print_info "Creating base directory..."
  mkdir -p "$INSTALL_DIR/instances"

  print_info "Setting up CLI shortcut..."
  cp "$0" "$BIN_PATH" && chmod +x "$BIN_PATH"

  print_info "Setting up automatic SSL renewal..."
  curl -sSL "$GITHUB_BASE_URL/marzforwarder-renew.service" -o /etc/systemd/system/marzforwarder-renew.service
  curl -sSL "$GITHUB_BASE_URL/marzforwarder-renew.timer" -o /etc/systemd/system/marzforwarder-renew.timer

  if [ ! -f /etc/systemd/system/marzforwarder-renew.service ] || [ ! -f /etc/systemd/system/marzforwarder-renew.timer ]; then
    print_error "Failed to download systemd timer files from GitHub."
    exit 1
  fi

  systemctl daemon-reload
  systemctl enable --now marzforwarder-renew.timer

  echo ""
  print_info "Let's configure your first forwarder:"
  echo -n "➤ Enter your domain (e.g. mydomain.com): "
  read DOMAIN
  echo -n "➤ Enter your panel address (e.g. panel.domain.com): "
  read PANEL
  echo -n "➤ Enter your panel port (e.g. 443): "
  read PORT

  if [ -z "$DOMAIN" ] || [ -z "$PANEL" ] || [ -z "$PORT" ]; then
    print_error "Invalid input. Installation aborted."
    exit 1
  fi

  print_info "Setting up forwarder for $DOMAIN → $PANEL:$PORT ..."
  add "$DOMAIN" "$PANEL" "$PORT"
}

function add {
  DOMAIN=$1
  PANEL=$2
  PORT=$3

  if [ -z "$DOMAIN" ] || [ -z "$PANEL" ] || [ -z "$PORT" ]; then
    print_error "Usage: marzforwarder add <domain> <panel> <port>"
    exit 1
  fi

  print_info "Adding new forwarder for $DOMAIN → $PANEL:$PORT"

  mkdir -p "$INSTALL_DIR/instances/$DOMAIN"
  PHP_PORT=$(shuf -i 10000-11000 -n 1)

  cat > "$INSTALL_DIR/instances/$DOMAIN/config.json" <<EOF
{
  "target_domain": "$PANEL",
  "target_port": $PORT,
  "local_php_port": $PHP_PORT
}
EOF

  curl -sSL "$GITHUB_BASE_URL/forward.php" -o "$INSTALL_DIR/instances/$DOMAIN/forward.php"
  if [ ! -f "$INSTALL_DIR/instances/$DOMAIN/forward.php" ]; then
    print_error "Failed to download forward.php from GitHub."
    exit 1
  fi

  # Check if port 80 is available
  if lsof -i :80 | grep LISTEN >/dev/null; then
    print_error "Port 80 is in use. Please stop Apache or any web server before proceeding."
    exit 1
  fi

  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
  if [ $? -ne 0 ]; then
    print_error "SSL generation failed for $DOMAIN. Make sure the domain points to this server and port 80 is free."
    exit 1
  fi

  create_service "$DOMAIN" "$PHP_PORT"
  systemctl enable --now marzforwarder-$DOMAIN

  print_success "Forwarder for $DOMAIN is created and running."
}

function create_service {
  DOMAIN=$1
  PHP_PORT=$2
  SERVICE_FILE="/etc/systemd/system/marzforwarder-$DOMAIN.service"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Marzban Sub Forwarder for $DOMAIN
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8443,reuseaddr,fork TCP:127.0.0.1:$PHP_PORT
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  cat > "$INSTALL_DIR/instances/$DOMAIN/run.sh" <<EOF
#!/bin/bash
cd "$INSTALL_DIR/instances/$DOMAIN"
php -S 127.0.0.1:$PHP_PORT forward.php
EOF

  chmod +x "$INSTALL_DIR/instances/$DOMAIN/run.sh"
}

function list {
  print_info "Active forwarders:"
  ls "$INSTALL_DIR/instances"
}

function remove {
  DOMAIN=$1
  if [ -z "$DOMAIN" ]; then
    print_error "Usage: marzforwarder remove <domain>"
    exit 1
  fi

  print_info "Removing forwarder $DOMAIN..."
  systemctl stop marzforwarder-$DOMAIN
  systemctl disable marzforwarder-$DOMAIN
  rm -f /etc/systemd/system/marzforwarder-$DOMAIN.service
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR/instances/$DOMAIN"
  certbot delete --cert-name "$DOMAIN" --non-interactive

  print_success "$DOMAIN has been removed."
}

function instance-start {
  DOMAIN=$1
  systemctl start marzforwarder-$DOMAIN
}

function uninstall {
  print_info "Uninstalling all Marzban forwarders..."

  for dir in "$INSTALL_DIR/instances/"*; do
    DOMAIN=$(basename "$dir")
    print_info "Removing forwarder: $DOMAIN"
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

  print_success "Uninstall complete."
}

function renew-cert {
  print_info "Stopping all forwarders before renewal..."
  for svc in $(systemctl list-units --type=service --no-legend | grep 'marzforwarder-.*\.service' | awk '{print $1}'); do
    systemctl stop "$svc"
  done

  print_info "Running certbot renew..."
  certbot renew

  print_info "Restarting forwarders..."
  for svc in $(systemctl list-units --type=service --no-legend | grep 'marzforwarder-.*\.service' | awk '{print $1}'); do
    systemctl start "$svc"
  done

  print_success "SSL renewal completed."
}

case "$1" in
  install) install ;;
  add) add "$2" "$3" "$4" ;;
  list) list ;;
  remove) remove "$2" ;;
  instance-start) instance-start "$2" ;;
  uninstall) uninstall ;;
  renew-cert) renew-cert ;;
  *) print_error "Unknown command. Use: install | add | list | remove | instance-start | uninstall | renew-cert" ;;
esac
