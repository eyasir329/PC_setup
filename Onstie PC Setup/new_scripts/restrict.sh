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
CHAIN="CONTEST_${USER^^}_OUT"  # Uppercase username for chain name

echo "Step 4: Configure IP-based firewall for domain filtering"
# Get current allowed domains from the centralized whitelist
ALLOWED_DOMAINS="/tmp/current_allowed_domains.txt"
WHITELIST_CONFIG="/usr/local/etc/contest-restriction/allowed.txt"

# Create config directory if it doesn't exist
mkdir -p "$(dirname "$WHITELIST_CONFIG")"

# Use the centralized whitelist file
if [ -f "$WHITELIST_CONFIG" ]; then
    cp "$WHITELIST_CONFIG" "$ALLOWED_DOMAINS"
elif [ -f "whitelist.txt" ]; then
    echo "Using local whitelist.txt file"
    cp "whitelist.txt" "$ALLOWED_DOMAINS"
    # Also create the centralized whitelist for future use
    cp "whitelist.txt" "$WHITELIST_CONFIG"
else
    echo "[ERROR] No whitelist found. Please create a whitelist.txt file with allowed domains."
    echo "Example whitelist.txt content:"
    echo "  codeforces.com"
    echo "  codechef.com" 
    echo "  atcoder.jp"
    exit 1
fi

echo "Step 5: Configure selective internet blocking with iptables"
# Clear any existing chain
iptables -t filter -D OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN" 2>/dev/null || true
if iptables -t filter -L "$CHAIN" &>/dev/null; then
  iptables -t filter -F "$CHAIN"
  iptables -t filter -X "$CHAIN"
fi

# Create new chain
iptables -t filter -N "$CHAIN"
iptables -t filter -I OUTPUT -m owner --uid-owner "$UID_USER" -j "$CHAIN"

# Allow DNS queries (essential for domain resolution)
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT

# Allow loopback traffic
iptables -A "$CHAIN" -o lo -j ACCEPT

# Allow established connections (for responses to allowed requests)
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Create a temporary script to resolve whitelisted domains to IPs
cat > /tmp/resolve_whitelist.sh << 'EOF'
#!/bin/bash
WHITELIST="/tmp/current_allowed_domains.txt"
OUTPUT_FILE="/tmp/allowed_ips.txt"

> "$OUTPUT_FILE"

