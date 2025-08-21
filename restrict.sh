#!/usr/bin/env bash
set -euo pipefail

# Contest Environment Restriction Script
# - Restricts user outbound traffic to whitelist-only
# - Blocks USB mass-storage mounting
# - Keeps rules persistent via systemd + timer
# - Handles reboot safely (waits for DNS, retries, uses cache)

DEFAULT_USER="participant"
RESTRICT_USER="${1:-$DEFAULT_USER}"

CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
LOCAL_WHITELIST="./whitelist.txt"

HELPER_SCRIPT="/usr/local/bin/update-contest-whitelist"
CONTEST_SERVICE="contest-restrict-$RESTRICT_USER"

echo "============================================"
echo "Contest Restriction - User: '$RESTRICT_USER' @ $(date)"
echo "============================================"

[[ $EUID -eq 0 ]] || { echo "❌ Must run as root"; exit 1; }
id "$RESTRICT_USER" >/dev/null 2>&1 || { echo "❌ User '$RESTRICT_USER' not found"; exit 1; }

# --- Step 1: Config init -----------------------------------------------------
echo "→ Preparing config at $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

if [[ ! -f "$WHITELIST_FILE" ]]; then
  if [[ -f "$LOCAL_WHITELIST" ]]; then
    cp "$LOCAL_WHITELIST" "$WHITELIST_FILE"
    echo "✅ Created $WHITELIST_FILE from local whitelist.txt"
  else
    echo "⚠️ No whitelist found. Creating default whitelist with hackerrank.com"
    echo "hackerrank.com" > "$WHITELIST_FILE"
    echo "✅ Created $WHITELIST_FILE with default entry: hackerrank.com"
  fi
else
  echo "✅ Whitelist exists at $WHITELIST_FILE"
fi

[[ -f "$DEPENDENCIES_FILE" ]] \
  && echo "✅ Optional dependencies file found" \
  || echo "⚠️  No discovered dependencies file (optional): $DEPENDENCIES_FILE"

# --- Step 2: Block USB mass-storage -----------------------------------------
echo "→ Blocking USB mass-storage"

cat > /etc/modprobe.d/contest-usb-storage-blacklist.conf <<'EOF'
# Contest: block USB mass storage
blacklist usb_storage
install usb_storage /bin/true
EOF
modprobe -r usb_storage 2>/dev/null || true

cat > /etc/polkit-1/rules.d/99-contest-block-mount.rules <<EOF
// Contest: Block mounting for $RESTRICT_USER
polkit.addRule(function(action, subject) {
  if ((action.id.indexOf("org.freedesktop.udisks2.") == 0 ||
       action.id.indexOf("org.freedesktop.UDisks2.") == 0) &&
      subject.user == "$RESTRICT_USER") {
    return polkit.Result.NO;
  }
});
EOF
echo "✅ USB mass-storage is blocked (kernel blacklisted + polkit)"

# --- Step 3: Helper that builds the whitelist chains -------------------------
echo "→ Installing helper: $HELPER_SCRIPT"
cat > "$HELPER_SCRIPT" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

DEFAULT_USER="participant"
USER="${1:-$DEFAULT_USER}"

CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"

CHAIN_OUT="CONTEST_${USER^^}_OUT"
DOMAIN_CACHE_FILE="$CONFIG_DIR/${USER}_domains_cache.txt"
IP_CACHE_FILE="$CONFIG_DIR/${USER}_ip_cache.txt"

need() { command -v "$1" >/dev/null 2>&1; }
need iptables   || (apt-get update -qq && apt-get install -y iptables)
need ip6tables  || (apt-get update -qq && apt-get install -y iptables)
need dig        || (apt-get update -qq && apt-get install -y dnsutils)

[[ -f "$WHITELIST_FILE" ]] || { echo "Error: $WHITELIST_FILE missing"; exit 1; }

ALLOWED_DNS_V4=("127.0.0.53" "127.0.0.1")
ALLOWED_DNS_V6=("::1")
if [[ -f /etc/resolv.conf ]]; then
  while read -r a b; do
    [[ "$a" == "nameserver" ]] || continue
    [[ "$b" =~ : ]] && ALLOWED_DNS_V6+=("$b") || ALLOWED_DNS_V4+=("$b")
  done < /etc/resolv.conf
