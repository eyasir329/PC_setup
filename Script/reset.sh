#!/bin/bash

echo "============================================"
echo "Undoing Restrictions Before Resetting Participant Account"
echo "============================================"

# Undo internet access and storage device restrictions

# Define the participant's username
PARTICIPANT_USER="participant"

# Remove Squid configuration
echo "Removing Squid configuration for domain-based access control..."
sudo rm -f /etc/squid/squid.conf

# Reinstall the original Squid configuration
echo "Restoring the original Squid configuration..."
sudo cp /etc/squid/squid.conf.bak /etc/squid/squid.conf

# Restart Squid to apply the original config
sudo systemctl restart squid

# Remove the udev rule for blocking storage devices for participant
echo "Removing udev rule for blocking storage devices for participant..."
sudo rm -f /etc/udev/rules.d/99-block-storage-participant.rules

# Reload udev rules to apply the changes
sudo udevadm control --reload-rules

# Remove Squid package if no longer needed
echo "Uninstalling Squid..."
sudo apt-get remove --purge squid -y
sudo apt-get autoremove -y

echo "============================================"
echo "✅ Internet access and storage device restrictions have been reverted."
echo "============================================"

echo "============================================"
echo "Resetting participant account to default..."
echo "============================================"

# 1. Ensure backup exists
if [ ! -d /opt/participant_backup ]; then
    echo "❌ Backup directory /opt/participant_backup does not exist. Cannot reset!"
    exit 1
fi

# 2. Ensure participant is logged out
if pgrep -u participant > /dev/null; then
    echo "❌ Participant is currently logged in. Please log them out before resetting."
    exit 1
fi

# 3. Delete current participant home
echo "Deleting current home directory files (except backup files)..."
sudo rm -rf /home/participant/*
if [ $? -ne 0 ]; then
    echo "❌ Failed to delete /home/participant/"
    exit 1
fi

# 4. Restore backup
echo "Restoring from backup..."
sudo rsync -aAX /opt/participant_backup/ /home/participant/
if [ $? -eq 0 ]; then
    echo "✅ Home directory restored."
else
    echo "❌ Error restoring from backup!"
    exit 1
fi

# 5. Fix ownership
echo "Fixing permissions..."
sudo chown -R participant:participant /home/participant
if [ $? -eq 0 ]; then
    echo "✅ Permissions fixed."
else
    echo "❌ Failed to fix permissions."
    exit 1
fi

# 6. Clean sensitive files
echo "Cleaning sensitive files (templates, code, etc.)..."
find /home/participant/ -type f -name "*.tmp" -exec rm -f {} \;
find /home/participant/ -type f -name "*.bak" -exec rm -f {} \;
find /home/participant/ -type f -name "*.*~" -exec rm -f {} \;

echo "Cleaning up config/cache folders..."
sudo rm -rf /home/participant/.cache/*
sudo rm -rf /home/participant/.local/share/*
sudo rm -rf /home/participant/.config/*

# 7. Verify essential software is intact
echo "Verifying that no essential software has been removed..."
sudo apt list --installed | grep -E "python3|git|vim|gcc|build-essential|openjdk-17-jdk|codeblocks|sublime-text|google-chrome-stable|firefox|code" > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Essential software is intact."
else
    echo "❌ Some essential software is missing or has been removed."
    exit 1
fi

# 8. Set permissions
echo "Setting permissions for participant's home..."
sudo chown -R participant:participant /home/participant
sudo chmod -R u+rwX /home/participant

# Ensure participant can execute files from anywhere in their home directory
find /home/participant -type f -name "*.out" -exec chmod +x {} \;
find /home/participant -type f -name "*.exe" -exec chmod +x {} \;

# 9. Create a writable directory for Code::Blocks projects (optional, if you want to set a default path)
sudo -u participant mkdir -p /home/participant/cb_projects
sudo chmod -R 755 /home/participant/cb_projects

# Set a default project directory in Code::Blocks settings (if desired)
# Assuming Code::Blocks config is stored in ~/.codeblocks/configurations.xml
sed -i 's|<DefaultWorkspaceDir>.*</DefaultWorkspaceDir>|<DefaultWorkspaceDir>/home/participant/cb_projects</DefaultWorkspaceDir>|' /home/participant/.codeblocks/configurations.xml

# Optional: Add the participant's home directory to PATH for easy execution of compiled programs
echo 'export PATH=$PATH:/home/participant' >> /home/participant/.bashrc

# 10. Install VS Code Extensions and Browser Add-ons
echo "============================================"
echo "Starting Installing VS Code Extensions"
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
echo "✅ Participant account has been reset successfully."
echo "============================================"
