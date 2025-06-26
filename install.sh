#!/bin/bash

echo "🔧 Marzban Forward Installer"

read -p "Enter your forwarder domain (e.g. forward.example.com): " DOMAIN

INSTALL_DIR="/var/www/marzban-forward"
CERTBOT_EMAIL="admin@$DOMAIN"

echo ""
echo "📦 Installing dependencies..."
apt update && apt install -y php php-curl certbot curl unzip

echo ""
echo "📁 Creating project directory..."
mkdir -p $INSTALL_DIR
cp forward.php $INSTALL_DIR/
cp config.json $INSTALL_DIR/

echo ""
echo "🔐 Generating SSL certificate for $DOMAIN..."
certbot certonly --standalone --preferred-challenges http -d $DOMAIN --agree-tos --email $CERTBOT_EMAIL --non-interactive

# Check cert success
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "❌ SSL certificate generation failed!"
  exit 1
fi

echo ""
echo "✅ SSL certificate created."

echo ""
echo "⏳ Setting up auto-renewal..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -

echo ""
echo "✅ Installation complete!"
echo "👉 Now run: bash start.sh $DOMAIN"
