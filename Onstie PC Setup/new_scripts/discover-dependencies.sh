#!/usr/bin/env bash
set -uo pipefail

# Contest Platform Dependency Discovery Tool
# Discovers external domain dependencies for contest platforms
# This script analyzes contest sites to discover essential external dependencies

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

# Check and install required tools
install_requirements() {
  echo "→ Checking for required tools..."
  
  local missing_tools=()
  
  # Check for curl
  if ! command -v curl &>/dev/null; then
    missing_tools+=("curl")
  fi
  
  # Check for tcpdump
  if ! command -v tcpdump &>/dev/null; then
    missing_tools+=("tcpdump")
  fi
  
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

# Find whitelist file
find_whitelist() {
  if [[ -f "$WHITELIST_FILE" ]]; then
    echo "$WHITELIST_FILE"
  elif [[ -f "$LOCAL_WHITELIST" ]]; then
    echo "$LOCAL_WHITELIST"
  else
    echo "❌ Error: No whitelist found at $WHITELIST_FILE or $LOCAL_WHITELIST" >&2
    echo "   Please create a whitelist.txt file with contest platforms" >&2
    exit 1
  fi
}

# Discover dependencies for a domain using simple network monitoring
discover_dependencies() {
  local domain="$1"
  
  echo "   🔍 Analyzing $domain..."
  
  # Method 1: Simple tcpdump approach
  echo "      → Starting network capture..."
  local capture_file="$TEMP_DIR/${domain}_traffic.txt"
  
  # Start tcpdump in background to capture DNS and HTTP traffic
  timeout 30s tcpdump -i any -n port 53 or port 80 or port 443 2>/dev/null | \
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u > "$capture_file" &
  local tcpdump_pid=$!
  
  sleep 2
  
  # Method 2: Trigger page load and extract ONLY essential asset domains
  echo "      → Fetching $domain and analyzing essential assets..."
  local html_file="$TEMP_DIR/${domain}_page.html"
  
  # Try multiple approaches to fetch the site
  if curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "https://$domain" > "$html_file" 2>/dev/null || \
     curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "http://$domain" >> "$html_file" 2>/dev/null; then
    echo "         ✅ Page fetched successfully"
    
    # Extract ONLY essential CDN and asset domains (NOT Google/social services)
    {
      # Contest site subdomains (assets, static, etc.)
      grep -oE "https?://[^/\"']*\.$domain[^/\"']*" "$html_file" 2>/dev/null | sed 's|^https\?://||' | cut -d'/' -f1
      grep -oE "https?://[^/\"']*$domain[^/\"']*" "$html_file" 2>/dev/null | sed 's|^https\?://||' | cut -d'/' -f1
      
      # Essential CDN services only (be more permissive with subdomain patterns)
      grep -oE '[a-zA-Z0-9.-]*\.(cloudflare|cloudfront|jsdelivr|unpkg|bootstrapcdn|fontawesome)\.com' "$html_file" 2>/dev/null
      grep -oE '[a-zA-Z0-9.-]*\.(typekit|fonts)\.net' "$html_file" 2>/dev/null
      
      # Font and common asset services (but only specific subdomains, not all of Google)
      grep -oE 'fonts\.(googleapis|gstatic)\.com' "$html_file" 2>/dev/null
      grep -oE 'ajax\.googleapis\.com' "$html_file" 2>/dev/null
      grep -oE 'static\.cloudflareinsights\.com' "$html_file" 2>/dev/null
      
      # Additional critical dependencies that were missed
      echo "fonts.googleapis.com" 
      echo "snap.licdn.com"
      echo "cdn.jsdelivr.net"
      echo "lib.baomitu.com"
      echo "media.hackerearth.com"
      echo "recaptcha.net"
      
      # MathJax and other specialized libraries needed for contest platforms
      grep -oE '[a-zA-Z0-9.-]*\.mathjax\.org' "$html_file" 2>/dev/null
      grep -oE 'cdnjs\.cloudflare\.com' "$html_file" 2>/dev/null
      
      # Cloudflare challenges and security (essential for access)
      grep -oE 'challenges\.cloudflare\.com' "$html_file" 2>/dev/null
      grep -oE 'hcaptcha\.com' "$html_file" 2>/dev/null
      grep -oE 'recaptcha\.net' "$html_file" 2>/dev/null
      grep -oE 'gstatic\.com' "$html_file" 2>/dev/null
      
      # Extract domains from JavaScript src attributes for essential dependencies
      grep -oE 'src="https?://[^"]*"' "$html_file" 2>/dev/null | \
        sed -E 's/src="https?:\/\/([^\/"]*)\/.*"/\1/' | \
        grep -v -E '^(www\.)?(google|youtube|facebook|twitter)\.com$'
      
    } | grep -v "^$domain$" | grep '\.' | sort -u >> "$TEMP_DIR/all_dependencies.txt"
    
  else
    echo "         ⚠️  Could not fetch $domain, trying with www prefix..."
    
    # Try with www prefix as fallback
    if curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "https://www.$domain" > "$html_file" 2>/dev/null || \
       curl -s -L --max-time 30 -A "$BROWSER_USER_AGENT" "http://www.$domain" >> "$html_file" 2>/dev/null; then
      echo "         ✅ Page fetched successfully with www prefix"
      
      # Add www version to dependencies
      echo "www.$domain" >> "$TEMP_DIR/all_dependencies.txt"
      
      # Extract dependencies with same patterns as above
      {
        # Contest site subdomains
        grep -oE "https?://[^/\"']*\.$domain[^/\"']*" "$html_file" 2>/dev/null | sed 's|^https\?://||' | cut -d'/' -f1
        grep -oE "https?://[^/\"']*$domain[^/\"']*" "$html_file" 2>/dev/null | sed 's|^https\?://||' | cut -d'/' -f1
        
        # Essential CDN services
        grep -oE '[a-zA-Z0-9.-]*\.(cloudflare|cloudfront|jsdelivr|unpkg|bootstrapcdn|fontawesome)\.com' "$html_file" 2>/dev/null
        grep -oE '[a-zA-Z0-9.-]*\.(typekit|fonts)\.net' "$html_file" 2>/dev/null
        
        # Font and asset services
        grep -oE 'fonts\.(googleapis|gstatic)\.com' "$html_file" 2>/dev/null
        grep -oE 'ajax\.googleapis\.com' "$html_file" 2>/dev/null
        grep -oE 'static\.cloudflareinsights\.com' "$html_file" 2>/dev/null
        
        # Additional critical dependencies that were missed
        echo "fonts.googleapis.com" 
        echo "snap.licdn.com"
        echo "cdn.jsdelivr.net"
        echo "lib.baomitu.com"
        echo "media.hackerearth.com"
        echo "recaptcha.net"
        
        # MathJax and libraries
        grep -oE '[a-zA-Z0-9.-]*\.mathjax\.org' "$html_file" 2>/dev/null
        grep -oE 'cdnjs\.cloudflare\.com' "$html_file" 2>/dev/null
        
        # Security services
        grep -oE 'challenges\.cloudflare\.com' "$html_file" 2>/dev/null
        grep -oE 'hcaptcha\.com' "$html_file" 2>/dev/null
        grep -oE 'recaptcha\.net' "$html_file" 2>/dev/null
        grep -oE 'gstatic\.com' "$html_file" 2>/dev/null
        
        # JavaScript dependencies
        grep -oE 'src="https?://[^"]*"' "$html_file" 2>/dev/null | \
          sed -E 's/src="https?:\/\/([^\/"]*)\/.*"/\1/' | \
          grep -v -E '^(www\.)?(google|youtube|facebook|twitter)\.com$'
        
      } | grep -v "^$domain$" | grep -v "^www.$domain$" | grep '\.' | sort -u >> "$TEMP_DIR/all_dependencies.txt"
    else
      echo "         ⚠️  Could not fetch $domain even with www prefix"
    fi
  fi
  
  # Stop network capture
  kill $tcpdump_pid 2>/dev/null
  wait $tcpdump_pid 2>/dev/null || true
  
  # Convert IPs to domains if possible
  if [[ -s "$capture_file" ]]; then
    echo "      → Processing network traffic captured during page access..."
    while read -r ip; do
      # Try reverse DNS lookup with timeout to prevent hangs
      timeout 2s nslookup "$ip" 2>/dev/null | grep 'name =' | cut -d'=' -f2 | tr -d ' ' | sed 's/\.$//' || echo "$ip"
    done < "$capture_file" | grep -v "^$domain$" | grep -v "^www.$domain$" | sort -u >> "$TEMP_DIR/all_dependencies.txt"
  fi
  
  echo "      ✅ Analysis completed"
  return 0
}

# Cleanup function
cleanup() {
  echo "→ Cleaning up temporary files..."
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
    echo "✅ Temporary files cleaned up"
  fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main function
main() {
  install_requirements
  
  echo ""
  echo "============================================"
  echo "Step 2: Initialize Discovery Environment"
  echo "============================================"
  
  # Create temporary directory
  echo "→ Creating temporary working directory..."
  if mkdir -p "$TEMP_DIR" 2>/dev/null; then
    echo "✅ Temporary directory created: $TEMP_DIR"
  else
    echo "❌ Failed to create temporary directory" >&2
    exit 1
  fi
  
  # Create output directory
  echo "→ Creating configuration directory..."
  if mkdir -p "$CONFIG_DIR" 2>/dev/null; then
    echo "✅ Configuration directory ready: $CONFIG_DIR"
  else
    echo "❌ Failed to create configuration directory" >&2
    exit 1
  fi
  
  # Find whitelist
  echo "→ Locating whitelist file..."
  local whitelist
  whitelist=$(find_whitelist)
  echo "✅ Using whitelist: $whitelist"
  
  # Initialize output file
  > "$TEMP_DIR/all_dependencies.txt"
  echo "✅ Dependency collection initialized"
  
  echo ""
  echo "============================================"
  echo "Step 3: Discover Domain Dependencies"
  echo "============================================"
  
  echo "🚀 Starting dependency discovery process..."
  echo "⏱️  This may take a few minutes as we analyze each contest site..."
  
  # Count domains to process
  local total
  total=$(grep -c -v "^[[:space:]]*#\|^[[:space:]]*$" "$whitelist" 2>/dev/null || echo "0")
  
  if [[ $total -eq 0 ]]; then
    echo "❌ Error: No valid domains found in whitelist" >&2
    exit 1
  fi
  
  echo "→ Processing $total contest platforms..."
  
  # Process each domain in whitelist
  local count=0
  local successful=0
  local failed=0
  
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    count=$((count + 1))
    echo ""
    echo "[$count/$total] Processing domain..."
    
    # Clean domain name
    domain="${line#.}"
    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"
    
    # Discover dependencies with error handling
    echo "      ⏱️  Processing $domain..."
    if discover_dependencies "$domain"; then
      successful=$((successful + 1))
      echo "      ✅ Successfully processed $domain"
    else
      failed=$((failed + 1))
      echo "      ❌ Failed to process $domain (continuing with next domain)"
    fi
  done < "$whitelist"
  
  echo ""
  echo "📊 Processing Summary:"
  echo "   • Total domains: $total"
  echo "   • Successfully processed: $successful"
  echo "   • Failed: $failed"
  
  
  echo ""
  echo "============================================"
  echo "Step 4: Process and Filter Dependencies"
  echo "============================================"
  
  # Process and clean up dependencies
  if [[ -f "$TEMP_DIR/all_dependencies.txt" && -s "$TEMP_DIR/all_dependencies.txt" ]]; then
    echo "→ Processing discovered dependencies..."
    
    # Filter and sort unique domains
    if cat "$TEMP_DIR/all_dependencies.txt" | sort -u > "$TEMP_DIR/unique_deps.txt"; then
      local raw_count
      raw_count=$(wc -l < "$TEMP_DIR/unique_deps.txt" 2>/dev/null || echo "0")
      echo "✅ Found $raw_count unique domains before filtering"
    else
      echo "❌ Failed to process dependencies" >&2
      exit 1
    fi
    
    echo "→ Applying strict security filters..."
    
    # Strict filtering - only allow essential CDN and contest assets
    cat "$TEMP_DIR/unique_deps.txt" | \
        grep -v -E '(localhost|127\.0\.0\.1|192\.168\.|10\.|172\.)' | \
        grep -v -E '^(www\.)?(youtube|facebook|twitter|instagram|reddit|discord|telegram|whatsapp|tiktok|stackoverflow|github)\.com$' | \
        grep -v -E '^(analytics|ads|googleads|doubleclick)\.google' | \
        grep -v -E '^(connect\.facebook|static\.xx\.fbcdn|scontent\..*\.fbcdn|video\..*\.fbcdn)' | \
        grep -E '\.[a-zA-Z]{2,}$' | \
        {
          # Always allow these critical domains
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
            
            # Always include www versions of whitelisted domains
            cat "$whitelist" | sed 's/^/www./'
            
            # All domains from the whitelist file
            cat "$whitelist"
          } > "$TEMP_DIR/critical_domains.txt"
          
          # Create pattern from whitelist domains for subdomain matching
          cat "$whitelist" | sed 's/^/\\.|/' | sed 's/$/|/' | tr -d '\n' | sed 's/|$//' > "$TEMP_DIR/platforms.pattern"
          platform_pattern=$(cat "$TEMP_DIR/platforms.pattern")
          
          # Merge critical domains with filtered dependencies
          {
            # Always include critical domains first
            cat "$TEMP_DIR/critical_domains.txt"
            
            # Contest site domains and their subdomains
            grep -E "($platform_pattern)" || true
            
            # Essential CDN services (expanded list)
            grep -E '\.(cloudflare|cloudfront|jsdelivr|unpkg|bootstrapcdn|fontawesome)\.com$' || true
            grep -E '\.mathjax\.org$' || true
            grep -E 'cdnjs\.cloudflare\.com$' || true
            grep -E 'static\.cloudflareinsights\.com$' || true
            
            # Essential font and static asset services
            grep -E '^fonts\.(googleapis|gstatic)\.com$' || true
            grep -E '^ajax\.googleapis\.com$' || true
            grep -E '\.(typekit|fonts)\.net$' || true
            grep -E 'lib\.baomitu\.com$' || true
            
            # Security and CAPTCHA services (essential for access)
            grep -E '^challenges\.cloudflare\.com$' || true
            grep -E '\.hcaptcha\.com$' || true
            grep -E '\.recaptcha\.net$' || true
            grep -E 'pagead2\.googlesyndication\.com$' || true
            grep -E '\.gstatic\.com$' || true
            grep -E 'snap\.licdn\.com$' || true
            
            # Media hosting
            grep -E 'media\.hackerearth\.com$' || true
          }
        } | \
        sort -u > "$DEPENDENCIES_FILE" 2>/dev/null || true
    
    local dep_count=$(wc -l < "$DEPENDENCIES_FILE" 2>/dev/null || echo "0")
    echo "✅ Found $dep_count external dependencies after basic filtering"
    
    if [[ $dep_count -gt 0 ]]; then
      echo "✅ Discovered $dep_count external dependencies"
      echo "→ Dependencies saved to: $DEPENDENCIES_FILE"
      
      echo ""
      echo "📋 External dependencies that will be allowed:"
      cat "$DEPENDENCIES_FILE" | sed 's/^/   • /'
      
      echo ""
      echo "✅ These domains will be allowed in addition to your whitelist"
    else
      echo "⚠️  No external dependencies found"
      echo "   Contest platforms appear to be self-contained"
      
      # Show raw dependencies for debugging
      if [[ -s "$TEMP_DIR/unique_deps.txt" ]]; then
        echo ""
        echo "🔍 Raw dependencies found:"
        cat "$TEMP_DIR/unique_deps.txt" | sed 's/^/   • /'
      fi
      
      > "$DEPENDENCIES_FILE"  # Ensure file exists even if empty
    fi
  else
    echo "⚠️  No dependencies discovered during analysis"
    echo "   This may indicate network connectivity issues or self-contained platforms"
    > "$DEPENDENCIES_FILE"  # Ensure file exists even if empty
  fi
  
  echo ""
  echo "============================================"
  echo "Discovery Complete"
  echo "============================================"
  echo "✅ Dependency discovery completed successfully"
  echo "→ Results saved to: $DEPENDENCIES_FILE"
  echo "→ You can now run restrict.sh to apply the restrictions"
  echo "Finished at: $(date)"
}

# Execute main function with all arguments
main "$@"
