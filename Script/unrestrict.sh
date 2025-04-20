#!/usr/bin/env bash
set -euo pipefail

# ensure root
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi

echo "[*] Reverting participant restrictions..."

USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
IPSET="participant_whitelist"
CRON_FILE="/etc/cron.d/participant-whitelist"
PKLA_FILE="/etc/polkit-1/localauthority/50-local.d/disable-participant-mount.pkla"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"

# 1) remove iptables hook
if iptables -t filter -C OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" &>/dev/null; then
  echo "[1] Removing OUTPUT hook for UID $USER"
  iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN"
fi

# 2) flush & delete the chain
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  echo "[2] Flushing and deleting chain $CHAIN"
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

# 3) destroy ipset
if ipset list "$IPSET" &>/dev/null; then
  echo "[3] Destroying ipset $IPSET"
  ipset destroy "$IPSET"
fi

# 4) remove cron job
if [[ -f "$CRON_FILE" ]]; then
  echo "[4] Removing cron file $CRON_FILE"
  rm -f "$CRON_FILE"
fi

# 5) remove polkit rule
if [[ -f "$PKLA_FILE" ]]; then
  echo "[5] Removing polkit rule $PKLA_FILE"
  rm -f "$PKLA_FILE"
  systemctl reload polkit.service &>/dev/null || echo "[!] Could not reload polkit, please reboot."
fi

# 6) remove udev rule
if [[ -f "$UDEV_RULES" ]]; then
  echo "[6] Removing udev rule $UDEV_RULES"
  rm -f "$UDEV_RULES"
  udevadm control --reload-rules && udevadm trigger
fi

echo "[*] Participant restrictions lifted."