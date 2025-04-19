#!/bin/bash

echo "============================================"
echo "Starting Internet Access and Storage Device Restriction"
echo "============================================"

# Define the participant's username
PARTICIPANT_USER="participant"

# List of allowed domains
ALLOWED_DOMAINS=(
    "codeforces.com" "codechef.com" "vjudge.net" "atcoder.jp"
    "hackerrank.com" "hackerearth.com" "topcoder.com"
    "spoj.com" "lightoj.com" "uva.onlinejudge.org"
    "cses.fi" "bapsoj.com" "toph.co"
)

# Install Squid
echo "Installing Squid..."
sudo apt update
sudo apt install squid -y

# Configure Squid for domain-based access control
SQUID_CONF="/etc/squid/squid.conf"
sudo cp $SQUID_CONF $SQUID_CONF.bak

# Allow access to specific domains
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "acl allowed_sites dstdomain .$domain" | sudo tee -a $SQUID_CONF
done

# Deny access to all other websites
sudo sed -i '/http_access deny all/i http_access allow allowed_sites' $SQUID_CONF

# Set up ACL for participant user (replace with correct IP)
sudo echo "acl participant src 192.168.1.100" | sudo tee -a $SQUID_CONF  # Replace with participant's IP or method
sudo echo "http_access allow participant" | sudo tee -a $SQUID_CONF

# Deny all other access by default
echo "http_access deny all" | sudo tee -a $SQUID_CONF

# Restart Squid to apply changes
sudo systemctl restart squid

# Block storage devices for participant only
echo "Blocking access to storage devices (USB, SSD, CD, etc.) for participant..."
echo 'SUBSYSTEM=="block", ACTION=="add", ATTRS{idVendor}!="0781", ATTRS{idProduct}!="5591", RUN+="/usr/bin/logger Storage device blocked for participant"' | sudo tee /etc/udev/rules.d/99-block-storage-participant.rules
echo 'ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd*", ENV{ID_FS_TYPE}=="vfat|ntfs|exfat", RUN+="/usr/bin/test -e /dev/$name && /bin/mount --bind /dev/null /dev/$name"' | sudo tee -a /etc/udev/rules.d/99-block-storage-participant.rules

# Reload udev rules to apply changes
sudo udevadm control --reload-rules

echo "============================================"
echo "✅ Internet access and storage device restrictions applied for participant."
echo "============================================"

