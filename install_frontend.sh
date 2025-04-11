#!/bin/bash

# Exit on critical errors
set -e

# Define versions
NODE_VERSION="20"
YARN_VERSION="1.22.19"

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

# Install PM2 globally
echo "Installing PM2 for process management..."
npm install -g pm2 || { echo -e "${RED}Error: Failed to install PM2${NC}"; exit 1; }
pm2 --version || { echo -e "${RED}Error: PM2 not working${NC}"; exit 1; }

# Create frontend user and group if they don't exist
echo "Setting up frontend user and group..."
groupadd -f frontend || echo "Group frontend already exists, skipping..."
if id "frontend" >/dev/null 2>&1; then
    echo "User frontend already exists, skipping creation..."
else
    useradd -m -s /bin/false -g frontend -d /home/frontend frontend
fi

# Create PM2 home directory for frontend user
echo "Setting up PM2 home directory for frontend user..."
mkdir -p /home/frontend/.pm2
chown frontend:frontend /home/frontend/.pm2
chmod 750 /home/frontend/.pm2

# Create configuration directory
echo "Setting up configuration directory..."
mkdir -p /var/www/dspace-ui

# Clone DSpace Angular source from your custom repository
echo "Cloning DSpace Angular source code from your GitHub repository..."
cd /usr/local/src

# Define your custom repository URL and directory
FRONTEND_REPO_URL="git@github.com:manojjsltc/sltc-dspace-angular-7.6.3.git"
FRONTEND_REPO_DIR="sltc-dspace-angular-7.6.3"

echo "Cloning frontend repository from: $FRONTEND_REPO_URL"
if ! git clone "$FRONTEND_REPO_URL" "$FRONTEND_REPO_DIR"; then
    echo -e "${RED}Error: Failed to clone frontend repository from $FRONTEND_REPO_URL${NC}"
    exit 1
fi

cd "$FRONTEND_REPO_DIR"

# Switch to the production branch
echo "Switching to production branch..."
if ! git checkout production; then
    echo -e "${RED}Error: Failed to switch to production branch. Ensure the branch exists.${NC}"
    exit 1
fi

echo "Successfully cloned DSpace Angular source to /usr/local/src/$FRONTEND_REPO_DIR"

# Install dependencies
echo "Installing frontend dependencies..."
yarn install || { echo -e "${RED}Error: Failed to install Yarn dependencies${NC}"; exit 1; }

# Build the frontend with increased memory limit
echo "Building DSpace frontend with increased memory limit..."
export NODE_OPTIONS="--max-old-space-size=6144"
yarn build:prod || { echo -e "${RED}Error: Failed to build frontend. Check memory or dependency issues.${NC}"; exit 1; }
unset NODE_OPTIONS  # Clean up to avoid affecting other processes

