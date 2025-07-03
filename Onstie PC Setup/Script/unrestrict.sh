#!/usr/bin/env bash
set -euo pipefail

echo "Step 0: Ensure script is executable"
SCRIPT_PATH=$(readlink -f "$0")
chmod +x "$SCRIPT_PATH"

echo "============================================"
echo " Starting Participant Unrestrict: $(date)"
echo "============================================"

echo "Step 1: Stop and disable systemd service"
systemctl stop participant-restrict.service 2>/dev/null || true
systemctl disable participant-restrict.service 2>/dev/null || true
rm -f /etc/systemd/system/participant-restrict.service
systemctl daemon-reload

echo "Step 2: Remove iptables OUTPUT hook"
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true

echo "Step 3: Clear NAT table rules for HTTP/HTTPS redirection"
iptables -t nat -D OUTPUT -p tcp --dport 80 -m owner --uid-owner "$UID_PARTICIPANT" -j REDIRECT --to-port 3128 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner --uid-owner "$UID_PARTICIPANT" -j REDIRECT --to-port 3128 2>/dev/null || true

echo "Step 4: Flush & delete iptables chain"
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

echo "Step 5: Restore Squid configuration"
if [ -f /etc/squid/squid.conf.backup ]; then
  mv /etc/squid/squid.conf.backup /etc/squid/squid.conf
  systemctl restart squid
fi

echo "Step 6: Remove environment variables"
rm -f /etc/profile.d/participant-proxy.sh

echo "Step 7: Restore disk & plugdev groups"
adduser "$USER" disk &>/dev/null || true
adduser "$USER" plugdev &>/dev/null || true

echo "Step 8: Remove Polkit rule"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-participant-mount.pkla"
if [[ -f "$PKLA_FILE" ]]; then
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || true
fi

echo "Step 9: Remove udev USB block rule"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"
if [[ -f "$UDEV_RULES" ]]; then
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "Step 10: Remove whitelist management tool"
rm -f /usr/local/bin/add-contest-domain

echo "============================================"
echo " Participant Unrestrict Completed!"
echo " All restrictions have been removed."
echo "============================================"