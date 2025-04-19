#!/bin/bash

echo "============================================"
echo "Starting Internet and USB Unrestriction for participant"
echo "============================================"

PARTICIPANT_USER="participant"
SQUID_CONF_FILE="/etc/squid/squid.conf"
SQUID_ALLOWED_DOMAINS_FILE="/etc/squid/allowed_domains.txt"
UDEV_RULE_FILE="/etc/udev/rules.d/99-block-usb-storage-participant.rules"

# 1. Restore original Squid config
if [ -f "${SQUID_CONF_FILE}.backup" ]; then
    echo "Restoring original Squid configuration..."
    sudo cp "${SQUID_CONF_FILE}.backup" "$SQUID_CONF_FILE"
    sudo systemctl restart squid
else
    echo "⚠️ No backup Squid config found. Skipping Squid restoration."
fi

# 2. Remove Squid allowed domains file
if [ -f "$SQUID_ALLOWED_DOMAINS_FILE" ]; then
    echo "Removing allowed domains list..."
    sudo rm -f "$SQUID_ALLOWED_DOMAINS_FILE"
fi

# 3. Remove participant from proxyusers group
echo "Removing participant from proxyusers group (if exists)..."
sudo gpasswd -d "$PARTICIPANT_USER" proxyusers || true

# 4. Reset iptables rules
echo "Flushing iptables rules..."
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo netfilter-persistent save

# 5. Remove USB block udev rule
if [ -f "$UDEV_RULE_FILE" ]; then
    echo "Removing USB storage block rule..."
    sudo rm -f "$UDEV_RULE_FILE"
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi

# 6. Optional: remove squid if you want
read -p "Do you want to completely remove Squid? (y/N): " REMOVE_SQUID
if [[ "$REMOVE_SQUID" =~ ^[Yy]$ ]]; then
    echo "Removing Squid..."
    sudo apt purge -y squid
    sudo apt autoremove -y
fi

echo "✅ Participant internet and USB restrictions have been lifted."
echo "🎯 System is back to unrestricted state."
