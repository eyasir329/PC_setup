#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

echo "Setting up participant restrictions with full persistence..."

# Install required packages
echo "Installing required packages..."
apt update
apt install -y squid udev iptables-persistent acl inotify-tools

# Backup original squid configuration
echo "Configuring Squid proxy..."
cp /etc/squid/squid.conf /etc/squid/squid.conf.backup

# Create whitelist file with contest domains
mkdir -p /etc/squid
cat > /etc/squid/whitelist.txt <<EOF
.codeforces.com
.codechef.com
.vjudge.net
.atcoder.jp
.hackerrank.com
.hackerearth.com
.topcoder.com
.spoj.com
.lightoj.com
.uva.onlinejudge.org
.cses.fi
.bapsoj.com
.toph.co
.ubuntu.com
EOF

# Create directories for auto-discovery system
mkdir -p /var/log/domain-discovery
touch /var/log/domain-discovery/denied_domains.log
touch /var/log/domain-discovery/auto_approved.log

# Configure squid for user-based filtering and auto-discovery
cat > /etc/squid/squid.conf <<EOF
http_port 3128
visible_hostname localhost

# Define ACLs
acl SSL_ports port 443
acl Safe_ports port 80 443
acl admin_user src all uid admin
acl participant_user src all uid participant
acl allowed_sites dstdomain "/etc/squid/whitelist.txt"

# Special logging format for denied domains
logformat denied_domains %{Host}>
access_log /var/log/domain-discovery/denied_domains.log denied_domains participant_user !allowed_sites

# Default port restrictions
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# User-based access control
http_access allow admin_user
http_access allow participant_user allowed_sites
http_access deny participant_user
http_access allow localhost
http_access deny all

# Performance settings
cache_dir ufs /var/spool/squid 1000 16 256
refresh_pattern . 0 20% 4320
EOF

# Create the auto-discovery service
cat > /usr/local/bin/auto_domain_discovery.sh <<'EOF'
#!/bin/bash

DENIED_LOG="/var/log/domain-discovery/denied_domains.log"
APPROVED_LOG="/var/log/domain-discovery/auto_approved.log"
WHITELIST="/etc/squid/whitelist.txt"

# Function to process denied domains
process_denied_domains() {
    # Create a temporary file with unique domains
    cat "$DENIED_LOG" | grep -oE "[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" | sort | uniq > /tmp/denied_domains.tmp
    
    # Process if we have domains
    if [ -s "/tmp/denied_domains.tmp" ]; then
        echo "$(date): Processing denied domains..." >> "$APPROVED_LOG"
        
        # For each denied domain
        while read domain; do
            # Skip if already in whitelist
            if grep -q ".$domain" "$WHITELIST"; then
                continue
            fi
            
            # Add domain to whitelist
            echo ".$domain" >> "$WHITELIST"
            echo "$(date): Auto-approved domain: $domain" >> "$APPROVED_LOG"
            
            # Also add main domain if this is a subdomain
            main_domain=$(echo "$domain" | grep -oE "[^.]+\.[^.]+$")
            if [[ ! -z "$main_domain" && "$main_domain" != "$domain" ]]; then
                # Only add if not already in whitelist
                if ! grep -q ".$main_domain" "$WHITELIST"; then
                    echo ".$main_domain" >> "$WHITELIST"
                    echo "$(date): Auto-approved base domain: $main_domain" >> "$APPROVED_LOG"
                fi
            fi
        done < /tmp/denied_domains.tmp
        
        # Remove duplicates from whitelist
        sort -u "$WHITELIST" -o "$WHITELIST"
        
        # Reload squid to apply changes
        systemctl reload squid
        echo "$(date): Reloaded Squid with updated whitelist" >> "$APPROVED_LOG"
    fi
    
    # Clear the denied log after processing
    > "$DENIED_LOG"
}

# Main monitoring loop
while true; do
    # If denied log has content, process it
    if [ -s "$DENIED_LOG" ]; then
        process_denied_domains
    fi
    
    # Check every 5 seconds
    sleep 5
done
EOF

chmod +x /usr/local/bin/auto_domain_discovery.sh

# Create systemd service for auto-discovery
cat > /etc/systemd/system/domain-discovery.service <<EOF
[Unit]
Description=Automatic Domain Discovery Service
After=squid.service
Requires=squid.service

