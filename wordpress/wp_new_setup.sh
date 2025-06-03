#!/bin/bash

# Check if PHP version is provided as the first argument
if [ -z "$1" ]; then
  echo "Error: Please provide a PHP version (e.g., 7.4, 8.0, 8.1, 8.2)"
  exit 1
fi
PHP_VERSION="$1"

# Check if WordPress version is provided as the second argument
if [ -z "$2" ]; then
  echo "Error: Please provide a WordPress version (e.g., 6.6.2)"
  exit 1
fi
WP_VERSION="$2"

# Validate WordPress version format (e.g., X.Y or X.Y.Z) using POSIX-compliant expr
if ! expr "$WP_VERSION" : '^[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?$' >/dev/null; then
  echo "Error: Invalid WordPress version format (e.g., use 6.6.2)"
  exit 1
fi

# Check if the WordPress version is downloadable
WP_URL="https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"
WP_FILE="wordpress-${WP_VERSION}.tar.gz"
echo "Checking if WordPress version $WP_VERSION is available..."
wget --spider "$WP_URL" 2>&1 | grep -q "200 OK"
if [ $? -ne 0 ]; then
  echo "Error: WordPress version $WP_VERSION not found (404 error). Check available versions at https://wordpress.org/download/releases/"
  exit 1
else
  echo "WordPress version $WP_VERSION is available for download."
fi

# Update and upgrade the system
echo "Updating and upgrading Ubuntu..."
sudo apt update -y
sudo apt upgrade -y

# Install Apache
echo "Installing Apache2..."
sudo apt install apache2 -y
sudo systemctl enable apache2
sudo systemctl start apache2

# Install MySQL
echo "Installing MySQL..."
sudo apt install mysql-server -y
sudo systemctl enable mysql
sudo systemctl start mysql

# Secure MySQL installation (optional, adjust as needed)
# Commenting out to avoid interactive prompts; run manually if needed
# sudo mysql_secure_installation

# Install PHP and required modules
echo "Installing PHP $PHP_VERSION and modules..."
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install php${PHP_VERSION} libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-mysql php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip -y

# Configure Apache to use PHP
echo "Configuring Apache for PHP..."
sudo sed -i "s/DirectoryIndex index.html/DirectoryIndex index.php index.html/" /etc/apache2/mods-enabled/dir.conf

# Configure Apache default virtual host for WordPress project
echo "Configuring Apache default virtual host with FollowSymLinks and AllowOverride..."
cat <<EOF | sudo tee /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Enable rewrite module and restart Apache
sudo a2enmod rewrite
sudo systemctl restart apache2

# Set up WordPress in /var/www/html
echo "Setting up WordPress in /var/www/html..."
sudo rm -rf /var/www/html/* # Clear existing files in /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Download and extract WordPress
cd /tmp
echo "Downloading WordPress version $WP_VERSION..."
wget "$WP_URL"
if [ $? -ne 0 ]; then
  echo "Error: Failed to download WordPress from $WP_URL"
  exit 1
fi
tar -xvzf "$WP_FILE"
sudo mv wordpress/* /var/www/html/
sudo rm -rf wordpress "$WP_FILE"

# Create MySQL database and user for WordPress
DB_NAME="wordpress"
DB_USER="wordpress_user"
DB_PASS="My7Pass@Word_9_8A_zE" # Change this to a strong password
echo "Creating MySQL database and user..."
sudo mysql -e "CREATE DATABASE $DB_NAME;"
sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Configure WordPress
echo "Configuring WordPress..."
sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/" /var/www/html/wp-config.php
sudo sed -i "s/username_here/$DB_USER/" /var/www/html/wp-config.php
sudo sed -i "s/password_here/$DB_PASS/" /var/www/html/wp-config.php

# Create .htaccess to increase upload limit and enable permalinks
echo "Creating .htaccess to increase upload limit..."
cat <<EOF | sudo tee /var/www/html/.htaccess
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
php_value upload_max_filesize 10G
php_value post_max_size 10G
php_value memory_limit 12G
php_value max_execution_time 600
php_value max_input_time 600
EOF

# Create php.ini to increase upload limit
echo "Creating php.ini to increase upload limit..."
cat <<EOF | sudo tee /var/www/html/php.ini
upload_max_filesize = 10G
post_max_size = 10G
memory_limit = 12G
max_execution_time = 600
max_input_time = 600
EOF

# Set proper permissions for .htaccess and php.ini
sudo chown www-data:www-data /var/www/html/.htaccess /var/www/html/php.ini
sudo chmod 644 /var/www/html/.htaccess /var/www/html/php.ini

# Set proper permissions for WordPress
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

echo "Setup complete! Access your WordPress site at http://your_server_ip"
echo "WordPress version $WP_VERSION installed."
echo "Complete the WordPress installation via the web interface."
echo "MySQL Database: $DB_NAME, User: $DB_USER, Password: $DB_PASS"
echo "Upload limit set to 10GB in .htaccess and php.ini (may be restricted by host)."