# Contest Environment Manager

A robust, professional Python-based system for managing contest environments with network restrictions, USB controls, and automated dependency management.

## 🚀 Quick Start

```bash
# Install the system
git clone <repository-url>
cd contest-manager
sudo ./install.sh install

# Set up a contest environment
sudo contest-manager setup --user alice

# Apply restrictions
sudo contest-manager restrict --user alice

# Check status
contest-manager status --user alice

# Remove restrictions when done
sudo contest-manager unrestrict --user alice
```

## 📋 What It Does

- **🔒 Network Restrictions**: Blocks internet access except whitelisted contest sites
- **📦 USB Controls**: Prevents USB storage while allowing keyboards/mice
- **🔍 Smart Dependencies**: Automatically discovers and allows essential CDNs/APIs
- **⚙️ System Management**: Complete user setup, reset, and environment management
- **📊 Monitoring**: Persistent restrictions with automatic IP updates
- **🛠️ Easy Management**: Simple CLI for all operations

## 📚 Documentation

- **[Installation Guide](INSTALL.md)** - Complete installation instructions
- **[Usage Guide](USAGE.md)** - Detailed usage examples and commands
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

## 🎯 Key Features

### Network Security
- Intelligent website dependency analysis
- Dynamic IP address tracking
- IPv4/IPv6 support
- Persistent iptables rules

### USB Management
- Hardware-level USB storage blocking
- Keyboard/mouse preservation
- Automatic device detection
- Clean removal system

### System Integration
- Systemd service management
- Automatic startup restoration
- User group permissions
- Desktop integration

### Monitoring & Maintenance
- Real-time status checking
- Periodic dependency updates
- Automatic error recovery
- Comprehensive logging

## 🛡️ Security Model

- **Root Operations**: System-level changes require root privileges
- **User Groups**: contest-manager group for controlled access
- **Service Isolation**: Separate systemd services for different functions
- **Clean Removal**: Complete cleanup on unrestrict

## 🔧 System Requirements

- **OS**: Ubuntu 18.04+ (or compatible Linux distribution)
- **Python**: 3.6+
- **Privileges**: Root access for installation and restrictions
- **Network**: Internet access for dependency analysis
- **Storage**: ~100MB for installation

## 📦 Installation

See [INSTALL.md](INSTALL.md) for detailed installation instructions.

**Quick Install:**
```bash
sudo ./install.sh install
```

## 🚀 Usage

See [USAGE.md](USAGE.md) for comprehensive usage guide.

**Basic Commands:**
```bash
contest-manager --help                    # Show help
sudo contest-manager setup --user alice   # Setup environment
sudo contest-manager restrict --user alice # Apply restrictions
contest-manager status --user alice       # Check status
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Contest Environment Manager                │
├─────────────────────────────────────────────────────────────┤
│  CLI Interface (manager.py)                                │
├─────────────────────────────────────────────────────────────┤
│  Core Scripts                                               │
│  ├── setup.py       │ User & software setup                │
│  ├── reset.py       │ Environment reset                    │
│  ├── restrict.py    │ Apply restrictions                   │
│  └── unrestrict.py  │ Remove restrictions                  │
├─────────────────────────────────────────────────────────────┤
│  Utilities                                                  │
│  ├── network_restrictor.py    │ iptables management        │
│  ├── usb_restrictor.py        │ USB device control         │
│  ├── dependency_analyzer.py   │ Website analysis           │
│  ├── user_manager.py          │ User account management    │
│  └── system_utils.py          │ System utilities           │
├─────────────────────────────────────────────────────────────┤
│  System Integration                                         │
│  ├── Systemd Services  │ Monitoring & persistence          │
│  ├── iptables Rules    │ Network filtering                 │
│  ├── udev Rules        │ USB device blocking               │
│  └── User Groups       │ Permission management             │
└─────────────────────────────────────────────────────────────┘
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

[Insert your license here]

## 📞 Support

- **Documentation**: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Issues**: Create a GitHub issue
- **Logs**: Check `journalctl -u contest-monitor.service`
- **Status**: Run `contest-manager status --user <username>`

## 🏆 Use Cases

- **Programming Contests**: ICPC, IUPC, Onsite Contests
- **Online Examinations**: Secure testing environments
- **Educational Labs**: Controlled internet access
- **Security Testing**: Restricted network environments

---

**Built with ❤️ for secure contest environments**
