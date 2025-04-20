#!/usr/bin/env bash
set -euo pipefail

echo "============================================"
echo " Starting Participant Restrict: $(date)"
echo "============================================"

echo "Step 1: Auto‑install missing tools"
declare -A PKG_FOR_CMD=(
  [ipset]=ipset
  [iptables]=iptables
  [udevadm]=udev
  [dig]=dnsutils
)
missing=()
for cmd in "${!PKG_FOR_CMD[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("${PKG_FOR_CMD[$cmd]}")
  fi
done
if (( ${#missing[@]} )); then
  echo " → Installing: ${missing[*]}"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y "${missing[@]}"
fi

echo "Step 2: Check for root & PATH"
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi
export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "Step 3: Initialize variables"
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"
IPSET="participant_whitelist"
DOMAINS=(
  codeforces.com codechef.com vjudge.net atcoder.jp
  hackerrank.com hackerearth.com topcoder.com
  spoj.com lightoj.com uva.onlinejudge.org
  cses.fi bapsoj.com toph.co
)

echo "Step 4: Flush or create ipset"
if ipset list "$IPSET" &>/dev/null; then
  ipset flush "$IPSET"
else
  ipset create "$IPSET" hash:ip family inet hashsize 1024
fi

echo "Step 5: Resolve domains → ipset"
for d in "${DOMAINS[@]}"; do
  echo " → $d"
  mapfile -t ips < <(
    dig +short A "$d" 2>/dev/null \
      | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      | sort -u
  )
  if (( ${#ips[@]} == 0 )); then
    echo "   [!] no A records, skipping"
    continue
  fi
  for ip in "${ips[@]}"; do
    echo "   · $ip"
    ipset add "$IPSET" "$ip" \
      || echo "     [!] failed to add $ip"
  done
done

echo "Step 6: Rebuild iptables chain"
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi
iptables -t filter -N "$CHAIN"
iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN"

echo "Step 7: Allow DNS & HTTP/HTTPS"
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp -m multiport --dports 80,443 \
         -m set --match-set "$IPSET" dst -j ACCEPT
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A "$CHAIN" -j REJECT

echo "Step 8: Configure cron job"
CRON_FILE="/etc/cron.d/participant-whitelist"
CRON_LINE="*/15 * * * * root bash /media/shazid/Files/MDPC/Script/restrict.sh >/dev/null 2>&1"
if ! grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null; then
  cat <<EOF >"$CRON_FILE"
# Refresh whitelist every 15 minutes
$CRON_LINE
EOF
fi

echo "Step 9: Block mounts via Polkit"
PKLA_DIR="/etc/polkit-1/localauthority/50-local.d"
PKLA_FILE="$PKLA_DIR/disable-participant-mount.pkla"
mkdir -p "$PKLA_DIR"
cat <<EOF >"$PKLA_FILE"
[Disable all mounts for participant]
Identity=unix-user:$USER
Action=org.freedesktop.udisks2.filesystem-mount
Action=org.freedesktop.udisks2.filesystem-mount-system
Action=org.freedesktop.udisks2.filesystem-unmount
Action=org.freedesktop.udisks2.eject
Action=org.freedesktop.udisks2.power-off-drive
ResultAny=no
ResultActive=no
ResultInactive=no
EOF
systemctl reload polkit.service &>/dev/null || true

echo "Step 10: Block USB storage via udev"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"
cat <<EOF >"$UDEV_RULES"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="sd[b-z][0-9]*", MODE="0000", OWNER="root", GROUP="root"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="mmcblk[0-9]*", MODE="0000", OWNER="root", GROUP="root"
EOF
udevadm control --reload-rules && udevadm trigger

echo "============================================"
echo " Participant Restrict Completed!"
echo "============================================"