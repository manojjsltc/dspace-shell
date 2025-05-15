#!/bin/bash

# Exit on critical errors
set -e

# Colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

# Check if dist zip file is provided as an argument
if [ -z "$1" ]; then
    echo -e "${RED}Error: Please provide the dist zip file name (e.g., dist-2025-04-13.zip)${NC}"
    echo "Usage: $0 <dist-zip-file>"
    exit 1
fi

DIST_ZIP="$1"
DIST_ZIP_PATH="/usr/local/src/dist-versions/$DIST_ZIP"

# Check if the dist zip file exists
if [ ! -f "$DIST_ZIP_PATH" ]; then
    echo -e "${RED}Error: Dist zip file $DIST_ZIP_PATH does not exist${NC}"
    exit 1
fi

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script as root (use sudo).${NC}"
    exit 1
fi

echo -e "${GREEN}Starting DSpace Frontend dist update...${NC}"

# Create a temporary directory for unzipping
TEMP_DIR=$(mktemp -d)
echo "Unzipping $DIST_ZIP to temporary directory $TEMP_DIR..."

# Unzip the dist folder
unzip -q "$DIST_ZIP_PATH" -d "$TEMP_DIR" || { echo -e "${RED}Error: Failed to unzip $DIST_ZIP${NC}"; rm -rf "$TEMP_DIR"; exit 1; }

# Verify that the unzipped content contains the expected dist files
if [ ! -d "$TEMP_DIR/dist" ]; then
    echo -e "${RED}Error: Unzipped content does not contain a 'dist' folder${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clear existing dist folder
echo "Clearing existing /var/www/dspace-ui/dist/..."
rm -rf /var/www/dspace-ui/dist/* || { echo -e "${RED}Error: Failed to clear /var/www/dspace-ui/dist/${NC}"; rm -rf "$TEMP_DIR"; exit 1; }

# Copy new dist folder
echo "Copying new dist folder to /var/www/dspace-ui/dist/..."
cp -r "$TEMP_DIR/dist/"* /var/www/dspace-ui/dist/ || { echo -e "${RED}Error: Failed to copy dist folder${NC}"; rm -rf "$TEMP_DIR"; exit 1; }

# Clean up temporary directory
rm -rf "$TEMP_DIR"
echo "Cleaned up temporary directory."

# Set permissions for /var/www/dspace-ui/dist
echo "Setting permissions for /var/www/dspace-ui/dist..."
for i in {1..3}; do
    if chown -R frontend:frontend /var/www/dspace-ui/dist; then
        break
    else
        echo -e "${RED}Warning: Failed to set ownership (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set ownership after 3 attempts${NC}"; exit 1; }
done
for i in {1..3}; do
    if chmod -R 755 /var/www/dspace-ui/dist; then
        break
    else
        echo -e "${RED}Warning: Failed to set permissions (attempt $i/3), retrying...${NC}"
        sleep 1
    fi
    [ "$i" -eq 3 ] && { echo -e "${RED}Error: Failed to set permissions after 3 attempts${NC}"; exit 1; }
done

# Restart PM2 process
echo "Restarting DSpace frontend with PM2..."
sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 restart /var/www/dspace-ui/dspace-ui.json || { echo -e "${RED}Error: Failed to restart frontend with PM2${NC}"; exit 1; }

# Verify PM2 process
echo "Verifying PM2 process..."
if sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 list | grep -q "dspace-ui"; then
    echo "Frontend process 'dspace-ui' is running under PM2"
else
    echo -e "${RED}Error: Frontend process not running in PM2. Checking logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
    exit 1
fi

# Verify port binding
echo "Checking if port 4000 is bound..."
sleep 5
if sudo lsof -i :class="highlight">4000 > /dev/null; then
    echo "Port 4000 is bound successfully"
else
    echo -e "${RED}Error: Port 4000 not bound. Checking PM2 logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
    exit 1
fi

# Verify frontend
echo "Verifying frontend update..."
sleep 5
if curl -s http://localhost:4000 >/dev/null; then
    echo -e "${GREEN}DSpace frontend update completed successfully!${NC}"
    echo "Frontend is running on http://localhost:4000"
    echo "Assuming NGINX is configured to proxy this to https://repo.sltc.ac.lk"
else
    echo -e "${RED}Warning: Frontend not accessible on http://localhost:4000. Check PM2 logs...${NC}"
    sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui --lines 20
    exit 1
fi

echo "View PM2 logs with: sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 logs dspace-ui"
echo "Manage PM2 process with: sudo -u frontend PM2_HOME=/home/frontend/.pm2 pm2 [start|stop|restart] dspace-ui"

exit 0