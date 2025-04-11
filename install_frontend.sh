#!/bin/bash

# Variables
DOMAIN="repo.sltc.ac.lk"
EMAIL="manojjsltc@gmail.com"  # Replace with your email
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"
SSR_URL="http://localhost:4000"  # SSR frontend
BACKEND_URL="http://localhost:8080"  # Backend

# Step 1: Update and Install Certbot and Nginx
echo "Updating package list and installing Certbot and Nginx..."
sudo apt update -y
sudo apt install -y certbot python3-certbot-nginx nginx

# Step 2: Create Initial Nginx Config (HTTP only)
echo "Creating initial Nginx configuration for $DOMAIN (HTTP)..."
cat <<EOF | sudo tee $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        root /var/www/html;  # Temporary for Certbot verification
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# Step 3: Enable and Test Nginx Config
echo "Enabling Nginx site and testing config..."
sudo ln -s $NGINX_CONF $NGINX_LINK 2>/dev/null || echo "Site already enabled"
sudo nginx -t && sudo systemctl restart nginx
if [ $? -ne 0 ]; then
    echo "Nginx config test failed. Check /etc/nginx/nginx.conf or $NGINX_CONF"
    exit 1
fi

# Step 4: Generate SSL with Certbot
echo "Generating SSL certificate for $DOMAIN..."
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
if [ $? -ne 0 ]; then
    echo "Certbot failed. Check DNS (A record for $DOMAIN) and /var/log/letsencrypt/letsencrypt.log"
    exit 1
fi

# Step 5: Update Nginx Config for HTTPS and Proxy
echo "Updating Nginx configuration for HTTPS and proxy..."
cat <<EOF | sudo tee $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass $SSR_URL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /server {
        proxy_pass $BACKEND_URL;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Step 6: Test and Restart Nginx
echo "Testing updated Nginx config and restarting..."
sudo nginx -t && sudo systemctl restart nginx
if [ $? -ne 0 ]; then
    echo "Nginx restart failed. Check config: $NGINX_CONF"
    exit 1
fi

# Step 7: Test Auto-Renewal
echo "Testing SSL auto-renewal..."
sudo certbot renew --dry-run

echo "Setup complete! Access at https://$DOMAIN"