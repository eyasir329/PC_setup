#!/bin/bash

# IUPC Participant Restrictions Script
# This script restricts internet access to specific sites and blocks storage devices
# for the participant user only

# Exit on any error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Constants
PARTICIPANT_USER="participant"
PARTICIPANT_UID=$(id -u $PARTICIPANT_USER 2>/dev/null || echo "")
ADMIN_USER="mdpc"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Check if participant user exists
if [ -z "$PARTICIPANT_UID" ]; then
    echo "Error: User '$PARTICIPANT_USER' does not exist" >&2
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Handle apply-only mode for systemd service
if [ "$1" = "--apply-only" ]; then
    echo "Running in apply-only mode for scheduled updates"
    # Only refresh the iptables rules for dynamic IP updates
    
    # Flush existing user-specific rules
    iptables -t mangle -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES 2>/dev/null || true
    iptables -t mangle -F PARTICIPANT_RULES 2>/dev/null || true
    
    # Create a new chain for participant restrictions
    iptables -t mangle -N PARTICIPANT_RULES 2>/dev/null || iptables -t mangle -F PARTICIPANT_RULES
    
    # Block the specified domains
    BLOCKED_DOMAINS=(
        "facebook.com"
        "instagram.com"
        "discord.com"
        "github.com"
        "gitlab.com"
        "chat.openai.com"
    )
    
    # Function to add domain blocking rules
    block_domain() {
        local domain=$1
        # Block both the domain and www subdomain
        for host in "$domain" "www.$domain"; do
            # Use host command to resolve IP addresses (handles dynamic IPs)
            if host_ips=$(host "$host" 2>/dev/null | grep "has address" | awk '{print $4}'); then
                for ip in $host_ips; then
                    echo "Blocking IP $ip for domain $host"
                    iptables -t mangle -A PARTICIPANT_RULES -d "$ip" -j DROP
                done
            else
                echo "Could not resolve $host, setting up DNS-based blocking"
                # Create a string match for DNS queries
                iptables -t mangle -A PARTICIPANT_RULES -p udp --dport 53 -m string --string "$host" --algo bm -j DROP
                iptables -t mangle -A PARTICIPANT_RULES -p tcp --dport 53 -m string --string "$host" --algo bm -j DROP
            fi
            
            # Check for IPv6 addresses as well
            if host_ips6=$(host -t AAAA "$host" 2>/dev/null | grep "has IPv6 address" | awk '{print $5}'); then
                for ip in $host_ips6; do
                    echo "Blocking IPv6 $ip for domain $host"
                    ip6tables -t mangle -A PARTICIPANT_RULES -d "$ip" -j DROP 2>/dev/null || true
                done
            fi
        done
    }
    
    # Add restriction to force DNS usage through standard ports only
    # This prevents DNS-over-HTTPS/TLS bypasses
    iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m string --string "POST" --algo bm -j DROP 2>/dev/null || true
    iptables -t mangle -A PARTICIPANT_RULES -p udp ! --dport 53 -m udp --dport 853 -j DROP 2>/dev/null || true
    iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 853 -j DROP 2>/dev/null || true
    iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 1.1.1.1 -j DROP 2>/dev/null || true
    iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 8.8.8.8 -j DROP 2>/dev/null || true
    iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 8.8.4.4 -j DROP 2>/dev/null || true
    
    for domain in "${BLOCKED_DOMAINS[@]}"; do
        block_domain "$domain"
    done
    
    # Apply the chain only to the participant user
    iptables -t mangle -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES
    
    # Save the iptables rules
    if command_exists netfilter-persistent; then
        netfilter-persistent save
    else
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        [ -x "$(command -v ip6tables-save)" ] && ip6tables-save > /etc/iptables/rules.v6
    fi
    
    echo "Rules refreshed successfully."
    exit 0
fi

echo "=== Setting up restrictions for IUPC ==="

# ==========================================
# INTERNET RESTRICTIONS
# ==========================================

echo "Setting up internet restrictions..."

# Install required packages if not already installed
if ! command_exists iptables || ! command_exists host; then
    apt-get update
    apt-get install -y iptables iptables-persistent dnsutils
fi

