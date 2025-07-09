# Installation Guide - Contest Environment Manager

Complete installation instructions for the Contest Environment Manager.

## 🚀 Quick Installation

### Option 1: Shell Script (Recommended)
```bash
# Download the project
git clone <repository-url>
cd contest-manager

# Install system-wide
sudo ./install.sh install
```

### Option 2: Python Installer (Advanced)
```bash
# Install with full control
sudo python3 install.py --install

# Custom installation options
sudo python3 install.py --install --skip-system    # Skip system packages
sudo python3 install.py --install --skip-python    # Skip Python packages
sudo python3 install.py --install --prefix /opt    # Custom install location
```

## 📋 Prerequisites

### System Requirements
- **OS**: Ubuntu 18.04+ (or compatible Linux distribution)
- **Python**: 3.6 or higher
- **Architecture**: x86_64 (amd64)
- **Memory**: 2GB RAM minimum
- **Storage**: 500MB free space
- **Network**: Internet connection for installation

### Required Privileges
- **Root access**: Required for installation and system-level restrictions
- **sudo access**: For running management commands

## 📦 What Gets Installed

### System Packages
The installer will install these system packages:

| Package | Purpose |
|---------|---------|
| `python3`, `python3-pip`, `python3-dev` | Python runtime and development |
| `iptables` | Firewall management |
| `udev`, `systemd` | System service management |
| `dnsutils` | DNS tools (dig, nslookup) |
| `usbutils` | USB device tools (lsusb) |
| `util-linux` | System utilities (mount, umount) |
| `chromium-browser` | Web browser for dependency analysis |
| `chromium-chromedriver` | Chrome WebDriver |
| `netfilter-persistent` | Firewall rule persistence |
| `build-essential` | Development tools |

### Python Packages
The installer will install these Python packages:

| Package | Version | Purpose |
|---------|---------|---------|
| `selenium` | >=4.0.0 | Web automation |
| `requests` | >=2.25.0 | HTTP library |
| `dnspython` | >=2.1.0 | DNS resolution |
| `psutil` | >=5.8.0 | System monitoring |

### Installation Locations
- **Executable**: `/usr/local/bin/contest-manager`
- **Library**: `/usr/local/lib/contest-manager/`
- **Configuration**: `/etc/contest-manager/`
- **Desktop Entry**: `/usr/share/applications/contest-manager.desktop`
- **Sudoers**: `/etc/sudoers.d/contest-manager`

## 🔧 Installation Process

### Step 1: Download
```bash
# Clone repository
git clone <repository-url>
cd contest-manager

# Or download and extract
wget <download-url>
tar -xzf contest-manager.tar.gz
cd contest-manager
```

### Step 2: Install
```bash
# Make installer executable
chmod +x install.sh

# Run installation
sudo ./install.sh install

# The installer will:
# - Update package database
# - Install system dependencies
# - Install Python packages
# - Create directories
# - Copy files to system locations
# - Set up permissions
# - Create wrapper script
# - Configure systemd integration
```

### Step 3: Verify Installation
```bash
# Test the command
contest-manager --help

# Check installation
which contest-manager
ls -la /usr/local/lib/contest-manager/
```

## ⚙️ Post-Installation Setup

### 1. Add Users to Contest Manager Group
```bash
# Add user to contest-manager group
sudo usermod -a -G contest-manager alice

# Verify group membership
groups alice

# User must log out and back in for group changes to take effect
```

### 2. Configure Whitelist
```bash
# Edit whitelist to add contest sites
sudo nano /etc/contest-manager/whitelist.txt

# Add sites like:
# codeforces.com
# atcoder.jp
# codechef.com
```

### 3. Test Installation
```bash
# Test basic functionality
contest-manager list

# Test user setup (creates test user)
sudo contest-manager setup --user testuser

# Test restrictions
sudo contest-manager restrict --user testuser
contest-manager status --user testuser
sudo contest-manager unrestrict --user testuser

# Clean up test user
sudo userdel -r testuser
```

## 🔍 Installation Verification

