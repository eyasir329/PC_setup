#!/usr/bin/env python3
"""
Intelligent Contest Environment Restrictor
Implements comprehensive restrictions for contest environments:
- Blocks internet access except whitelisted sites and their essential dependencies
- Blocks USB storage devices while allowing keyboards/mice
- Dynamically discovers and allows only essential dependencies
- Handles IPv4/IPv6 and dynamic IPs
"""

import os
import sys
import time
import argparse
import json
from pathlib import Path
from typing import List, Set, Dict
import subprocess

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'utils'))

from dependency_analyzer import DependencyAnalyzer
from network_restrictor import NetworkRestrictor
from usb_restrictor import USBRestrictor
from common import print_header, print_status, print_error, print_warning


class ContestRestrictor:
    def __init__(self, user: str, config_dir: str = None):
        self.user = user
        self.config_dir = config_dir or os.path.dirname(os.path.dirname(__file__))
        self.whitelist_file = os.path.join(self.config_dir, 'whitelist.txt')
        self.cache_file = os.path.join(self.config_dir, '.dependency_cache.json')
        
        # Initialize components
        self.dependency_analyzer = DependencyAnalyzer()
        self.network_restrictor = NetworkRestrictor(user)
        self.usb_restrictor = USBRestrictor(user)
        
        # Configuration
        self.whitelisted_sites = set()
        self.essential_dependencies = set()
        self.restriction_active = False
        
    def load_whitelist(self) -> bool:
        """Load whitelisted sites from file."""
        try:
            if not os.path.exists(self.whitelist_file):
                print_error(f"Whitelist file not found: {self.whitelist_file}")
                return False
            
            with open(self.whitelist_file, 'r') as f:
                sites = [line.strip() for line in f if line.strip() and not line.startswith('#')]
            
            self.whitelisted_sites = set(sites)
            print_status(f"Loaded {len(self.whitelisted_sites)} whitelisted sites")
            
            return True
        except Exception as e:
            print_error(f"Failed to load whitelist: {e}")
            return False
    
    def load_dependency_cache(self) -> Dict:
        """Load cached dependency analysis results."""
        try:
            if os.path.exists(self.cache_file):
                with open(self.cache_file, 'r') as f:
                    cache = json.load(f)
                print_status(f"Loaded dependency cache with {len(cache)} entries")
                return cache
        except Exception as e:
            print_warning(f"Failed to load dependency cache: {e}")
        
        return {}
    
    def save_dependency_cache(self, cache: Dict):
        """Save dependency analysis results to cache."""
        try:
            with open(self.cache_file, 'w') as f:
                json.dump(cache, f, indent=2)
            print_status("Dependency cache saved")
        except Exception as e:
            print_warning(f"Failed to save dependency cache: {e}")
    
    def analyze_dependencies(self, force_refresh: bool = False) -> bool:
        """Analyze dependencies for all whitelisted sites."""
        print_header("Analyzing Website Dependencies")
        
        # Load cached results
        cache = {} if force_refresh else self.load_dependency_cache()
        
        all_dependencies = set()
        
        for site in self.whitelisted_sites:
            print(f"→ Analyzing {site}...")
            
            # Check cache first
            if site in cache and not force_refresh:
                dependencies = set(cache[site])
                print_status(f"  Using cached dependencies: {len(dependencies)} domains")
            else:
                # Analyze site
                try:
                    dependencies = self.dependency_analyzer.analyze_site(site)
                    cache[site] = list(dependencies)
                    print_status(f"  Found {len(dependencies)} essential dependencies")
                except Exception as e:
                    print_error(f"  Failed to analyze {site}: {e}")
                    dependencies = set()
                    cache[site] = []
            
            all_dependencies.update(dependencies)
        
        # Save updated cache
        self.save_dependency_cache(cache)
        
        self.essential_dependencies = all_dependencies
        print_status(f"Total essential dependencies: {len(all_dependencies)}")
        
        return True
    
    def apply_network_restrictions(self) -> bool:
        """Apply network restrictions using iptables."""
        print_header("Applying Network Restrictions")
        
        try:
            # Initialize network restrictor
            if not self.network_restrictor.install_dependencies():
                print_error("Failed to install network dependencies")
                return False
            
            # Setup iptables chains
            if not self.network_restrictor.setup_iptables_chains():
                print_error("Failed to setup iptables chains")
                return False
            
            # Add whitelisted domains
            print("→ Adding whitelisted domains...")
            for domain in self.whitelisted_sites:
                if not self.network_restrictor.allow_domain(domain):
                    print_warning(f"Failed to allow domain: {domain}")
            
            # Add essential dependencies
            print("→ Adding essential dependencies...")
            for domain in self.essential_dependencies:
                if not self.network_restrictor.allow_domain(domain):
                    print_warning(f"Failed to allow dependency: {domain}")
            
            # Apply default restrictions
            if not self.network_restrictor.apply_default_restrictions():
                print_error("Failed to apply default restrictions")
                return False
            
            print_status("Network restrictions applied successfully")
            return True
            
        except Exception as e:
            print_error(f"Failed to apply network restrictions: {e}")
            return False
    
    def apply_usb_restrictions(self) -> bool:
        """Apply USB storage restrictions."""
        print_header("Applying USB Storage Restrictions")
        
        try:
            return self.usb_restrictor.apply_usb_restrictions()
        except Exception as e:
            print_error(f"Failed to apply USB restrictions: {e}")
            return False
    
    def check_dependencies(self) -> bool:
        """Check if all required dependencies are available."""
        print_header("Checking System Dependencies")
        
        required_tools = [
            'iptables', 'ip6tables', 'udevadm', 'systemctl',
            'lsusb', 'mount', 'umount', 'dig', 'nslookup'
        ]
        
        missing_tools = []
        for tool in required_tools:
            try:
                subprocess.run(['which', tool], check=True, capture_output=True)
            except subprocess.CalledProcessError:
                missing_tools.append(tool)
        
        if missing_tools:
            print_error(f"Missing required tools: {', '.join(missing_tools)}")
            print("Please install missing tools and try again.")
            return False
        
        # Check Python dependencies
        try:
            import selenium
            import dns.resolver
            import requests
        except ImportError as e:
            print_error(f"Missing Python dependencies: {e}")
            print("Please install required packages: pip install selenium dnspython requests")
            return False
        
        print_status("All dependencies available")
        return True
    
    def create_monitoring_service(self) -> bool:
        """Create systemd service for monitoring and updating restrictions."""
        service_content = f"""[Unit]
Description=Contest Environment Monitor
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 {os.path.abspath(__file__)} --user {self.user} --monitor
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
"""
        
        timer_content = f"""[Unit]
Description=Contest Environment Update Timer
Requires=contest-monitor.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min

[Install]
WantedBy=timers.target
"""
        
        try:
            # Create service file
            with open('/etc/systemd/system/contest-monitor.service', 'w') as f:
                f.write(service_content)
            
            # Create timer file
            with open('/etc/systemd/system/contest-monitor.timer', 'w') as f:
                f.write(timer_content)
            
            # Reload systemd and enable
            subprocess.run(['systemctl', 'daemon-reload'], check=True)
            subprocess.run(['systemctl', 'enable', 'contest-monitor.timer'], check=True)
            subprocess.run(['systemctl', 'start', 'contest-monitor.timer'], check=True)
            
            print_status("Monitoring service created and started")
            return True
            
        except Exception as e:
            print_error(f"Failed to create monitoring service: {e}")
            return False
    
    def monitor_and_update(self):
        """Monitor and update restrictions periodically."""
        print_header("Contest Environment Monitor")
        
        while True:
            try:
                print(f"→ Updating restrictions at {time.strftime('%Y-%m-%d %H:%M:%S')}")
                
                # Smart dependency update (checks freshness)
                if not self.smart_dependency_update():
                    print_warning("Failed to update dependencies")
                
                # Update IP addresses for domains
                self.network_restrictor.update_domain_ips()
                
                # Check system status
                print("→ Checking system status...")
                
                # Sleep for 30 minutes
                time.sleep(1800)
                
            except KeyboardInterrupt:
                print("\n→ Monitor stopping...")
                break
            except Exception as e:
                print_error(f"Monitor error: {e}")
                time.sleep(300)  # Wait 5 minutes on error
    
    def get_restriction_status(self) -> Dict:
        """Get current restriction status."""
        return {
            'user': self.user,
            'network_active': self.network_restrictor.is_active(),
            'usb_active': self.usb_restrictor.get_restriction_status(),
            'whitelisted_sites': len(self.whitelisted_sites),
            'essential_dependencies': len(self.essential_dependencies),
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
        }
    
    def show_status(self):
        """Show current restriction status."""
        print_header("Contest Environment Status")
        
        status = self.get_restriction_status()
        
        print(f"User: {status['user']}")
        print(f"Network restrictions: {'✅ Active' if status['network_active'] else '❌ Inactive'}")
        print(f"USB restrictions: {'✅ Active' if status['usb_active']['udev_rules_active'] else '❌ Inactive'}")
        print(f"Whitelisted sites: {status['whitelisted_sites']}")
        print(f"Essential dependencies: {status['essential_dependencies']}")
        print(f"Last updated: {status['timestamp']}")
        
        # Show network details
        print("\n📊 Network Status:")
        self.network_restrictor.show_status()
        
        # Show USB details
        print("\n📊 USB Status:")
        self.usb_restrictor.show_status()
        
        # Show whitelisted sites
        if self.whitelisted_sites:
            print("\n📊 Whitelisted Sites:")
            for site in sorted(self.whitelisted_sites):
                print(f"   - {site}")
    
    def apply_restrictions(self, force_refresh: bool = False, skip_usb: bool = False, skip_network: bool = False) -> bool:
        """Apply all restrictions."""
        print_header("Applying Contest Environment Restrictions")
        
        # Check if running as root
        if os.geteuid() != 0:
            print_error("This script must be run as root to modify system settings")
            return False
        
        # Check dependencies
        if not self.check_dependencies():
            return False
        
        # Load whitelist
        if not self.load_whitelist():
            return False
        
        success = True
        
        # Analyze dependencies
        if not skip_network:
            if not self.analyze_dependencies(force_refresh):
                success = False
        
        # Apply network restrictions
        if not skip_network:
            if not self.apply_network_restrictions():
                success = False
        
        # Apply USB restrictions
        if not skip_usb:
            if not self.apply_usb_restrictions():
                success = False
        
        # Create monitoring service
        if success:
            self.create_monitoring_service()
            
        # Ensure persistence after reboot
        if success:
            self.ensure_persistence()
        
        if success:
            print_header("✅ Contest Environment Restrictions Applied Successfully")
            print("The following restrictions are now active:")
            print("   🌐 Internet access limited to whitelisted sites and dependencies")
            print("   🔒 USB storage devices blocked (keyboards/mice still work)")
            print("   📊 Monitoring service started for automatic updates")
            print(f"   👤 Restrictions applied for user: {self.user}")
            
        else:
            print_header("❌ Some Restrictions Failed to Apply")
            print("Please check the errors above and try again.")
        
        return success
    
    def remove_restrictions(self) -> bool:
        """Remove all restrictions."""
        print_header("Removing Contest Environment Restrictions")
        
        # Check if running as root
        if os.geteuid() != 0:
            print_error("This script must be run as root to modify system settings")
            return False
        
        success = True
        
        # Remove network restrictions
        try:
            if not self.network_restrictor.remove_restrictions():
                success = False
        except Exception as e:
            print_error(f"Failed to remove network restrictions: {e}")
            success = False
        
        # Remove USB restrictions
        try:
            if not self.usb_restrictor.remove_usb_restrictions():
                success = False
        except Exception as e:
            print_error(f"Failed to remove USB restrictions: {e}")
            success = False
        
        # Remove monitoring service
        try:
            subprocess.run(['systemctl', 'stop', 'contest-monitor.timer'], check=False)
            subprocess.run(['systemctl', 'disable', 'contest-monitor.timer'], check=False)
            
            for service_file in ['/etc/systemd/system/contest-monitor.service', 
                               '/etc/systemd/system/contest-monitor.timer']:
                if os.path.exists(service_file):
                    os.remove(service_file)
            
            subprocess.run(['systemctl', 'daemon-reload'], check=True)
            print_status("Monitoring service removed")
            
        except Exception as e:
            print_warning(f"Failed to remove monitoring service: {e}")
        
        if success:
            print_header("✅ Contest Environment Restrictions Removed Successfully")
            print("All restrictions have been removed:")
            print("   🌐 Internet access restored")
            print("   🔓 USB storage devices allowed")
            print("   📊 Monitoring service stopped")
        else:
            print_header("❌ Some Restrictions Failed to Remove")
            print("Please check the errors above and try manual cleanup if needed.")
        
        return success
    
    def ensure_persistence(self) -> bool:
        """Ensure restrictions persist after reboot."""
        print("→ Ensuring persistence after reboot...")
        
        try:
            # Save current iptables rules
            self.save_iptables_rules()
            
            # Create startup script to restore rules
            self.create_startup_script()
            
            # Install netfilter-persistent if available
            self.install_netfilter_persistent()
            
            print_status("Persistence configured successfully")
            return True
        except Exception as e:
            print_error(f"Failed to configure persistence: {e}")
            return False
    
    def save_iptables_rules(self):
        """Save current iptables rules to file."""
        rules_file = f"/etc/iptables/contest-rules-{self.user}"
        
        # Create directory if it doesn't exist
        os.makedirs("/etc/iptables", exist_ok=True)
        
        # Save IPv4 rules
        subprocess.run(f"iptables-save > {rules_file}.v4", shell=True, check=True)
        
        # Save IPv6 rules
        subprocess.run(f"ip6tables-save > {rules_file}.v6", shell=True, check=True)
        
        print_status(f"iptables rules saved to {rules_file}")
    
    def create_startup_script(self):
        """Create script to restore rules on boot."""
        script_content = f"""#!/bin/bash
# Contest Environment Rule Restoration Script
# Auto-generated by restrict.py

# Restore IPv4 rules
if [ -f "/etc/iptables/contest-rules-{self.user}.v4" ]; then
    iptables-restore < /etc/iptables/contest-rules-{self.user}.v4
fi

# Restore IPv6 rules
if [ -f "/etc/iptables/contest-rules-{self.user}.v6" ]; then
    ip6tables-restore < /etc/iptables/contest-rules-{self.user}.v6
fi
"""
        
        script_path = f"/etc/systemd/system/contest-restore-{self.user}.service"
        service_content = f"""[Unit]
Description=Contest Environment Rules Restoration for {self.user}
After=network.target
Before=contest-monitor.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '{script_content.strip()}'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""
        
        with open(script_path, 'w') as f:
            f.write(service_content)
        
        # Enable the service
        subprocess.run(['systemctl', 'enable', f'contest-restore-{self.user}.service'], check=True)
        
        print_status(f"Startup restoration service created: {script_path}")
    
    def install_netfilter_persistent(self):
        """Install netfilter-persistent for automatic rule persistence."""
        try:
            # Try to install netfilter-persistent
            subprocess.run(['apt', 'install', '-y', 'netfilter-persistent'], 
                         check=False, capture_output=True)
            
            # If successful, save rules using netfilter-persistent
            subprocess.run(['netfilter-persistent', 'save'], 
                         check=False, capture_output=True)
            
            print_status("netfilter-persistent configured")
        except Exception:
            print_warning("netfilter-persistent not available, using custom solution")
    
    def check_dependency_freshness(self) -> bool:
        """Check if dependencies need to be re-analyzed."""
        import time
        
        cache_age_hours = 24  # Re-analyze every 24 hours
        
        if not os.path.exists(self.cache_file):
            return True  # No cache, need to analyze
        
        cache_mtime = os.path.getmtime(self.cache_file)
        current_time = time.time()
        age_hours = (current_time - cache_mtime) / 3600
        
        if age_hours > cache_age_hours:
            print_warning(f"Dependency cache is {age_hours:.1f} hours old, recommend refresh")
            return True
        
        return False
    
    def smart_dependency_update(self) -> bool:
        """Intelligently update dependencies based on age and changes."""
        print("→ Checking dependency freshness...")
        
        # Check if cache is old
        needs_refresh = self.check_dependency_freshness()
        
        if needs_refresh:
            print("→ Dependencies are stale, performing refresh...")
            return self.analyze_dependencies(force_refresh=True)
        else:
            print("→ Dependencies are fresh, skipping analysis")
            return True
    
def main():
    parser = argparse.ArgumentParser(
        description="Intelligent Contest Environment Restrictor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo python3 restrict.py --user alice --apply
  sudo python3 restrict.py --user alice --remove
  sudo python3 restrict.py --user alice --status
  sudo python3 restrict.py --user alice --apply --force-refresh
  sudo python3 restrict.py --user alice --apply --skip-usb
        """
    )
    
    parser.add_argument('--user', required=True, help='Username to apply restrictions for')
    parser.add_argument('--apply', action='store_true', help='Apply all restrictions')
    parser.add_argument('--remove', action='store_true', help='Remove all restrictions')
    parser.add_argument('--status', action='store_true', help='Show current restriction status')
    parser.add_argument('--monitor', action='store_true', help='Run monitoring service')
    parser.add_argument('--force-refresh', action='store_true', help='Force refresh of dependency analysis')
    parser.add_argument('--skip-usb', action='store_true', help='Skip USB restrictions')
    parser.add_argument('--skip-network', action='store_true', help='Skip network restrictions')
    parser.add_argument('--config-dir', help='Configuration directory path')
    
    args = parser.parse_args()
    
    # Create restrictor instance
    restrictor = ContestRestrictor(args.user, args.config_dir)
    
    # Execute requested action
    if args.apply:
        success = restrictor.apply_restrictions(
            force_refresh=args.force_refresh,
            skip_usb=args.skip_usb,
            skip_network=args.skip_network
        )
        sys.exit(0 if success else 1)
    
    elif args.remove:
        success = restrictor.remove_restrictions()
        sys.exit(0 if success else 1)
    
    elif args.status:
        restrictor.load_whitelist()
        restrictor.show_status()
        sys.exit(0)
    
    elif args.monitor:
        restrictor.load_whitelist()
        restrictor.monitor_and_update()
        sys.exit(0)
    
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()