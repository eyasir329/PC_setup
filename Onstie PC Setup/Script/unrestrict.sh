#!/usr/bin/env bash
set -euo pipefail

echo "Step 0: Ensure script is executable"
SCRIPT_PATH=$(readlink -f "$0")
chmod +x "$SCRIPT_PATH"

echo "============================================"
echo " Starting Participant Unrestrict: $(date)"
echo "============================================"

echo "Step 1: Remove iptables OUTPUT hook"
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true

echo "Step 2: Flush & delete iptables chain"
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

echo "Step 3: Destroy ipset"
IPSET="participant_whitelist"
if ipset list "$IPSET" &>/dev/null; then
  ipset destroy "$IPSET"
fi

echo "Step 4: Remove cron job"
CRON_FILE="/etc/cron.d/participant-whitelist"
rm -f "$CRON_FILE"

echo "Step 5: Restore disk & plugdev groups"
adduser "$USER" disk    &>/dev/null || true
adduser "$USER" plugdev &>/dev/null || true

echo "Step 6: Remove Polkit rule"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-participant-mount.pkla"
if [[ -f "$PKLA_FILE" ]]; then
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || true
fi

echo "Step 7: Remove udev USB block rule"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"
if [[ -f "$UDEV_RULES" ]]; then
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "============================================"
echo " Participant Unrestrict Completed!"
echo "============================================"