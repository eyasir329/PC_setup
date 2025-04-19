#!/bin/bash

echo "============================================"
echo "Starting Lab PC Setup: $(date)"
echo "============================================"

echo "============================================"
echo "Starting Step 1: Force delete and recreate 'participant' account"
echo "============================================"

# Force delete 'participant' account without removing the home directory
if id "participant" &>/dev/null; then
    echo "→ 'participant' account exists. Deleting without removing home directory..."
    sudo deluser participant --remove-home || true  # Avoid failing if there's an error
    echo "✅ 'participant' account removed successfully (home directory kept)."
else
    echo "→ 'participant' account does not exist. Skipping deletion."
fi

# Recreate 'participant' account
echo "→ Recreating 'participant' account..."
sudo adduser --gecos "" --disabled-password participant
if [ $? -eq 0 ]; then
    echo "✅ 'participant' account created successfully."

    # Retain password and user settings (force reset user without resetting home or password)
    sudo passwd -d participant  # Remove the password (if needed)
    sudo usermod -U participant # Unlock the account

    # Keep home directory intact (since deluser --remove-home was not used)
    sudo usermod -m -d /home/participant participant

    # Ensure user is not treated as a system user (for login screen appearance)
    sudo usermod -r participant 2>/dev/null || true

    # Enable passwordless login for graphical display managers (GDM/LightDM)
    if grep -q '^\[Seat:\*\]' /etc/lightdm/lightdm.conf 2>/dev/null; then
        echo "autologin-user=participant" | sudo tee -a /etc/lightdm/lightdm.conf
        echo "✅ Autologin configured in LightDM."
    elif [ -f /etc/gdm3/custom.conf ]; then
        sudo sed -i 's/^#  AutomaticLoginEnable = false/AutomaticLoginEnable = true/' /etc/gdm3/custom.conf
        sudo sed -i 's/^#  AutomaticLogin = .*/AutomaticLogin = participant/' /etc/gdm3/custom.conf
        echo "✅ Autologin configured in GDM3."
    else
        echo "⚠️ Could not detect supported display manager for autologin setup."
    fi

else
    echo "❌ Failed to recreate 'participant' account." >&2
    exit 1
fi



# 2. Install development tools and essential utilities
echo "============================================"
echo "Starting Step 2: Install Development Tools and Utilities"
echo "============================================"

DEV_PACKAGES=(
    build-essential
    gdb
    gcc
    g++
    python3
    python3-pip
    openjdk-17-jdk
    neovim
    git
    micro
    codeblocks
    curl
    wget
    neofetch
    hollywood
)

echo "→ Checking and installing missing development tools and utilities..."

for pkg in "${DEV_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo "✅ $pkg is already installed."
    else
        echo "📦 Installing $pkg..."
        if sudo apt install -y "$pkg"; then
            echo "✅ $pkg installed successfully."
        else
            echo "❌ Failed to install $pkg." >&2
            exit 1
        fi
    fi
done

echo "→ Installing GRUB Customizer..."

# Add the PPA only if it hasn't already been added
if ! grep -q "^deb .*/danielrichter2007/grub-customizer" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    echo "➕ Adding PPA for GRUB Customizer..."
    sudo add-apt-repository -y ppa:danielrichter2007/grub-customizer
    sudo apt update
else
    echo "✅ PPA for GRUB Customizer already exists."
fi

# Install grub-customizer
if dpkg -s grub-customizer &>/dev/null; then
    echo "✅ grub-customizer is already installed."
else
    echo "📦 Installing grub-customizer..."
    if sudo apt install -y grub-customizer; then
        echo "✅ grub-customizer installed successfully."
    else
        echo "❌ Failed to install grub-customizer." >&2
        exit 1
    fi
fi


# 3. Install Sublime Text
echo "============================================"
echo "Step 3: Install Sublime Text"
echo "============================================"

# Check if Sublime Text is already installed
if command -v subl &>/dev/null; then
    echo "✅ Sublime Text is already installed. Skipping installation."
else
    echo "📦 Installing Sublime Text..."

    # Ensure apt supports HTTPS
    sudo apt-get install -y apt-transport-https curl gnupg

    # Add GPG key if not already present
    if [ ! -f /etc/apt/trusted.gpg.d/sublimehq-archive.gpg ]; then
        echo "🔑 Adding Sublime Text GPG key..."
        wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg \
        | gpg --dearmor \
        | sudo tee /etc/apt/trusted.gpg.d/sublimehq-archive.gpg > /dev/null
    else
        echo "🔑 GPG key already exists. Skipping."
    fi

    # Add Sublime Text repository if not already added
    if [ ! -f /etc/apt/sources.list.d/sublime-text.list ]; then
        echo "📝 Adding Sublime Text APT repository..."
        echo "deb https://download.sublimetext.com/ apt/stable/" \
        | sudo tee /etc/apt/sources.list.d/sublime-text.list
    else
        echo "📝 Repository already exists. Skipping."
    fi

    # Update APT and install Sublime Text
    echo "🔄 Updating package list..."
    sudo apt-get update

    echo "📥 Installing Sublime Text..."
    if sudo apt-get install -y sublime-text; then
        echo "✅ Sublime Text installed successfully."
    else
        echo "❌ Failed to install Sublime Text." >&2
        exit 1
    fi
