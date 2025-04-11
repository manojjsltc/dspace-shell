#!/bin/bash

# Exit on critical errors
set -e

# Define versions
NODE_VERSION="20"
YARN_VERSION="1.22.19"
SWAP_SIZE="8G"

# Colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script as root (use sudo).${NC}"
    exit 1
fi

echo -e "${GREEN}Starting DSpace Frontend installation on Ubuntu 22.04...${NC}"

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Configure swap space if not already 8GB
echo "Configuring 8GB swap space..."
if ! swapon --show | grep -q "8G"; then
    echo "Creating 8GB swap file..."
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    echo "Swap space configured to 8GB"
else
    echo "8GB swap space already exists, skipping..."
fi

# Clean up any existing Node.js installation
echo "Removing existing Node.js to ensure clean install..."
apt remove nodejs -y
apt autoremove -y
apt autoclean

# Install Node.js from Nodesource (includes npm)
echo "Installing Node.js and npm from Nodesource..."
apt install -y curl gnupg
curl -fsSL https://deb.nodesource.com/setup_"$NODE_VERSION".x | bash -
apt install -y nodejs || { echo -e "${RED}Error: Failed to install Node.js${NC}"; exit 1; }

# Verify Node.js and npm
echo "Verifying Node.js and npm installations..."
node -v || { echo -e "${RED}Error: Node.js not working${NC}"; exit 1; }
npm -v || { echo -e "${RED}Error: npm not installed${NC}"; exit 1; }

# Install Yarn globally
echo "Installing Yarn..."
npm install -g yarn@"$YARN_VERSION" || { echo -e "${RED}Error: Failed to install Yarn${NC}"; exit 1; }
yarn --version || { echo -e "${RED}Error: Yarn not working${NC}"; exit 1; }

# Create frontend directory and setup
echo "Setting up DSpace frontend application..."
mkdir -p /opt/dspace-frontend
cd /opt/dspace-frontend

# Download DSpace Angular source
echo "Downloading DSpace Angular source code..."
curl -L -o dspace-angular.tar.gz https://github.com/DSpace/dspace-angular/archive/refs/tags/dspace-7.6.3.tar.gz || {
    echo -e "${RED}Error: Failed to download DSpace Angular source${NC}";
    exit 1;
}
tar -xzf dspace-angular.tar.gz --strip-components=1 || {
    echo -e "${RED}Error: Failed to extract DSpace Angular source${NC}";
    exit 1;
}
rm dspace-angular.tar.gz

# Install dependencies
echo "Installing frontend dependencies..."
yarn install || { echo -e "${RED}Error: Failed to install Yarn dependencies${NC}"; exit 1; }

# Configure environment
echo "Configuring frontend environment..."
cat <<EOL > config/config.prod.yml
environment: production
rest:
  host: manojjx.shop
  port: 443
  ssl: true
  nameSpace: /server
ui:
  host: localhost  # Bind to localhost instead of domain
  port: 4000
  ssl: false
EOL

# Build the frontend
echo "Building DSpace frontend..."
yarn build:prod || { echo -e "${RED}Error: Failed to build frontend${NC}"; exit 1; }

# Set permissions with retry logic
echo "Setting frontend permissions..."
groupadd -f frontend || echo "Group frontend already exists, skipping..."
if id "frontend" >/dev/null 2>&1; then
    echo "User frontend already exists, skipping creation..."
else
    useradd -s /bin/false -g frontend -d /opt/dspace-frontend frontend
fi
for i in {1..3}; do
    if chown -R frontend:frontend /opt/dspace-frontend; then
        break
    else
        echo -e "${RED}Warning: Failed to set ownership (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set ownership after 3 attempts${NC}"; exit 1; }
done
for i in {1..3}; do
    if chmod -R 750 /opt/dspace-frontend; then
        break
    else
        echo -e "${RED}Warning: Failed to set permissions (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set permissions after 3 attempts${NC}"; exit 1; }
done

# Start frontend with Node.js and debug
echo "Starting DSpace frontend..."
sudo -u frontend nohup node dist/server/main.js > /opt/dspace-frontend/frontend.log 2>&1 &
sleep 5  # Give more time to start
if ps aux | grep -v grep | grep "node dist/server/main.js" > /dev/null; then
    echo "Frontend process detected in the background"
else
    echo -e "${RED}Error: Frontend process not running. Checking logs...${NC}"
    cat /opt/dspace-frontend/frontend.log
    exit 1
fi
if sudo lsof -i :4000 > /dev/null; then
    echo "Port 4000 is bound successfully"
else
    echo -e "${RED}Error: Port 4000 not bound. Checking logs...${NC}"
    cat /opt/dspace-frontend/frontend.log
    exit 1
fi

# Verify frontend
echo "Verifying frontend installation..."
sleep 5
if curl -s http://localhost:4000 >/dev/null; then
    echo -e "${GREEN}DSpace frontend installation completed successfully!${NC}"
    echo "Frontend is running on http://localhost:4000"
    echo "Assuming NGINX is configured to proxy this to https://manojjx.shop"
else
    echo -e "${RED}Warning: Frontend not accessible on http://localhost:4000. Check logs at /opt/dspace-frontend/frontend.log${NC}"
    cat /opt/dspace-frontend/frontend.log
fi

echo "Frontend logs: /opt/dspace-frontend/frontend.log"

exit 0