while IFS= read -r domain; do
    if [[ "$domain" =~ ^[[:space:]]*# ]] || [[ -z "$domain" ]]; then
        continue
    fi
    
    # Remove leading dot if present
    clean_domain="${domain#.}"
    
    echo "Resolving $clean_domain..."
    
    # Resolve domain to IPs
    dig +short "$clean_domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> "$OUTPUT_FILE" 2>/dev/null
    
    # Also resolve common subdomains that contest sites might use
    for subdomain in www api cdn static assets m mobile app secure auth login register; do
        dig +short "$subdomain.$clean_domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> "$OUTPUT_FILE" 2>/dev/null
    done
done

# Add common infrastructure domains that contest sites typically depend on
echo "Resolving common infrastructure domains..."
for infra_domain in fonts.googleapis.com fonts.gstatic.com cdnjs.cloudflare.com ajax.googleapis.com code.jquery.com maxcdn.bootstrapcdn.com unpkg.com jsdelivr.net cdn.jsdelivr.net; do
    echo "Resolving infrastructure: $infra_domain"
    dig +short "$infra_domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> "$OUTPUT_FILE" 2>/dev/null
done

# Remove duplicates and sort
sort -u "$OUTPUT_FILE" -o "$OUTPUT_FILE"
echo "Resolved $(wc -l < "$OUTPUT_FILE") unique IP addresses"
EOF

chmod +x /tmp/resolve_whitelist.sh
/tmp/resolve_whitelist.sh

# Add rules to allow traffic to whitelisted IPs
if [ -f /tmp/allowed_ips.txt ]; then
    while IFS= read -r ip; do
        if [[ -n "$ip" ]]; then
            iptables -A "$CHAIN" -d "$ip" -j ACCEPT
        fi
    done < /tmp/allowed_ips.txt
    echo "✅ Added rules for $(wc -l < /tmp/allowed_ips.txt) whitelisted IPs"
fi

# Allow access to common infrastructure IPs that contest sites might use
# DNS servers and popular CDNs
iptables -A "$CHAIN" -d 8.8.8.8 -j ACCEPT       # Google DNS
iptables -A "$CHAIN" -d 8.8.4.4 -j ACCEPT       # Google DNS
iptables -A "$CHAIN" -d 1.1.1.1 -j ACCEPT       # Cloudflare DNS
iptables -A "$CHAIN" -d 1.0.0.1 -j ACCEPT       # Cloudflare DNS
iptables -A "$CHAIN" -d 208.67.222.222 -j ACCEPT # OpenDNS
iptables -A "$CHAIN" -d 208.67.220.220 -j ACCEPT # OpenDNS

# Block everything else
iptables -A "$CHAIN" -j REJECT --reject-with icmp-net-unreachable

echo "✅ iptables rules configured with IP-based whitelisting"

# Create a script to update allowed IPs dynamically
cat > /usr/local/bin/update-contest-whitelist << 'EOF'
#!/bin/bash
# Script to update whitelist IPs for contest restrictions
USER_ARG="$1"
if [ -z "$USER_ARG" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

UID_USER=$(id -u "$USER_ARG")
CHAIN="CONTEST_${USER_ARG^^}_OUT"

echo "Updating whitelist IPs for user $USER_ARG..."

# Get current allowed domains from centralized whitelist
ALLOWED_DOMAINS="/tmp/current_allowed_domains.txt"
WHITELIST_CONFIG="/usr/local/etc/contest-restriction/allowed.txt"

if [ -f "$WHITELIST_CONFIG" ]; then
    cp "$WHITELIST_CONFIG" "$ALLOWED_DOMAINS"
else
    echo "[ERROR] Centralized whitelist not found. Cannot update whitelist."
    echo "Run 'sudo cmanager add domain.com' to create whitelist first."
    exit 1
fi

# Resolve new IPs
/tmp/resolve_whitelist.sh

# Remove old IP rules but keep essential ones
iptables -F "$CHAIN" 2>/dev/null || {
    echo "[ERROR] Chain $CHAIN not found. Is restriction active?"
    exit 1
}

# Re-add essential rules
iptables -A "$CHAIN" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -p tcp --dport 53 -j ACCEPT
iptables -A "$CHAIN" -o lo -j ACCEPT
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Add new IP rules for whitelisted domains
if [ -f /tmp/allowed_ips.txt ]; then
    ip_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" ]]; then
            iptables -A "$CHAIN" -d "$ip" -j ACCEPT
            ((ip_count++))
        fi
    done < /tmp/allowed_ips.txt
    echo "Added $ip_count whitelisted IPs"
fi

# Re-add common infrastructure domains for the update script too
echo "Resolving common infrastructure domains..."
for infra_domain in fonts.googleapis.com fonts.gstatic.com cdnjs.cloudflare.com ajax.googleapis.com code.jquery.com maxcdn.bootstrapcdn.com unpkg.com jsdelivr.net cdn.jsdelivr.net; do
    dig +short "$infra_domain" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> /tmp/allowed_ips.txt 2>/dev/null
done

# Re-add any new infrastructure IPs
if [ -f /tmp/allowed_ips.txt ]; then
    sort -u /tmp/allowed_ips.txt -o /tmp/allowed_ips.txt
    while IFS= read -r ip; do
        if [[ -n "$ip" ]]; then
            iptables -A "$CHAIN" -d "$ip" -j ACCEPT 2>/dev/null || true
        fi
    done < /tmp/allowed_ips.txt
fi

# Re-add common infrastructure IPs (DNS, CDNs)
iptables -A "$CHAIN" -d 8.8.8.8 -j ACCEPT       # Google DNS
iptables -A "$CHAIN" -d 8.8.4.4 -j ACCEPT       # Google DNS
iptables -A "$CHAIN" -d 1.1.1.1 -j ACCEPT       # Cloudflare DNS
iptables -A "$CHAIN" -d 1.0.0.1 -j ACCEPT       # Cloudflare DNS
iptables -A "$CHAIN" -d 208.67.222.222 -j ACCEPT # OpenDNS
iptables -A "$CHAIN" -d 208.67.220.220 -j ACCEPT # OpenDNS

# Block everything else
iptables -A "$CHAIN" -j REJECT --reject-with icmp-net-unreachable

echo "✅ Whitelist IPs updated successfully for user $USER_ARG"
EOF

chmod +x /usr/local/bin/update-contest-whitelist

echo "Step 6: Create systemd service for persistence"
# Create a systemd service file with user-specific name
cat > "/etc/systemd/system/contest-restrict-$USER.service" << EOF
[Unit]
Description=Contest Environment Internet Restriction Service for user $USER
After=network.target
Wants=network.target

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
systemctl enable "contest-restrict-$USER.service"
echo "✅ Boot-time service installed and enabled"

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
echo " Use 'cmanager add domain.com' to add more domains"
echo " Use 'cmanager list' to view current whitelist"
echo " Use 'cmanager update' to refresh IPs"
echo "============================================"
