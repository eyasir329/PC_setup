#!/bin/bash

# Use RESTRICT_USER if set, otherwise default to "participant"
USER="${RESTRICT_USER:-${1:-participant}}"

# Configuration
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
WHITELIST_FILE="$SCRIPT_DIR/whitelist.txt"
SYSTEM_WHITELIST="/usr/local/etc/contest-restriction/allowed.txt"
IP_CACHE_DIR="/var/cache/contest-restriction"
IP_CACHE_FILE="$IP_CACHE_DIR/resolved-ips.txt"
UPDATE_SCRIPT="/usr/local/bin/update-contest-whitelist"
SYSTEMD_SERVICE="contest-restrict-$USER.service"
CRON_JOB="/etc/cron.d/contest-whitelist-updater"
USB_RULES="/etc/udev/rules.d/99-contest-usb-block.rules"
POLKIT_RULES="/etc/polkit-1/rules.d/99-contest-block-mount.rules"

echo "============================================"
echo "Starting Internet Restriction Setup for user '$USER': $(date)"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root." >&2
    exit 1
fi

# Step 1: Set up directory structure
echo "============================================"
echo "Step 1: Setting up directory structure"
echo "============================================"

# Create necessary directories
echo "→ Creating configuration directories..."
mkdir -p "$(dirname "$SYSTEM_WHITELIST")"
mkdir -p "$IP_CACHE_DIR"

# Handle whitelist file
if [ -f "$WHITELIST_FILE" ]; then
    # Local whitelist.txt exists - copy it to system location
    echo "→ Copying local whitelist.txt to system location..."
    cp "$WHITELIST_FILE" "$SYSTEM_WHITELIST"
    echo "✅ Local whitelist copied successfully."
elif [ -f "$SYSTEM_WHITELIST" ]; then
    # System whitelist already exists
    echo "→ Using existing system whitelist at $SYSTEM_WHITELIST"
    echo "✅ System whitelist found."
else
    # Neither whitelist exists - create a default one
    echo "→ No whitelist found. Creating a default whitelist..."
    cat > "$SYSTEM_WHITELIST" << EOF
# Default contest platforms whitelist
# Add more domains as needed using: sudo cmanager add domain.com
codeforces.com
codechef.com
vjudge.net
atcoder.jp
hackerrank.com
hackerearth.com
topcoder.com
spoj.com
lightoj.com
onlinejudge.org
uva.onlinejudge.org
cses.fi
EOF
    echo "✅ Default whitelist created successfully."
fi

# Step 2: Create IP resolution script
echo "============================================"
echo "Step 2: Creating IP resolution helper script"
echo "============================================"

echo "→ Creating whitelist update script..."
cat > "$UPDATE_SCRIPT" << 'EOF'
#!/bin/bash

# Configuration
WHITELIST="/usr/local/etc/contest-restriction/allowed.txt"
IP_CACHE_DIR="/var/cache/contest-restriction"
IP_CACHE_FILE="$IP_CACHE_DIR/resolved-ips.txt"
TEMP_IP_FILE="$IP_CACHE_DIR/temp-ips.txt"
LOG_FILE="/var/log/contest-restriction.log"

# Ensure directory exists
mkdir -p "$IP_CACHE_DIR"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_message "This script must be run as root."
    exit 1
fi

# Check if whitelist exists
if [ ! -f "$WHITELIST" ]; then
    log_message "Whitelist file not found at $WHITELIST"
    exit 1
fi

log_message "Starting IP resolution process..."

# Clear temporary file
> "$TEMP_IP_FILE"

