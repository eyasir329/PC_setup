# Contest Environment Setup for NEUPC

> Netrokona University Programming Club  
> _Maintained for our club. [Original Repository](https://github.com/ShazidMashrafi/MDPC) - from MDPC_

---

## 🚀 Features

- 🎯 **User Account Management**  
  Effortlessly set up and reset user accounts with all essential development tools pre-installed for a consistent contest environment.

- 🌐 **Internet Restrictions**  
  Enforce IP-based internet access control, ensuring participants can only reach approved contest resources.

- 🔒 **USB Device Blocking**  
  Automatically block access to USB storage devices during contests to maintain integrity and prevent data leaks.

- ⚙️ **Automated Software Installation**  
  Instantly install and configure popular development tools (VS Code, compilers, etc.) with a single command.

- 📝 **Domain Whitelisting**  
  Allow access only to specific contest platforms and their dependencies using a managed whitelist.

- 🔄 **Smart Dependency Discovery**  
  Auto-detect and permit essential CDNs, fonts, and APIs required by contest sites.

- 🛡️ **Persistent & Secure**  
  All restrictions and configurations survive reboots, with robust systemd integration for reliability.

- 🖥️ **Easy CLI Management**  
  Simple commands for setup, restriction, unrestriction, and status—no manual steps required.

- 🔗 **Network & USB Controls**  
  Network access limited to whitelisted sites (Squid + iptables); USB storage blocked, but keyboard/mouse allowed.

---

## 0️⃣ Prerequisites

- **Operating System:**  
  Debian or Ubuntu (requires root or sudo privileges).

- **Network:**  
  Active internet connection (required for package installation and dependency discovery).

- **Project Directory:**  
  Ensure you are in the project folder containing all of the following files:
  - `cmanager`
  - `discover-dependencies.sh`
  - `install.sh`
  - `README.md`
  - `reset.sh`
  - `restrict.sh`
  - `setup.sh`
  - `unrestrict.sh`
  - `whitelist.txt`

---

## 1️⃣ Install the Tool

```bash
cd /path/to/project
sudo bash install.sh            # installs to /usr/local/share/contest-manager and symlinks /usr/local/bin/cmanager
# (optional) use a custom command name:
# sudo bash install.sh labmgr
```

> **Note:** Must be run as root because it writes to system directories (`/usr/local`, `/usr/local/bin`).

### 🛠️ What the Installer Does

- **Creates the main install directory:**  
  `/usr/local/share/contest-manager/` is created to store all scripts and resources.

- **Copies all scripts:**  
  All scripts (`cmanager`, `restrict.sh`, etc.) from the project folder are copied into the install directory.

- **Installs the whitelist:**  
  If `whitelist.txt` is present, it is copied to `/usr/local/etc/contest-restriction/`.

- **Sets file permissions:**  
  The whitelist file is set to permissions `644` (readable by all, writable by owner).

- **Handles missing whitelist:**  
  If `whitelist.txt` is missing, the installer warns the admin to create one later (either manually or using `cmanager add`).

- **Makes scripts executable:**  
  All main scripts are set to be executable (`rwxr-xr-x`).

- **Creates a command symlink:**  
  A symbolic link named `$COMMAND_NAME` (default: `cmanager`) is created in `/usr/local/bin`, pointing to the `cmanager` script. This allows you to run `cmanager` (or your chosen name) from anywhere in the terminal.

---

### 📝 Commands Table

| Command             | Description                                      | Example                                |
| ------------------- | ------------------------------------------------ | -------------------------------------- |
| `setup [USER]`      | Set up lab PC with required software and user    | `sudo cmanager setup contestant`       |
| `reset [USER]`      | Reset user account to clean state                | `sudo cmanager reset participant`      |
| `restrict [USER]`   | Enable internet restrictions for user            | `sudo cmanager restrict participant`   |
| `unrestrict [USER]` | Remove all restrictions for user                 | `sudo cmanager unrestrict participant` |
| `discover`          | Discover external dependencies for contest sites | `sudo cmanager discover`               |
| `status [USER]`     | Show restriction status                          | `sudo cmanager status participant`     |
| `list`              | List currently whitelisted domains               | `sudo cmanager list`                   |
| `add DOMAIN`        | Add domain to whitelist                          | `sudo cmanager add codeforces.com`     |
| `remove DOMAIN`     | Remove domain from whitelist                     | `sudo cmanager remove facebook.com`    |
| `help`              | Show help message                                | `sudo cmanager help`                   |

---

## 2️⃣ Prepare the User

Create/configure the contest account (default is `participant`):

```bash
sudo cmanager setup                 # or: sudo cmanager setup <username>
```

This installs tools, creates a backup snapshot, and readies the account.

---

## 3️⃣ Build the Whitelist

Edit allowed contest sites (one per line). You can edit the **system** file or your **local** file:

**System file (recommended):**

```bash
sudo nano /usr/local/etc/contest-restriction/whitelist.txt
```

**Example lines:**

```
codeforces.com
atcoder.jp
codechef.com
```

> If you only edit the local `whitelist.txt` in the repo, the scripts will copy it to the system path on first use.

---

## 4️⃣ Discover External Dependencies (CDNs/fonts/etc.)

**Discover dependencies** (recommended before restricting):

```bash
sudo cmanager discover
```

This generates:

```
/usr/local/etc/contest-restriction/dependencies.txt
```

Tip: You can see what it found:

```bash
cmanager dependencies
```

### 🔍 Dependency Discovery

The system includes an advanced dependency discovery feature to ensure contest platforms function correctly while maintaining strict security. This process works as follows:

- **Simulates browser visits:**  
  Automatically visits each contest platform to mimic real user access.

- **Captures DNS queries:**  
  Monitors and records all DNS queries to identify external resources required by the contest sites.

- **Filters forbidden domains:**  
  Excludes access to non-allowed domains such as `google.com`, `github.com`, `stackoverflow.com`, and others.

- **Keeps only essential dependencies:**  
  Retains only the necessary technical resources (CDNs, APIs, fonts, static assets) required for the contest platforms to work.

- **Double-layer filtering:**  
  Applies two layers of filtering for enhanced security, ensuring only safe and required domains are permitted.

This approach guarantees that contest sites remain fully functional for participants, while access to unrelated or potentially insecure resources is strictly blocked.

---

## 5️⃣ Apply the Restrictions

Apply restrictions by running the restrict command:

```bash
sudo cmanager restrict                 # or: sudo cmanager restrict <username>
```

This:

- Blocks USB storage for that user
- Creates/updates firewall chains to only allow your whitelist + discovered dependencies
- Sets up a systemd service to keep rules current

---

## 6️⃣ Verify

Check the status:

```bash
cmanager status                        # or: cmanager status <username>
```

You should see:

- Service: enabled and active
- Firewall: active

Also check lists:

```bash
cmanager list
cmanager dependencies
```

Quick functional test:

```bash
curl -I https://codeforces.com    # should succeed (200/301)
curl -I https://google.com        # should be blocked

sudo -u participant curl -I https://hackerrank.com
sudo -u participant curl -I https://google.com
sudo iptables -S OUTPUT | grep CONTEST_          # should show the per-user -j CONTEST_*_OUT jump
```

---

## 7️⃣ During the Contest (Updates on the Fly)

**Add a domain:**

```bash
sudo cmanager add example.com
sudo cmanager restrict             # re-apply to load new domain IPs
```

**Remove a domain:**

```bash
sudo cmanager remove example.com
sudo cmanager restrict
```

---

## 8️⃣ After the Contest

**Restore full access (remove all restrictions):**

```bash
sudo cmanager unrestrict           # or: sudo cmanager unrestrict <username>
```

The unrestrict process:

- Stops and removes all systemd services and timers
- Removes all iptables rules and custom chains for the user
- Restores USB storage access by removing udev and polkit rules
- Cleans up configuration files (with user confirmation for global files)
- Verifies complete removal of all restrictions

---

## 9️⃣ Reset the Account for the Next User/Round

Put the home directory back to the clean snapshot made during setup:

```bash
sudo cmanager reset                # or: sudo cmanager reset <username>
```

- Purpose: Resets a user’s home directory to a clean state using a backup, preserving only original files. Useful for returning a contestant’s environment to pristine condition.

- Picks up $RESET_USER from cmanager or defaults to “participant”.

---

## 🔧 Handy Troubleshooting

- **Whitelist missing:**  
  Create `/usr/local/etc/contest-restriction/whitelist.txt` and rerun steps 4–5.
- **Rules not applying:**  
  Run `sudo cmanager restrict <user>` again.
- **Service check:**  
  `systemctl status contest-restrict-<user>.service`
- **See iptables chains:**  
  `sudo iptables -L | grep CONTEST` (and `sudo ip6tables -L | grep CONTEST`)
- **Nothing loads:**  
  Ensure DNS works and you ran discovery (step

---
