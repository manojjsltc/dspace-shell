#!/bin/bash

# Change ownership of dspace-ui directory
sudo chown -R ubuntu:ubuntu /var/www/dspace-ui

# Change permissions of dspace-ui directory
sudo chmod -R 755 /var/www/dspace-ui

# Create/overwrite config.production.yaml with specified content
cat << EOF > /var/www/dspace-ui/config/config.production.yaml
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
cat << EOF > /var/www/dspace-ui/dspace-ui.json
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