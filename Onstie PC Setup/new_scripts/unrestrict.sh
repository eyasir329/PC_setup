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

echo "Step 1: Check if user exists"
if ! id "$USER" &>/dev/null; then
  echo "[ERROR] User '$USER' does not exist."
  exit 1
fi
UID_USER=$(id -u "$USER")

echo "Step 2: Stop and disable systemd service"
systemctl stop "contest-restrict-$USER.service" 2>/dev/null || true
systemctl disable "contest-restrict-$USER.service" 2>/dev/null || true
rm -f "/etc/systemd/system/contest-restrict-$USER.service"
systemctl daemon-reload

echo "Step 3: Remove iptables OUTPUT hook"
CHAIN="CONTEST_${USER^^}_OUT"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN" 2>/dev/null || true

echo "Step 4: Clear NAT table rules for HTTP/HTTPS redirection"
# No NAT rules in new approach, but keeping for compatibility

echo "Step 5: Flush & delete iptables chain"
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

echo "Step 6: Clean up legacy configuration files"
# Remove legacy Squid configuration if it exists
if [ -f /etc/squid/squid.conf.backup ]; then
  echo "Restoring original Squid configuration..."
  mv /etc/squid/squid.conf.backup /etc/squid/squid.conf 2>/dev/null || true
  systemctl restart squid 2>/dev/null || true
fi

# Remove contest-specific Squid files
rm -f /etc/squid/whitelist.txt
rm -rf "/etc/squid/acls/restricted_uid_$USER.txt"

echo "Step 7: Remove environment variables"
# Remove proxy files (legacy)
rm -f "/etc/profile.d/contest-proxy-$USER.sh"
rm -f "/etc/profile.d/mdpc-proxy-$USER.sh"

# Clean up whitelist helper scripts
rm -f /tmp/resolve_whitelist.sh
rm -f /tmp/allowed_ips.txt
rm -f /usr/local/bin/update-contest-whitelist
rm -f /usr/local/bin/contest-dns-bypass

echo "Step 8: Restore disk & plugdev groups"
adduser "$USER" disk &>/dev/null || true
adduser "$USER" plugdev &>/dev/null || true

echo "Step 9: Remove Polkit rule"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-$USER-mount.pkla"
if [[ -f "$PKLA_FILE" ]]; then
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || true
fi

echo "Step 10: Remove udev USB block rule"
UDEV_RULES="/etc/udev/rules.d/99-usb-block-$USER.rules"
if [[ -f "$UDEV_RULES" ]]; then
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "============================================"
echo " Unrestrict for user '$USER' completed!"
echo "============================================"