# Flush existing user-specific rules
iptables -t mangle -D OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES 2>/dev/null || true
iptables -t mangle -F PARTICIPANT_RULES 2>/dev/null || true
iptables -t mangle -X PARTICIPANT_RULES 2>/dev/null || true

# Create a new chain for participant restrictions
iptables -t mangle -N PARTICIPANT_RULES 2>/dev/null || iptables -t mangle -F PARTICIPANT_RULES

# Example blocked domains - replace with your specific domains
BLOCKED_DOMAINS=(
    "facebook.com"
    "instagram.com"
    "discord.com"
    "github.com"
    "gitlab.com"
    "chat.openai.com"
)

# Add restriction to force DNS usage through standard ports only
# This prevents DNS-over-HTTPS/TLS bypasses
iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m string --string "POST" --algo bm -j DROP 2>/dev/null || true
iptables -t mangle -A PARTICIPANT_RULES -p udp ! --dport 53 -m udp --dport 853 -j DROP 2>/dev/null || true
iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 853 -j DROP 2>/dev/null || true
iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 1.1.1.1 -j DROP 2>/dev/null || true
iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 8.8.8.8 -j DROP 2>/dev/null || true
iptables -t mangle -A PARTICIPANT_RULES -p tcp ! --dport 53 -m tcp --dport 443 -d 8.8.4.4 -j DROP 2>/dev/null || true

# Function to add domain blocking rules
block_domain() {
    local domain=$1
    # Block both the domain and www subdomain
    for host in "$domain" "www.$domain"; do
        # Use host command to resolve IP addresses (handles dynamic IPs)
        if host_ips=$(host "$host" 2>/dev/null | grep "has address" | awk '{print $4}'); then
            for ip in $host_ips; then
                echo "Blocking IP $ip for domain $host"
                iptables -t mangle -A PARTICIPANT_RULES -d "$ip" -j DROP
            done
        else
            echo "Could not resolve $host, setting up DNS-based blocking"
            # Create a string match for DNS queries
            iptables -t mangle -A PARTICIPANT_RULES -p udp --dport 53 -m string --string "$host" --algo bm -j DROP
            iptables -t mangle -A PARTICIPANT_RULES -p tcp --dport 53 -m string --string "$host" --algo bm -j DROP
        fi
        
        # Check for IPv6 addresses as well
        if host_ips6=$(host -t AAAA "$host" 2>/dev/null | grep "has IPv6 address" | awk '{print $5}'); then
            for ip in $host_ips6; then
                echo "Blocking IPv6 $ip for domain $host"
                ip6tables -t mangle -A PARTICIPANT_RULES -d "$ip" -j DROP 2>/dev/null || true
            done
        fi
    done
}

# Block the specified domains
for domain in "${BLOCKED_DOMAINS[@]}"; do
    block_domain "$domain"
done

# Apply the chain only to the participant user
iptables -t mangle -A OUTPUT -m owner --uid-owner $PARTICIPANT_UID -j PARTICIPANT_RULES

# Save the iptables rules
if command_exists netfilter-persistent; then
    netfilter-persistent save
else
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    [ -x "$(command -v ip6tables-save)" ] && ip6tables-save > /etc/iptables/rules.v6
fi

# Create a systemd service to apply rules on startup and periodically refresh for dynamic IPs
cat > /etc/systemd/system/iupc-restrictions.service << EOF
[Unit]
Description=IUPC Participant Restrictions
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/restrict.sh --apply-only
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

# Create a timer to refresh rules every 30 minutes (for dynamic IP changes)
cat > /etc/systemd/system/iupc-restrictions.timer << EOF
[Unit]
Description=Run IUPC restrictions refresh periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
EOF

# ==========================================
# STORAGE DEVICE RESTRICTIONS
# ==========================================

echo "Setting up storage device restrictions..."

# Create udev rules to restrict USB and external drives for participant user
cat > /etc/udev/rules.d/99-iupc-restrictions.rules << EOF
# Prevent participant user from accessing USB storage devices
SUBSYSTEM=="block", ACTION=="add", ATTRS{removable}=="1", ENV{ID_BUS}=="usb", \
    RUN+="/bin/sh -c 'chown root:root %N; chmod 0600 %N; mkdir -p /media/blocked'"

