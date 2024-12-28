#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default paths
DEFAULT_INSTALL_DIR="/opt/webtrufflehog"

# Function to print error and exit
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to print warning
warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Function to print success
success() {
    echo -e "${GREEN}$1${NC}"
}

# make sure script is run as root
if [ "$EUID" -ne 0 ]; then
    error_exit "Please run this script as root"
fi

# Parse command line arguments
CHROME_DIR=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --chrome-dir) CHROME_DIR="$2"; shift ;;
        *) error_exit "Unknown parameter: $1" ;;
    esac
    shift
done

# Check if chrome directory is provided
if [ -z "$CHROME_DIR" ]; then
    error_exit "Please provide your Chrome/Chromium config directory using --chrome-dir\n\nTo find your Chrome config directory:\n1. Open Chrome/Chromium\n2. Go to chrome://version\n3. Look for 'Profile Path'\n4. Use the parent directory of that path\n\nExample:\nIf Profile Path is '/home/user/.config/google-chrome/Default'\nUse: --chrome-dir '/home/user/.config/google-chrome'"
fi

# check if native messaging hosts directory exists
if [ ! -d "$CHROME_DIR/NativeMessagingHosts" ]; then
    error_exit "Native messaging hosts directory does not exist. Trying parent directory..."
    CHROME_DIR=$(dirname "$CHROME_DIR")
    if [ ! -d "$CHROME_DIR/NativeMessagingHosts" ]; then
        error_exit "Native messaging hosts directory does not exist. Please create it first."
    fi
fi

# Check if trufflehog is installed
if ! command -v trufflehog &> /dev/null; then
    error_exit "trufflehog is not installed. Please install it first and add it to your system PATH."
fi

# Set installation directory for native messaging host
INSTALL_NMH_DIR="$CHROME_DIR/NativeMessagingHosts"

# Create installation directories
echo "Creating installation directories..."
mkdir -p "$DEFAULT_INSTALL_DIR" || error_exit "Failed to create installation directory"
mkdir -p "$INSTALL_NMH_DIR" || error_exit "Failed to create native messaging hosts directory"

# Copy files to installation directory
echo "Copying files to installation directory..."
cp native_host.py "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy native_host.py"
cp manifest.json "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy manifest.json"
cp -r icons "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy icons"
cp popup.html "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy popup.html"
cp popup.js "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy popup.js"
cp background.js "$DEFAULT_INSTALL_DIR/" || error_exit "Failed to copy background.js"

# Make native host executable
chmod +x "$DEFAULT_INSTALL_DIR/native_host.py" || error_exit "Failed to make native_host.py executable"

# Update com.webtrufflehog.json with correct path
echo "Configuring native messaging host..."
sed "s/REPLACE_ME/$(echo -n $DEFAULT_INSTALL_DIR | sed 's/\//\\\//g')\/native_host.py/g" com.webtrufflehog.json > "$INSTALL_NMH_DIR/com.webtrufflehog.json" || error_exit "Failed to create native messaging host configuration"

# Set correct permissions
chmod 644 "$INSTALL_NMH_DIR/com.webtrufflehog.json" || error_exit "Failed to set permissions on native messaging host configuration"

# Create results directory and file with correct permissions
mkdir -p /tmp/webtrufflehog || error_exit "Failed to create results directory"
touch /tmp/results.json || error_exit "Failed to create results file"
chmod 644 /tmp/results.json || error_exit "Failed to set permissions on results file"

# Verify installation
echo "Verifying installation..."
if [ ! -x "$DEFAULT_INSTALL_DIR/native_host.py" ]; then
    error_exit "Native host is not executable"
fi

if [ ! -f "$INSTALL_NMH_DIR/com.webtrufflehog.json" ]; then
    error_exit "Native messaging host configuration not found"
fi

# Installation complete
success "Installation completed successfully!"
echo
echo "Installation details:"
echo "- Main files installed to: $DEFAULT_INSTALL_DIR"
echo "- Native messaging host configuration: $INSTALL_NMH_DIR/com.webtrufflehog.json"
echo "- Results file location: /tmp/results.json"
echo
echo "Usage:"
echo "- Load the extension in Chrome/Chromium by going to chrome://extensions/"
echo "- Enable Developer mode"
echo "- Click 'Load unpacked' and select: $DEFAULT_INSTALL_DIR"
echo
warning "Note: You may need to restart Chrome for the changes to take effect"