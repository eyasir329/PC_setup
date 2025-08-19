#!/usr/bin/env bash
set -uo pipefail

# Contest Platform Dependency Discovery Tool
# Discovers external domain dependencies for contest platforms
# Supports both IPv4 and IPv6 network traffic

# Configuration
CONFIG_DIR="/usr/local/etc/contest-restriction"
WHITELIST_FILE="$CONFIG_DIR/whitelist.txt"
LOCAL_WHITELIST="whitelist.txt"
DEPENDENCIES_FILE="$CONFIG_DIR/dependencies.txt"
TEMP_DIR=$(mktemp -d)
BROWSER_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

echo "============================================"
echo "Contest Platform Dependency Discovery Tool"
echo "Starting at: $(date)"
echo "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Error: This script must be run as root"
  echo "   Reason: Required to install packages and access system directories"
  exit 1
fi

echo "============================================"
echo "Step 1: Install Required Tools"
echo "============================================"

install_requirements() {
  echo "→ Checking for required tools..."
  local missing_tools=()
  if ! command -v curl &>/dev/null; then missing_tools+=("curl"); fi
  if ! command -v tcpdump &>/dev/null; then missing_tools+=("tcpdump"); fi
  if ! command -v nslookup &>/dev/null; then missing_tools+=("dnsutils"); fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo "→ Installing missing tools: ${missing_tools[*]}"
    if apt-get update -qq 2>/dev/null && apt-get install -y "${missing_tools[@]}" 2>/dev/null; then
      echo "✅ All required tools installed successfully"
    else
      echo "❌ Failed to install some tools - continuing anyway"
    fi
  else
    echo "✅ All required tools are already installed"
  fi
}

find_whitelist() {
  if [[ -f "$WHITELIST_FILE" ]]; then
    echo "$WHITELIST_FILE"
  elif [[ -f "$LOCAL_WHITELIST" ]]; then
    echo "$LOCAL_WHITELIST"
  else
    echo "❌ Error: No whitelist found" >&2
    exit 1
  fi
}

discover_dependencies() {
  local domain="$1"
  echo "   🔍 Analyzing $domain..."

  local capture_file="$TEMP_DIR/${domain}_traffic.txt"

  echo "      → Starting network capture (IPv4 + IPv6)..."
  timeout 30s tcpdump -i any -n port 53 or port 80 or port 443 2>/dev/null | \
    grep -oE '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)|([0-9a-fA-F:]+:[0-9a-fA-F:]+)' | \
    sort -u > "$capture_file" &
  local tcpdump_pid=$!
  sleep 2

  echo "      → Fetching $domain..."
  local html_file="$TEMP_DIR/${domain}_page.html"
  if curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "https://$domain" > "$html_file" 2>/dev/null || \
     curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "http://$domain" >> "$html_file" 2>/dev/null; then
    extract_dependencies "$html_file" "$domain"
  else
    echo "         ⚠️ Could not fetch $domain, trying with www prefix..."
    if curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "https://www.$domain" > "$html_file" 2>/dev/null || \
       curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "http://www.$domain" >> "$html_file" 2>/dev/null; then
      echo "www.$domain" >> "$TEMP_DIR/all_dependencies.txt"
      extract_dependencies "$html_file" "$domain"
    fi
  fi

  kill $tcpdump_pid 2>/dev/null
  wait $tcpdump_pid 2>/dev/null || true

  if [[ -s "$capture_file" ]]; then
    echo "      → Processing network traffic..."
    while read -r ip; do
      timeout 2s nslookup "$ip" 2>/dev/null | awk '/name =/ {print $4}' | sed 's/\.$//' || true
    done < "$capture_file" | grep '\.' | grep -v "^$domain$" | grep -v "^www.$domain$" | sort -u >> "$TEMP_DIR/all_dependencies.txt"
  fi

  echo "      ✅ Analysis completed"
  return 0
}

