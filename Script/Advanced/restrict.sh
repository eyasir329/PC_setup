#!/bin/bash

echo "============================================"
echo "Starting Internet Access and Storage Device Restriction for participant"
echo "============================================"

PARTICIPANT_USER="participant"

# Allowed domains
ALLOWED_DOMAINS=(
    "codeforces.com" "codechef.com" "vjudge.net" "atcoder.jp"
    "hackerrank.com" "hackerearth.com" "topcoder.com"
    "spoj.com" "lightoj.com" "uva.onlinejudge.org"
    "cses.fi" "bapsoj.com" "toph.co"
)

# Install dnsmasq
echo "Installing dnsmasq..."
sudo apt update
sudo apt install -y dnsmasq

# Stop and disable systemd-resolved to free up port 53
echo "Stopping systemd-resolved to free up port 53..."
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Configure dnsmasq
echo "Configuring dnsmasq for DNS filtering..."
DNSMASQ_CONF="/etc/dnsmasq.conf"
if ! grep -q "listen-address=127.0.0.1" "$DNSMASQ_CONF"; then
    sudo bash -c 'echo "listen-address=127.0.0.1" >> /etc/dnsmasq.conf'
fi
if ! grep -q "bind-interfaces" "$DNSMASQ_CONF"; then
    sudo bash -c 'echo "bind-interfaces" >> /etc/dnsmasq.conf'
fi

# Add allowed domains to dnsmasq configuration
echo "Creating DNS whitelist for allowed domains..."
WHITELIST_FILE="/etc/dnsmasq.d/allowed_domains.conf"
sudo bash -c ">$WHITELIST_FILE"
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "address=/$domain/127.0.0.1" | sudo tee -a "$WHITELIST_FILE" > /dev/null
done

# Restart dnsmasq
echo "Restarting dnsmasq..."
sudo systemctl restart dnsmasq
if systemctl is-active --quiet dnsmasq; then
    echo "✅ dnsmasq is running and DNS filtering is active."
else
    echo "❌ dnsmasq failed to start. Check logs for details."
    exit 1
fi

# Redirect traffic from participant to use dnsmasq for DNS
echo "Redirecting DNS traffic for participant user only..."
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER)

# Block all outgoing traffic for the participant user and only allow DNS to local dnsmasq server (port 5353)
sudo iptables -A OUTPUT -m owner ! --uid-owner $PARTICIPANT_UID -j ACCEPT   # Allow all other users' internet access
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p udp --dport 5353 -j ACCEPT   # Allow DNS traffic for participant
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -p tcp --dport 5353 -j ACCEPT   # Allow DNS traffic for participant
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j REJECT   # Block all other traffic for participant

# Save iptables rules
sudo sh -c "iptables-save > /etc/iptables.rules"

# Make persistent with systemd or rc.local
if ! grep -q "iptables-restore < /etc/iptables.rules" /etc/rc.local 2>/dev/null; then
    echo "Setting iptables rules to persist (rc.local)..."
    sudo bash -c 'echo -e "#!/bin/bash\niptables-restore < /etc/iptables.rules\nexit 0" > /etc/rc.local'
    sudo chmod +x /etc/rc.local
fi

# USB Storage Restriction for Participant User
echo "Blocking USB storage devices (pen drives, SSDs, memory cards) for participant..."

UDEV_RULE_FILE="/etc/udev/rules.d/99-block-usb-storage-participant.rules"
sudo bash -c "cat > $UDEV_RULE_FILE" <<EOF
# Block USB storage devices (pen drives, SSDs, memory cards) for participant user
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]", ENV{ID_BUS}=="usb", ENV{ID_USB_DRIVER}=="usb-storage", RUN+="/usr/bin/logger USB storage device blocked for $PARTICIPANT_USER"
EOF
sudo udevadm control --reload-rules

echo "============================================"
echo "✅ Internet and USB storage restrictions successfully applied to participant."
echo "============================================"
