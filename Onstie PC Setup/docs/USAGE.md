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

# Apply restrictions (uses whitelist from requirements/whitelist.txt)
sudo contest-manager restrict --user alice

# Check status
contest-manager status --user alice

# Remove restrictions
sudo contest-manager unrestrict --user alice

# Reset environment
sudo contest-manager reset --user alice
```

## 🧑‍💻 User Management

### Setting Up a Contest User
```bash
sudo contest-manager setup --user contestant
# Creates user, installs software, configures environment
```

### Resetting a User Environment
```bash
sudo contest-manager reset --user contestant
# Resets user to clean state
```

## 🔒 Restriction Management

- Restrictions are applied using Squid and iptables.
- Whitelisted domains are read from `requirements/whitelist.txt` (or as configured).
- Dependencies are analyzed and cached automatically.

## ✅ Whitelist Management

- Edit `requirements/whitelist.txt` to add/remove allowed domains.
- To reset to default, copy from `requirements/whitelist.default.txt`.
- No domains are hardcoded; all are file-driven.

## 📊 Monitoring & Status

```bash
contest-manager status --user alice
```
Shows current restriction and USB status for the user.

## 🛠️ Advanced Usage
- See `docs/INSTALL.md` for manual install and Playwright setup.
- See `docs/TROUBLESHOOTING.md` for common issues.

## 💡 Best Practices
- Always edit whitelists and requirements via the files in `requirements/`.
- Use the CLI for all management tasks.
- Review dependency analysis after applying restrictions.