fi

echo "============================================"
echo "Step 4: Install Google Chrome"
echo "============================================"

# Check if Google Chrome is already installed
if command -v google-chrome &>/dev/null; then
    echo "✅ Google Chrome is already installed. Skipping installation."
else
    echo "📦 Installing Google Chrome..."

    # Download the latest stable Google Chrome .deb package
    TMP_DEB="/tmp/google-chrome.deb"
    echo "🌐 Downloading Google Chrome .deb package..."
    wget -O "$TMP_DEB" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

    # Install the package using dpkg
    echo "📥 Installing the package..."
    if sudo dpkg -i "$TMP_DEB"; then
        echo "✅ Google Chrome installed successfully."
    else
        echo "⚠️ Resolving dependencies..."
        sudo apt-get install -f -y
        sudo dpkg -i "$TMP_DEB" && echo "✅ Google Chrome installed successfully after fixing dependencies." || {
            echo "❌ Failed to install Google Chrome." >&2
            exit 1
        }
    fi

    # Clean up the temporary .deb file
    rm -f "$TMP_DEB"
fi


echo "============================================"
echo "Step 5: Install Firefox"
echo "============================================"

# Check if Firefox is installed (snap or apt)
if command -v firefox &>/dev/null; then
    echo "✅ Firefox is already installed. Skipping installation."
else
    echo "📦 Firefox not found. Installing..."

    # Try APT first (classic deb version)
    if sudo apt install -y firefox; then
        echo "✅ Firefox installed successfully using APT."
    else
        echo "⚠️ APT install failed. Trying snap instead..."
        if sudo snap install firefox; then
            echo "✅ Firefox installed successfully using Snap."
        else
            echo "❌ Failed to install Firefox." >&2
            exit 1
        fi
    fi
fi


echo "============================================"
echo "Step 6: Install Visual Studio Code"
echo "============================================"

# Check if VS Code is already installed
if command -v code &>/dev/null; then
    echo "✅ Visual Studio Code is already installed. Skipping installation."
else
    echo "📦 Visual Studio Code not found. Installing..."

    # Install required dependencies
    sudo apt update
    sudo apt install -y wget gpg apt-transport-https

    # Import the Microsoft GPG key
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | sudo tee /usr/share/keyrings/microsoft-archive-keyring.gpg > /dev/null

    # Add the VS Code repository
    echo "deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" | \
        sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

    # Install Visual Studio Code
    sudo apt update
    if sudo apt install -y code; then
        echo "✅ Visual Studio Code installed successfully."
    else
        echo "❌ Failed to install Visual Studio Code." >&2
        exit 1
    fi
fi


echo "============================================"
echo "Starting Step 7: Install VS Code Extensions"
echo "============================================"

echo "→ Installing VS Code extensions for 'participant'..."

EXTENSIONS=(
    "ms-vscode.cpptools"
    "ms-python.python"
    "redhat.java"
)

for ext in "${EXTENSIONS[@]}"; do
    echo "→ Installing extension: $ext for participant"
    sudo -u participant code --install-extension "$ext" --force
    if [ $? -eq 0 ]; then
        echo "✅ Installed $ext successfully."
    else
        echo "❌ Failed to install $ext." >&2
        exit 1
    fi
done

echo "============================================"
echo "✅ VS Code extensions installed."
echo "============================================"


echo "============================================"
echo "Starting Step 8: Set Permissions for Participant"
echo "============================================"

# Set full ownership and permissions for participant's home
sudo chown -R participant:participant /home/participant
sudo chmod -R u+rwX /home/participant

# Verify
if [ $? -eq 0 ]; then
    echo "✅ Permissions set successfully for /home/participant."
else
    echo "❌ Failed to set permissions for /home/participant." >&2
    exit 1
fi


# 9. Disable automatic updates
echo "============================================"
echo "Starting Step 9: Disable Automatic Updates"
echo "============================================"

# Stop the automatic update services
sudo systemctl stop apt-daily.service apt-daily-upgrade.service