# Read whitelist and resolve IPs
while read -r domain || [ -n "$domain" ]; do
    # Skip comments and empty lines
    [[ "$domain" =~ ^#.*$ ]] && continue
    [[ -z "$domain" ]] && continue
    
    log_message "Resolving IPs for domain: $domain"
    
    # Resolve IPv4 addresses
    ipv4s=$(dig +short A "$domain" 2>/dev/null)
    if [ -n "$ipv4s" ]; then
        for ip in $ipv4s; do
            echo "IPv4 $domain $ip" >> "$TEMP_IP_FILE"
        done
    fi
    
    # Resolve www subdomain if it exists
    ipv4s=$(dig +short A "www.$domain" 2>/dev/null)
    if [ -n "$ipv4s" ]; then
        for ip in $ipv4s; do
            echo "IPv4 www.$domain $ip" >> "$TEMP_IP_FILE"
        done
    fi
    
    # Resolve common subdomains
    for subdomain in api cdn static assets; do
        ipv4s=$(dig +short A "$subdomain.$domain" 2>/dev/null)
        if [ -n "$ipv4s" ]; then
            for ip in $ipv4s; do
                echo "IPv4 $subdomain.$domain $ip" >> "$TEMP_IP_FILE"
            done
        fi
    done
    
    # Resolve IPv6 addresses
    ipv6s=$(dig +short AAAA "$domain" 2>/dev/null)
    if [ -n "$ipv6s" ]; then
        for ip in $ipv6s; do
            echo "IPv6 $domain $ip" >> "$TEMP_IP_FILE"
        done
    fi
    
    # Sleep briefly to avoid overwhelming DNS servers
    sleep 0.5
done < "$WHITELIST"

# Check if we resolved any IPs
if [ ! -s "$TEMP_IP_FILE" ]; then
    log_message "Warning: No IP addresses were resolved. Check network connectivity."
    exit 1
fi

# Update the main IP cache file
mv "$TEMP_IP_FILE" "$IP_CACHE_FILE"
chmod 644 "$IP_CACHE_FILE"

# Update iptables rules for all restricted users
for service in /etc/systemd/system/contest-restrict-*.service; do
    if [ -f "$service" ]; then
        username=$(basename "$service" | cut -d'-' -f3 | cut -d'.' -f1)
        log_message "Updating iptables rules for user: $username"
        
        # Extract user ID
        user_id=$(id -u "$username" 2>/dev/null)
        if [ -z "$user_id" ]; then
            log_message "Warning: User $username not found, skipping."
            continue
        fi
        
        # Flush existing rules for user
        iptables -D OUTPUT -m owner --uid-owner "$user_id" -j "CONTEST_${username^^}_OUT" 2>/dev/null || true
        iptables -F "CONTEST_${username^^}_OUT" 2>/dev/null || true
        iptables -X "CONTEST_${username^^}_OUT" 2>/dev/null || true
        
        # Create new chain
        iptables -N "CONTEST_${username^^}_OUT"
        
        # Allow established connections
        iptables -A "CONTEST_${username^^}_OUT" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        
        # Allow DNS (needed to resolve domains)
        iptables -A "CONTEST_${username^^}_OUT" -p udp --dport 53 -j ACCEPT
        iptables -A "CONTEST_${username^^}_OUT" -p tcp --dport 53 -j ACCEPT
        
        # Allow loopback
        iptables -A "CONTEST_${username^^}_OUT" -o lo -j ACCEPT
        
        # Allow access to whitelisted IPs
        while read -r line; do
            ip_type=$(echo "$line" | awk '{print $1}')
            domain=$(echo "$line" | awk '{print $2}')
            ip=$(echo "$line" | awk '{print $3}')
            
            if [ "$ip_type" = "IPv4" ]; then
                iptables -A "CONTEST_${username^^}_OUT" -d "$ip" -j ACCEPT
            elif [ "$ip_type" = "IPv6" ]; then
                ip6tables -A "CONTEST_${username^^}_OUT" -d "$ip" -j ACCEPT 2>/dev/null || true
            fi
        done < "$IP_CACHE_FILE"
        
        # Default deny
        iptables -A "CONTEST_${username^^}_OUT" -j REJECT
        ip6tables -A "CONTEST_${username^^}_OUT" -j REJECT 2>/dev/null || true
        
        # Apply the chain to the user's traffic
        iptables -A OUTPUT -m owner --uid-owner "$user_id" -j "CONTEST_${username^^}_OUT"
        ip6tables -A OUTPUT -m owner --uid-owner "$user_id" -j "CONTEST_${username^^}_OUT" 2>/dev/null || true
    fi
done

log_message "IP resolution and firewall update completed successfully."
exit 0
EOF

# Make the script executable
chmod +x "$UPDATE_SCRIPT"
echo "✅ Update script created successfully."

# Step 3: Set up iptables rules
echo "============================================"
echo "Step 3: Setting up iptables rules"
echo "============================================"

echo "→ Installing required packages..."
apt-get update
apt-get install -y iptables iptables-persistent dnsutils udev

# Get the user's UID
USER_ID=$(id -u "$USER" 2>/dev/null)
if [ -z "$USER_ID" ]; then
    echo "❌ Error: User $USER does not exist!" >&2
    exit 1
fi

echo "→ Configuring iptables for user $USER (UID: $USER_ID)..."

# Create a custom chain for the user
iptables -F "CONTEST_${USER^^}_OUT" 2>/dev/null || true
iptables -X "CONTEST_${USER^^}_OUT" 2>/dev/null || true
iptables -N "CONTEST_${USER^^}_OUT"

# Set default policy: drop all outgoing traffic for the user
iptables -A "CONTEST_${USER^^}_OUT" -j REJECT

# Add the user's traffic to the custom chain
iptables -D OUTPUT -m owner --uid-owner "$USER_ID" -j "CONTEST_${USER^^}_OUT" 2>/dev/null || true
iptables -A OUTPUT -m owner --uid-owner "$USER_ID" -j "CONTEST_${USER^^}_OUT"

# Save iptables rules
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
else
    echo "→ netfilter-persistent not found, installing..."
    apt-get install -y iptables-persistent
    netfilter-persistent save
fi

echo "✅ Base iptables configuration completed."

# Step 4: Create the systemd service for update script
echo "============================================"
echo "Step 4: Setting up systemd service"
echo "============================================"

echo "→ Creating systemd service..."
cat > "/etc/systemd/system/$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Internet restrictions for user $USER
After=network.target

[Service]
Type=oneshot
ExecStart=$UPDATE_SCRIPT
RemainAfterExit=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable "$SYSTEMD_SERVICE"
systemctl start "$SYSTEMD_SERVICE"

if systemctl is-active "$SYSTEMD_SERVICE" &>/dev/null; then
    echo "✅ Systemd service started successfully."
else
    echo "❌ Failed to start systemd service." >&2
    exit 1
fi

# Step 5: Set up cron job for regular updates
echo "============================================"
echo "Step 5: Setting up scheduled updates"
echo "============================================"

echo "→ Creating cron job for IP updates..."
cat > "$CRON_JOB" << EOF
# Update whitelisted IP addresses every 15 minutes
*/15 * * * * root $UPDATE_SCRIPT >/dev/null 2>&1
EOF

chmod 644 "$CRON_JOB"
echo "✅ Cron job created successfully."

# Step 6: Block USB storage devices
echo "============================================"
echo "Step 6: Blocking USB storage devices"
echo "============================================"

echo "→ Creating udev rules to block USB storage..."
cat > "$USB_RULES" << 'EOF'
# Block USB storage devices
ACTION=="add", SUBSYSTEMS=="usb", SUBSYSTEM=="block", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}!="046d", ATTR{idProduct}!="c52b", ENV{ID_USB_DRIVER}=="usb-storage", RUN+="/bin/sh -c 'echo 0 > /sys/$DEVPATH/authorized'"

# Allow USB hub, keyboard, mouse, etc.
SUBSYSTEM=="usb", ATTRS{bInterfaceClass}=="03", TAG+="contest_allowed_usb"
SUBSYSTEM=="usb", ATTRS{bInterfaceClass}=="09", TAG+="contest_allowed_usb"
SUBSYSTEM=="usb", ATTRS{bInterfaceClass}=="01", ATTRS{bInterfaceSubClass}=="01", TAG-="contest_allowed_usb"
EOF

chmod 644 "$USB_RULES"
echo "✅ USB blocking rules created."

# Step 7: Block mounting of external devices via polkit
echo "============================================"
echo "Step 7: Blocking device mounting"
echo "============================================"

echo "→ Creating polkit rules to prevent mounting..."
cat > "$POLKIT_RULES" << EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.encrypted-unlock" ||
         action.id == "org.freedesktop.udisks2.eject-media") &&
        subject.user == "$USER") {
        return polkit.Result.NO;
    }
});
EOF