# Create a specific rule for SD cards and other removable media
SUBSYSTEM=="block", ACTION=="add", ATTRS{removable}=="1", \
    RUN+="/bin/sh -c 'chown root:root %N; chmod 0600 %N'"
EOF

# Reload udev rules
udevadm control --reload-rules
udevadm trigger

# Set up AppArmor profile for participant user to restrict mounting
if ! command_exists apparmor_parser; then
    apt-get update
    apt-get install -y apparmor apparmor-utils
fi

# Create AppArmor profile
mkdir -p /etc/apparmor.d/
cat > /etc/apparmor.d/usr.local.bin.participant-restricted << EOF
#include <tunables/global>

profile participant-restricted {
  #include <abstractions/base>
  #include <abstractions/user-tmp>
  #include <abstractions/X>
  #include <abstractions/fonts>
  #include <abstractions/gnome>
  
  # Allow basic applications and utilities
  /usr/bin/** rmix,
  /bin/** rmix,
  /lib/** rm,
  /lib64/** rm,
  /usr/lib/** rm,
  
  # Deny access to storage devices
  deny /media/** rwlkmx,
  deny /mnt/** rwlkmx,
  
  # Allow access to home directory
  owner /home/participant/** rwlkmx,
  
  # Block access to other partitions
  deny /windows/** rwlkmx,
  deny /boot/** rwlkmx,
  deny /dev/sd* rwlkmx,
  deny /dev/hd* rwlkmx,
  deny /dev/nvme* rwlkmx,
}
EOF

# Load AppArmor profile
apparmor_parser -r /etc/apparmor.d/usr.local.bin.participant-restricted 2>/dev/null || true

# Configure PAM to apply AppArmor profile for participant
if ! grep -q "participant-restricted" /etc/pam.d/common-session; then
    echo "session optional pam_exec.so /usr/local/bin/apply-aa-profile" >> /etc/pam.d/common-session
    
    # Create the helper script
    cat > /usr/local/bin/apply-aa-profile << SCRIPT
#!/bin/bash
if [ "\$PAM_USER" = "$PARTICIPANT_USER" ]; then
    aa-exec -p participant-restricted -- "\$@"
fi
SCRIPT
    chmod +x /usr/local/bin/apply-aa-profile
fi

# Modify fstab to prevent automounting only for non-system partitions
cp /etc/fstab /etc/fstab.backup
# Safely modify only Windows/NTFS partitions, not system ones
sed -i '/ntfs/s/defaults/defaults,noauto/' /etc/fstab 2>/dev/null || true
sed -i '/windows/s/defaults/defaults,noauto/' /etc/fstab 2>/dev/null || true

# Enable and start services
systemctl daemon-reload
systemctl enable iupc-restrictions.service
systemctl enable iupc-restrictions.timer
systemctl start iupc-restrictions.service
systemctl start iupc-restrictions.timer

# Create a marker file to indicate restrictions are active
touch /etc/iupc-restrictions-active

# Create a verification function to test if restrictions are working
verify_restrictions() {
    echo "=== Verifying restrictions ==="
    
    # Test DNS blocking (will fail if blocking works)
    echo "Testing DNS blocking..."
    su - $PARTICIPANT_USER -c "host facebook.com" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "✓ DNS blocking working correctly"
    else
        echo "✗ DNS blocking may not be working"
        echo "   Additional verification recommended."
    fi
    
    # Test file permissions
    echo "Testing storage access..."
    mkdir -p /media/test_drive
    touch /media/test_drive/testfile
    su - $PARTICIPANT_USER -c "cat /media/test_drive/testfile" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "✓ Storage restrictions working correctly"
    else
        echo "✗ Storage restrictions may not be working"
        echo "   Additional verification recommended."
    fi
    rmdir /media/test_drive 2>/dev/null || true
}

verify_restrictions

echo "=== IUPC Restrictions setup complete ==="
echo "Internet restrictions: ENABLED"
echo "Storage restrictions: ENABLED"
echo "Restrictions apply only to user: $PARTICIPANT_USER"
echo "Admin user $ADMIN_USER has full access"
echo ""
echo "To remove restrictions, run: $SCRIPT_DIR/unrestrict.sh"