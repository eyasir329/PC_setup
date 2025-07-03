#!/usr/bin/env bash
set -euo pipefail

echo "Step 0: Ensure script is executable"
SCRIPT_PATH=$(readlink -f "$0")
chmod +x "$SCRIPT_PATH"

echo "============================================"
echo " Starting Participant Restrict: $(date)"
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
USER="participant"
UID_PARTICIPANT=$(id -u "$USER")
CHAIN="PARTICIPANT_OUT"

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

# Define participant user by UID
acl participant_user src all ident_regex -i ^$USER$
acl participant_user_ip src all myip
external_acl_type participant_check %SRC /bin/sh -c 'id -u $USER | grep -q "$UID_PARTICIPANT"'

# Define allowed domains
acl whitelist dstdomain "/etc/squid/whitelist.txt"

# Security rules - block unsafe ports
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Allow localhost admin access
http_access allow localhost

# Allow participant only to whitelisted sites 
# (using IP matching since transparent proxy won't have auth)
acl participant_uid src owner UID_OF_$UID_PARTICIPANT
http_access allow participant_uid whitelist
http_access deny participant_uid

# Allow everyone else full access
http_access allow all

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
pid_filename /var/run/squid.pid

# SSL bump settings for HTTPS inspection (commented by default)
# Uncommenting would require SSL certificate setup
# ssl_bump server-first all
# sslproxy_cert_error allow all
# sslproxy_flags DONT_VERIFY_PEER

# Disable caching for simplicity
cache deny all
EOF

# Create special ACL file for participant identification
mkdir -p /etc/squid/acls/
echo "$UID_PARTICIPANT" > /etc/squid/acls/participant_uid.txt

# Restart Squid to apply changes
echo "Restarting Squid service..."
systemctl restart squid
systemctl enable squid

echo "Step 5: Configure transparent proxy with iptables"
# Clear any existing PARTICIPANT_OUT chain
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN" 2>/dev/null || true
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi
iptables -t filter -N "$CHAIN"
iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_PARTICIPANT" -j "$CHAIN"

# Allow DNS queries
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# Allow access to Squid proxy port
iptables -A "$CHAIN" -p tcp --dport 3128 -j ACCEPT

# Allow established connections
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Redirect all HTTP/HTTPS traffic to Squid
iptables -t nat -F
iptables -t nat -A OUTPUT -p tcp --dport 80 -m owner --uid-owner "$UID_PARTICIPANT" -j REDIRECT --to-port 3128
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$UID_PARTICIPANT" -j REDIRECT --to-port 3128

# Block everything else
iptables -A "$CHAIN" -j REJECT

# Create environment variables for the participant user
cat > /etc/profile.d/participant-proxy.sh << EOF
if [ "\$(id -un)" = "participant" ]; then
    export http_proxy=http://localhost:3128
    export https_proxy=http://localhost:3128
    export no_proxy=localhost,127.0.0.1
fi
EOF
chmod +x /etc/profile.d/participant-proxy.sh

echo "Step 6: Create systemd service to run at boot"
# Create a systemd service file
cat > /etc/systemd/system/participant-restrict.service << EOF
[Unit]
Description=Participant Internet Restriction Service
After=network.target squid.service
Wants=squid.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable participant-restrict.service
echo " → Boot-time service installed and enabled"

echo "Step 7: Block mounts via Polkit"
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

echo "Step 8: Block USB storage via udev"
UDEV_RULES="/etc/udev/rules.d/99-usb-block.rules"
cat <<EOF >"$UDEV_RULES"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="sd[b-z][0-9]*", MODE="0000", OWNER="root", GROUP="root"
SUBSYSTEM=="block", ENV{ID_BUS}=="usb", KERNEL=="mmcblk[0-9]*", MODE="0000", OWNER="root", GROUP="root"
EOF
udevadm control --reload-rules && udevadm trigger

echo "Step 9: Create domain whitelist management tool"
WHITELIST_TOOL="/usr/local/bin/add-contest-domain"
cat > "$WHITELIST_TOOL" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 domain.name"
  echo "Example: $0 example.com"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 
  exit 1
fi

DOMAIN="$1"
WHITELIST="/etc/squid/whitelist.txt"

# Add domain with leading dot to match subdomains too
if grep -q ".$DOMAIN" "$WHITELIST"; then
  echo "Domain $DOMAIN already in whitelist"
else
  echo ".$DOMAIN" >> "$WHITELIST"
  echo "Added domain: $DOMAIN"
  systemctl restart squid
  echo "Squid service restarted"
fi
EOF
chmod +x "$WHITELIST_TOOL"

echo "============================================"
echo " Participant Restrict Completed!"
echo " To add new domains: add-contest-domain example.com"
echo "============================================"