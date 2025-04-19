#!/bin/bash

echo "============================================"
echo "Starting Internet Access and Storage Device Restriction for participant"
echo "============================================"

PARTICIPANT_USER="participant"
ALLOWED_DOMAINS=(
    "codeforces.com"
    "codechef.com"
    "vjudge.net"
    "atcoder.jp"
    "hackerrank.com"
    "hackerearth.com"
    "topcoder.com"
    "spoj.com"
    "lightoj.com"
    "uva.onlinejudge.org"
    "cses.fi"
    "bapsoj.com"
    "toph.co"
)

SQUID_CONF_FILE="/etc/squid/squid.conf"
SQUID_ALLOWED_DOMAINS_FILE="/etc/squid/allowed_domains.txt"

# 1. Install and configure Squid proxy
echo "Installing Squid proxy server..."
sudo apt update
sudo apt install -y squid iptables-persistent

# Backup existing Squid config
echo "Backing up original Squid config..."
sudo cp $SQUID_CONF_FILE "${SQUID_CONF_FILE}.backup"

# Configure allowed domains
echo "Configuring allowed domains for Squid..."
sudo bash -c "cat > $SQUID_ALLOWED_DOMAINS_FILE" <<EOF
$(for domain in "${ALLOWED_DOMAINS[@]}"; do echo ".$domain"; done)
EOF

# Update Squid configuration
echo "Updating Squid configuration..."
sudo bash -c "cat > $SQUID_CONF_FILE" <<EOF
# Ports
http_port 3128

# ACLs
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

acl allowed_sites dstdomain "/etc/squid/allowed_domains.txt"

# Allow only access to allowed sites
http_access allow CONNECT allowed_sites
http_access allow allowed_sites

# Deny all other access
http_access deny all
EOF

# Restart Squid to apply changes
echo "Restarting Squid service..."
sudo systemctl restart squid
sudo systemctl enable squid

# 2. Setup iptables to force participant user traffic through Squid

echo "Setting up iptables rules to force $PARTICIPANT_USER to use Squid proxy..."

# Create a group for proxy users if it doesn't exist
if ! getent group proxyusers > /dev/null; then
    sudo groupadd proxyusers
fi

# Add participant user to proxy group
sudo usermod -aG proxyusers $PARTICIPANT_USER

# Flush old rules
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Mark participant's packets
sudo iptables -t mangle -A OUTPUT -m owner --gid-owner proxyusers -p tcp --dport 80 -j MARK --set-mark 1
sudo iptables -t mangle -A OUTPUT -m owner --gid-owner proxyusers -p tcp --dport 443 -j MARK --set-mark 1

# Redirect marked packets to Squid
sudo iptables -t nat -A OUTPUT -m mark --mark 1 -p tcp --dport 80 -j REDIRECT --to-port 3128
sudo iptables -t nat -A OUTPUT -m mark --mark 1 -p tcp --dport 443 -j REDIRECT --to-port 3128

# Save iptables rules
sudo netfilter-persistent save

# 3. Restrict USB storage for participant
echo "Blocking USB storage devices (pen drives, SSDs) for $PARTICIPANT_USER..."

UDEV_RULE_FILE="/etc/udev/rules.d/99-block-usb-storage-participant.rules"
sudo bash -c "cat > $UDEV_RULE_FILE" <<EOF
# Block USB storage for 'participant'
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_USB_DRIVER}=="usb-storage", ENV{USER}=="$PARTICIPANT_USER", RUN+="/usr/bin/logger USB storage device blocked for $PARTICIPANT_USER"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "✅ Squid proxy installed and configured."
echo "✅ Internet restricted for 'participant' except allowed sites."
echo "✅ USB storage devices blocked for 'participant'."
echo "🎯 Setup complete."
