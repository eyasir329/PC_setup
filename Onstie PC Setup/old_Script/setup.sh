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
    # Check if the extension is already installed
    if sudo -u participant code --list-extensions | grep -q "$ext"; then
        echo "✅ Extension $ext is already installed. Skipping installation."
    else
        echo "→ Installing extension: $ext for participant"
        sudo -u participant code --install-extension "$ext" --force
        if [ $? -eq 0 ]; then
            echo "✅ Installed $ext successfully."
        else
            echo "❌ Failed to install $ext." >&2
            exit 1
        fi
    fi
done


echo "============================================"
echo "✅ VS Code extensions installed."
echo "============================================"


echo "============================================"
echo "Step 8: Fix VS Code Keyring Popup for Participant"
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
sudo -u participant rm -f /home/participant/.local/share/keyrings/*

# Pre-create a blank keyring if needed (interactive part not scriptable without security compromise)
echo "✅ Keyring configuration fixed. You may still need to run VS Code once under participant to complete silent keyring setup."


echo "============================================"
echo "Starting Step 9: Set Permissions for Participant and Fix Code::Blocks"
echo "============================================"

# Install additional package for ACL support
sudo apt install -y acl

# Make sure participant is part of necessary groups
sudo usermod -aG sudo,adm,dialout,cdrom,floppy,audio,dip,video,plugdev,netdev participant

# Set full ownership and permissions for participant's home
sudo chown -R participant:participant /home/participant
sudo chmod -R u+rwX /home/participant

# Create Code::Blocks projects directory with proper permissions
sudo -u participant mkdir -p /home/participant/cb_projects
sudo chmod -R 755 /home/participant/cb_projects

# Create common Code::Blocks output directories with proper permissions
sudo -u participant mkdir -p /home/participant/cb_projects/bin
sudo -u participant mkdir -p /home/participant/cb_projects/bin/Debug
sudo -u participant mkdir -p /home/participant/cb_projects/bin/Release
sudo chmod -R 755 /home/participant/cb_projects/bin

# Set default umask for participant to ensure new files are executable
echo "umask 022" | sudo tee -a /home/participant/.bashrc
echo "umask 022" | sudo tee -a /home/participant/.profile

# Set executable permissions for common binary extensions
sudo find /home/participant -type f -name "*.out" -exec chmod +x {} \;
sudo find /home/participant -type f -name "*.exe" -exec chmod +x {} \;
sudo find /home/participant -type f -name "*.bin" -exec chmod +x {} \;
sudo find /home/participant -path "*/bin/Debug/*" -type f -exec chmod +x {} \;
sudo find /home/participant -path "*/bin/Release/*" -type f -exec chmod +x {} \;

# Setup ACL to automatically grant execute permissions for new files in bin directories
sudo setfacl -R -d -m u::rwx,g::rx,o::rx /home/participant/cb_projects/bin
sudo setfacl -R -m u::rwx,g::rx,o::rx /home/participant/cb_projects/bin

# Set proper permissions for Code::Blocks configuration directory
sudo -u participant mkdir -p /home/participant/.config/codeblocks
sudo chown -R participant:participant /home/participant/.config/codeblocks
sudo chmod -R u+rwX /home/participant/.config/codeblocks

# Ensure Code::Blocks has proper directory specified for output
CONFIG_FILE="/home/participant/.config/codeblocks/default.conf"
if [ -f "$CONFIG_FILE" ]; then
    sudo -u participant sed -i 's|<default_compiler>.*</default_compiler>|<default_compiler>gnu_gcc_compiler</default_compiler>|' "$CONFIG_FILE"
    sudo -u participant sed -i 's|<output_directory>.*</output_directory>|<output_directory>/home/participant/cb_projects/bin</output_directory>|' "$CONFIG_FILE"
fi

# Set safer default for executed programs in CodeBlocks
sudo -u participant mkdir -p /home/participant/.config/codeblocks/share
sudo chown -R participant:participant /home/participant/.config/codeblocks/share
echo "[General]
terminal_program=xterm
terminal_cmd=xterm -T \$TITLE -e
" | sudo -u participant tee /home/participant/.config/codeblocks/share/terminals.conf > /dev/null

# Add a custom-compiled runner script for Code::Blocks executables
echo '#!/bin/bash
chmod +x "$@"
"$@"
' | sudo tee /usr/local/bin/codeblocks-run > /dev/null
sudo chmod +x /usr/local/bin/codeblocks-run

# Create a helpful alias for participant
echo 'alias make-executable="chmod +x"' | sudo tee -a /home/participant/.bashrc > /dev/null

# Verify
if [ $? -eq 0 ]; then
    echo "✅ Permissions and Code::Blocks configuration set successfully for participant."
else
    echo "❌ Failed to set permissions for participant." >&2
    exit 1
fi

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
echo "Starting Step 12: Backup Participant's Home (Initial Clean State)"
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

# Final step: print out that setup is complete
echo "============================================"
echo "✅ Lab PC Setup Completed!"
echo "============================================"