#!/bin/bash

echo "============================================"
echo "Setting Up Strict Internet & Storage Restrictions for participant"
echo "============================================"

PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER 2>/dev/null)

if [ -z "$PARTICIPANT_UID" ]; then
    echo "Error: User $PARTICIPANT_USER does not exist!"
    exit 1
fi

# Define allowed domains
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

echo "1. Setting up direct iptables filtering..."

# Flush existing rules for this user
sudo iptables -t filter -F OUTPUT
sudo iptables -t nat -F OUTPUT

# Create a new chain specifically for the participant user
sudo iptables -N PARTICIPANT_RULES 2>/dev/null || sudo iptables -F PARTICIPANT_RULES
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES

# Allow DNS lookups to resolve the allowed domains
sudo iptables -A PARTICIPANT_RULES -p udp --dport 53 -j ACCEPT
sudo iptables -A PARTICIPANT_RULES -p tcp --dport 53 -j ACCEPT

# Allow loopback connections
sudo iptables -A PARTICIPANT_RULES -o lo -j ACCEPT

# Allow connections to allowed domains
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "Allowing access to $domain..."
    
    # Resolve domain to IPs
    IPS=$(host -t A "$domain" | grep "has address" | awk '{print $4}')
    
    # Add rules for each IP
    for ip in $IPS; do
        sudo iptables -A PARTICIPANT_RULES -d $ip -j ACCEPT
    done
    
    # Also handle subdomains
    IPS=$(host -t A "www.$domain" | grep "has address" | awk '{print $4}')
    for ip in $IPS; do
        sudo iptables -A PARTICIPANT_RULES -d $ip -j ACCEPT
    done
done

# Block everything else
sudo iptables -A PARTICIPANT_RULES -j DROP

echo "2. Setting up transparent proxy with hostname filtering..."

# Install required packages
sudo apt update
sudo apt install -y squid tinyproxy iptables-persistent

# Configure tinyproxy for domain filtering
sudo bash -c "cat > /etc/tinyproxy/tinyproxy.conf" <<EOF
User nobody
Group nogroup
Port 8888
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogFile "/var/log/tinyproxy/tinyproxy.log"
LogLevel Info
PidFile "/var/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
ViaProxyName "tinyproxy"
ConnectPort 443
ConnectPort 80

# Only allow participant's user ID
Allow 127.0.0.1

# Filter mode
Filter "/etc/tinyproxy/filter"
FilterDefaultDeny Yes
FilterExtended On
EOF

# Create filter file with allowed domains
sudo bash -c "cat > /etc/tinyproxy/filter" <<EOF
# Allowed domains
$(for domain in "${ALLOWED_DOMAINS[@]}"; do echo "$domain"; echo "www.$domain"; done)
EOF

# Transparent redirection for the participant user
sudo iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $PARTICIPANT_UID --dport 80 -j REDIRECT --to-port 8888
sudo iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner $PARTICIPANT_UID --dport 443 -j REDIRECT --to-port 8888

# Restart tinyproxy
sudo systemctl restart tinyproxy
sudo systemctl enable tinyproxy

echo "3. Setting up comprehensive storage blocking..."

