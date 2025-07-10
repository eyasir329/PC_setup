#!/usr/bin/env python3
"""
Contest Environment Manager - Core Manager Module
"""

import os
import sys
import json
import time
import subprocess
from pathlib import Path
from typing import Set, Dict, List, Optional

from ..utils.common import print_header, print_status, print_error, print_warning, print_step
from ..utils.user_manager import create_contest_user, reset_user_account
from ..utils.software_installer import (
    install_programming_languages, install_basic_editors, 
    install_sublime_text, install_vscode, install_vscode_extensions,
    install_grub_customizer, install_browsers, verify_essential_software
)
from ..utils.system_utils import (
    disable_system_updates, cleanup_system, fix_vscode_keyring, fix_codeblocks_permissions,
    clean_temporary_files, fix_user_permissions, create_project_directories, add_user_to_groups
)
from ..utils.network_restrictor import apply_network_restrictions, remove_network_restrictions
from ..utils.usb_restrictor import apply_usb_restrictions, remove_usb_restrictions


class ContestManager:
    """Main contest environment manager class."""
    
    def __init__(self, config_dir: Optional[str] = None):
        """Initialize the contest manager.
        
        Args:
            config_dir: Custom configuration directory path
        """
        self.config_dir = Path(config_dir) if config_dir else Path("/etc/contest-manager")
        self.whitelist_file = self.config_dir / "whitelist.txt"
        self.cache_file = self.config_dir / ".dependency_cache.json"
        
        # Ensure config directory exists
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize default whitelist if it doesn't exist
        if not self.whitelist_file.exists():
            self._create_default_whitelist()
    
    def _create_default_whitelist(self):
        """Create a default whitelist file from requirements/whitelist.default.txt if available, else create an empty file."""
        requirements_dir = Path(__file__).parent.parent.parent / 'requirements'
        default_whitelist_path = requirements_dir / 'whitelist.default.txt'
        try:
            if default_whitelist_path.exists():
                with open(default_whitelist_path, 'r') as src, open(self.whitelist_file, 'w') as dst:
                    dst.write("# Contest Environment Manager - Whitelisted Sites\n")
                    dst.write("# Add one domain per line\n")
                    dst.write("# Comments start with #\n\n")
                    for line in src:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            dst.write(f"{line}\n")
            else:
                with open(self.whitelist_file, 'w') as f:
                    f.write("# Contest Environment Manager - Whitelisted Sites\n")
                    f.write("# Add one domain per line\n")
                    f.write("# Comments start with #\n\n")
            print_status(f"Created default whitelist: {self.whitelist_file}")
        except Exception as e:
            print_error(f"Failed to create default whitelist: {e}")
    
    def load_whitelist(self) -> Set[str]:
        """Load whitelisted domains from file."""
        try:
            if not self.whitelist_file.exists():
                return set()
            
            with open(self.whitelist_file, 'r') as f:
                domains = set()
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        domains.add(line.lower())
                return domains
        except Exception as e:
            print_error(f"Failed to load whitelist: {e}")
            return set()
    
    def save_whitelist(self, domains: Set[str]) -> bool:
        """Save whitelisted domains to file."""
        try:
            with open(self.whitelist_file, 'w') as f:
                f.write("# Contest Environment Manager - Whitelisted Sites\n")
                f.write("# Add one domain per line\n")
                f.write("# Comments start with #\n\n")
                for domain in sorted(domains):
                    f.write(f"{domain}\n")
            return True
        except Exception as e:
            print_error(f"Failed to save whitelist: {e}")
            return False
    
    def add_domain(self, domain: str) -> bool:
        """Add a domain to the whitelist."""
        # Normalize domain
        domain = self._normalize_domain(domain)
        
        if not domain:
            print_error("Invalid domain format")
            return False
        
        domains = self.load_whitelist()
        
        if domain in domains:
            print_warning(f"Domain '{domain}' is already in the whitelist")
            return True
        
        domains.add(domain)
        
        if self.save_whitelist(domains):
            print_status(f"Added '{domain}' to whitelist")
            print_status(f"Total domains: {len(domains)}")
            return True
        else:
            print_error(f"Failed to add '{domain}' to whitelist")
            return False
    
    def remove_domain(self, domain: str) -> bool:
        """Remove a domain from the whitelist."""
        domain = self._normalize_domain(domain)
        
        if not domain:
            print_error("Invalid domain format")
            return False
        
        domains = self.load_whitelist()
        
        if domain not in domains:
            print_warning(f"Domain '{domain}' is not in the whitelist")
            return True
        
        domains.remove(domain)
        
        if self.save_whitelist(domains):
            print_status(f"Removed '{domain}' from whitelist")
            print_status(f"Total domains: {len(domains)}")
            return True
        else:
            print_error(f"Failed to remove '{domain}' from whitelist")
            return False
    
    def list_domains(self) -> List[str]:
        """List all domains in the whitelist."""
        domains = self.load_whitelist()
        return sorted(domains)
    
    def show_domains(self):
        """Display all domains in the whitelist."""
        domains = self.list_domains()
        
        if not domains:
            print("No domains in whitelist")
            return
        
        print(f"Whitelisted domains ({len(domains)} total):")
        print("=" * 50)
        for domain in domains:
            print(f"  {domain}")
        print("=" * 50)
    
    def load_dependencies(self) -> Dict[str, List[str]]:
        """Load dependency cache."""
        try:
            if self.cache_file.exists():
                with open(self.cache_file, 'r') as f:
                    return json.load(f)
        except Exception as e:
            print_warning(f"Failed to load dependency cache: {e}")
        
        return {}
    
    def show_dependencies(self):
        """Show resolved dependencies for whitelisted domains."""
        domains = self.load_whitelist()
        
        if not domains:
            print("No domains in whitelist")
            return
        
        # Check if cache file exists
        if not self.cache_file.exists():
            print("No dependency cache found.")
            print("Run 'contest-manager restrict --user <username>' first to analyze dependencies.")
            return
        
        try:
            cache = self.load_dependencies()
        except Exception as e:
            print_error(f"Failed to load dependency cache: {e}")
            return
        
        if not cache:
            print("Dependency cache is empty.")
            print("Run 'contest-manager restrict --user <username>' first to analyze dependencies.")
            return
        
        # Get cache file modification time
        cache_mtime = os.path.getmtime(self.cache_file)
        cache_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(cache_mtime))
        
        # Count total dependencies
        all_dependencies = set()
        analyzed_count = 0
        for domain in domains:
            if domain in cache:
                analyzed_count += 1
                all_dependencies.update(cache[domain])
        
        print(f"Resolved Dependencies ({len(all_dependencies)} total)")
        print("=" * 60)
        print(f"Based on {len(domains)} whitelisted domains")
        print(f"Analyzed: {analyzed_count}/{len(domains)} domains")
        print(f"Cache updated: {cache_time}")
        print()
        
        # Show dependencies per domain
        for domain in sorted(domains):
            if domain in cache:
                deps = cache[domain]
                if deps:
                    print(f"📊 {domain} → {len(deps)} dependencies:")
                    for dep in sorted(deps):
                        print(f"   • {dep}")
                    print()
                else:
                    print(f"📊 {domain} → No dependencies found")
                    print()
            else:
                print(f"📊 {domain} → Not analyzed yet")
                print()
        
        # Show all unique dependencies
        if all_dependencies:
            print("🔗 All Unique Dependencies:")
            print("-" * 30)
            for dep in sorted(all_dependencies):
                print(f"   • {dep}")
            
            print("-" * 30)
            print(f"Total: {len(all_dependencies)} unique dependencies")
            print()
            print("💡 These dependencies will be automatically allowed when restrictions are active.")
        
        # Show refresh hint if not all domains analyzed
        if analyzed_count < len(domains):
            print()
            print("🔄 Some domains haven't been analyzed yet.")
            print("   Run 'contest-manager restrict --user <username>' to analyze all domains.")
    
    def setup_user(self, username: str) -> bool:
        """Set up a contest user with all required software and configurations.
        
        Args:
            username: The username to set up
            
        Returns:
            True if successful, False otherwise
        """
        try:
            print_header(f"Contest Environment Setup for user '{username}'")
            
            # Step 1: Setup user account
            print_step(1, f"Setting up user account '{username}'")
            if not create_contest_user(username):
                print_error("Failed to create contest user")
                return False
            
            # Step 2: Install programming languages
            print_step(2, "Installing programming languages")
            if not install_programming_languages():
                print_error("Failed to install programming languages")
                return False
            
            # Step 3: Install basic editors
            print_step(3, "Installing basic editors")
            if not install_basic_editors():
                print_error("Failed to install basic editors")
                return False
            
            # Step 4: Install Sublime Text
            print_step(4, "Installing Sublime Text")
            if not install_sublime_text():
                print_warning("Failed to install Sublime Text")
            
            # Step 5: Install VS Code
            print_step(5, "Installing VS Code")
            if not install_vscode():
                print_warning("Failed to install VS Code")
            else:
                if not install_vscode_extensions(username):
                    print_warning("Failed to install VS Code extensions")
            
            # Step 6: Install GRUB Customizer
            print_step(6, "Installing GRUB Customizer")
            if not install_grub_customizer():
                print_warning("Failed to install GRUB Customizer")
            
            # Step 7: Install browsers
            print_step(7, "Installing browsers")
            if not install_browsers():
                print_warning("Failed to install browsers")
            
            # Step 8: System configurations
            print_step(8, "Configuring system settings")
            disable_system_updates()
            
            # Step 9: Fix permissions and configurations
            print_step(9, "Fixing permissions and configurations")
            fix_vscode_keyring(username)
            fix_codeblocks_permissions(username)
            fix_user_permissions(username)
            create_project_directories(username)
            add_user_to_groups(username)
            
            # Step 10: System cleanup
            print_step(10, "Cleaning up system")
            cleanup_system()
            clean_temporary_files(username)
            
            # Step 11: Verify installation
            print_step(11, "Verifying installation")
            if not verify_essential_software():
                print_warning("Some essential software verification failed")
            
            print_status(f"✅ Setup completed successfully for user '{username}'")
            return True
            
        except Exception as e:
            print_error(f"Setup failed: {e}")
            return False
    
    def reset_user(self, username: str) -> bool:
        """Reset a contest user to clean state.
        
        Args:
            username: The username to reset
            
        Returns:
            True if successful, False otherwise
        """
        try:
            print_header(f"Resetting user '{username}' to clean state")
            
            # Remove any existing restrictions first
            print_step(1, "Removing existing restrictions")
            self.remove_restrictions(username)
            
            # Reset user account
            print_step(2, "Resetting user account")
            if not reset_user_account(username):
                print_error("Failed to reset user account")
                return False
            
            # Fix permissions
            print_step(3, "Fixing permissions")
            fix_user_permissions(username)
            create_project_directories(username)
            
            # Clean temporary files
            print_step(4, "Cleaning temporary files")
            clean_temporary_files()
            
            print_status(f"✅ User '{username}' reset successfully")
            return True
            
        except Exception as e:
            print_error(f"Reset failed: {e}")
            return False
    
    def _save_iptables_rules(self, username: str):
        """Save current iptables rules for both IPv4 and IPv6 for the user."""
        rules_dir = Path("/etc/iptables")
        rules_dir.mkdir(parents=True, exist_ok=True)
        rules_file_v4 = rules_dir / f"contest-rules-{username}.v4"
        rules_file_v6 = rules_dir / f"contest-rules-{username}.v6"
        try:
            subprocess.run(f"iptables-save > {rules_file_v4}", shell=True, check=True)
            subprocess.run(f"ip6tables-save > {rules_file_v6}", shell=True, check=True)
            print_status(f"iptables rules saved to {rules_file_v4} and {rules_file_v6}")
        except Exception as e:
            print_warning(f"Failed to save iptables rules: {e}")

    def _create_restore_service(self, username: str):
        """Create a systemd service to restore iptables rules on boot."""
        service_name = f"contest-restore-{username}.service"
        service_path = Path(f"/etc/systemd/system/{service_name}")
        rules_file_v4 = f"/etc/iptables/contest-rules-{username}.v4"
        rules_file_v6 = f"/etc/iptables/contest-rules-{username}.v6"
        script = f"""#!/bin/bash\n"
        script += f"if [ -f '{rules_file_v4}' ]; then iptables-restore < '{rules_file_v4}'; fi\n"
        script += f"if [ -f '{rules_file_v6}' ]; then ip6tables-restore < '{rules_file_v6}'; fi\n"
        script += """
        service_content = f"""[Unit]
Description=Contest Environment Rules Restoration for {username}
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '{script.strip()}'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""
        try:
            with open(service_path, 'w') as f:
                f.write(service_content)
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", service_name], check=True)
            print_status(f"Startup restoration service created: {service_path}")
        except Exception as e:
            print_warning(f"Failed to create/enable restore service: {e}")

    def _try_netfilter_persistent(self):
        """Try to use netfilter-persistent for automatic rule persistence."""
        try:
            subprocess.run(["apt", "install", "-y", "netfilter-persistent"], check=False, capture_output=True)
            subprocess.run(["netfilter-persistent", "save"], check=False, capture_output=True)
            print_status("netfilter-persistent configured for rule persistence")
            return True
        except Exception:
            print_warning("netfilter-persistent not available, using custom solution")
            return False

    def apply_restrictions(self, username: str) -> bool:
        """Apply network and USB restrictions for a user, then analyze and cache dependencies. Also persist iptables rules."""
        try:
            print_header(f"Applying restrictions for user '{username}'")

            # Apply network restrictions
            print_step(1, "Applying network restrictions")
            if not apply_network_restrictions(username, str(self.whitelist_file)):
                print_error("Failed to apply network restrictions")
                return False

            # Apply USB restrictions
            print_step(2, "Applying USB restrictions")
            if not apply_usb_restrictions(username):
                print_error("Failed to apply USB restrictions")
                return False

            # Analyze dependencies for each whitelisted domain
            print_step(3, "Analyzing dependencies for whitelisted domains")
            try:
                from ..utils.dependency_analyzer import DependencyAnalyzer
                analyzer = DependencyAnalyzer()
                whitelist = self.list_domains()
                dependency_cache = {}
                for domain in whitelist:
                    try:
                        deps = list(analyzer.analyze_domain(domain))
                        dependency_cache[domain] = deps
                    except Exception as e:
                        print_warning(f"Dependency analysis failed for {domain}: {e}")
                        dependency_cache[domain] = []
                # Save dependency cache
                with open(self.cache_file, 'w') as f:
                    json.dump(dependency_cache, f, indent=2)
                print_status(f"Dependency cache updated: {self.cache_file}")
            except Exception as e:
                print_error(f"Dependency analysis failed: {e}")

            # Save iptables rules and create restore service
            print_step(4, "Persisting iptables rules for reboot")
            if not self._try_netfilter_persistent():
                self._save_iptables_rules(username)
                self._create_restore_service(username)

            print_status(f"✅ Restrictions applied successfully for user '{username}'")
            return True

        except Exception as e:
            print_error(f"Failed to apply restrictions: {e}")
            return False
    
    def remove_restrictions(self, username: str) -> bool:
        """Remove network and USB restrictions for a user.
        
        Args:
            username: The username to remove restrictions for
            
        Returns:
            True if successful, False otherwise
        """
        try:
            print_header(f"Removing restrictions for user '{username}'")
            
            # Remove network restrictions
            print_step(1, "Removing network restrictions")
            if not remove_network_restrictions(username):
                print_error("Failed to remove network restrictions")
                return False
            
            # Remove USB restrictions
            print_step(2, "Removing USB restrictions")
            if not remove_usb_restrictions(username):
                print_error("Failed to remove USB restrictions")
                return False
            
            print_status(f"✅ Restrictions removed successfully for user '{username}'")
            return True
            
        except Exception as e:
            print_error(f"Failed to remove restrictions: {e}")
            return False
    
    def show_status(self, username: str) -> bool:
        """Show current restriction status for a user.
        
        Args:
            username: The username to check status for
            
        Returns:
            True if successful, False otherwise
        """
        try:
            print_header(f"Restriction Status for user '{username}'")
            
            # Check network restrictions
            print_step(1, "Checking network restrictions")
            network_status = self._check_network_status(username)
            
            # Check USB restrictions
            print_step(2, "Checking USB restrictions")
            usb_status = self._check_usb_status(username)
            
            # Display status
            print("\n" + "=" * 50)
            print(f"Status for user: {username}")
            print("=" * 50)
            print(f"Network restrictions: {'✅ ACTIVE' if network_status else '❌ INACTIVE'}")
            print(f"USB restrictions:     {'✅ ACTIVE' if usb_status else '❌ INACTIVE'}")
            print("=" * 50)
            
            return True
            
        except Exception as e:
            print_error(f"Failed to check status: {e}")
            return False
    
    def _check_network_status(self, username: str) -> bool:
        """Check if network restrictions are active for a user."""
        try:
            # Check if iptables rules exist for the user
            result = subprocess.run(
                ['iptables', '-t', 'mangle', '-L', 'OUTPUT', '-v', '-n'],
                capture_output=True, text=True
            )
            
            if result.returncode == 0:
                return f"--uid-owner {username}" in result.stdout
            
            return False
        except Exception:
            return False
    
    def _check_usb_status(self, username: str) -> bool:
        """Check if USB restrictions are active for a user."""
        try:
            # Check if udev rules exist
            udev_rules_path = Path("/etc/udev/rules.d/99-contest-usb-block.rules")
            if udev_rules_path.exists():
                with open(udev_rules_path, 'r') as f:
                    content = f.read()
                    return "SUBSYSTEM==\"usb\"" in content
            
            return False
        except Exception:
            return False

    def _normalize_domain(self, domain: str) -> str:
        """Normalize domain name."""
        if not domain:
            return ""
        
        # Remove protocol
        domain = domain.replace('http://', '').replace('https://', '')
        
        # Remove path
        domain = domain.split('/')[0]
        
        # Remove port
        domain = domain.split(':')[0]
        
        # Convert to lowercase
        domain = domain.lower().strip()
        
        # Basic validation
        if not domain or '.' not in domain:
            return ""
        
        return domain
    
    def _create_periodic_refresh_service(self, username: str, interval_minutes: int = 30):
        """Create a systemd service and timer to periodically re-analyze dependencies and reapply restrictions."""
        service_name = f"contest-refresh-{username}.service"
        timer_name = f"contest-refresh-{username}.timer"
        service_path = Path(f"/etc/systemd/system/{service_name}")
        timer_path = Path(f"/etc/systemd/system/{timer_name}")
        # The CLI command to reapply restrictions
        exec_cmd = f"/usr/bin/contest-manager restrict {username}"
        service_content = f"""[Unit]
Description=Contest Environment Periodic Restriction Refresh for {username}
After=network.target

[Service]
Type=oneshot
ExecStart={exec_cmd}

[Install]
WantedBy=multi-user.target
"""
        timer_content = f"""[Unit]
Description=Timer for periodic contest restriction refresh ({interval_minutes} min)

[Timer]
OnBootSec=5min
OnUnitActiveSec={interval_minutes}min

[Install]
WantedBy=timers.target
"""
        try:
            with open(service_path, 'w') as f:
                f.write(service_content)
            with open(timer_path, 'w') as f:
                f.write(timer_content)
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", timer_name], check=True)
            subprocess.run(["systemctl", "start", timer_name], check=True)
            print_status(f"Periodic refresh service and timer created: {service_path}, {timer_path}")
        except Exception as e:
            print_warning(f"Failed to create/enable periodic refresh service/timer: {e}")

    def install_periodic_refresh(self, username: str, interval_minutes: int = 30):
        """Public method to install the periodic refresh systemd job for a user."""
        print_step("*", f"Setting up periodic dependency refresh every {interval_minutes} minutes for '{username}'")
        self._create_periodic_refresh_service(username, interval_minutes)
