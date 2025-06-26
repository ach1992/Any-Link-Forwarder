#!/bin/bash

CONFIG_FILE="config.json"

echo "🔧 Marzban Forward Configuration"
echo ""

read -p "Enter target Marzban domain (e.g. panel.example.com): " DOMAIN
read -p "Enter target Marzban port (default: 8443): " PORT

# If port empty, use 8443
if [ -z "$PORT" ]; then
  PORT=8443
fi

# Save to config.json
cat > "$CONFIG_FILE" <<EOF
{
  "target_domain": "$DOMAIN",
  "target_port": $PORT
}
EOF

echo ""
echo "✅ Config saved to $CONFIG_FILE"
cat "$CONFIG_FILE"
