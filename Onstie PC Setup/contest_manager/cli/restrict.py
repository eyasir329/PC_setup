#!/usr/bin/env python3
"""
Contest Environment Restrict CLI (Robust Squid Proxy Integration)
"""

import sys
import argparse
import subprocess
import pwd
from ..core.manager import ContestManager
from ..utils.common import check_root, get_project_root

SQUID_WHITELIST = "/etc/squid/whitelist.txt"
SQUID_HTTP_PORT = 3128
SQUID_HTTPS_PORT = 3129
SQUID_SERVICE = "squid"


def create_parser():
    parser = argparse.ArgumentParser(
        description="Enable internet restrictions for contest environment using Squid proxy (robust mode)",
        prog="contest-restrict"
    )
    parser.add_argument('user', nargs='?', default='participant', help='Username to restrict (default: participant)')
    parser.add_argument('--config-dir', type=str, help='Configuration directory path (default: project root)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose output')
    return parser


def update_squid_whitelist(domains):
    with open(SQUID_WHITELIST, 'w') as f:
        for domain in sorted(domains):
            f.write(domain + '\n')
    subprocess.run(['systemctl', 'reload', SQUID_SERVICE], check=True)


def setup_squid_iptables(user):
    uid = pwd.getpwnam(user).pw_uid
    # Remove any previous rules for this user (avoid duplicates)
    subprocess.run(['iptables', '-t', 'nat', '-D', 'OUTPUT', '-p', 'tcp', '--dport', '80', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', str(SQUID_HTTP_PORT)], check=False)
    subprocess.run(['iptables', '-t', 'nat', '-D', 'OUTPUT', '-p', 'tcp', '--dport', '443', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', str(SQUID_HTTPS_PORT)], check=False)
    # Add new rules
    subprocess.run(['iptables', '-t', 'nat', '-A', 'OUTPUT', '-p', 'tcp', '--dport', '80', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', str(SQUID_HTTP_PORT)], check=True)
    subprocess.run(['iptables', '-t', 'nat', '-A', 'OUTPUT', '-p', 'tcp', '--dport', '443', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REDIRECT', '--to-port', str(SQUID_HTTPS_PORT)], check=True)
    # Block all other direct outbound traffic for this user
    subprocess.run(['iptables', '-A', 'OUTPUT', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    # Block IPv6 for this user
    subprocess.run(['ip6tables', '-A', 'OUTPUT', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    # Block all outbound DNS except to trusted resolver (optional, set your DNS IP)
    # subprocess.run(['iptables', '-A', 'OUTPUT', '-p', 'udp', '--dport', '53', '!', '-d', '8.8.8.8', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)
    # subprocess.run(['iptables', '-A', 'OUTPUT', '-p', 'tcp', '--dport', '53', '!', '-d', '8.8.8.8', '-m', 'owner', '--uid-owner', str(uid), '-j', 'REJECT'], check=False)


def main():
    parser = create_parser()
    args = parser.parse_args()
    check_root()
    config_dir = args.config_dir or get_project_root()
    manager = ContestManager(config_dir=config_dir)
    try:
        # 1. Get all whitelisted domains and dependencies
        all_domains = manager.get_all_whitelisted_domains_and_dependencies(args.user)
        # 2. Update Squid whitelist and reload
        update_squid_whitelist(all_domains)
        # 3. Set up robust iptables redirect and block for the user
        setup_squid_iptables(args.user)
        print(f"Restrictions applied for user '{args.user}' using robust Squid proxy setup.")
        sys.exit(0)
    except KeyboardInterrupt:
        print("\nRestriction cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"Restriction error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
