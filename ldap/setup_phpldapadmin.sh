#!/bin/bash

# Script to install and configure phpLDAPadmin, downgrade PHP to 7.4, and disable anonymous binds
# Accepts domain, password, and IP as parameters, splits domain at dots for base DN

# Exit on error
set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to display usage
usage() {
    log "Usage: $0 --domain <domain> --password <password> --ip <ip>"
    log "Example: $0 --domain manojjx.shop --password 1qaz@WSX --ip 127.0.0.1"
    exit 1
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    log "ERROR: This script must be run as root. Use sudo."
    exit 1
fi

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --domain) DOMAIN="$2"; shift ;;
        --password) PASSWORD="$2"; shift ;;
        --ip) IP="$2"; shift ;;
        *) log "ERROR: Unknown parameter: $1"; usage ;;
    esac
    shift
done

# Validate parameters
if [ -z "$DOMAIN" ] || [ -z "$PASSWORD" ] || [ -z "$IP" ]; then
    log "ERROR: All parameters --domain, --password, and --ip are required."
    usage
fi

# Validate IP format (basic check)
if ! [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log "ERROR: Invalid IP address format: $IP"
    exit 1
fi

# Split domain into components and construct base DN
IFS='.' read -ra DOMAIN_PARTS <<< "$DOMAIN"
BASE_DN=""
for i in "${!DOMAIN_PARTS[@]}"; do
    if [ $i -eq 0 ]; then
        BASE_DN="dc=${DOMAIN_PARTS[$i]}"
    else
        BASE_DN="$BASE_DN,dc=${DOMAIN_PARTS[$i]}"
    fi
done
log "Constructed base DN: $BASE_DN"

# Update package lists
log "Updating package lists..."
apt update

# Install phpLDAPadmin
log "Installing phpLDAPadmin..."
apt install phpldapadmin -y

# Add ondrej/php repository for PHP 7.4
log "Adding ondrej/php repository..."
apt install -y software-properties-common
add-apt-repository ppa:ondrej/php -y
apt update

# Install PHP 7.4 and required modules
log "Installing PHP 7.4 and modules..."
apt install php7.4 php7.4-ldap php7.4-xml -y

# Disable PHP 8.1 and enable PHP 7.4
log "Switching to PHP 7.4..."
a2dismod php8.1 2>/dev/null || true
a2enmod php7.4
systemctl restart apache2
log "PHP version: $(php -v | head -n 1)"

# Configure phpLDAPadmin
log "Configuring phpLDAPadmin..."
CONFIG_FILE="/etc/phpldapadmin/config.php"
cat <<EOF > $CONFIG_FILE
<?php
\$config = new Config();
\$servers = \$config->getServerList();
\$servers->newServer('ldap_pla');
\$servers->setValue('server','name','My LDAP Server');
\$servers->setValue('server','host','$IP');
\$servers->setValue('server','base',array('$BASE_DN'));
\$servers->setValue('login','bind_id','cn=admin,$BASE_DN');
\$servers->setValue('login','auth_type','session');
?>
EOF
log "phpLDAPadmin configuration updated at $CONFIG_FILE"

# Set permissions for config file
chown www-data:www-data $CONFIG_FILE
chmod 640 $CONFIG_FILE

# Disable anonymous binds in OpenLDAP
log "Disabling anonymous binds in OpenLDAP..."
cat <<EOF > /tmp/disable_anon.ldif
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/disable_anon.ldif
rm /tmp/disable_anon.ldif

# Restart slapd service
log "Restarting slapd service..."
systemctl restart slapd
if systemctl is-active --quiet slapd; then
    log "slapd service is running"
else
    log "ERROR: slapd service failed to start. Check logs with 'journalctl -xeu slapd.service'"
    exit 1
fi

# Verify LDAP connectivity
log "Testing LDAP connectivity..."
if ldapsearch -x -H ldap://$IP -D "cn=admin,$BASE_DN" -w "$PASSWORD" -b "$BASE_DN" >/dev/null 2>&1; then
    log "LDAP connectivity test successful"
else
    log "ERROR: LDAP connectivity test failed. Verify admin credentials, IP, and base DN."
    exit 1
fi

# Restart Apache to ensure all changes are applied
log "Restarting Apache..."
systemctl restart apache2

# Final instructions
log "Setup complete! Access phpLDAPadmin at http://$IP/phpldapadmin"
log "Login DN: cn=admin,$BASE_DN"
log "Password: $PASSWORD"
log "If issues persist, check logs:"
log "- Apache: /var/log/apache2/error.log"
log "- LDAP: journalctl -xeu slapd.service"