fi
ALLOWED_DNS_V4=($(printf "%s\n" "${ALLOWED_DNS_V4[@]}" | sort -u))
ALLOWED_DNS_V6=($(printf "%s\n" "${ALLOWED_DNS_V6[@]}" | sort -u))

# Create/flush chains
if iptables -L "$CHAIN_OUT" -n >/dev/null 2>&1; then
  iptables -F "$CHAIN_OUT"
else
  iptables -N "$CHAIN_OUT"
fi
if ip6tables -L "$CHAIN_OUT" -n >/dev/null 2>&1; then
  ip6tables -F "$CHAIN_OUT" 2>/dev/null || true
else
  ip6tables -N "$CHAIN_OUT" 2>/dev/null || true
fi

# Defaults
iptables  -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A "$CHAIN_OUT" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
iptables  -A "$CHAIN_OUT" -d 127.0.0.0/8 -j ACCEPT
ip6tables -A "$CHAIN_OUT" -d ::1/128 -j ACCEPT 2>/dev/null || true
for ip in "${ALLOWED_DNS_V4[@]}"; do
  iptables -A "$CHAIN_OUT" -p udp -d "$ip" --dport 53 -j ACCEPT
  iptables -A "$CHAIN_OUT" -p tcp -d "$ip" --dport 53 -j ACCEPT
done
for ip in "${ALLOWED_DNS_V6[@]}"; do
  ip6tables -A "$CHAIN_OUT" -p udp -d "$ip" --dport 53 -j ACCEPT 2>/dev/null || true
  ip6tables -A "$CHAIN_OUT" -p tcp -d "$ip" --dport 53 -j ACCEPT 2>/dev/null || true
done

resolve_domain() {
  local d="$1" out=""
  out+=$(dig +short +time=2 +tries=1 "$d" A 2>/dev/null)$'\n'
  out+=$(dig +short +time=2 +tries=1 "$d" AAAA 2>/dev/null)$'\n'
  for s in www cdn static api assets; do
    out+=$(dig +short +time=2 +tries=1 "$s.$d" A 2>/dev/null)$'\n'
    out+=$(dig +short +time=2 +tries=1 "$s.$d" AAAA 2>/dev/null)$'\n'
  done
  printf "%s\n" "$out" | awk 'NF'
}

