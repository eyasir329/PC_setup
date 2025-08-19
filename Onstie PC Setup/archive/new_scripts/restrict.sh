#!/usr/bin/env bash
set -euo pipefail

# Contest Environment Restriction Script
# This script restricts internet access and USB storage for contest participants
# allowing only specified domains in the whitelist

# Configuration
DEFAULT_USER="participant"
RESTRICT_USER="${1:-$DEFAULT_USER}"
CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
LOCAL_WHITELIST="whitelist.txt"
SCRIPT_DIR="/usr/local/share/contest-manager"
HELPER_SCRIPT="/usr/local/bin/update-contest-whitelist"
CHAIN_PREFIX="CONTEST"
CONTEST_SERVICE="contest-restrict-$RESTRICT_USER"

echo "============================================"
echo "Contest Environment Restriction - User: '$RESTRICT_USER'"
echo "Starting at: $(date)"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: This script must be run as root"
  exit 1
fi

# Ensure the user exists
if ! id "$RESTRICT_USER" &>/dev/null; then
  echo "❌ Error: User '$RESTRICT_USER' does not exist"
  exit 1
fi

echo "============================================"
echo "Step 1: Initialize Configuration"
echo "============================================"

# Create configuration directory
echo "→ Creating configuration directory..."
mkdir -p "$CONFIG_DIR"
if [[ $? -eq 0 ]]; then
  echo "✅ Configuration directory created: $CONFIG_DIR"
else
  echo "❌ Failed to create configuration directory" >&2
  exit 1
fi

# Check for whitelist file
echo "→ Setting up whitelist configuration..."
if [[ ! -f "$WHITELIST_FILE" && -f "$LOCAL_WHITELIST" ]]; then
  echo "→ Creating system whitelist from local whitelist.txt..."
  cp "$LOCAL_WHITELIST" "$WHITELIST_FILE"
  echo "✅ System whitelist created from local file"
elif [[ ! -f "$WHITELIST_FILE" && ! -f "$LOCAL_WHITELIST" ]]; then
  echo "❌ Error: No whitelist found. Please create whitelist.txt or $WHITELIST_FILE"
  exit 1
else
  echo "✅ Whitelist configuration found"
fi

# Add HackerRank domains to whitelist if not already present
echo "→ Ensuring HackerRank domains are in whitelist..."
HACKERRANK_DOMAINS=(
  "hackerrank.com"
  "www.hackerrank.com"
  "api.hackerrank.com"
  "cdn.hackerrank.com"
  "assets.hackerrank.com"
  "static.hackerrank.com"
  "hrcdn.net"
  "www.hrcdn.net"
)

for domain in "${HACKERRANK_DOMAINS[@]}"; do
  if ! grep -q "$domain" "$WHITELIST_FILE"; then
    echo "$domain" >> "$WHITELIST_FILE"
    echo "  ✅ Added: $domain"
  fi
done

# Check for dependency discovery results
echo "→ Checking for discovered dependencies..."
if [[ ! -f "$DEPENDENCIES_FILE" ]]; then
  echo "⚠️  Warning: No discovered dependencies found. Consider running discover-dependencies.sh first."
  echo "→ Proceeding with static dependencies only."
else
  echo "✅ Discovered dependencies found"
fi

echo "============================================"
echo "Step 2: Configure USB Storage Restrictions"
echo "============================================"

echo "→ Setting up USB storage device blocking..."

# Create udev rules to block USB storage
echo "→ Creating udev rules for USB storage blocking..."
cat > /etc/udev/rules.d/99-contest-block-usb.rules << EOL
# Contest Environment Manager: Block USB storage for $RESTRICT_USER
ACTION=="add", SUBSYSTEMS=="usb", ATTRS{bInterfaceClass}=="08", ENV{ID_USB_INTERFACE_NUM}=="*", TAG+="uaccess", TAG+="udev-acl", OWNER="root", GROUP="root"
EOL

if [[ $? -eq 0 ]]; then
  echo "✅ USB storage udev rules created"
else
  echo "❌ Failed to create USB storage udev rules" >&2
  exit 1
fi

# Create polkit rules to prevent mounting
echo "→ Creating polkit rules to prevent mounting..."
cat > /etc/polkit-1/rules.d/99-contest-block-mount.rules << EOL
// Contest Environment Manager: Block mounting for $RESTRICT_USER
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.freedesktop.udisks2.") == 0 ||
         action.id.indexOf("org.freedesktop.UDisks2.") == 0) &&
        subject.user == "$RESTRICT_USER") {
        return polkit.Result.NO;
    }
});
EOL

