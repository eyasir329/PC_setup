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

# 1. Install required packages
echo "Installing required packages..."
sudo apt update
sudo apt install -y squid iptables-persistent iproute2 net-tools apparmor-utils

# Backup existing Squid config
echo "Backing up original Squid config..."
sudo cp $SQUID_CONF_FILE "${SQUID_CONF_FILE}.backup"

# Configure allowed domains
echo "Configuring allowed domains for Squid..."
sudo bash -c "cat > $SQUID_ALLOWED_DOMAINS_FILE" <<EOF
$(for domain in "${ALLOWED_DOMAINS[@]}"; do echo ".$domain"; done)
EOF

# 2. Setting up network namespace for participant user
echo "Setting up network namespace for $PARTICIPANT_USER..."

# Create the network namespace setup script
sudo bash -c "cat > /usr/local/bin/setup-participant-net.sh" <<'EOF'
#!/bin/bash

# Create network namespace if it doesn't exist
if ! ip netns list | grep -q participant_ns; then
    ip netns add participant_ns
fi

# Create virtual interfaces if they don't exist
if ! ip link show veth0 &>/dev/null; then
    ip link add veth0 type veth peer name veth1
fi

# Connect veth0 to default network and veth1 to participant namespace
ip link set veth0 up
ip link set veth1 netns participant_ns

# Configure IP addresses
ip addr add 10.0.0.1/24 dev veth0
ip netns exec participant_ns ip link set lo up
ip netns exec participant_ns ip link set veth1 up
ip netns exec participant_ns ip addr add 10.0.0.2/24 dev veth1

# Setup routing in the namespace
ip netns exec participant_ns ip route add default via 10.0.0.1

# Enable NAT for outgoing connections
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward

# Clear any existing redirection rules for the namespace
iptables -t nat -F PREROUTING
iptables -t nat -A PREROUTING -s 10.0.0.2 -p tcp --dport 80 -j REDIRECT --to-port 3128
iptables -t nat -A PREROUTING -s 10.0.0.2 -p tcp --dport 443 -j REDIRECT --to-port 3128

# Log successful setup
echo "$(date): Network namespace setup complete" >> /var/log/participant-net.log
EOF

# Make the script executable
sudo chmod +x /usr/local/bin/setup-participant-net.sh

# Create network namespace service
sudo bash -c "cat > /etc/systemd/system/participant-network.service" <<EOF
[Unit]
Description=Setup participant network restrictions
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-participant-net.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# 3. Improved user namespace switching with logging
echo "Setting up improved namespace switching..."

# Create a logging directory
sudo mkdir -p /var/log/participant-net
sudo chmod 755 /var/log/participant-net

# First script: Mark participant logins for namespace entry
sudo bash -c "cat > /usr/local/bin/mark-participant-login.sh" <<'EOF'
#!/bin/bash

# Create log with helpful debug info
exec >> /var/log/participant-net/login.log 2>&1
echo "$(date): Login script executed for user: $PAM_USER (TTY: $PAM_TTY, Service: $PAM_SERVICE)"

if [ "$PAM_USER" = "participant" ]; then
    # Create a marker file for this session
    touch /var/log/participant-net/sessions/$$.marker
    echo "$(date): Marked session $$ for namespace entry"
    
    # Set up environment for network switching
    mkdir -p /run/participant-net
    echo $$ > /run/participant-net/latest_login.pid
fi

exit 0
EOF

# Second script: Apply network namespace to user sessions
sudo bash -c "cat > /usr/local/bin/apply-participant-ns.sh" <<'EOF'
#!/bin/bash

# Directory for session markers
mkdir -p /var/log/participant-net/sessions
mkdir -p /run/participant-net

# Logging
exec >> /var/log/participant-net/apply.log 2>&1
echo "$(date): Starting network namespace application"

