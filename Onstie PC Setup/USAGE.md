# Usage Guide - Contest Environment Manager

This guide covers all aspects of using the Contest Environment Manager after installation.

## 📋 Table of Contents

- [Basic Commands](#basic-commands)
- [User Management](#user-management)
- [Restriction Management](#restriction-management)
- [Whitelist Management](#whitelist-management)
- [Monitoring & Status](#monitoring--status)
- [Advanced Usage](#advanced-usage)
- [Best Practices](#best-practices)

## 🚀 Basic Commands

### Getting Help
```bash
contest-manager --help              # Show all commands
contest-manager help                # Alternative help command
```

### Core Operations
```bash
# Setup contest environment
sudo contest-manager setup --user alice

# Apply restrictions
sudo contest-manager restrict --user alice

# Check status
contest-manager status --user alice

# Remove restrictions
sudo contest-manager unrestrict --user alice

# Reset environment
sudo contest-manager reset --user alice
```

## 👥 User Management

### Setting Up a Contest User

```bash
# Create and configure a contest user
sudo contest-manager setup --user contestant

# This will:
# - Create user account if it doesn't exist
# - Install essential contest software
# - Set up programming environments
# - Configure desktop environment
# - Create user backup for reset capability
```

### Resetting a User Environment

```bash
# Reset user to clean state
sudo contest-manager reset --user contestant

# This will:
# - Restore home directory from backup
# - Clean temporary files
# - Fix common software issues
# - Restore default settings
```

### User Account Features

The system automatically:
- Creates user with appropriate permissions
- Installs contest software (GCC, Python, Java, etc.)
- Sets up code editors (VS Code, CodeBlocks)
- Configures desktop environment
- Creates system backup for reset

## 🔒 Restriction Management

### Applying Restrictions

```bash
# Apply all restrictions
sudo contest-manager restrict --user alice

# This activates:
# - Network restrictions (only whitelisted sites)
# - USB storage blocking
# - Automatic dependency resolution
# - System monitoring
```

### Removing Restrictions

```bash
# Remove all restrictions
sudo contest-manager unrestrict --user alice

# This removes:
# - All network restrictions
# - USB storage blocks
# - Monitoring services
# - System state cleanup
```

### Restriction Features

**Network Restrictions:**
- Blocks all internet access except whitelisted sites
- Automatically discovers and allows essential dependencies
- Handles dynamic IP addresses
- Supports IPv4 and IPv6

**USB Controls:**
- Blocks USB storage devices
- Allows keyboards and mice
- Prevents data exfiltration
- Clean removal when restrictions lifted

## 📝 Whitelist Management

### Adding Sites

```bash
# Add a contest site
contest-manager add codeforces.com

# Add multiple sites
contest-manager add atcoder.jp
contest-manager add codechef.com
```

### Removing Sites

```bash
# Remove a site
contest-manager remove codeforces.com
```

### Viewing Whitelisted Sites

```bash
# List all whitelisted sites
contest-manager list

# Output example:
# Whitelisted domains (15 total):
# ==================================================
#   atcoder.jp
#   codechef.com
#   codeforces.com
#   ...
# ==================================================
```

### Managing Dependencies

```bash
# View resolved dependencies
contest-manager dependencies

# This shows:
# - Dependencies for each whitelisted site
# - Total unique dependencies
# - Cache information
# - Refresh recommendations
```

## 📊 Monitoring & Status

### Checking System Status

```bash
# Check overall status
contest-manager status --user alice

# Example output:
# Contest Environment Status
# User: alice
# Network restrictions: ✅ Active
# USB restrictions: ✅ Active
# Whitelisted sites: 15
# Essential dependencies: 45
# Last updated: 2025-01-15 10:30:00
```

### Monitoring Services

```bash
# Check systemd services
sudo systemctl status contest-monitor.timer
sudo systemctl status contest-monitor.service

# View logs
journalctl -u contest-monitor.service -f

# Check specific user restrictions
sudo systemctl status contest-restore-alice.service
```

## 🔧 Advanced Usage

### Custom Configuration Directory

```bash
# Use custom config directory
contest-manager --config-dir /path/to/config list
sudo contest-manager --config-dir /path/to/config restrict --user alice
```

### Force Dependency Refresh

```bash
# Force fresh dependency analysis
sudo contest-manager restrict --user alice --force-refresh
```

### Selective Restrictions

```bash
# Apply only network restrictions
sudo contest-manager restrict --user alice --skip-usb

# Apply only USB restrictions
sudo contest-manager restrict --user alice --skip-network
```

### Manual Script Execution

```bash
# Run individual scripts directly
sudo python3 /usr/local/lib/contest-manager/restrict.py --user alice --apply
sudo python3 /usr/local/lib/contest-manager/setup.py alice
```

## 📋 Best Practices

### Pre-Contest Setup

1. **Prepare Environment**
   ```bash
   sudo contest-manager setup --user contestant
   ```

2. **Test Whitelist**
   ```bash
   # Add contest sites
   contest-manager add codeforces.com
   contest-manager add atcoder.jp
   
   # Verify list
   contest-manager list
   ```

3. **Test Restrictions**
   ```bash
   # Apply and test
   sudo contest-manager restrict --user contestant
   contest-manager status --user contestant
   
   # Remove for final preparation
   sudo contest-manager unrestrict --user contestant
   ```

### During Contest

1. **Apply Restrictions**
   ```bash
   sudo contest-manager restrict --user contestant
   ```

2. **Monitor Status**
   ```bash
   contest-manager status --user contestant
   ```

3. **Handle Issues**
   ```bash
   # Check logs if problems occur
   journalctl -u contest-monitor.service -f
   
   # Emergency unrestrict
   sudo contest-manager unrestrict --user contestant
   ```

### Post-Contest

1. **Remove Restrictions**
   ```bash
   sudo contest-manager unrestrict --user contestant
   ```

2. **Reset Environment**
   ```bash
   sudo contest-manager reset --user contestant
   ```

### Multiple Users

```bash
# Set up multiple contestants
sudo contest-manager setup --user contestant1
sudo contest-manager setup --user contestant2
sudo contest-manager setup --user contestant3

# Apply restrictions to all
sudo contest-manager restrict --user contestant1
sudo contest-manager restrict --user contestant2
sudo contest-manager restrict --user contestant3

# Check status for all
contest-manager status --user contestant1
contest-manager status --user contestant2
contest-manager status --user contestant3
```

## 🛠️ Troubleshooting Quick Reference

### Common Issues

**Network not working:**
```bash
# Check status
contest-manager status --user alice

# View dependencies
contest-manager dependencies

# Force refresh
sudo contest-manager restrict --user alice --force-refresh
```

**USB still working:**
```bash
# Check USB status
contest-manager status --user alice

# Reapply restrictions
sudo contest-manager unrestrict --user alice
sudo contest-manager restrict --user alice
```

**Service not starting:**
```bash
# Check service status
sudo systemctl status contest-monitor.timer

# Restart service
sudo systemctl restart contest-monitor.timer

# Check logs
journalctl -u contest-monitor.service -f
```

### Emergency Procedures

**Complete System Reset:**
```bash
# Remove all restrictions
sudo contest-manager unrestrict --user alice

# Clean up any remaining rules
sudo iptables -F CONTEST_CHAIN || true
sudo iptables -D OUTPUT -j CONTEST_CHAIN || true
sudo iptables -X CONTEST_CHAIN || true

# Remove udev rules
sudo rm -f /etc/udev/rules.d/99-contest-usb-*.rules
sudo udevadm control --reload-rules

# Restart networking
sudo systemctl restart networking
```

**Manual Service Cleanup:**
```bash
# Stop all services
sudo systemctl stop contest-monitor.timer
sudo systemctl stop contest-monitor.service

# Remove service files
sudo rm -f /etc/systemd/system/contest-monitor.*
sudo rm -f /etc/systemd/system/contest-restore-*.service

# Reload systemd
sudo systemctl daemon-reload
```

## 📚 Additional Resources

- **Installation**: See [INSTALL.md](INSTALL.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **System Logs**: `journalctl -u contest-monitor.service`
- **Configuration**: `/etc/contest-manager/`

---

For more help, run `contest-manager --help` or check the troubleshooting guide.