if [[ $? -eq 0 ]]; then
  echo "✅ Polkit mount blocking rules created"
else
  echo "❌ Failed to create polkit rules" >&2
  exit 1
fi

# Reload udev rules
echo "→ Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

if [[ $? -eq 0 ]]; then
  echo "✅ USB storage restrictions applied successfully"
else
  echo "❌ Failed to reload udev rules" >&2
  exit 1
fi

echo "============================================"
echo "Step 3: Create Network Restriction Helper Script"
echo "============================================"

echo "→ Creating IP whitelist update script..."

cat > "$HELPER_SCRIPT" << 'EOL'
#!/usr/bin/env bash
set -euo pipefail

# Configuration
DEFAULT_USER="participant"
USER="${1:-$DEFAULT_USER}"
CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
CHAIN_IN="CONTEST_${USER^^}_IN"
CHAIN_OUT="CONTEST_${USER^^}_OUT"
DOMAIN_CACHE_FILE="$CONFIG_DIR/${USER}_domains_cache.txt"
IP_CACHE_FILE="$CONFIG_DIR/${USER}_ip_cache.txt"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root"
  exit 1
fi

# Ensure fresh start by checking and recreating chains if needed
echo "Ensuring iptables chains are properly set up..."

# For IPv4
if iptables -L "$CHAIN_IN" &>/dev/null; then
  iptables -F "$CHAIN_IN"
else
  iptables -N "$CHAIN_IN"
fi

if iptables -L "$CHAIN_OUT" &>/dev/null; then
  iptables -F "$CHAIN_OUT"
else
  iptables -N "$CHAIN_OUT"
fi

# For IPv6
if ip6tables -L "$CHAIN_IN" &>/dev/null 2>/dev/null; then
  ip6tables -F "$CHAIN_IN" 2>/dev/null || true
else
  ip6tables -N "$CHAIN_IN" 2>/dev/null || true
fi

if ip6tables -L "$CHAIN_OUT" &>/dev/null 2>/dev/null; then
  ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
else
  ip6tables -N "$CHAIN_OUT" 2>/dev/null || true
fi

# Set default policies
# IPv4
iptables -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A "$CHAIN_OUT" -d 127.0.0.0/8 -j ACCEPT
iptables -A "$CHAIN_OUT" -p udp --dport 53 -j ACCEPT  # Allow DNS
iptables -A "$CHAIN_OUT" -j REJECT

# IPv6
ip6tables -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
ip6tables -A "$CHAIN_OUT" -d ::1/128 -j ACCEPT 2>/dev/null || true
ip6tables -A "$CHAIN_OUT" -p udp --dport 53 -j ACCEPT 2>/dev/null || true  # Allow DNS
ip6tables -A "$CHAIN_OUT" -j REJECT 2>/dev/null || true

# Ensure required tools are installed
missing_tools=()
if ! command -v "iptables" &>/dev/null; then
  missing_tools+=("iptables")
fi
if ! command -v "ip6tables" &>/dev/null; then
  missing_tools+=("iptables")  # ip6tables is part of iptables package
fi
if ! command -v "dig" &>/dev/null || ! command -v "host" &>/dev/null; then
  missing_tools+=("dnsutils")
fi

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Installing required tools: ${missing_tools[*]}"
  apt-get update -qq
  apt-get install -y "${missing_tools[@]}"
  echo "Tools installed successfully"
fi

# Functions to resolve domains (faster version)
resolve_domain() {
  local domain="$1"
  
  # Use dig with timeout and simplified output
  dig +short +time=2 +tries=1 "$domain" A "$domain" AAAA 2>/dev/null | grep -E '^[0-9]+\.|^[0-9a-f]*:' || true
  
  # Try common subdomains for contest platforms - extremely important for functionality
  for subdomain in "www.$domain" "cdn.$domain" "static.$domain" "api.$domain" "assets.$domain"; do
    dig +short +time=2 +tries=1 "$subdomain" A "$subdomain" AAAA 2>/dev/null | grep -E '^[0-9]+\.|^[0-9a-f]*:' || true
  done
}