# Find all participant processes
echo "$(date): Looking for participant processes..."
for PROC in $(pgrep -u participant); do
    echo "$(date): Found process $PROC, applying namespace"
    # Move this process to the network namespace
    ip netns exec participant_ns /bin/true 2>/dev/null || { echo "$(date): Namespace doesn't exist!"; exit 1; }
    
    ip netns attach participant_ns $PROC 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "$(date): Successfully applied namespace to $PROC"
    else
        echo "$(date): Failed to apply namespace to $PROC"
    fi
done

echo "$(date): Namespace application complete"
exit 0
EOF

# Make the scripts executable
sudo chmod +x /usr/local/bin/mark-participant-login.sh
sudo chmod +x /usr/local/bin/apply-participant-ns.sh

# Create service to automatically apply namespace
sudo bash -c "cat > /etc/systemd/system/apply-participant-namespace.service" <<EOF
[Unit]
Description=Apply network namespace to participant processes
After=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-participant-ns.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Set up sudoers entry for participant to use ip netns
sudo bash -c "cat > /etc/sudoers.d/participant-netns" <<EOF
# Allow participant to use ip netns commands
participant ALL=(ALL) NOPASSWD: /usr/sbin/ip netns exec participant_ns *
EOF
sudo chmod 0440 /etc/sudoers.d/participant-netns

# Configure PAM for multiple login methods
echo "Configuring PAM for multiple login methods..."
for service in login gdm lightdm sddm common-session; do
    if [ -f "/etc/pam.d/$service" ]; then
        grep -q "mark-participant-login.sh" "/etc/pam.d/$service" || \
            sudo bash -c "echo 'session    required     pam_exec.so /usr/local/bin/mark-participant-login.sh' >> /etc/pam.d/$service"
    fi
done

# Create a script that runs in participant's .profile
sudo bash -c "cat > /home/$PARTICIPANT_USER/.participant_net.sh" <<'EOF'
#!/bin/bash

# Only execute for participant user
if [ "$(whoami)" = "participant" ]; then
    # Enter network namespace for this session
    sudo ip netns exec participant_ns bash -c "exec env $(env | grep -v '^PATH=' | cut -d= -f1 | xargs -I{} echo -n '{}=\"${}\" ')"
fi
EOF
sudo chmod +x /home/$PARTICIPANT_USER/.participant_net.sh

# Add to participant's bash profile
grep -q "participant_net.sh" /home/$PARTICIPANT_USER/.profile || \
    echo "source ~/.participant_net.sh" >> /home/$PARTICIPANT_USER/.profile

# 4. Update Squid configuration
echo "Updating Squid configuration..."
sudo bash -c "cat > $SQUID_CONF_FILE" <<EOF
# Squid configuration
http_port 3128
https_port 3128 cert=/var/lib/squid/ssl_cert/myCA.pem ssl-bump
acl SSL_ports port 443
acl CONNECT method CONNECT

# Basic settings
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 ::1
acl Safe_ports port 80 443

# Define participant's IP
acl participant_net src 10.0.0.0/24

# Define allowed domains
acl allowed_sites dstdomain "/etc/squid/allowed_domains.txt"

# SSL Bump settings
ssl_bump peek all
ssl_bump bump all

# Access control rules
http_access allow localhost
http_access allow participant_net allowed_sites
http_access deny participant_net
http_access allow localhost
http_access deny all

# Cache and other settings
coredump_dir /var/spool/squid
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

# Log settings
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF

# Generate SSL certificate for Squid HTTPS interception
echo "Generating SSL certificate for Squid..."
sudo mkdir -p /var/lib/squid/ssl_cert
cd /var/lib/squid/ssl_cert
sudo openssl req -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 \
    -subj "/CN=Proxy CA" \
    -keyout myCA.pem -out myCA.pem
sudo chown -R proxy:proxy /var/lib/squid/ssl_cert

# 5. Comprehensive storage device blocking
echo "Setting up comprehensive storage blocking for $PARTICIPANT_USER..."