### Check System Dependencies
```bash
# Verify system tools
which python3 iptables systemctl udevadm

# Check Python packages
python3 -c "import selenium, requests, dns.resolver, psutil"

# Test Chrome/Chromium
google-chrome --version || chromium-browser --version
chromedriver --version
```

### Check Installation Integrity
```bash
# Verify files exist
ls -la /usr/local/bin/contest-manager
ls -la /usr/local/lib/contest-manager/
ls -la /etc/contest-manager/

# Check permissions
ls -la /usr/local/bin/contest-manager
ls -la /etc/sudoers.d/contest-manager

# Test command execution
contest-manager --help
contest-manager list
```

### Check Services
```bash
# Check group exists
getent group contest-manager

# Test sudo permissions (as contest-manager group member)
sudo contest-manager --help

# Check systemd integration
systemctl list-unit-files | grep contest
```

## 🎯 Platform-Specific Notes

### Ubuntu/Debian
```bash
# Update package database first
sudo apt update

# Install using apt
sudo ./install.sh install

# Alternative manual installation
sudo apt install python3 python3-pip iptables systemd dnsutils usbutils
sudo python3 install.py --install
```

### CentOS/RHEL/Fedora
```bash
# For CentOS/RHEL 8+
sudo dnf install python3 python3-pip iptables systemd bind-utils usbutils

# For older CentOS/RHEL
sudo yum install python3 python3-pip iptables systemd bind-utils usbutils

# Run installer
sudo python3 install.py --install
```

### Arch Linux
```bash
# Install dependencies
sudo pacman -S python python-pip iptables systemd dnsutils usbutils

# Run installer
sudo python3 install.py --install
```

## ❌ Uninstallation

### Option 1: Shell Script
```bash
sudo ./install.sh uninstall
```

### Option 2: Python Installer
```bash
sudo python3 install.py --uninstall
```

### Option 3: Manual Removal
```bash
# Remove files
sudo rm -rf /usr/local/bin/contest-manager
sudo rm -rf /usr/local/lib/contest-manager
sudo rm -f /usr/share/applications/contest-manager.desktop
sudo rm -f /etc/sudoers.d/contest-manager

# Remove group
sudo groupdel contest-manager

# Remove configuration (optional)
sudo rm -rf /etc/contest-manager
```

## 🔧 Troubleshooting Installation

### Common Issues

**Permission Denied:**
```bash
# Ensure running as root
sudo ./install.sh install

# Check file permissions
ls -la install.sh
chmod +x install.sh
```

**Missing Dependencies:**
```bash
# Install missing system packages
sudo apt install python3 python3-pip

# Update pip
sudo python3 -m pip install --upgrade pip
```

**Network Issues:**
```bash
# Check internet connection
ping -c 4 google.com

# Use alternative package sources
sudo apt update --fix-missing
```

### Installation Logs
```bash
# Check installation output
sudo ./install.sh install 2>&1 | tee install.log

# Check system logs
journalctl -xe
```

## 🔄 Updating

### Update System
```bash
# Update to latest version
git pull origin main
sudo ./install.sh install

# Or download new version
wget <latest-release-url>
tar -xzf contest-manager-latest.tar.gz
cd contest-manager
sudo ./install.sh install
```

### Backup Before Update
```bash
# Backup configuration
sudo cp -r /etc/contest-manager /etc/contest-manager.backup

# Backup custom changes
sudo tar -czf contest-manager-backup.tar.gz /etc/contest-manager /usr/local/lib/contest-manager
```

## 📚 Next Steps

After successful installation:

1. **Read Usage Guide**: See [USAGE.md](USAGE.md) for detailed usage instructions
2. **Configure Whitelist**: Add contest sites to `/etc/contest-manager/whitelist.txt`
3. **Test System**: Run through test procedures above
4. **Add Users**: Add contest participants to the contest-manager group
5. **Set Up Environment**: Use `contest-manager setup` for each user

For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

**Installation complete!** Your Contest Environment Manager is ready to use.