# Check if chains exist, create them if not
ensure_chains() {
  # IPv4 chains
  if ! iptables -L "$CHAIN_IN" &>/dev/null; then
    iptables -N "$CHAIN_IN" || true
  fi
  
  if ! iptables -L "$CHAIN_OUT" &>/dev/null; then
    iptables -N "$CHAIN_OUT" || true
  fi
  
  # IPv6 chains
  if ! ip6tables -L "$CHAIN_IN" &>/dev/null; then
    ip6tables -N "$CHAIN_IN" || true
  fi
  
  if ! ip6tables -L "$CHAIN_OUT" &>/dev/null; then
    ip6tables -N "$CHAIN_OUT" || true
  fi
}

# Clear existing IP rules but preserve the chain structure
clear_chain() {
  local chain="$1"
  # Flush both IPv4 and IPv6 chains but don't delete them
  iptables -F "$chain" 2>/dev/null || true
  ip6tables -F "$chain" 2>/dev/null || true
}

# Batch add IPs to reduce iptables calls
add_ips_to_chain() {
  local chain="$1"
  local ip_list="$2"
  
  # Process IPv4 and IPv6 addresses separately for efficiency
  local ipv4_list=$(echo "$ip_list" | grep -E '^[0-9]+\.' | head -20 || true)  # Limit to 20 IPs per domain
  local ipv6_list=$(echo "$ip_list" | grep -E '^[0-9a-f]*:' | head -20 || true)
  
  # Add IPv4 addresses
  for ip in $ipv4_list; do
    iptables -A "$chain" -d "$ip" -j ACCEPT 2>/dev/null || true
  done
  
  # Add IPv6 addresses
  for ip in $ipv6_list; do
    ip6tables -A "$chain" -d "$ip" -j ACCEPT 2>/dev/null || true
  done
}

# Check if whitelist file exists
if [[ ! -f "$WHITELIST_FILE" ]]; then
  echo "Error: Whitelist file not found at $WHITELIST_FILE"
  exit 1
fi

# Ensure the chains exist
ensure_chains

# Clear existing IP rules
clear_chain "$CHAIN_OUT"

# Set default policies for IPv4
iptables -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A "$CHAIN_OUT" -d 127.0.0.0/8 -j ACCEPT
iptables -A "$CHAIN_OUT" -p udp --dport 53 -j ACCEPT  # Allow DNS

# Set default policies for IPv6
ip6tables -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
ip6tables -A "$CHAIN_OUT" -d ::1/128 -j ACCEPT 2>/dev/null || true
ip6tables -A "$CHAIN_OUT" -p udp --dport 53 -j ACCEPT 2>/dev/null || true  # Allow DNS

# Track processed domains to avoid duplicates
> "$DOMAIN_CACHE_FILE"
> "$IP_CACHE_FILE"

# Process whitelist
echo "Updating whitelist IPs for user '$USER'..."

# Collect all domains first
all_domains=()
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  
  # Clean up domain name
  domain="${line#.}"
  domain="${domain#http://}"
  domain="${domain#https://}"
  domain="${domain%%/*}"
  
  all_domains+=("$domain")
done < "$WHITELIST_FILE"

# Process all domains efficiently
> "$DOMAIN_CACHE_FILE"
> "$IP_CACHE_FILE"
all_ips=""

echo "Processing ${#all_domains[@]} whitelist domains..."
for domain in "${all_domains[@]}"; do
  echo "  → $domain"
  echo "$domain" >> "$DOMAIN_CACHE_FILE"
  
  # Get IPs for main domain and common subdomains
  for subdomain_prefix in "" "www." "api." "cdn."; do
    if [[ -n "$subdomain_prefix" ]]; then
      target_domain="${subdomain_prefix}${domain}"
    else
      target_domain="$domain"
    fi
    
    domain_ips=$(resolve_domain "$target_domain")
    if [[ -n "$domain_ips" ]]; then
      all_ips+="$domain_ips"$'\n'
    fi
  done
done

# Remove duplicates and add to cache
unique_ips=$(echo "$all_ips" | sort -u | grep -v "^$" || true)
echo "$unique_ips" >> "$IP_CACHE_FILE"

# Add IPs to iptables in batches
echo "Adding $(echo "$unique_ips" | wc -l) unique IP addresses to firewall..."
add_ips_to_chain "$CHAIN_OUT" "$unique_ips"