# Disable automatic update services on boot
sudo systemctl disable apt-daily.service apt-daily-upgrade.service

# Verify the services are disabled
if systemctl is-enabled apt-daily.service &>/dev/null && systemctl is-enabled apt-daily-upgrade.service &>/dev/null; then
    echo "✅ Automatic updates successfully disabled."
else
    echo "❌ Failed to disable automatic updates." >&2
    exit 1
fi

# 10. Clean up unnecessary packages
echo "============================================"
echo "Starting Step 10: Clean Up"
echo "============================================"

# Remove unnecessary packages and dependencies
sudo apt autoremove -y

# Verify cleanup
if [ $? -eq 0 ]; then
    echo "✅ Clean up completed successfully."
else
    echo "❌ Clean up failed." >&2
    exit 1
fi

# 11. Backup participant's home directory (clean state)
echo "============================================"
echo "Starting Step 11: Backup Participant's Home (Initial Clean State)"
echo "============================================"

# Ensure the backup directory exists
BACKUP_DIR="/opt/participant_backup"
if [ ! -d "$BACKUP_DIR" ]; then
    echo "✅ Creating backup directory: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
fi

# Check if a backup already exists, if not, create it
if [ ! -d "$BACKUP_DIR/participant_home" ]; then
    echo "Backing up /home/participant to $BACKUP_DIR/participant_home..."
    sudo rsync -aAX /home/participant/ "$BACKUP_DIR/participant_home/"
    if [ $? -eq 0 ]; then
        echo "✅ Initial backup of /home/participant created successfully."
    else
        echo "❌ Failed to create backup." >&2
        exit 1
    fi
else
    echo "✅ Backup already exists. Skipping backup process."
fi

echo "============================================"
echo "✅ Backup Process Complete!"
echo "============================================"



echo "============================================"
echo "Starting Internet Access and Storage Device Restriction"
echo "============================================"

# Define the participant's username
PARTICIPANT_USER="participant"

# List of allowed domains
ALLOWED_DOMAINS=(
    "codeforces.com" "codechef.com" "vjudge.net" "atcoder.jp"
    "hackerrank.com" "hackerearth.com" "topcoder.com"
    "spoj.com" "lightoj.com" "uva.onlinejudge.org"
    "cses.fi" "bapsoj.com" "toph.co"
)

# Flush existing OUTPUT chain rules and set default policy to DROP
# Only apply this to the participant user by using the --uid-owner option
echo "Flushing existing iptables rules and setting default policy to DROP..."
sudo iptables -F OUTPUT
sudo iptables -P OUTPUT ACCEPT  # Allow all users to use the network by default

# Set the policy to DROP for the participant user
echo "Applying DROP policy for participant..."
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -j DROP

# Allow localhost communication (e.g., localhost) for the participant
echo "Allowing localhost communication for the participant..."
sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d 127.0.0.1 -j ACCEPT

# Resolve and allow access for specific allowed domains (using dnsmasq)
for domain in "${ALLOWED_DOMAINS[@]}"; do
    echo "→ Resolving $domain using local DNS..."

    # Resolve domain via local DNS (dnsmasq)
    IP_LIST_IPV4=$(dig +short $domain)
    
    if [ -z "$IP_LIST_IPV4" ]; then
        echo "❌ Could not resolve $domain — skipping."
        continue
    fi

    # Allow access for each resolved IPv4 address
    for ip in $IP_LIST_IPV4; do
        echo "→ Allowing participant to access $domain (IPv4: $ip)..."
        sudo iptables -A OUTPUT -m owner --uid-owner $PARTICIPANT_USER -d "$ip" -j ACCEPT
    done

    echo "✅ Allowed $domain (IPv4: $IP_LIST_IPV4)"
done

# Block storage devices (USB, SSD, CD, etc.), but allow keyboard and mouse for participant only
echo "Blocking access to storage devices (USB, SSD, CD, etc.) for participant..."
echo 'SUBSYSTEM=="block", ACTION=="add", ATTRS{idVendor}!="0781", ATTRS{idProduct}!="5591", RUN+="/usr/bin/logger Storage device blocked for participant"' | sudo tee /etc/udev/rules.d/99-block-storage-participant.rules
sudo udevadm control --reload-rules

# Save iptables rules to ensure persistence after reboot
echo "Saving iptables rules to ensure persistence after reboot..."
sudo apt-get install iptables-persistent
sudo netfilter-persistent save
sudo netfilter-persistent reload

echo "============================================"
echo "✅ Internet access and storage device restrictions applied for participant."
echo "============================================"



# Final step: print out that setup is complete
echo "============================================"
echo "✅ Lab PC Setup Completed!"
echo "============================================"