# Create AppArmor profile for participant user
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
    
    # Allow terminal apps
    /usr/bin/gnome-terminal* Ux,
    /usr/bin/xterm Ux,
    
    # Allow programming tools
    /usr/bin/gcc* Ux,
    /usr/bin/g++* Ux,
    /usr/bin/python* Ux,
    /usr/bin/java* Ux,
    /usr/bin/vim* Ux,
    /usr/bin/nano* Ux,
    /usr/bin/code* Ux,
    
    # Block access to external storage
    deny /media/** rw,
    deny /mnt/** rw,
    deny /run/media/** rw,
    deny /dev/sd* rw,
}
EOF

# Create more effective udev rules
sudo bash -c "cat > /etc/udev/rules.d/99-block-usb-storage-participant.rules" <<EOF
# Block USB storage access for $PARTICIPANT_USER
SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ENV{ID_BUS}=="usb", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
SUBSYSTEM=="block", KERNEL=="sd[a-z]*", ENV{ID_TYPE}=="disk", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
SUBSYSTEM=="block", KERNEL=="nvme[0-9]n[0-9]p[0-9]", TAG+="uaccess", OWNER="root", GROUP="root", MODE="0600"
EOF

# Configure systemd mount units to block mounting
echo "Blocking mount points for participant user..."
sudo bash -c "cat > /etc/systemd/system/media.mount" <<EOF
[Unit]
Description=Block /media access
Before=local-fs.target

[Mount]
What=tmpfs
Where=/media
Type=tmpfs
Options=mode=0700,uid=0,gid=0,size=1K

[Install]
WantedBy=local-fs.target
EOF

# Add fstab entries to handle other partitions
echo "Securing fstab entries..."
sudo bash -c "cat >> /etc/fstab" <<EOF
# Restrict access to external drives
tmpfs   /media          tmpfs   mode=0700,uid=0,gid=0,size=1k      0 0
tmpfs   /mnt            tmpfs   mode=0700,uid=0,gid=0,size=1k      0 0
EOF

# Create a firewall script for the participant user
sudo bash -c "cat > /usr/local/bin/participant-firewall.sh" <<EOF
#!/bin/bash

# Run this inside the participant namespace to block non-whitelisted domains
ip netns exec participant_ns bash -c '
# Default policy: block all outgoing connections
iptables -P OUTPUT DROP

# Allow local connections
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 127.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 10.0.0.0/24 -j ACCEPT

# Allow connections to DNS servers (to resolve allowed domains)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow connections to allowed domains via proxy
iptables -A OUTPUT -p tcp --dport 3128 -j ACCEPT
'
EOF
sudo chmod +x /usr/local/bin/participant-firewall.sh

# 6. Apply all configurations
echo "Applying configurations..."
# Create session directory
sudo mkdir -p /var/log/participant-net/sessions
sudo chmod 755 /var/log/participant-net/sessions

# Enable and start the participant network service
sudo systemctl daemon-reload
sudo systemctl enable participant-network.service
sudo systemctl start participant-network.service
sudo systemctl enable apply-participant-namespace.service
sudo systemctl start apply-participant-namespace.service

# Run the firewall script
sudo /usr/local/bin/participant-firewall.sh

# Restart Squid to apply changes
sudo systemctl restart squid
sudo systemctl enable squid

# Enable AppArmor for participant
sudo apparmor_parser -r /etc/apparmor.d/user.$PARTICIPANT_USER

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Mount the restricted directories
sudo mount -a

echo "✅ Network namespace isolation configured for $PARTICIPANT_USER."
echo "✅ Squid proxy installed and configured with SSL interception."
echo "✅ Multiple layer restrictions applied (network namespace + firewall + proxy)."
echo "✅ Internet restricted to allowed sites only."
echo "✅ Storage access comprehensively blocked."
echo "🔍 Check logs at /var/log/participant-net/ if issues persist."
echo "🎯 Setup complete! Please reboot to ensure all changes take effect."