# Process discovered dependencies if available
if [[ -f "$DEPENDENCIES_FILE" ]]; then
  echo "Processing discovered dependencies..."
  
  # Define blocked domains as a safety check
  blocked_domains="google\.com|github\.com|youtube\.com|facebook\.com|twitter\.com|instagram\.com|reddit\.com|stackoverflow\.com|stackexchange\.com|discord\.com|telegram\.org|whatsapp\.com|tiktok\.com|linkedin\.com|medium\.com|wikipedia\.org|amazon\.com|microsoft\.com|apple\.com|openai\.com|chatgpt\.com|anthropic\.com|claude\.ai|gemini\.google\.com|bard\.google\.com|bing\.com|yahoo\.com|duckduckgo\.com|search\.yahoo\.com|yandex\.com|baidu\.com"
  
  # Collect dependency domains
  dep_domains=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Clean up domain name
    domain="${line#.}"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    
    # Additional safety check - skip blocked domains
    if echo "$domain" | grep -qE "($blocked_domains)"; then
      echo "  ⚠️  Skipping blocked domain: $domain"
      continue
    fi
    
    # Skip if already processed
    if grep -q "^$domain$" "$DOMAIN_CACHE_FILE"; then
      continue
    fi
    
    dep_domains+=("$domain")
  done < "$DEPENDENCIES_FILE"
  
  # Process dependency domains efficiently
  dep_ips=""
  echo "Processing ${#dep_domains[@]} dependency domains..."
  for domain in "${dep_domains[@]}"; do
    echo "  → $domain"
    echo "$domain" >> "$DOMAIN_CACHE_FILE"
    
    domain_ips=$(resolve_domain "$domain")
    if [[ -n "$domain_ips" ]]; then
      dep_ips+="$domain_ips"$'\n'
    fi
  done
  
  # Add dependency IPs
  if [[ -n "$dep_ips" ]]; then
    unique_dep_ips=$(echo "$dep_ips" | sort -u | grep -v "^$" || true)
    echo "$unique_dep_ips" >> "$IP_CACHE_FILE"
    echo "Adding $(echo "$unique_dep_ips" | wc -l) dependency IP addresses..."
    add_ips_to_chain "$CHAIN_OUT" "$unique_dep_ips"
  fi
fi

# Add essential CDNs and dependencies
common_cdns=(
  "cloudflare.com"
  "cloudfront.net"
  "jsdelivr.net"
  "unpkg.com"
  "jquery.com"
  "bootstrapcdn.com"
  "fontawesome.com"
  "fonts.googleapis.com"
  "fonts.gstatic.com"
  "ajax.googleapis.com"
  "cdnjs.cloudflare.com"
  "gstatic.com"
  "challenges.cloudflare.com"
  "mathjax.org"
  "cdn.mathjax.org"
  "static.cloudflareinsights.com"
  "hcaptcha.com"
  "recaptcha.net"
  "typekit.net"
  "fonts.net"
  "hackerrank.com"
  "www.hackerrank.com"
  "api.hackerrank.com"
  "assets.hackerrank.com"
  "static.hackerrank.com"
  "fonts.googleapis.com"   # already included, needed by HackerRank
  "fonts.gstatic.com"     # already included
  "cdnjs.cloudflare.com"  # already included
  "stackblitz.io"         # sometimes used in embedded coding exercises
  "unpkg.com"             # already included
  "code.jquery.com"       # some challenge pages use jQuery CDN
)

echo "Adding essential CDN IPs..."
cdn_ips=""
for cdn in "${common_cdns[@]}"; do
  # Skip if already processed
  if grep -q "^$cdn$" "$DOMAIN_CACHE_FILE"; then
    continue
  fi
  
  echo "  → $cdn"
  echo "$cdn" >> "$DOMAIN_CACHE_FILE"
  
  domain_ips=$(resolve_domain "$cdn")
  if [[ -n "$domain_ips" ]]; then
    cdn_ips+="$domain_ips"$'\n'
  fi
done

# Add CDN IPs
if [[ -n "$cdn_ips" ]]; then
  unique_cdn_ips=$(echo "$cdn_ips" | sort -u | grep -v "^$" || true)
  echo "$unique_cdn_ips" >> "$IP_CACHE_FILE"
  echo "Adding $(echo "$unique_cdn_ips" | wc -l) CDN IP addresses..."
  add_ips_to_chain "$CHAIN_OUT" "$unique_cdn_ips"
fi

# Set default deny at the end
iptables -A "$CHAIN_OUT" -j REJECT --reject-with icmp-host-unreachable
ip6tables -A "$CHAIN_OUT" -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || true

echo "Whitelist IPs updated successfully for user '$USER'"
EOL

# Make the script executable
chmod +x "$HELPER_SCRIPT"

if [[ $? -eq 0 ]]; then
  echo "✅ Network restriction helper script created successfully"