# Parse whitelist
mapfile -t domains < <(awk '
  /^[[:space:]]*#/ {next}
  /^[[:space:]]*$/ {next}
  {g=$0; sub(/^https?:\/\//,"",g); sub(/^www\./,"",g);
   sub(/\/.*$/,"",g); sub(/^\./,"",g); print tolower(g)}' "$WHITELIST_FILE" | sort -u)

# Add extra deps (skip blocked)
blocked='(google\.com|github\.com|youtube\.com|facebook\.com|twitter\.com|instagram\.com|reddit\.com|stackoverflow\.com|stackexchange\.com|discord\.com|telegram\.org|whatsapp\.com|tiktok\.com|linkedin\.com|medium\.com|wikipedia\.org|amazon\.com|microsoft\.com|apple\.com|openai\.com|chatgpt\.com|anthropic\.com|claude\.ai|gemini\.google\.com|bard\.google\.com|bing\.com|yahoo\.com|duckduckgo\.com|search\.yahoo\.com|yandex\.com|baidu\.com)'
if [[ -f "$DEPENDENCIES_FILE" ]]; then
  while read -r line; do
    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
    d="${line#http://}"; d="${d#https://}"; d="${d%%/*}"; d="${d#.}"
    d="$(printf "%s" "$d" | tr '[:upper:]' '[:lower:]')"
    [[ "$d" =~ $blocked ]] && { echo "  ↷ skip blocked dep: $d"; continue; }
    domains+=("$d")
  done < "$DEPENDENCIES_FILE"
fi

# Add useful CDNs
domains+=("cloudflare.com" "cloudfront.net" "jsdelivr.net" "unpkg.com" "jquery.com" "bootstrapcdn.com" \
           "fontawesome.com" "fonts.googleapis.com" "fonts.gstatic.com" "ajax.googleapis.com" "cdnjs.cloudflare.com" \
           "gstatic.com" "challenges.cloudflare.com" "mathjax.org" "static.cloudflareinsights.com" "hcaptcha.com" \
           "recaptcha.net" "typekit.net" "fonts.net")

mapfile -t domains < <(printf "%s\n" "${domains[@]}" | sort -u)

> "$DOMAIN_CACHE_FILE"
> "$IP_CACHE_FILE"

all_ips=""
for d in "${domains[@]}"; do
  echo "  → $d"
  echo "$d" >> "$DOMAIN_CACHE_FILE"
  ips="$(resolve_domain "$d" || true)"
  [[ -n "$ips" ]] && all_ips+="$ips"$'\n'
done

unique_ips="$(printf "%s\n" "$all_ips" | sort -u)"

if [[ -z "$unique_ips" ]]; then
  echo "⚠️ No IPs resolved. Using cached IPs if available."
  if [[ -s "$IP_CACHE_FILE" ]]; then
    unique_ips="$(cat "$IP_CACHE_FILE")"
  else
    echo "❌ No whitelist IPs available. Exiting to avoid total lockout."
    exit 1
  fi
else
  echo "$unique_ips" > "$IP_CACHE_FILE"
fi

ipv4s="$(printf "%s\n" "$unique_ips" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
ipv6s="$(printf "%s\n" "$unique_ips" | grep -E ':' || true)"

while read -r ip; do [[ -n "$ip" ]] && iptables -A "$CHAIN_OUT" -d "$ip" -j ACCEPT; done <<< "$ipv4s"
while read -r ip; do [[ -n "$ip" ]] && ip6tables -A "$CHAIN_OUT" -d "$ip" -j ACCEPT 2>/dev/null || true; done <<< "$ipv6s"

iptables  -A "$CHAIN_OUT" -j REJECT --reject-with icmp-host-unreachable
ip6tables -A "$CHAIN_OUT" -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || true

uid="$(id -u "$USER")"
iptables  -C OUTPUT -m owner --uid-owner "$uid" -j "$CHAIN_OUT" 2>/dev/null || \
  iptables  -I OUTPUT 1 -m owner --uid-owner "$uid" -j "$CHAIN_OUT"
ip6tables -C OUTPUT -m owner --uid-owner "$uid" -j "$CHAIN_OUT" 2>/dev/null || \
  ip6tables -I OUTPUT 1 -m owner --uid-owner "$uid" -j "$CHAIN_OUT" 2>/dev/null || true

echo "✔ Whitelist applied for user '$USER' (IPs: $(printf "%s\n" "$unique_ips" | wc -l))"
EOS
chmod +x "$HELPER_SCRIPT"
echo "✅ Helper installed"

# --- Step 4: systemd persistence --------------------------------------------
echo "→ Installing systemd unit + timer"

cat > "/etc/systemd/system/$CONTEST_SERVICE.service" <<EOF
[Unit]
Description=Contest Restrictions (update whitelist) for $RESTRICT_USER
Wants=network-online.target
After=network-online.target
Requires=network-online.target

[Service]
Type=oneshot
ExecStart=$HELPER_SCRIPT $RESTRICT_USER
RemainAfterExit=yes
ExecStartPost=/bin/bash -c 'for i in 1 2 3; do sleep 10; $HELPER_SCRIPT $RESTRICT_USER && break; done'

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/$CONTEST_SERVICE.timer" <<EOF
[Unit]
Description=Refresh contest whitelist for $RESTRICT_USER every 30m

[Timer]
OnBootSec=30sec
OnUnitActiveSec=30min
Unit=$CONTEST_SERVICE.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$CONTEST_SERVICE.service"
systemctl enable --now "$CONTEST_SERVICE.timer"

echo "✅ systemd persistence enabled"

echo "============================================"
echo "✅ Contest Restrictions Applied for $RESTRICT_USER"
echo "============================================"

# --- Summary -----------------------------------------------------------------
echo "============================================"
echo "✅ Contest Environment Restrictions Applied"
echo "User:        $RESTRICT_USER"
echo "Whitelist:   $WHITELIST_FILE"
echo "Deps file:   $DEPENDENCIES_FILE (optional)"
echo "DNS:         Locked to system resolvers only"
echo "USB storage: Blocked (kernel + polkit)"
echo "Persistence: systemd service+timer (30m refresh)"
echo "============================================"
