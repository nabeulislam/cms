#!/usr/bin/env bash

# ==============================================================================
# CMS Docker Master Setup Script
# ==============================================================================
# This script automates the installation of Docker, Docker Compose,
# and system dependencies on Linux, configures non-root user permissions,
# and enables Docker BuildKit globally to avoid Dockerfile heredoc syntax errors.
# ==============================================================================

set -euo pipefail

# ANSI color codes for premium terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}======================================================================${NC}"
echo -e "${CYAN}             CMS Docker Environment Auto-Setup & Installer             ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run with sudo privileges.${NC}"
    echo -e "Please run: ${GREEN}sudo $0${NC}"
    exit 1
fi

# Detect actual (non-root) user who invoked sudo
TARGET_USER="${SUDO_USER:-$USER}"
if [ "$TARGET_USER" = "root" ]; then
    echo -e "${YELLOW}WARNING: Running directly as root. Non-root user permissions will not be mapped.${NC}"
fi

# 2. Install basic dependencies (curl, git)
echo -e "\n${BLUE}[1/5] Checking and installing basic dependencies...${NC}"
if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo -e "Installing curl and git..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl git ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl git ca-certificates
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl git ca-certificates
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl git ca-certificates
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y curl git ca-certificates
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl git ca-certificates
    else
        echo -e "${RED}ERROR: Could not find a supported package manager to install curl and git.${NC}"
        echo -e "Please install them manually and re-run this script."
        exit 1
    fi
else
    echo -e "${GREEN}Dependencies (curl, git) are already installed.${NC}"
fi

# 3. Install/Update Docker using official convenience script
echo -e "\n${BLUE}[2/5] Installing Docker Suite via official convenience script...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm -f get-docker.sh

# 4. Enable Docker BuildKit globally (Fixes Dockerfile heredoc <<EOF syntax errors)
echo -e "\n${BLUE}[3/5] Configuring Docker Daemon (BuildKit & Features)...${NC}"
DAEMON_JSON="/etc/docker/daemon.json"
mkdir -p /etc/docker

if [ -f "$DAEMON_JSON" ]; then
    echo -e "Backing up existing $DAEMON_JSON to $DAEMON_JSON.bak..."
    cp "$DAEMON_JSON" "$DAEMON_JSON.bak"
    
    # Merge buildkit configuration using Python (failsafe if jq is not installed)
    python3 -c '
import json, sys
try:
    with open("'"$DAEMON_JSON"'", "r") as f:
        data = json.load(f)
except Exception:
    data = {}
if "features" not in data:
    data["features"] = {}
data["features"]["buildkit"] = True
with open("'"$DAEMON_JSON"'", "w") as f:
    json.dump(data, f, indent=4)
'
else
    # Create new configuration
    echo -e "Creating new daemon configuration..."
    cat > "$DAEMON_JSON" <<EOF
{
    "features": {
        "buildkit": true
    }
}
EOF
fi
echo -e "${GREEN}BuildKit configured successfully in $DAEMON_JSON!${NC}"

# 5. Set up User Permissions (No-Sudo access)
if [ "$TARGET_USER" != "root" ]; then
    echo -e "\n${BLUE}[4/5] Setting up Docker Group & Permissions for ${TARGET_USER}...${NC}"
    # Ensure docker group exists
    if ! getent group docker >/dev/null; then
        groupadd docker
        echo -e "Created docker group."
    fi
    
    # Add user to the docker group
    usermod -aG docker "$TARGET_USER"
    echo -e "${GREEN}User '${TARGET_USER}' successfully added to the 'docker' group!${NC}"
else
    echo -e "\n${YELLOW}[4/5] Skipping user group mapping (running as root)...${NC}"
fi

# 6. Start & Enable Docker Services
echo -e "\n${BLUE}[5/5] Launching and Enabling Docker Services...${NC}"
systemctl daemon-reload
systemctl enable docker.service
systemctl restart docker.service
systemctl enable containerd.service
systemctl restart containerd.service

# 7. Setup Verification
echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${GREEN}✓ Docker Suite and BuildKit configured successfully!${NC}"
echo -e "${BLUE}======================================================================${NC}"
echo -e "\n${YELLOW}IMPORTANT NEXT STEP:${NC}"
if [ "$TARGET_USER" != "root" ]; then
    echo -e "To apply the new docker group permissions to your current terminal session"
    echo -e "without logging out or restarting, run the following command:"
    echo -e "\n    ${GREEN}newgrp docker${NC}\n"
    echo -e "After that, you can run the CMS development system directly:"
    echo -e "    ${CYAN}./docker/cms-dev.sh${NC}\n"
else
    echo -e "You can now run the CMS development system directly:"
    echo -e "    ${CYAN}./docker/cms-dev.sh${NC}\n"
fi
echo -e "${BLUE}======================================================================${NC}"
