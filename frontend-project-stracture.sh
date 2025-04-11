#!/bin/bash

# Change ownership of dspace-ui directory
sudo chown -R ubuntu:ubuntu /var/www/dspace-ui

# Change permissions of dspace-ui directory
sudo chmod -R 755 /var/www/dspace-ui

# Check if config directory exists, create it if it doesn't
if [ ! -d "/var/www/dspace-ui/config" ]; then
    echo "Config directory does not exist. Creating /var/www/dspace-ui/config..."
    sudo mkdir -p /var/www/dspace-ui/config
    # Set ownership and permissions for the new config directory
    sudo chown ubuntu:ubuntu /var/www/dspace-ui/config
    sudo chmod 755 /var/www/dspace-ui/config
fi

# Create/overwrite config.production.yaml with specified content
sudo tee /var/www/dspace-ui/config/config.production.yaml > /dev/null << EOF
ui:
  ssl: false
  host: localhost
  port: 4000
  nameSpace: /

rest:
  ssl: true
  host: manojjx.shop
  port: 443
  nameSpace: /server
EOF

# Create/overwrite dspace-ui.json with specified content
sudo tee /var/www/dspace-ui/dspace-ui.json > /dev/null << EOF
{
    "apps": [
        {
           "name": "dspace-ui",
           "cwd": "/opt/dspace-ui-deploy",
           "script": "dist/server/main.js",
           "instances": "max",
           "exec_mode": "cluster",
           "env": {
                "NODE_ENV": "production",
                "DSPACE_REST_SSL": "true",
                "DSPACE_REST_HOST": "manojjx.shop",
                "DSPACE_REST_PORT": "443",
                "DSPACE_REST_NAMESPACE": "/server"
                }
        }
    ]
}
EOF

# Display confirmation
echo "Configuration files have been created/updated successfully!"
echo "Files modified:"
echo "- /var/www/dspace-ui/config/config.production.yaml"
echo "- /var/www/dspace-ui/dspace-ui.json"