# Troubleshooting Guide - Contest Environment Manager

This guide helps resolve common issues with the Contest Environment Manager.

## 📋 Table of Contents

- [Installation Issues](#installation-issues)
- [Network Problems](#network-problems)
- [USB Control Issues](#usb-control-issues)
- [Service Problems](#service-problems)
- [Permission Issues](#permission-issues)
- [Performance Issues](#performance-issues)
- [Emergency Procedures](#emergency-procedures)
- [Diagnostic Commands](#diagnostic-commands)

## 🛠️ Installation Issues

### Missing System Dependencies

**Problem:** Installation fails with missing packages

**Solution:**
```bash
# Check which packages are missing
sudo apt update
sudo apt install -y python3 python3-pip iptables systemd

# For CentOS/RHEL/Fedora
sudo yum install -y python3 python3-pip iptables systemd

# Retry installation
sudo ./install.sh install
```

### Python Package Installation Failures

**Problem:** pip install fails for required packages

**Solution:**
```bash
# Update pip
sudo python3 -m pip install --upgrade pip

# Install packages individually
sudo python3 -m pip install selenium requests dnspython psutil

# For Ubuntu, try using system packages
sudo apt install -y python3-selenium python3-requests python3-dnspython python3-psutil

# Install from requirements file
sudo python3 -m pip install -r requirements/requirements.txt
```

### Playwright or Browser Issues

**Problem:** Playwright or browser dependencies not installed

**Solution:**
```bash
# Install Playwright and dependencies
sudo python3 -m playwright install
sudo python3 -m playwright install-deps
```

### Whitelist/Requirements Issues

**Problem:** Domains not being restricted/allowed as expected

**Solution:**
- Edit `requirements/whitelist.txt` to update allowed domains
- To reset, copy from `requirements/whitelist.default.txt`
- No domains are hardcoded; all are file-driven

## 🌐 Network Problems

### Whitelisted Sites Not Working

**Problem:** Cannot access whitelisted sites despite restrictions being active

**Diagnosis:**
```bash
# Check restriction status
contest-manager status --user alice

# View current iptables rules
sudo iptables -L CONTEST_CHAIN -v

# Check DNS resolution
dig codeforces.com
nslookup codeforces.com
```

**Solution:**
```bash
# Force refresh dependencies
sudo contest-manager restrict --user alice --force-refresh

# Check whitelist format
contest-manager list

# Manually add missing dependencies
contest-manager add cdn.codeforces.com
contest-manager add api.codeforces.com
```

### DNS Resolution Issues

**Problem:** Sites resolve to different IPs

**Solution:**
```bash
# Check current DNS settings
cat /etc/resolv.conf

# Update DNS (temporary fix)
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Force IP address update
sudo systemctl restart contest-monitor.service

# Check dependency cache
contest-manager dependencies
```

### IPv6 Issues

**Problem:** IPv6 connections not working

**Solution:**
```bash
# Check IPv6 support
ip -6 addr show

# Verify IPv6 iptables rules
sudo ip6tables -L CONTEST_CHAIN -v

# Disable IPv6 if causing issues
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Firewall Conflicts

**Problem:** Existing firewall rules conflict

**Solution:**
```bash
# Check for ufw
sudo ufw status

# Disable ufw temporarily
sudo ufw disable

# Check for firewalld
sudo systemctl status firewalld

# Stop firewalld if running
sudo systemctl stop firewalld
sudo systemctl disable firewalld

# Reapply contest restrictions
sudo contest-manager restrict --user alice
```

## 🔌 USB Control Issues

### USB Storage Still Working

**Problem:** USB storage devices are not blocked

**Diagnosis:**
```bash
# Check USB restriction status
contest-manager status --user alice

# List USB devices
lsusb

# Check udev rules
ls -la /etc/udev/rules.d/99-contest-usb-*

# Test USB device detection
sudo udevadm monitor
```

**Solution:**
```bash
# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Reapply USB restrictions
sudo contest-manager unrestrict --user alice
sudo contest-manager restrict --user alice

# Check for conflicting rules
sudo udevadm test /sys/class/block/sdb1
```

### Keyboard/Mouse Not Working

**Problem:** Input devices blocked incorrectly

**Solution:**
```bash
# Check udev rules for input devices
grep -r "input" /etc/udev/rules.d/99-contest-usb-*

# Temporarily remove all USB rules
sudo rm -f /etc/udev/rules.d/99-contest-usb-*.rules
sudo udevadm control --reload-rules

# Reapply restrictions (should fix input devices)
sudo contest-manager restrict --user alice
```

### USB Detection Issues

**Problem:** USB devices not detected properly

**Solution:**
```bash
# Check USB subsystem
lsmod | grep usb

# Restart USB subsystem
sudo modprobe -r usb_storage
sudo modprobe usb_storage

# Check device permissions
ls -la /dev/sd*
```

## 🔄 Service Problems

### Monitor Service Not Starting

**Problem:** contest-monitor.timer/service fails to start

**Diagnosis:**
```bash
# Check service status
sudo systemctl status contest-monitor.timer
sudo systemctl status contest-monitor.service

# View service logs
journalctl -u contest-monitor.service -f

# Check service files
ls -la /etc/systemd/system/contest-monitor.*
```

**Solution:**
```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable contest-monitor.timer
sudo systemctl start contest-monitor.timer

# Check for conflicts
sudo systemctl list-units --failed

# Recreate service files
sudo contest-manager restrict --user alice
```

### Service Crashes

**Problem:** Services crash repeatedly

**Solution:**
```bash
# Check crash logs
journalctl -u contest-monitor.service --since "1 hour ago"

# Increase service timeout
sudo systemctl edit contest-monitor.service

# Add override:
[Service]
TimeoutStartSec=120
RestartSec=60
```

### Timer Not Triggering

**Problem:** Periodic updates not running

**Solution:**
```bash
# Check timer status
sudo systemctl list-timers contest-monitor.timer

# Manual timer test
sudo systemctl start contest-monitor.service

# Check timer configuration
systemctl cat contest-monitor.timer
```

## 🔐 Permission Issues

### User Not in Contest Group

**Problem:** Permission denied for non-root users

**Solution:**
```bash
# Add user to contest-manager group
sudo usermod -a -G contest-manager alice

# Verify group membership
groups alice

# User needs to log out and back in
# Or use: su - alice
```

### Sudoers Configuration Problems

**Problem:** Sudo commands not working for contest-manager group

**Solution:**
```bash
# Check sudoers file
sudo visudo -f /etc/sudoers.d/contest-manager

# Verify syntax
sudo visudo -c

# Recreate sudoers file
sudo rm -f /etc/sudoers.d/contest-manager
sudo ./install.sh install
```

### File Permission Issues

**Problem:** Config files not readable/writable

**Solution:**
```bash
# Fix config file permissions
sudo chown root:contest-manager /etc/contest-manager/whitelist.txt
sudo chmod 664 /etc/contest-manager/whitelist.txt

# Fix executable permissions
sudo chmod 755 /usr/local/bin/contest-manager
sudo chmod 755 /usr/local/lib/contest-manager/*.py
```

## 🐌 Performance Issues

### Slow Dependency Analysis

**Problem:** Restriction application takes too long

**Solution:**
```bash
# Use cached dependencies
contest-manager dependencies

# Skip dependency refresh
sudo contest-manager restrict --user alice --skip-network

# Reduce whitelist size
contest-manager list
# Remove unnecessary sites
```

### High CPU Usage

**Problem:** Monitor service using too much CPU

**Solution:**
```bash
# Check process usage
top -p $(pgrep -f contest-monitor)

# Adjust monitor frequency
sudo systemctl edit contest-monitor.timer

# Add override:
[Timer]
OnUnitActiveSec=60min
```

### Memory Issues

**Problem:** High memory usage during analysis

**Solution:**
```bash
# Check memory usage
free -h

# Reduce concurrent analysis
# Edit dependency_analyzer.py timeout settings

# Add swap if needed
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## 🚨 Emergency Procedures

### Complete System Reset

**When:** System is completely broken

**Procedure:**
```bash
# 1. Stop all services
sudo systemctl stop contest-monitor.timer
sudo systemctl stop contest-monitor.service

# 2. Remove all iptables rules
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# 3. Remove udev rules
sudo rm -f /etc/udev/rules.d/99-contest-usb-*.rules
sudo udevadm control --reload-rules

# 4. Clean up services
sudo rm -f /etc/systemd/system/contest-monitor.*
sudo rm -f /etc/systemd/system/contest-restore-*.service
sudo systemctl daemon-reload

# 5. Restart networking
sudo systemctl restart networking
```

### Emergency Unrestrict

**When:** Cannot access contest-manager command

**Procedure:**
```bash
# Direct script execution
sudo python3 /usr/local/lib/contest-manager/unrestrict.py --user alice --remove

# Manual iptables cleanup
sudo iptables -F CONTEST_CHAIN 2>/dev/null || true
sudo iptables -D OUTPUT -j CONTEST_CHAIN 2>/dev/null || true
sudo iptables -X CONTEST_CHAIN 2>/dev/null || true

# Manual udev cleanup
sudo rm -f /etc/udev/rules.d/99-contest-usb-*.rules
sudo udevadm control --reload-rules
```

### Recovery After System Crash

**When:** System restarted unexpectedly

**Procedure:**
```bash
# Check if restrictions are still active
contest-manager status --user alice

# Verify services are running
sudo systemctl status contest-monitor.timer

# If services failed, restart them
sudo systemctl start contest-monitor.timer

# Check for corruption
sudo contest-manager restrict --user alice --force-refresh
```

## 🔍 Diagnostic Commands

### System Information

```bash
# System overview
uname -a
lsb_release -a
python3 --version

# Network status
ip addr show
ip route show
cat /etc/resolv.conf

# Service status
systemctl status contest-monitor.timer
systemctl status contest-monitor.service

# Process information
ps aux | grep contest
ps aux | grep python3
```

### Network Diagnostics

```bash
# iptables rules
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n

# Active connections
netstat -tulpn
ss -tulpn

# DNS testing
dig google.com
nslookup codeforces.com

# Connectivity testing
ping -c 4 8.8.8.8
curl -I https://codeforces.com
```

### USB Diagnostics

```bash
# USB devices
lsusb -v
lsblk

# udev rules
ls -la /etc/udev/rules.d/99-contest-usb-*
udevadm info --query=all --name=/dev/sdb1

# Device monitoring
sudo udevadm monitor --kernel --subsystem-match=usb
```

### Log Analysis

```bash
# System logs
journalctl -u contest-monitor.service -f
journalctl -u contest-monitor.timer -f

# System messages
tail -f /var/log/syslog
tail -f /var/log/messages

# Authentication logs
tail -f /var/log/auth.log
```

## 📞 Getting Help

### Log Collection

```bash
# Create diagnostic report
mkdir -p /tmp/contest-debug
contest-manager status --user alice > /tmp/contest-debug/status.txt
sudo iptables -L -v -n > /tmp/contest-debug/iptables.txt
systemctl status contest-monitor.timer > /tmp/contest-debug/services.txt
journalctl -u contest-monitor.service > /tmp/contest-debug/logs.txt

# Create archive
tar -czf contest-debug.tar.gz /tmp/contest-debug/
```

### Common Solutions Summary

| Problem | Quick Fix |
|---------|-----------|
| Network not working | `sudo contest-manager restrict --user alice --force-refresh` |
| USB still working | `sudo udevadm control --reload-rules` |
| Service not starting | `sudo systemctl restart contest-monitor.timer` |
| Permission denied | `sudo usermod -a -G contest-manager username` |
| High CPU usage | Edit timer frequency in systemd |
| Emergency reset | Run emergency unrestrict procedure |

---

If issues persist after trying these solutions, collect diagnostic information and seek support through your system administrator or the project maintainers.