# Create AppArmor profile for the participant user
sudo bash -c "cat > /etc/apparmor.d/user.$PARTICIPANT_USER" <<EOF
# AppArmor profile for $PARTICIPANT_USER
#include <tunables/global>
/home/$PARTICIPANT_USER/** {
    #include <abstractions/base>
    #include <abstractions/user-tmp>
    #include <abstractions/X>
    #include <abstractions/gnome>
    
    # Allow home directory access
    /home/$PARTICIPANT_USER/** rw,
    
    # Allow essential programming tools
    /usr/bin/gcc* Ux,
    /usr/bin/g++* Ux,
    /usr/bin/python* Ux,
    /usr/bin/java* Ux,
    /usr/bin/vim* Ux,
    /usr/bin/nano* Ux,
    /usr/bin/code* Ux,
    /usr/bin/gnome-terminal* Ux,
    /usr/bin/xterm Ux,
    
    # Block access to external storage
    deny /media/** rw,
    deny /mnt/** rw,
    deny /run/media/** rw,
    deny /dev/sd* rw,
    deny /dev/nvme* rw,
}
EOF

# Load the AppArmor profile
sudo apparmor_parser -r /etc/apparmor.d/user.$PARTICIPANT_USER

# Create udev rules to block USB storage
sudo bash -c "cat > /etc/udev/rules.d/99-block-usb-storage-participant.rules" <<EOF
# Block USB storage access for $PARTICIPANT_USER
SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ENV{ID_BUS}=="usb", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ENV{ID_TYPE}=="disk", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]p[0-9]", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
EOF

# Mount tmpfs on removable media directories
sudo bash -c "cat > /etc/systemd/system/block-external-storage.service" <<EOF
[Unit]
Description=Block external storage for participant user
Before=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mount -t tmpfs -o size=1k,mode=0700,uid=0,gid=0 tmpfs /media
ExecStart=/bin/mount -t tmpfs -o size=1k,mode=0700,uid=0,gid=0 tmpfs /mnt
RemainAfterExit=yes

[Install]
WantedBy=local-fs.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable block-external-storage.service
sudo systemctl start block-external-storage.service

echo "4. Creating maintenance script for dynamic IPs..."

# Create a script that periodically updates IP rules
sudo bash -c "cat > /usr/local/bin/update-allowed-ips.sh" <<'EOF'
#!/bin/bash

# List of allowed domains
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

PARTICIPANT_UID=$(id -u participant)

# Clear existing rules
iptables -F PARTICIPANT_RULES

# Allow DNS lookups
iptables -A PARTICIPANT_RULES -p udp --dport 53 -j ACCEPT
iptables -A PARTICIPANT_RULES -p tcp --dport 53 -j ACCEPT

# Allow loopback
iptables -A PARTICIPANT_RULES -o lo -j ACCEPT

# Resolve and allow each domain
for domain in "${ALLOWED_DOMAINS[@]}"; do
    # Resolve domain to IPs
    IPS=$(host -t A "$domain" | grep "has address" | awk '{print $4}')
    
    # Add rules for each IP
    for ip in $IPS; do
        iptables -A PARTICIPANT_RULES -d $ip -j ACCEPT
    done
    
    # Also handle www subdomain
    IPS=$(host -t A "www.$domain" | grep "has address" | awk '{print $4}')
    for ip in $IPS; do
        iptables -A PARTICIPANT_RULES -d $ip -j ACCEPT
    done
done

# Block everything else
iptables -A PARTICIPANT_RULES -j DROP

echo "$(date): Updated IP rules for allowed domains" >> /var/log/participant-restriction.log
EOF

sudo chmod +x /usr/local/bin/update-allowed-ips.sh

# Create a timer to update IPs hourly
sudo bash -c "cat > /etc/systemd/system/update-allowed-ips.service" <<EOF
[Unit]
Description=Update allowed IPs for participant user

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-allowed-ips.sh
EOF

sudo bash -c "cat > /etc/systemd/system/update-allowed-ips.timer" <<EOF
[Unit]
Description=Update allowed IPs hourly

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Unit=update-allowed-ips.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable update-allowed-ips.timer
sudo systemctl start update-allowed-ips.timer

echo "5. Setting up IP forwarding persistence..."

# Make sure IP forwarding rules persist across reboots
sudo bash -c "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
sudo sysctl -p

# Save iptables rules
sudo netfilter-persistent save
sudo netfilter-persistent reload

echo "✅ Direct filtering by user ID implemented."
echo "✅ Transparent proxy with hostname filtering configured."
echo "✅ Storage access comprehensively blocked."
echo "✅ Dynamic IP updating scheduled hourly."
echo "✅ Rules saved for persistence across reboots."
echo "🎯 Restrictions are active immediately - no reboot needed."
echo ""
echo "To verify restrictions are working:"
echo "1. Check if the participant user can only access allowed sites"
echo "2. Run this to see active rules: sudo iptables -L PARTICIPANT_RULES"
echo "3. Check logs: sudo cat /var/log/tinyproxy/tinyproxy.log"