chmod 644 "$POLKIT_RULES"
echo "✅ Polkit rules created."

# Step 8: Reload rules and services
echo "============================================"
echo "Step 8: Applying all rules"
echo "============================================"

# Run the update script to resolve IPs and apply iptables rules
echo "→ Running initial IP resolution and applying rules..."
"$UPDATE_SCRIPT"

# Reload udev rules
echo "→ Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo "✅ All rules applied successfully."

# Step 9: Apply the rules immediately
echo "============================================"
echo "Step 9: Testing configuration"
echo "============================================"

echo "→ Testing internet restrictions..."
sudo -u "$USER" curl -s --connect-timeout 5 google.com >/dev/null
if [ $? -ne 0 ]; then
    echo "✅ General internet access is blocked for $USER."
else
    echo "❌ Warning: General internet access is still available for $USER."
fi

# Test allowed domains
for domain in $(grep -v "^#" "$SYSTEM_WHITELIST" | grep -v "^$"); do
    echo "→ Testing access to $domain..."
    sudo -u "$USER" curl -s --connect-timeout 5 "https://$domain" >/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Access to $domain is allowed."
    else
        echo "⚠️ Access to $domain might be restricted. This could be due to IP resolution delay or site unavailability."
    fi
    sleep 1
done

# Final message
echo "============================================"
echo "✅ Internet restrictions successfully set up for user $USER!"
echo "✅ USB storage devices blocked for user $USER!"
echo "✅ Allowed domains: $(grep -v "^#" "$SYSTEM_WHITELIST" | grep -v "^$" | tr '\n' ' ')"
echo "============================================"
echo ""
echo "To verify restrictions are working:"
echo "1. Log in as $USER"
echo "2. Try to access a non-whitelisted website"
echo "3. Try to access a whitelisted website"
echo "4. Try to plug in a USB storage device"
echo "============================================"