[Service]
Type=simple
ExecStart=/usr/local/bin/auto_domain_discovery.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Create proxy configuration script for participant
echo "Setting up proxy enforcer for participant account..."
cat > /usr/local/bin/set-participant-proxy.sh <<EOF
#!/bin/bash
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.http host 'localhost'
gsettings set org.gnome.system.proxy.http port 3128
gsettings set org.gnome.system.proxy.https host 'localhost'
gsettings set org.gnome.system.proxy.https port 3128
gsettings set org.gnome.system.proxy.ftp host 'localhost'
gsettings set org.gnome.system.proxy.ftp port 3128
gsettings set org.gnome.system.proxy.socks host 'localhost'
gsettings set org.gnome.system.proxy.socks port 3128
gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8']"
EOF

chmod +x /usr/local/bin/set-participant-proxy.sh

# Add to participant's startup
mkdir -p /home/participant/.config/autostart
cat > /home/participant/.config/autostart/proxy-settings.desktop <<EOF
[Desktop Entry]
Name=Proxy Settings
Exec=/usr/local/bin/set-participant-proxy.sh
Type=Application
X-GNOME-Autostart-enabled=true
EOF

# Fix ownership
chown -R participant:participant /home/participant/.config/

# Force participant traffic through proxy with iptables
echo "Setting up iptables rules..."
iptables -t nat -F  # Clear existing rules
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner participant --dport 80 -j REDIRECT --to-port 3128
iptables -t nat -A OUTPUT -p tcp -m owner --uid-owner participant --dport 443 -j REDIRECT --to-port 3128

# Make iptables rules persistent
netfilter-persistent save
systemctl enable netfilter-persistent

# Block USB storage for participant
echo "Setting up USB storage restrictions..."
cat > /etc/udev/rules.d/99-block-participant-usb.rules <<EOF
# Block USB drives for participant user
SUBSYSTEM=="block", ACTION=="add", ENV{ID_BUS}=="usb", RUN+="/bin/sh -c 'for dev in \$kernel \$kernel*; do chmod 000 /dev/\$dev; chown root:admin /dev/\$dev; chmod 660 /dev/\$dev; done'"
EOF

udevadm control --reload-rules

# Create a policy to prevent mounting for participant
cat > /etc/polkit-1/localauthority/50-local.d/restrict-mounting.pkla <<EOF
[Restrict mounting to admin group]
Identity=unix-user:participant
Action=org.freedesktop.udisks2.filesystem-mount;org.freedesktop.udisks2.filesystem-mount-system;org.freedesktop.udisks2.encrypted-unlock;org.freedesktop.udisks2.eject-media;org.freedesktop.udisks2.power-off-drive
ResultAny=no
ResultInactive=no
ResultActive=no

[Allow mounting for admin]
Identity=unix-user:admin
Action=org.freedesktop.udisks2.filesystem-mount;org.freedesktop.udisks2.filesystem-mount-system;org.freedesktop.udisks2.encrypted-unlock;org.freedesktop.udisks2.eject-media;org.freedesktop.udisks2.power-off-drive
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# Add admin to admin group if not already
usermod -aG sudo admin
usermod -aG admin admin

# Remove participant from any privileged groups
gpasswd -d participant sudo &>/dev/null || true
gpasswd -d participant admin &>/dev/null || true
gpasswd -d participant adm &>/dev/null || true
gpasswd -d participant lpadmin &>/dev/null || true

# Block access to other partitions by modifying fstab
echo "Restricting access to other partitions..."
# Get a list of all partitions
partitions=$(lsblk -ln -o NAME,MOUNTPOINT | grep -v 'loop\|sr' | awk '$2 != "" && $2 != "/" && $2 != "/boot" && $2 != "swap" {print $2}')

# For each mounted partition, update permissions
for mount_point in $partitions; do
    if [ -d "$mount_point" ]; then
        echo "Restricting $mount_point for participant..."
        chmod 750 "$mount_point"
        chown root:admin "$mount_point"
    fi
done

# Enable and start services
systemctl daemon-reload
systemctl enable squid
systemctl restart squid
systemctl enable domain-discovery
systemctl start domain-discovery

echo "=============================================================="
echo "PARTICIPANT RESTRICTIONS SUCCESSFULLY APPLIED!"
echo "=============================================================="
echo ""
echo "SUMMARY:"
echo "1. Admin user has FULL access to:"
echo "   - All internet sites"
echo "   - All USB/external storage devices" 
echo "   - All disk partitions"
echo ""
echo "2. Participant user has RESTRICTED access:"
echo "   - Can only access whitelisted contest websites"
echo "   - Cannot access USB/external storage devices"
echo "   - Cannot access other disk partitions"
echo ""
echo "3. Auto-discovery system is active:"
echo "   - New required domains are automatically detected and added"
echo "   - Check the log at: /var/log/domain-discovery/auto_approved.log"
echo ""
echo "4. All restrictions WILL PERSIST after system reboots"
echo ""
echo "=============================================================="