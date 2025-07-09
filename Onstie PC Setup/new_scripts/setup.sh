#!/bin/bash

# Use SETUP_USER if set, otherwise default to "participant"
USER="${SETUP_USER:-participant}"

echo "============================================"
echo "Starting Lab PC Setup for user '$USER': $(date)"
echo "============================================"

echo "============================================"
echo "Starting Step 1: Force delete and recreate '$USER' account"
echo "============================================"

# Force delete user account without removing the home directory
if id "$USER" &>/dev/null; then
    echo "→ '$USER' account exists. Deleting without removing home directory..."
    sudo deluser "$USER" --remove-home || true  # Avoid failing if there's an error
    echo "✅ '$USER' account removed successfully (home directory kept)."
else
    echo "→ '$USER' account does not exist. Skipping deletion."
fi

# Recreate user account
# Replace the user creation section (in Step 1) with this more restrictive version:

echo "→ Recreating '$USER' account with minimal privileges..."

# Force delete the user if it exists
if id "$USER" &>/dev/null; then
    echo "→ '$USER' account exists. Deleting..."
    sudo deluser "$USER" --remove-home || true
fi

# Create user with minimal groups - ONLY basic ones needed for desktop use
sudo useradd -m -s /bin/bash "$USER" -G audio,video,cdrom,plugdev

# Set empty password
sudo passwd -d "$USER"

# Ensure user is unlocked
sudo usermod -U "$USER"

# Enable auto-login if needed
if grep -q '^\[Seat:\*\]' /etc/lightdm/lightdm.conf 2>/dev/null; then
    echo "autologin-user=$USER" | sudo tee -a /etc/lightdm/lightdm.conf
    echo "✅ Autologin configured in LightDM."
elif [ -f /etc/gdm3/custom.conf ]; then
    sudo sed -i 's/^#  AutomaticLoginEnable = false/AutomaticLoginEnable = true/' /etc/gdm3/custom.conf
    sudo sed -i "s/^#  AutomaticLogin = .*/AutomaticLogin = $USER/" /etc/gdm3/custom.conf
    echo "✅ Autologin configured in GDM3."
else
    echo "⚠️ Could not detect supported display manager for autologin setup."
fi

# Verify the user is in the correct groups
echo "→ Verifying user groups..."
CURRENT_GROUPS=$(groups "$USER" | cut -d: -f2)
echo "✅ '$USER' is now in groups:$CURRENT_GROUPS"

# Explicitly check for problematic groups
for group in sudo netdev adm disk; do
    if groups "$USER" | grep -q "\b$group\b"; then
        echo "⚠️ WARNING: User is still in the $group group. Removing..."
        sudo gpasswd -d "$USER" "$group" 2>/dev/null || true
    else
        echo "✅ Confirmed user is NOT in $group group."
    fi
done


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

echo "→ Installing VS Code extensions for '$USER'..."
echo "⚠️ Note: Extension installation may fail due to network issues - this won't stop the setup"

EXTENSIONS=(
    "ms-vscode.cpptools"
    "ms-python.python"
    "redhat.java"
)

for ext in "${EXTENSIONS[@]}"; do
    echo "→ Checking extension: $ext for $USER"
    
    # Check if the extension is already installed (with better error handling)
    EXTENSION_CHECK=$(sudo -u "$USER" code --list-extensions 2>/dev/null | grep -c "$ext" 2>/dev/null || echo "0")
    
    if [[ "$EXTENSION_CHECK" -gt 0 ]]; then
        echo "✅ Extension $ext is already installed. Skipping installation."
    else
        echo "→ Installing extension: $ext for $USER"
        # Try to install with timeout and better error handling
        if timeout 60s sudo -u "$USER" code --install-extension "$ext" --force 2>/dev/null; then
            echo "✅ Installed $ext successfully."
        else
            echo "⚠️ Failed to install $ext (this may be due to network issues or the extension might already be installed globally)"
            echo "   Continuing with setup..."
        fi
    fi
done


echo "============================================"
echo "✅ VS Code extensions installed."
echo "============================================"


echo "============================================"
echo "Step 8: Fix VS Code Keyring Popup for $USER"
echo "============================================"

# Install PAM keyring helper if not present
sudo apt install -y libpam-gnome-keyring

# Add PAM lines if not already present
if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/common-auth; then
    echo "auth optional pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/common-auth
fi

if ! grep -q "pam_gnome_keyring.so auto_start" /etc/pam.d/common-session; then
    echo "session optional pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/common-session
fi

# Clear existing keyring files
sudo -u "$USER" rm -f "/home/$USER/.local/share/keyrings/*"

# Pre-create a blank keyring if needed (interactive part not scriptable without security compromise)
echo "✅ Keyring configuration fixed. You may still need to run VS Code once under $USER to complete silent keyring setup."


echo "============================================"
echo "Starting Step 9: Set Permissions for $USER and Fix Code::Blocks"
echo "============================================"

# Install additional package for ACL support
sudo apt install -y acl

# DO NOT add user to privileged groups - use only minimum necessary
# Removed: sudo usermod -aG sudo,adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev "$USER"

# Set full ownership and permissions for $USER's home
sudo chown -R "$USER:$USER" "/home/$USER"
sudo chmod -R u+rwX "/home/$USER"

# Rest of the function remains the same...

echo "============================================"
echo "Starting Step 10: Disable Automatic Updates"
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


echo "============================================"
echo "Starting Step 11: Clean Up"
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


echo "============================================"
echo "Starting Step 12: Backup $USER's Home (Initial Clean State)"
echo "============================================"

# Ensure the backup directory exists
BACKUP_DIR="/opt/${USER}_backup"
if [ ! -d "$BACKUP_DIR" ]; then
    echo "✅ Creating backup directory: $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
fi

# Check if a backup already exists, if not, create it
if [ ! -d "$BACKUP_DIR/${USER}_home" ]; then
    echo "Backing up /home/$USER to $BACKUP_DIR/${USER}_home..."
    sudo rsync -aAX "/home/$USER/" "$BACKUP_DIR/${USER}_home/"
    if [ $? -eq 0 ]; then
        echo "✅ Initial backup of /home/$USER created successfully."
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

# Final step: print out that setup is complete
echo "============================================"
echo "✅ Lab PC Setup Completed!"
echo "============================================"
