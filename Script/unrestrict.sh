#!/usr/bin/env bash
set -euo pipefail

# ensure root
if (( EUID != 0 )); then
  echo "[ERROR] root only"
  exit 1
fi

USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
IPSET="participant_whitelist"
CRON_FILE="/etc/cron.d/participant-whitelist"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-participant-mount.pkla"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"

echo "[*] Reverting participant restrictions"

# 1) remove OUTPUT hook
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true

# 2) flush & delete chain
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

# 3) destroy ipset
if ipset list "$IPSET" &>/dev/null; then
  ipset destroy "$IPSET"
fi

# 4) remove cron
rm -f "$CRON_FILE"

# 5) remove polkit rule
rm -f "$PKLA_FILE"
systemctl reload polkit.service &>/dev/null || echo "    ! polkit reload failed"

# 6) remove udev rule
rm -f "$UDEV_RULES"
udevadm control --reload-rules && udevadm trigger

echo "[*] Done, restrictions lifted."