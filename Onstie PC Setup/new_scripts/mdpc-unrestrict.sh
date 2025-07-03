#!/usr/bin/env bash
set -euo pipefail

# Use RESTRICT_USER if set, otherwise default to "participant"
USER="${RESTRICT_USER:-participant}"

echo "Step 0: Ensure script is executable"
SCRIPT_PATH=$(readlink -f "$0")
chmod +x "$SCRIPT_PATH"

echo "============================================"
echo " Starting Unrestrict for user '$USER': $(date)"
echo "============================================"

echo "Step 1: Stop and disable systemd service"
systemctl stop "mdpc-restrict-$USER.service" 2>/dev/null || true
systemctl disable "mdpc-restrict-$USER.service" 2>/dev/null || true
rm -f "/etc/systemd/system/mdpc-restrict-$USER.service"
systemctl daemon-reload

echo "Step 2: Remove iptables OUTPUT hook"
UID_USER=$(id -u "$USER")
CHAIN="MDPC_${USER^^}_OUT"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN" 2>/dev/null || true

echo "Step 3: Clear NAT table rules for HTTP/HTTPS redirection"
iptables -t nat -D OUTPUT -p tcp --dport 80 -m owner --uid-owner "$UID_USER" -j REDIRECT --to-port 3128 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner --uid-owner "$UID_USER" -j REDIRECT --to-port 3128 2>/dev/null || true

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
rm -f "/etc/profile.d/mdpc-proxy-$USER.sh"

echo "Step 7: Restore disk & plugdev groups"
adduser "$USER" disk &>/dev/null || true
adduser "$USER" plugdev &>/dev/null || true

echo "Step 8: Remove Polkit rule"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-$USER-mount.pkla"
if [[ -f "$PKLA_FILE" ]]; then
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || true
fi

echo "Step 9: Remove udev USB block rule"
UDEV_RULES="/etc/udev/rules.d/99-usb-block-$USER.rules"
if [[ -f "$UDEV_RULES" ]]; then
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "============================================"
echo " Unrestrict for user '$USER' completed!"
echo "============================================"
