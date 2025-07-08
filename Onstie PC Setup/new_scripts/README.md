# Contest Environment Manager

A comprehensive system for managing programming contest environments with internet restrictions, user account management, and automated setup for programming contests.

## Features

- **User Account Management**: Set up and reset user accounts with pre-configured development tools
- **Internet Restrictions**: IP-based internet access control for contest environments  
- **USB Device Blocking**: Prevent access to USB storage devices during contests
- **Automated Software Installation**: Install and configure development tools (VS Code, compilers, etc.)
- **Domain Whitelisting**: Allow access to specific contest platforms and their dependencies

## Quick Start

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd contest-environment-manager

# Install with default command name 'cmanager'
sudo bash install.sh

# Or install with custom command name
sudo bash install.sh contest-mgr
sudo bash install.sh labmgr
sudo bash install.sh pcmgr
```

### Basic Usage

```bash
# Set up a contest environment for default user 'participant'
sudo cmanager setup

# Set up for a specific user
sudo cmanager setup contestant

# Restrict internet access for a user
sudo cmanager restrict participant

# Check restriction status
sudo cmanager status participant

# Reset user account to clean state
sudo cmanager reset participant

# Remove all restrictions
sudo cmanager unrestrict participant
```

**Note**: Replace `cmanager` with your chosen command name if you installed with a custom name.

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `setup [USER]` | Set up lab PC with required software and user account | `sudo cmanager setup contestant` |
| `reset [USER]` | Reset user account to clean state | `sudo cmanager reset participant` |
| `restrict [USER]` | Enable internet restrictions for user | `sudo cmanager restrict participant` |
| `unrestrict [USER]` | Remove all restrictions for user | `sudo cmanager unrestrict participant` |
| `status [USER]` | Show restriction status | `sudo cmanager status participant` |
| `help` | Show help message | `sudo cmanager help` |

## Whitelist Management

The system uses simple text files for domain management:

### Configuration Files

| File | Location | Description |
|------|----------|-------------|
| `whitelist.txt` | Current directory | Local whitelist file for testing |
| `allowed.txt` | `/usr/local/etc/contest-restriction/` | System-wide whitelist file |

### Workflow

1. **Edit the whitelist file** directly with allowed domains:
   ```bash
   # Edit system whitelist
   sudo nano /usr/local/etc/contest-restriction/allowed.txt
   
   # Or edit local whitelist for testing
   nano whitelist.txt
   ```

2. **Add domains** (one per line):
   ```
   codeforces.com
   atcoder.jp
   codechef.com
   ```

3. **Apply changes** by running the restrict command:
   ```bash
   sudo cmanager restrict participant
   ```

### Example whitelist.txt
```
codeforces.com
atcoder.jp
codechef.com
leetcode.com
```

## How It Works

### Internet Restrictions (New Approach)
- **IP-based whitelisting** - Resolves allowed domains to IP addresses
- **Full access for whitelisted domains** - Contest sites can access any resources they need
- **Automatic subdomain support** - Includes www, api, cdn, static, assets subdomains
- **DNS resolution allowed** for domain lookups
- **Dynamic IP updates** via helper scripts

### USB Storage Blocking
- **udev rules** to block USB storage devices
- **Polkit rules** to prevent mounting
- Affects pendrives, SSDs, and other removable storage

### User Management
- Creates user accounts with development tools
- Configures **autologin** for contest environments
- Sets up **Code::Blocks**, **VS Code**, and compilers
- Creates **backup snapshots** for easy reset

## Technical Details

### System Requirements
- Ubuntu/Debian-based Linux distribution
- Root access for installation and management
- Network connectivity for initial setup

### Installed Software
- Development tools: `gcc`, `g++`, `python3`, `git`
- IDEs: `code` (VS Code), `codeblocks`
- Browsers: `firefox`, `google-chrome-stable`
- Network utilities: `iptables`, `dnsutils`

### File Locations
- Scripts: `/usr/local/share/contest-manager/`
- Whitelist: `/usr/local/etc/contest-restriction/allowed.txt`
- User backups: `/opt/{username}_backup/`
- Helper scripts: `/usr/local/bin/whitelist-manager.sh`, `/usr/local/bin/update-contest-whitelist`

## Configuration

### Custom Command Name
You can install the tool with any command name you prefer:

```bash
# Install as 'contest-mgr'
sudo bash install.sh contest-mgr

# Install as 'labmgr' 
sudo bash install.sh labmgr

# Install as 'pcmgr'
sudo bash install.sh pcmgr
```

The installer creates a symlink in `/usr/local/bin/` with your chosen name, so you can use commands like:
```bash
sudo contest-mgr setup
sudo labmgr restrict participant
sudo pcmgr status
```

### Default Whitelisted Domains
The system includes common contest platforms:
- Contest sites: codeforces.com, codechef.com, atcoder.jp, hackerrank.com, etc.
- You can add more domains using the whitelist-manager.sh script

You can customize the default list by editing the `whitelist.txt` file and running:
```bash
sudo cmanager update
```

### Customization
- Modify `setup.sh` to change installed software
- Edit whitelist template in `restrict.sh`
- Adjust user permissions in setup scripts

## Security Features

- User-specific iptables rules prevent network bypass
- IP-based whitelisting allows full access to contest domains and their dependencies
- Service persistence across reboots via systemd
- Comprehensive USB device blocking via udev and polkit
- No proxy requirements - direct internet access for whitelisted domains

## Troubleshooting

### Common Issues

1. **Command not found**: Ensure installation completed successfully
2. **Permission denied**: Run commands with `sudo`
3. **User doesn't exist**: Create user first or specify existing user
4. **Services not starting**: Check system logs with `journalctl`

### Debug Commands
```bash
# Check service status
sudo systemctl status contest-restrict-participant.service

# View iptables rules for user
sudo iptables -L CONTEST_PARTICIPANT_OUT -n -v

# Update whitelist IPs manually
sudo update-contest-whitelist participant

# Test domain resolution
dig codeforces.com
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request

## License

This project is released under the MIT License. See LICENSE file for details.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review system logs for error details