extract_dependencies() {
  local html_file="$1"
  local domain="$2"
  {
    grep -oE "https?://[^/\"']*\.$domain[^/\"']*" "$html_file" | sed 's|^https\?://||' | cut -d'/' -f1
    grep -oE "https?://[^/\"']*$domain[^/\"']*" "$html_file" | sed 's|^https\?://||' | cut -d'/' -f1
    grep -oE '[a-zA-Z0-9.\-]*\.(cloudflare|cloudfront|jsdelivr|unpkg|bootstrapcdn|fontawesome)\.com' "$html_file"
    grep -oE '[a-zA-Z0-9.-]*\.(typekit|fonts)\.net' "$html_file"
    grep -oE 'fonts\.(googleapis|gstatic)\.com' "$html_file"
    grep -oE 'ajax\.googleapis\.com' "$html_file"
    grep -oE 'static\.cloudflareinsights\.com' "$html_file"
    echo "fonts.googleapis.com"
    echo "snap.licdn.com"
    echo "cdn.jsdelivr.net"
    echo "lib.baomitu.com"
    echo "media.hackerearth.com"
    echo "recaptcha.net"
    grep -oE '[a-zA-Z0-9.-]*\.mathjax\.org' "$html_file"
    grep -oE 'cdnjs\.cloudflare\.com' "$html_file"
    grep -oE 'challenges\.cloudflare\.com' "$html_file"
    grep -oE 'hcaptcha\.com' "$html_file"
    grep -oE 'recaptcha\.net' "$html_file"
    grep -oE 'gstatic\.com' "$html_file"
    grep -oE 'src="https?://[^"]*"' "$html_file" | sed -E 's/src="https?:\/\/([^\/"]*)\/.*"/\1/' | grep -v -E '^(www\.)?(google|youtube|facebook|twitter)\.com$'
  } | grep -v "^$domain$" | grep '\.' | sort -u >> "$TEMP_DIR/all_dependencies.txt"
}

cleanup() {
  [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

main() {
  install_requirements
  echo "→ Creating configuration directory..."
  mkdir -p "$CONFIG_DIR" || { echo "❌ Failed to create $CONFIG_DIR"; exit 1; }
  local whitelist
  whitelist=$(find_whitelist)
  echo "✅ Using whitelist: $whitelist"

  > "$TEMP_DIR/all_dependencies.txt"

  local total=$(grep -c -v "^[[:space:]]*#\|^[[:space:]]*$" "$whitelist" || echo 0)
  [[ $total -eq 0 ]] && { echo "❌ Error: No valid domains found"; exit 1; }

  local count=0 successful=0 failed=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    count=$((count + 1))
    domain="${line#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
    if discover_dependencies "$domain"; then successful=$((successful + 1)); else failed=$((failed + 1)); fi
  done < "$whitelist"

  echo ""
  echo "📊 Summary: total=$total success=$successful failed=$failed"

  if [[ -s "$TEMP_DIR/all_dependencies.txt" ]]; then
    sort -u "$TEMP_DIR/all_dependencies.txt" > "$TEMP_DIR/unique_deps.txt"
    raw_count=$(wc -l < "$TEMP_DIR/unique_deps.txt")
    echo "✅ Found $raw_count unique domains before filtering"

    # Always-allowed critical domains
    {
      echo "fonts.googleapis.com"
      echo "snap.licdn.com"
      echo "cdn.jsdelivr.net"
      echo "lib.baomitu.com"
      echo "media.hackerearth.com"
      echo "recaptcha.net"
      echo "gstatic.com"
      echo "www.google.com"
      echo "www.gstatic.com"
      sed 's/^/www./' "$whitelist"
      cat "$whitelist"
    } > "$TEMP_DIR/critical_domains.txt"

    # Build platform regex
    local platform_pattern
    platform_pattern=$(sed 's/^/\\.|/;s/$/|/' "$whitelist" | tr -d '\n' | sed 's/|$//')

    # Merge
    {
      cat "$TEMP_DIR/critical_domains.txt"
      grep -E "($platform_pattern)" "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.(cloudflare|cloudfront|jsdelivr|unpkg|bootstrapcdn|fontawesome)\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.mathjax\.org$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E 'cdnjs\.cloudflare\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E 'static\.cloudflareinsights\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '^fonts\.(googleapis|gstatic)\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '^ajax\.googleapis\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.(typekit|fonts)\.net$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E 'lib\.baomitu\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '^challenges\.cloudflare\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.hcaptcha\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.recaptcha\.net$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E '\.gstatic\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E 'snap\.licdn\.com$' "$TEMP_DIR/unique_deps.txt" || true
      grep -E 'media\.hackerearth\.com$' "$TEMP_DIR/unique_deps.txt" || true
    } | sort -u > "$DEPENDENCIES_FILE"

    dep_count=$(wc -l < "$DEPENDENCIES_FILE")
    echo "✅ Final list: $dep_count dependencies"
    echo "→ Saved to $DEPENDENCIES_FILE"
  else
    echo "⚠️ No dependencies discovered"
    > "$DEPENDENCIES_FILE"
  fi

  echo "============================================"
  echo "Discovery Complete at $(date)"
  echo "============================================"
}

main "$@"
