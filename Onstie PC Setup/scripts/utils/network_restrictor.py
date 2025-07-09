#!/usr/bin/env python3
"""
Network Restriction Manager
Manages iptables rules for intelligent internet filtering.
"""

import subprocess
import socket
import ipaddress
import time
from typing import Set, List, Dict
import dns.resolver
import dns.exception
import os


class NetworkRestrictor:
    def __init__(self, user: str):
        self.user = user
        self.user_uid = self.get_user_uid(user)
        self.chain_in = f"CONTEST_{user.upper()}_IN"
        self.chain_out = f"CONTEST_{user.upper()}_OUT"
        self.allowed_domains = set()
        self.domain_ips = {}
        
    def get_user_uid(self, user: str) -> int:
        """Get UID for the specified user."""
        try:
            import pwd
            return pwd.getpwnam(user).pw_uid
        except KeyError:
            raise ValueError(f"User '{user}' does not exist")
    
    def run_command(self, cmd: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Run a command and return the result."""
        try:
            result = subprocess.run(cmd, check=check, capture_output=True, text=True)
            return result
        except subprocess.CalledProcessError as e:
            if check:
                print(f"❌ Command failed: {' '.join(cmd)}")
                print(f"Error: {e.stderr}")
                raise
            return e
    
    def install_dependencies(self):
        """Install required network tools."""
        required_packages = ['iptables', 'dnsutils', 'python3-dnspython']
        
        print("→ Installing network dependencies...")
        for package in required_packages:
            try:
                # Check if package is installed
                result = self.run_command(['dpkg', '-s', package], check=False)
                if result.returncode == 0:
                    print(f"  ✅ {package} already installed")
                else:
                    print(f"  📦 Installing {package}...")
                    self.run_command(['apt', 'install', '-y', package])
                    print(f"  ✅ {package} installed")
            except Exception as e:
                print(f"  ❌ Failed to install {package}: {e}")
    
    def clear_existing_rules(self):
        """Clear existing iptables rules for this user."""
        print(f"→ Clearing existing rules for user '{self.user}'...")
        
        # Remove jump rules
        self.run_command(['iptables', '-D', 'OUTPUT', '-m', 'owner', 
                         '--uid-owner', str(self.user_uid), '-j', self.chain_out], check=False)
        
        # Flush and delete chains
        for chain in [self.chain_in, self.chain_out]:
            self.run_command(['iptables', '-F', chain], check=False)
            self.run_command(['iptables', '-X', chain], check=False)
            
            # IPv6
            self.run_command(['ip6tables', '-F', chain], check=False)
            self.run_command(['ip6tables', '-X', chain], check=False)
        
        print("✅ Existing rules cleared")
    
    def create_chains(self):
        """Create iptables chains for the user."""
        print(f"→ Creating iptables chains for user '{self.user}'...")
        
        # Create IPv4 chains
        self.run_command(['iptables', '-N', self.chain_in])
        self.run_command(['iptables', '-N', self.chain_out])
        
        # Create IPv6 chains
        self.run_command(['ip6tables', '-N', self.chain_in], check=False)
        self.run_command(['ip6tables', '-N', self.chain_out], check=False)
        
        print("✅ Chains created")
    
    def setup_default_rules(self):
        """Setup default allow/deny rules."""
        print("→ Setting up default rules...")
        
        # IPv4 default rules
        # Allow established and related connections
        self.run_command(['iptables', '-A', self.chain_out, '-m', 'state', 
                         '--state', 'ESTABLISHED,RELATED', '-j', 'ACCEPT'])
        
        # Allow localhost
        self.run_command(['iptables', '-A', self.chain_out, '-d', '127.0.0.0/8', '-j', 'ACCEPT'])
        
        # Allow DNS (required for domain resolution)
        self.run_command(['iptables', '-A', self.chain_out, '-p', 'udp', '--dport', '53', '-j', 'ACCEPT'])
        self.run_command(['iptables', '-A', self.chain_out, '-p', 'tcp', '--dport', '53', '-j', 'ACCEPT'])
        
        # IPv6 default rules
        self.run_command(['ip6tables', '-A', self.chain_out, '-m', 'state', 
                         '--state', 'ESTABLISHED,RELATED', '-j', 'ACCEPT'], check=False)
        self.run_command(['ip6tables', '-A', self.chain_out, '-d', '::1/128', '-j', 'ACCEPT'], check=False)
        self.run_command(['ip6tables', '-A', self.chain_out, '-p', 'udp', '--dport', '53', '-j', 'ACCEPT'], check=False)
        self.run_command(['ip6tables', '-A', self.chain_out, '-p', 'tcp', '--dport', '53', '-j', 'ACCEPT'], check=False)
        
        print("✅ Default rules configured")
    
    def resolve_domain_ips(self, domain: str) -> Set[str]:
        """Resolve domain to IP addresses (both IPv4 and IPv6)."""
        ips = set()
        
        try:
            # Get IPv4 addresses
            try:
                ipv4_result = dns.resolver.resolve(domain, 'A')
                for ip in ipv4_result:
                    ips.add(str(ip))
            except dns.exception.DNSException:
                pass
            
            # Get IPv6 addresses
            try:
                ipv6_result = dns.resolver.resolve(domain, 'AAAA')
                for ip in ipv6_result:
                    ips.add(str(ip))
            except dns.exception.DNSException:
                pass
            
            # Also try common subdomains
            subdomains = ['www', 'api', 'cdn', 'static', 'assets']
            for subdomain in subdomains:
                subdomain_name = f"{subdomain}.{domain}"
                try:
                    ipv4_result = dns.resolver.resolve(subdomain_name, 'A')
                    for ip in ipv4_result:
                        ips.add(str(ip))
                except dns.exception.DNSException:
                    pass
                
                try:
                    ipv6_result = dns.resolver.resolve(subdomain_name, 'AAAA')
                    for ip in ipv6_result:
                        ips.add(str(ip))
                except dns.exception.DNSException:
                    pass
        
        except Exception as e:
            print(f"  ⚠️ Failed to resolve {domain}: {e}")
        
        return ips
    
    def add_domain_rules(self, domains: Set[str]):
        """Add iptables rules for allowed domains."""
        print(f"→ Adding rules for {len(domains)} domains...")
        
        total_ips = 0
        for domain in domains:
            print(f"  🔍 Resolving {domain}...")
            ips = self.resolve_domain_ips(domain)
            
            if ips:
                self.domain_ips[domain] = ips
                total_ips += len(ips)
                
                for ip in ips:
                    try:
                        # Determine if IPv4 or IPv6
                        ip_obj = ipaddress.ip_address(ip)
                        if ip_obj.version == 4:
                            self.run_command(['iptables', '-A', self.chain_out, '-d', ip, '-j', 'ACCEPT'])
                        else:
                            self.run_command(['ip6tables', '-A', self.chain_out, '-d', ip, '-j', 'ACCEPT'], check=False)
                    except ValueError:
                        print(f"    ❌ Invalid IP address: {ip}")
                    except Exception as e:
                        print(f"    ❌ Failed to add rule for {ip}: {e}")
                
                print(f"    ✅ {len(ips)} IPs added for {domain}")
            else:
                print(f"    ⚠️ No IPs found for {domain}")
        
        print(f"✅ Added rules for {total_ips} IP addresses")
    
    def add_essential_cdns(self):
        """Add rules for essential CDNs and services."""
        essential_cdns = [
            # Essential CDNs
            'cloudflare.com', 'cloudfront.net', 'fastly.com',
            'jsdelivr.net', 'unpkg.com', 'cdnjs.cloudflare.com',
            
            # Font services
            'fonts.googleapis.com', 'fonts.gstatic.com', 'typekit.net',
            
            # Security services
            'recaptcha.net', 'hcaptcha.com', 'gstatic.com',
            
            # Math rendering
            'mathjax.org', 'cdn.mathjax.org',
            
            # Essential APIs (filtered)
            'ajax.googleapis.com'
        ]
        
        print("→ Adding essential CDN rules...")
        self.add_domain_rules(set(essential_cdns))
    
    def finalize_rules(self):
        """Add final deny rules and apply user-specific rules."""
        print("→ Finalizing restriction rules...")
        
        # Add final REJECT rules
        self.run_command(['iptables', '-A', self.chain_out, '-j', 'REJECT', 
                         '--reject-with', 'icmp-host-unreachable'])
        self.run_command(['ip6tables', '-A', self.chain_out, '-j', 'REJECT', 
                         '--reject-with', 'icmp6-adm-prohibited'], check=False)
        
        # Apply rules to user
        self.run_command(['iptables', '-A', 'OUTPUT', '-m', 'owner', 
                         '--uid-owner', str(self.user_uid), '-j', self.chain_out])
        self.run_command(['ip6tables', '-A', 'OUTPUT', '-m', 'owner', 
                         '--uid-owner', str(self.user_uid), '-j', self.chain_out], check=False)
        
        print("✅ Restriction rules applied")
    
    def create_update_script(self, config_dir: str):
        """Create a script to update domain IPs periodically."""
        script_path = f"/usr/local/bin/update-contest-whitelist-{self.user}"
        
        script_content = f'''#!/usr/bin/env python3
"""
Automatic IP update script for contest restrictions.
"""

import sys
import os
sys.path.insert(0, '{os.path.dirname(__file__)}')

from network_restrictor import NetworkRestrictor

def main():
    restrictor = NetworkRestrictor('{self.user}')
    
    # Read current domains
    domains = set()
    whitelist_file = '{config_dir}/whitelist.txt'
    deps_file = '{config_dir}/dependencies.txt'
    
    for file_path in [whitelist_file, deps_file]:
        try:
            with open(file_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        domains.add(line)
        except FileNotFoundError:
            continue
    
    if domains:
        print(f"Updating IPs for {{len(domains)}} domains...")
        restrictor.update_domain_ips(domains)
        print("✅ IP update completed")
    else:
        print("⚠️ No domains found to update")

if __name__ == "__main__":
    main()
'''
        
        with open(script_path, 'w') as f:
            f.write(script_content)
        
        # Make executable
        subprocess.run(['chmod', '+x', script_path])
        print(f"✅ Update script created: {script_path}")
    
    def update_domain_ips(self, domains: Set[str]):
        """Update IP addresses for domains (for periodic updates)."""
        print("→ Updating domain IP addresses...")
        
        # Clear existing domain-specific rules (keep default rules)
        self.run_command(['iptables', '-F', self.chain_out])
        self.run_command(['ip6tables', '-F', self.chain_out], check=False)
        
        # Re-add default rules
        self.setup_default_rules()
        
        # Add updated domain rules
        self.add_domain_rules(domains)
        self.add_essential_cdns()
        
        # Finalize
        self.finalize_rules()
    
    def setup_iptables_chains(self) -> bool:
        """Setup iptables chains (wrapper for restrict.py compatibility)."""
        try:
            self.install_dependencies()
            self.clear_existing_rules()
            self.create_chains()
            self.setup_default_rules()
            return True
        except Exception as e:
            print(f"❌ Failed to setup iptables chains: {e}")
            return False
    
    def allow_domain(self, domain: str) -> bool:
        """Allow a single domain (wrapper for restrict.py compatibility)."""
        try:
            self.allowed_domains.add(domain)
            ips = self.resolve_domain_ips(domain)
            
            if ips:
                self.domain_ips[domain] = ips
                
                for ip in ips:
                    try:
                        ip_obj = ipaddress.ip_address(ip)
                        if ip_obj.version == 4:
                            self.run_command(['iptables', '-I', self.chain_out, '-d', ip, '-j', 'ACCEPT'])
                        else:
                            self.run_command(['ip6tables', '-I', self.chain_out, '-d', ip, '-j', 'ACCEPT'], check=False)
                    except ValueError:
                        print(f"    ❌ Invalid IP address: {ip}")
                        continue
                
                print(f"✅ Allowed domain {domain} with {len(ips)} IPs")
                return True
            else:
                print(f"⚠️ No IPs found for domain {domain}")
                return False
        except Exception as e:
            print(f"❌ Failed to allow domain {domain}: {e}")
            return False
    
    def apply_default_restrictions(self) -> bool:
        """Apply default restrictions (wrapper for restrict.py compatibility)."""
        try:
            self.finalize_rules()
            return True
        except Exception as e:
            print(f"❌ Failed to apply default restrictions: {e}")
            return False
    
    def remove_restrictions(self) -> bool:
        """Remove all network restrictions."""
        try:
            print(f"🔓 Removing network restrictions for user '{self.user}'...")
            
            # Remove jump rules
            self.run_command(['iptables', '-D', 'OUTPUT', '-m', 'owner', 
                             '--uid-owner', str(self.user_uid), '-j', self.chain_out], check=False)
            self.run_command(['ip6tables', '-D', 'OUTPUT', '-m', 'owner', 
                             '--uid-owner', str(self.user_uid), '-j', self.chain_out], check=False)
            
            # Flush and delete chains
            for chain in [self.chain_in, self.chain_out]:
                self.run_command(['iptables', '-F', chain], check=False)
                self.run_command(['iptables', '-X', chain], check=False)
                self.run_command(['ip6tables', '-F', chain], check=False)
                self.run_command(['ip6tables', '-X', chain], check=False)
            
            # Remove update script
            update_script = f"/usr/local/bin/update-contest-whitelist-{self.user}"
            if os.path.exists(update_script):
                os.remove(update_script)
                print(f"✅ Removed update script: {update_script}")
            
            # Clear internal state
            self.allowed_domains.clear()
            self.domain_ips.clear()
            
            print("✅ Network restrictions removed successfully")
            return True
            
        except Exception as e:
            print(f"❌ Failed to remove network restrictions: {e}")
            return False

    def apply_restrictions(self, domains: Set[str], dependencies: Set[str]):
        """Apply network restrictions for specified domains and dependencies."""
        print(f"🚫 Applying network restrictions for user '{self.user}'...")
        
        self.install_dependencies()
        self.clear_existing_rules()
        self.create_chains()
        self.setup_default_rules()
        
        # Combine domains and dependencies
        all_allowed_domains = domains.union(dependencies)
        print(f"→ Total allowed domains: {len(all_allowed_domains)}")
        
        self.add_domain_rules(all_allowed_domains)
        self.add_essential_cdns()
        self.finalize_rules()
        
        print("✅ Network restrictions applied successfully!")
        
        # Save allowed domains for updates
        self.allowed_domains = all_allowed_domains
        
        return True
    
    def is_active(self) -> bool:
        """Check if network restrictions are currently active."""
        try:
            # Check if our custom chains exist
            result = self.run_command(['iptables', '-L', self.chain_out], check=False)
            if result.returncode != 0:
                return False
            
            # Check if chains have rules
            result = self.run_command(['iptables', '-L', self.chain_out, '-n'], check=False)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                # If chain exists and has more than just the header lines
                return len(lines) > 2
            
            return False
        except:
            return False
    
    def show_status(self):
        """Show current restriction status."""
        active = self.is_active()
        print(f"   Network restrictions: {'✅ Active' if active else '❌ Inactive'}")
        
        if active:
            print(f"   Allowed domains: {len(self.allowed_domains)}")
            print(f"   Resolved IPs: {len(self.domain_ips)}")
            
            if self.allowed_domains:
                print("   Active domains:")
                for domain in sorted(self.allowed_domains):
                    ip_count = len(self.domain_ips.get(domain, []))
                    print(f"     - {domain} ({ip_count} IPs)")

def main():
    """Test the network restrictor."""
    import sys
    
    if len(sys.argv) != 2:
        print("Usage: python3 network_restrictor.py <username>")
        sys.exit(1)
    
    user = sys.argv[1]
    restrictor = NetworkRestrictor(user)
    
    # Test with some domains
    test_domains = {'codeforces.com', 'codechef.com'}
    test_deps = {'fonts.googleapis.com', 'cloudflare.com'}
    
    restrictor.apply_restrictions(test_domains, test_deps)


if __name__ == "__main__":
    main()
