#!/usr/bin/env bash
set -euo pipefail

# --- auto‑install missing tools ---
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
  echo "[*] Installing missing packages: ${missing[*]}"
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y "${missing[@]}"
fi
# --- end auto‑install ---

# ensure root
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi

# ensure sbin in PATH
export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "[*] Starting participant network & device lockdown..."

# parameters
DOMAINS=(
  codeforces.com
  codechef.com
  vjudge.net
  atcoder.jp
  hackerrank.com
  hackerearth.com
  topcoder.com
  spoj.com
  lightoj.com
  uva.onlinejudge.org
  cses.fi
  bapsoj.com
  toph.co
)
IPSET="participant_whitelist"
CHAIN="PARTICIPANT_OUT"
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")

# 1) create or flush ipset
if ipset list "$IPSET" &>/dev/null; then
  echo "[1] Flushing existing ipset $IPSET"
  ipset flush "$IPSET"
else
  echo "[1] Creating ipset $IPSET"
  ipset create "$IPSET" hash:ip family inet hashsize 1024
fi

# 2) resolve domains → add to ipset
echo "[2] Resolving and adding domain IPs to $IPSET"
for d in "${DOMAINS[@]}"; do
  echo "   → $d"
  mapfile -t ips < <(
    dig +short A "$d" 2>/dev/null \
      | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
      | sort -u
  )
  if (( ${#ips[@]} == 0 )); then
    echo "      [!] no A records found, skipping"
    continue
  fi
  for ip in "${ips[@]}"; do
    echo "      · $ip"
    ipset add "$IPSET" "$ip" || echo "      [!] Failed to add $ip"
  done
done

# 3) rebuild iptables chain
echo "[3] Rebuilding iptables chain $CHAIN"
iptables -t filter -F "$CHAIN" 2>/dev/null || true
iptables -t filter -X "$CHAIN" 2>/dev/null || true
iptables -t filter -N "$CHAIN"

# hook chain to OUTPUT for participant
if ! iptables -t filter -C OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" &>/dev/null; then
  iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN"
fi

# 4) allow DNS
echo "[4] Allowing DNS lookups"
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# 5) allow HTTP/HTTPS only to whitelisted IPs
echo "[5] Allowing HTTP/HTTPS to whitelisted IPs"
iptables -A "$CHAIN" -p tcp -m multiport --dports 80,443 \
         -m set --match-set "$IPSET" dst -j ACCEPT

# 6) allow established
echo "[6] Allowing ESTABLISHED,RELATED traffic"
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 7) drop everything else
echo "[7] Dropping all other traffic for $USER"
iptables -A "$CHAIN" -j REJECT

# 8) install/update cron job
CRON_FILE="/etc/cron.d/participant-whitelist"
CRON_LINE="*/15 * * * * root bash /media/shazid/Files/MDPC/Script/restrict.sh >/dev/null 2>&1"
echo "[8] Ensuring cron job in $CRON_FILE"
if ! grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null; then
  cat <<EOF > "$CRON_FILE"
# Refresh whitelist every 15 minutes
$CRON_LINE
EOF
  echo "    · Cron job written."
else
  echo "    · Cron job already present."
fi

# 9) block mount attempts via Polkit
PKLA_DIR="/etc/polkit-1/localauthority/50-local.d"
PKLA_FILE="$PKLA_DIR/disable-participant-mount.pkla"
echo "[9] Ensuring Polkit block in $PKLA_FILE"
mkdir -p "$PKLA_DIR"
cat <<EOF > "$PKLA_FILE"
[Block all mounts for participant]
Identity=unix-user:$USER
Action=org.freedesktop.udisks2.*
ResultAny=no
ResultActive=no
ResultInactive=no
EOF
systemctl reload polkit.service &>/dev/null || echo "    ! Could not reload polkit—reboot to apply."

# 10) block USB storage via udev
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"
echo "[10] Writing udev rule to deny USB storage"
cat <<EOF > "$UDEV_RULES"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", DEVTYPE=="disk", MODE="0000"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", DEVTYPE=="partition", MODE="0000"
EOF
udevadm control --reload-rules && udevadm trigger

echo "[*] Done."