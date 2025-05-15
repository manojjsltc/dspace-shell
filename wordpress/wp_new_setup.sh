#!/bin/bash

# Check if PHP version is provided as an argument
if [ -z "$1" ]; then
  echo "Error: Please provide a PHP version (e.g., 7.4, 8.0, 8.1)"
  exit 1
fi

PHP_VERSION="$1"

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
sudo mysql_secure_installation

# Install PHP and required modules
echo "Installing PHP $PHP_VERSION and modules..."
sudo apt install software-properties-common -y
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install php${PHP_VERSION} libapache2-mod-php${PHP_VERSION} php${PHP_VERSION}-mysql php${PHP_VERSION}-curl php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-xmlrpc php${PHP_VERSION}-zip -y

# Configure Apache to use PHP
echo "Configuring Apache for PHP..."
sudo sed -i "s/DirectoryIndex index.html/DirectoryIndex index.php index.html/" /etc/apache2/mods-enabled/dir.conf
sudo systemctl restart apache2

# Set up WordPress directly in /var/www/html
echo "Setting up WordPress in /var/www/html..."
sudo rm -rf /var/www/html/* # Clear existing files in /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

# Download and extract WordPress
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
sudo mv wordpress/* /var/www/html/
sudo rm -rf wordpress latest.tar.gz

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

# Enable Apache rewrite module
sudo a2enmod rewrite
sudo systemctl restart apache2

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html

echo "Setup complete! Access your WordPress site at http://your_server_ip"
echo "Complete the WordPress installation via the web interface."
echo "MySQL Database: $DB_NAME, User: $DB_USER, Password: $DB_PASS"