# Copy dist folder to /var/www/dspace-ui/dist
echo "Copying dist folder to /var/www/dspace-ui/dist..."
mkdir -p /var/www/dspace-ui/dist
cp -r dist/* /var/www/dspace-ui/dist/ || { echo -e "${RED}Error: Failed to copy dist folder${NC}"; exit 1; }

# Set permissions for application directory with retry logic
echo "Setting permissions for /usr/local/src/$FRONTEND_REPO_DIR..."
for i in {1..3}; do
    if chown -R frontend:frontend /usr/local/src/"$FRONTEND_REPO_DIR"; then
        break
    else
        echo -e "${RED}Warning: Failed to set ownership for /usr/local/src/$FRONTEND_REPO_DIR (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set ownership for /usr/local/src/$FRONTEND_REPO_DIR after 3 attempts${NC}"; exit 1; }
done
for i in {1..3}; do
    if chmod -R 750 /usr/local/src/"$FRONTEND_REPO_DIR"; then
        break
    else
        echo -e "${RED}Warning: Failed to set permissions for /usr/local/src/$FRONTEND_REPO_DIR (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set permissions for /usr/local/src/$FRONTEND_REPO_DIR after 3 attempts${NC}"; exit 1; }
done

# Set permissions for /var/www/dspace-ui with retry logic
echo "Setting permissions for /var/www/dspace-ui..."
for i in {1..3}; do
    if chown -R frontend:frontend /var/www/dspace-ui; then
        break
    else
        echo -e "${RED}Warning: Failed to set ownership for /var/www/dspace-ui (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set ownership for /var/www/dspace-ui after 3 attempts${NC}"; exit 1; }
done
for i in {1..3}; do
    if chmod -R 755 /var/www/dspace-ui; then
        break
    else
        echo -e "${RED}Warning: Failed to set permissions for /var/www/dspace-ui (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set permissions for /var/www/dspace-ui after 3 attempts${NC}"; exit 1; }
done

# Create config directory if it doesn't exist
if [ ! -d "/var/www/dspace-ui/config" ]; then
    echo "Config directory does not exist. Creating /var/www/dspace-ui/config..."
    mkdir -p /var/www/dspace-ui/config
    chown frontend:frontend /var/www/dspace-ui/config
    chmod 755 /var/www/dspace-ui/config
fi

# Create/overwrite config.production.yaml
echo "Creating /var/www/dspace-ui/config/config.production.yaml..."
tee /var/www/dspace-ui/config/config.production.yaml > /dev/null << EOF
ui:
  ssl: false
  host: localhost
  port: 4000
  nameSpace: /

rest:
  ssl: true
  host: repo.sltc.ac.lk
  port: 443
  nameSpace: /server
EOF
chown frontend:frontend /var/www/dspace-ui/config/config.production.yaml
chmod 644 /var/www/dspace-ui/config/config.production.yaml

# Create/overwrite dspace-ui.json
echo "Creating /var/www/dspace-ui/dspace-ui.json..."
tee /var/www/dspace-ui/dspace-ui.json > /dev/null << EOF
{
    "apps": [
        {
           "name": "dspace-ui",
           "cwd": "/var/www/dspace-ui",
           "script": "dist/server/main.js",
           "instances": "max",
           "exec_mode": "cluster",
           "env": {
                "NODE_ENV": "production",
                "DSPACE_REST_SSL": "true",
                "DSPACE_REST_HOST": "repo.sltc.ac.lk",
                "DSPACE_REST_PORT": "443",
                "DSPACE_REST_NAMESPACE": "/server",
                "PM2_HOME": "/home/frontend/.pm2"
           }
        }
    ]
}
EOF
chown frontend:frontend /var/www/dspace-ui/dspace-ui.json
chmod 644 /var/www/dspace-ui/dspace-ui.json

# Display configuration confirmation
echo "Configuration files have been created/updated successfully!"
echo "Files modified:"
echo "- /var/www/dspace-ui/dist/"
echo "- /var/www/dspace-ui/config/config.production.yaml"
echo "- /var/www/dspace-ui/dspace-ui.json"

# Clean up any existing PM2 processes for frontend user
echo "Cleaning up existing PM2 processes..."
sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 delete all || true

# Start frontend with PM2 using dspace-ui.json
echo "Starting DSpace frontend with PM2..."
sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 start /var/www/dspace-ui/dspace-ui.json || { echo -e "${RED}Error: Failed to start frontend with PM2${NC}"; exit 1; }

# Save PM2 process list to persist across reboots
echo "Saving PM2 process list..."
sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 save || { echo -e "${RED}Error: Failed to save PM2 process list${NC}"; exit 1; }

# Configure PM2 to start on system boot
echo "Configuring PM2 to start on system boot..."
sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 startup systemd -u frontend | bash || { echo -e "${RED}Error: Failed to configure PM2 startup${NC}"; exit 1; }

# Verify PM2 process
echo "Verifying PM2 process..."
if sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 list | grep -q "dspace-ui"; then
    echo "Frontend process is running under PM2 with name 'dspace-ui'"
else
    echo -e "${RED}Error: Frontend process not running in PM2. Checking logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
    exit 1
fi

# Verify port binding
echo "Checking if port 4000 is bound..."
sleep 5
if sudo lsof -i :4000 > /dev/null; then
    echo "Port 4000 is bound successfully"
else
    echo -e "${RED}Error: Port 4000 not bound. Checking PM2 logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
    exit 1
fi

# Verify frontend
echo "Verifying frontend installation..."
sleep 5
if curl -s http://localhost:4000 >/dev/null; then
    echo -e "${GREEN}DSpace frontend installation completed successfully!${NC}"
    echo "Frontend is running on http://localhost:4000"
    echo "Assuming NGINX is configured to proxy this to https://repo.sltc.ac.lk"
else
    echo -e "${RED}Warning: Frontend not accessible on http://localhost:4000. Check PM2 logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
fi

echo "View PM2 logs with: sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui"
echo "Manage PM2 process with: sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 [start|stop|restart] dspace-ui"

exit 0