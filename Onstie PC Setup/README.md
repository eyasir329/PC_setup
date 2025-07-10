# Contest Environment Manager

A robust method of setting up a PC for onsite competitive programming contests.

---

## 🚀 Quick Start

```sh
# Clone the repository
git clone <repository-url>
cd contest-manager

# Install (as root)
sudo ./install.sh

# Set up a contest user (default: 'participant')
sudo contest-manager setup --user alice
# or simply
sudo contest-manager setup              # sets up 'participant' user

# Restrict internet to whitelisted sites (default user: 'participant')
sudo contest-manager restrict --user alice
# or
sudo contest-manager restrict           # restricts 'participant'

# Check status (default user: 'participant')
contest-manager status --user alice
# or
contest-manager status                  # checks 'participant'

# Remove restrictions (default user: 'participant')
sudo contest-manager unrestrict --user alice
# or
sudo contest-manager unrestrict         # removes from 'participant'
```

---

## ✨ Features
- **Network Restrictions:** Only allow whitelisted contest sites (Squid + iptables)
- **USB Controls:** Block USB storage, allow keyboard/mouse
- **Smart Dependencies:** Auto-detect and allow essential CDNs/APIs
- **Easy CLI:** One command for setup, restrict, unrestrict, and status
- **Persistent & Secure:** Survives reboot, systemd integration

---

## 📚 Documentation
- [Install Guide](docs/INSTALL.md)
- [Usage Guide](docs/USAGE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

---

## 🛠️ Requirements
- Ubuntu 18.04+ (or compatible Linux)
- Python 3.6+
- Root privileges for install/restriction

---

## 🏆 Use Cases
- Programming contests (ICPC, IUPC, NCPC & onsite programming contests)
- Secure online exams
- Educational labs

---

**Built with ❤️ for secure, fair contests.**
