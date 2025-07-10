# Contest Environment Manager Installation Guide

## Quick Install

Run the provided install script as root:

```sh
sudo bash install.sh
```

This will install all system dependencies, the Python package, and Playwright browsers.

## Manual Install

1. Install system dependencies:
   ```sh
   sudo apt-get update
   sudo apt-get install squid iptables ip6tables dnsutils usbutils util-linux python3-pip python3-venv
   ```
2. Install the Python package:
   ```sh
   sudo pip3 install --break-system-packages .
   ```
3. Install Playwright browsers:
   ```sh
   sudo python3 -m playwright install
   sudo python3 -m playwright install-deps
   ```
4. (Optional) Edit `requirements/whitelist.txt` to set allowed domains.
   - To reset to default, copy from `requirements/whitelist.default.txt`.

See USAGE.md and TROUBLESHOOTING.md for more info.
