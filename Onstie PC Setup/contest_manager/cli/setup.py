#!/usr/bin/env python3
"""
Contest Environment Setup CLI
"""

import sys
import argparse
from ..core.manager import ContestManager
from ..utils.common import check_root, get_project_root


def create_parser():
    """Create the setup argument parser."""
    parser = argparse.ArgumentParser(
        description="Set up lab PC with all required software and user account",
        prog="contest-setup"
    )
    
    parser.add_argument(
        'user',
        nargs='?',
        default='participant',
        help='Username to set up (default: participant)'
    )
    
    parser.add_argument(
        '--config-dir',
        type=str,
        help='Configuration directory path (default: project root)'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output'
    )
    
    return parser


def main():
    """Main setup CLI entry point."""
    parser = create_parser()
    args = parser.parse_args()
    
    check_root()
    
    # Initialize the manager
    config_dir = args.config_dir or get_project_root()
    manager = ContestManager(config_dir=config_dir)
    
    try:
        success = manager.setup_user(args.user)
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\nSetup cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"Setup error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