else
  echo "❌ Failed to create helper script" >&2
  exit 1
fi

echo "============================================"
echo "Step 4: Configure Network Restrictions"
echo "============================================"

echo "→ Setting up firewall restrictions for $RESTRICT_USER..."

# Define chains for the specific user
CHAIN_IN="CONTEST_${RESTRICT_USER^^}_IN"
CHAIN_OUT="CONTEST_${RESTRICT_USER^^}_OUT"

# Get user UID
USER_UID=$(id -u "$RESTRICT_USER")

echo "→ Clearing any existing firewall rules for $RESTRICT_USER..."

# Remove existing IPv4 rules in OUTPUT chain if any
iptables -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null || true

# Remove existing IPv6 rules in OUTPUT chain if any
ip6tables -D OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null || true

# Delete the chains if they exist to ensure a completely fresh start
iptables -F "$CHAIN_IN" 2>/dev/null || true
iptables -X "$CHAIN_IN" 2>/dev/null || true
iptables -F "$CHAIN_OUT" 2>/dev/null || true
iptables -X "$CHAIN_OUT" 2>/dev/null || true

# Same for IPv6
ip6tables -F "$CHAIN_IN" 2>/dev/null || true
ip6tables -X "$CHAIN_IN" 2>/dev/null || true
ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
ip6tables -X "$CHAIN_OUT" 2>/dev/null || true

echo "✅ Existing firewall rules cleared"

echo "→ Creating new chains for contest restrictions..."
# Create new chains
iptables -N "$CHAIN_IN"
iptables -N "$CHAIN_OUT"
ip6tables -N "$CHAIN_IN" 2>/dev/null || true
ip6tables -N "$CHAIN_OUT" 2>/dev/null || true

if [[ $? -eq 0 ]]; then
  echo "✅ Iptables chains created"
else
  echo "❌ Failed to create iptables chains" >&2
  exit 1
fi

# Update whitelist FIRST (before applying jump rules)
echo "→ Initializing whitelist IP addresses..."
"$HELPER_SCRIPT" "$RESTRICT_USER"

if [[ $? -eq 0 ]]; then
  echo "✅ Initial whitelist update completed"
else
  echo "❌ Failed to update whitelist" >&2
  exit 1
fi

# Create user-specific filter rules AFTER populating the chains
echo "→ Applying user-specific firewall rules..."

# Add new IPv4 rules (only OUTPUT chain - INPUT chain with owner module doesn't work)
iptables -A OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT"

# Add new IPv6 rules (only OUTPUT chain)
ip6tables -A OUTPUT -m owner --uid-owner "$USER_UID" -j "$CHAIN_OUT" 2>/dev/null || echo "  Warning: IPv6 rules not applied (ip6tables may not be available)"

if [[ $? -eq 0 ]]; then
  echo "✅ Firewall rules applied successfully"
else
  echo "❌ Failed to apply firewall rules" >&2
  exit 1
fi

echo "============================================"
echo "Step 5: Configure systemd services"
echo "============================================"

# Whitelist service (applies after network is up)
cat > "/etc/systemd/system/${CONTEST_SERVICE}.service" << EOL
[Unit]
Description=Contest Environment Restrictions for $RESTRICT_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-contest-whitelist $RESTRICT_USER
RemainAfterExit=yes
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOL

# Timer for periodic refresh
cat > "/etc/systemd/system/${CONTEST_SERVICE}.timer" << EOL
[Unit]
Description=Periodically update contest whitelist IPs for $RESTRICT_USER

[Timer]
OnBootSec=1min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
EOL

echo "→ Enabling and starting systemd services..."
systemctl daemon-reload
systemctl enable --now "${CONTEST_SERVICE}.service"
systemctl enable --now "${CONTEST_SERVICE}.timer"

if [[ $? -eq 0 ]]; then
  echo "✅ Persistence services configured and started"
else
  echo "❌ Failed to configure persistence services" >&2
  exit 1
fi

echo "============================================"
echo "✅ Contest Environment Restrictions Applied Successfully!"
echo "============================================"

echo "Summary:"
echo "→ User: '$RESTRICT_USER'"
echo "→ Internet access: Limited to whitelisted domains only"
echo "→ USB storage devices: Blocked (keyboards/mice still work)"
echo "→ Persistence: Enabled (survives reboots)"
echo "→ Auto-updates: IP addresses refresh every 30 minutes"
echo "→ HackerRank domains: Added to whitelist"
echo "→ Completed at: $(date)"

echo "============================================"