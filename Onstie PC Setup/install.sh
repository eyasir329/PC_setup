#!/bin/bash
# Contest Environment Manager - Shell Installer Wrapper
# This script is a simple wrapper around the Python installer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_INSTALLER="$SCRIPT_DIR/install.py"

print_header() {
    echo -e "\n${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
}

check_installer() {
    if [[ ! -f "$PYTHON_INSTALLER" ]]; then
        print_error "Python installer not found: $PYTHON_INSTALLER"
        exit 1
    fi
}

main() {
    print_header "Contest Environment Manager - Shell Installer"
    
    check_python
    check_installer
    
    case "${1:-}" in
        install)
            print_success "Calling Python installer with 'install' command..."
            shift # Remove 'install' from arguments
            exec python3 "$PYTHON_INSTALLER" --install "$@"
            ;;
        uninstall)
            print_success "Calling Python installer with 'uninstall' command..."
            shift # Remove 'uninstall' from arguments
            exec python3 "$PYTHON_INSTALLER" --uninstall "$@"
            ;;
        *)
            echo "Usage: $0 {install|uninstall} [options]"
            echo ""
            echo "Commands:"
            echo "  install    - Install the contest environment manager"
            echo "  uninstall  - Uninstall the contest environment manager"
            echo ""
            echo "Options (for install):"
            echo "  --prefix PATH      - Installation prefix (default: /usr/local)"
            echo "  --skip-system      - Skip system package installation"
            echo "  --skip-python      - Skip Python package installation"
            echo ""
            echo "Examples:"
            echo "  sudo $0 install"
            echo "  sudo $0 install --skip-system"
            echo "  sudo $0 install --prefix /opt"
            echo "  sudo $0 uninstall"
            echo ""
            echo "For more options, use: python3 install.py --help"
            exit 1
            ;;
    esac
}

main "$@"
