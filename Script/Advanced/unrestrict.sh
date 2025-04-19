#!/bin/bash

echo "============================================"
echo "Removing Internet and USB storage restrictions for participant"
echo "============================================"

PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u "$PARTICIPANT_USER")

# -------------------------------
# Restore full Internet Access
# -------------------------------

echo "Removing iptables rules for participant..."
# Flush all rules (safe since we're customizing only OUTPUT rules)
sudo iptables -F OUTPUT

# Save clean iptables
sudo sh -c "iptables-save > /etc/iptables.rules"

# Disable iptables restore via rc.local (if present)
if grep -q "iptables-restore < /etc/iptables.rules" /etc/rc.local 2>/dev/null; then
    echo "Disabling rc.local iptables restoration..."
    sudo sed -i '/iptables-restore < \/etc\/iptables.rules/d' /etc/rc.local
fi

# -------------------------------
# Remove dnsmasq DNS Filtering
# -------------------------------

echo "Removing dnsmasq DNS filtering..."
sudo systemctl stop dnsmasq
sudo systemctl disable dnsmasq

# Restore systemd-resolved
echo "Restoring systemd-resolved..."
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved

# Remove dnsmasq config changes
sudo sed -i '/listen-address=127.0.0.1/d' /etc/dnsmasq.conf
sudo sed -i '/bind-interfaces/d' /etc/dnsmasq.conf
sudo rm -f /etc/dnsmasq.d/allowed_domains.conf

# -------------------------------
# Remove USB Storage Restrictions
# -------------------------------

UDEV_RULE_FILE="/etc/udev/rules.d/99-block-usb-storage-participant.rules"
if [ -f "$UDEV_RULE_FILE" ]; then
    echo "Removing USB block udev rule..."
    sudo rm "$UDEV_RULE_FILE"
    sudo udevadm control --reload-rules
fi

echo "============================================"
echo "✅ All restrictions for participant have been removed."
echo "============================================"
