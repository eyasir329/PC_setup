#!/usr/bin/env bash
set -euo pipefail

# Use RESTRICT_USER if set, otherwise default to "participant"
USER="${RESTRICT_USER:-participant}"

echo "Step 0: Ensure script is executable"
SCRIPT_PATH=$(readlink -f "$0")
chmod +x "$SCRIPT_PATH"

echo "============================================"
echo " Starting Restriction for user '$USER': $(date)"
echo "============================================"

echo "Step 1: Auto‑install missing tools"
declare -A PKG_FOR_CMD=(
  [ipset]=ipset
  [iptables]=iptables
  [udevadm]=udev
  [dig]=dnsutils
  [squid]=squid
  [htpasswd]=apache2-utils
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

echo "Step 2: Check for root & PATH"
if (( EUID != 0 )); then
  echo "[ERROR] Must be run as root."
  exit 1
fi
export PATH=$PATH:/usr/local/sbin:/usr/sbin:/sbin

echo "Step 3: Initialize variables"
# Get UID of specified user
if ! id "$USER" &>/dev/null; then
  echo "[ERROR] User '$USER' does not exist."
  exit 1
fi
UID_USER=$(id -u "$USER")
CHAIN="MDPC_${USER^^}_OUT"  # Uppercase username for chain name

echo "Step 4: Configure Squid proxy for domain-based filtering"
# Back up original config if it exists and this is first run
if [ ! -f /etc/squid/squid.conf.backup ]; then
  cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
fi

# Create whitelist file with all permitted domains
cat > /etc/squid/whitelist.txt << EOF
# Contest sites - main domains
.codeforces.com
.codechef.com
.vjudge.net
.atcoder.jp
.hackerrank.com
.hackerearth.com
.topcoder.com
.spoj.com
.lightoj.com
.onlinejudge.org
.uva.onlinejudge.org
.cses.fi
.bapsoj.com
.toph.co

# Common CDNs and resources
.cloudflare.com
.cloudfront.net
.jsdelivr.net
.googleapis.com
.gstatic.com
.jquery.com
.mathjax.org
.gravatar.com
.fastly.net
.akamaized.net
.fontawesome.com
.googlesyndication.com
.google-analytics.com
.doubleclick.net
.typekit.net
.ajax.googleapis.com
.maxcdn.com
.bootstrapcdn.com
.unpkg.com
.polyfill.io
.recaptcha.net
.google.com
EOF

# Create Squid config
cat > /etc/squid/squid.conf << EOF
# Basic settings
http_port 3128
visible_hostname contest-proxy

# Access control definitions
acl localnet src 127.0.0.1/8
acl SSL_ports port 443
acl Safe_ports port 80 443

# Define restricted user by UID
acl restricted_user src all ident_regex -i ^$USER$
external_acl_type user_check %SRC /bin/sh -c 'id -u $USER | grep -q "$UID_USER"'

# Define allowed domains
acl whitelist dstdomain "/etc/squid/whitelist.txt"

# Security rules - block unsafe ports
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Allow localhost admin access
http_access allow localhost

# Allow restricted user only to whitelisted sites 
# (using IP matching since transparent proxy won't have auth)
acl restricted_uid src owner UID_OF_$UID_USER
http_access allow restricted_uid whitelist
http_access deny restricted_uid

# Allow everyone else full access
http_access allow all

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# Disable caching for simplicity
cache deny all
EOF

# Create special ACL file for user identification
mkdir -p /etc/squid/acls/
echo "$UID_USER" > "/etc/squid/acls/restricted_uid_$USER.txt"

# Restart Squid to apply changes
echo "Restarting Squid service..."
systemctl restart squid
systemctl enable squid

echo "Step 5: Configure transparent proxy with iptables"
# Clear any existing chain
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN" 2>/dev/null || true
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi
iptables -t filter -N "$CHAIN"
iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN"

# Allow DNS queries
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# Allow access to Squid proxy port
iptables -A "$CHAIN" -p tcp --dport 3128 -j ACCEPT

# Allow established connections
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Redirect all HTTP/HTTPS traffic to Squid
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner "$UID_USER" -j REDIRECT --to-port 3128
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$UID_USER" -j REDIRECT --to-port 3128

# Block everything else
iptables -A "$CHAIN" -j REJECT

# Create environment variables for the user
cat > "/etc/profile.d/mdpc-proxy-$USER.sh" << EOF
if [ "\$(id -un)" = "$USER" ]; then
    export http_proxy=http://localhost:3128
    export https_proxy=http://localhost:3128
    export no_proxy=localhost,127.0.0.1
fi
EOF
chmod +x "/etc/profile.d/mdpc-proxy-$USER.sh"

echo "Step 6: Create systemd service to run at boot"
# Create a systemd service file with user-specific name
cat > "/etc/systemd/system/mdpc-restrict-$USER.service" << EOF
[Unit]
Description=MDPC Internet Restriction Service for user $USER
After=network.target squid.service
Wants=squid.service

[Service]
Type=oneshot
Environment="RESTRICT_USER=$USER"
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable "mdpc-restrict-$USER.service"
echo " → Boot-time service installed and enabled"

echo "Step 7: Block mounts via Polkit"
PKLA_DIR="/etc/polkit-1/localauthority/50-local.d"
PKLA_FILE="$PKLA_DIR/disable-$USER-mount.pkla"
mkdir -p "$PKLA_DIR"
cat <<EOF >"$PKLA_FILE"
[Disable all mounts for $USER]
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

echo "Step 8: Block USB storage via udev"
UDEV_RULES="/etc/udev/rules.d/99-usb-block-$USER.rules"
cat <<EOF >"$UDEV_RULES"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="sd[b-z][0-9]*", OWNER="root", GROUP="root", MODE="0000"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="mmcblk[0-9]*", OWNER="root", GROUP="root", MODE="0000"
EOF
udevadm control --reload-rules && udevadm trigger

echo "============================================"
echo " Restriction for user '$USER' completed!"
echo " Use 'mdpc add domain.com' to add more domains"
echo " Use 'mdpc status $USER' to check current restrictions"
echo "============================================"
