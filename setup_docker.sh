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

# 2. Check System Package Manager & OS
echo -e "\n${BLUE}[1/5] Checking OS and Package Manager...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "Detected OS: ${GREEN}${NAME} ${VERSION:-}${NC}"
else
    echo -e "${YELLOW}Could not read /etc/os-release. Assuming Debian-compatible system...${NC}"
fi

# Map Deepin or other derivative codenames to Debian Bookworm (stable)
CODENAME="${VERSION_CODENAME:-}"
OS_ID="${ID:-}"

if [ "${OS_ID}" = "deepin" ] || [ "${CODENAME}" = "crimson" ] || [ "${CODENAME}" = "beige" ]; then
    echo -e "${YELLOW}Non-standard Debian/Ubuntu derivative detected (Deepin Crimson/Beige).${NC}"
    echo -e "Mapping codename '${CODENAME}' to upstream Debian stable ${GREEN}bookworm${NC} to prevent 404 errors."
    CODENAME="bookworm"
    OS_ID="debian"
fi

# Fallback defaults if codename/OS is missing or unsupported
if [ -z "${CODENAME}" ]; then
    CODENAME="bookworm"
fi
if [ -z "${OS_ID}" ] || [ "${OS_ID}" = "deepin" ]; then
    OS_ID="debian"
fi

# Clean up any bad configurations left by previous failed installation attempts
# This MUST happen before running apt-get update to avoid 404 blockages.
# We clear both traditional (.list) and modern DEB822 (.sources) formats.
rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources

# Install general dependencies
echo -e "Installing base system dependencies (curl, git, apt-transport-https)..."
apt-get update -y
apt-get install -y curl git apt-transport-https ca-certificates gnupg lsb-release

# 3. Install/Update Docker and Docker Compose using manual mapped repository
echo -e "\n${BLUE}[2/5] Setting up official Docker repository & installing Docker Suite...${NC}"

echo -e "Setting up GPG keyring for Docker..."
mkdir -p /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo -e "Writing Docker apt repository list with codename: ${CODENAME}..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_ID} \
  ${CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
echo -e "Updating package index and installing modern Docker CE and Compose..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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
