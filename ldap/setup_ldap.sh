#!/bin/bash

# Check if the script is running with bash
if [ -z "$BASH" ]; then
    echo "Error: This script must be run with bash, not sh or another shell."
    echo "Run it as: bash $0 <domain>"
    echo "Or make it executable and run: ./$0 <domain>"
    exit 1
fi

# Check if exactly one domain is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 manojjx.shop"
    exit 1
fi

DOMAIN=$1

# Update system
sudo apt update && sudo apt upgrade -y

# Install OpenLDAP and utilities
sudo apt install slapd ldap-utils -y

# Split domain into components
IFS='.' read -r -a DC <<< "$DOMAIN"
# Create dc string for LDAP (e.g., dc=manojjx,dc=shop)
DC_STRING=$(printf "dc=%s," "${DC[@]}" | sed 's/,$//')
# Organization name from first domain component
ORG_NAME="${DC[0]} Organization"
# Count number of components
COMPONENT_COUNT=${#DC[@]}
echo "Domain: $DOMAIN has $COMPONENT_COUNT components ($DC_STRING)"

# Configure slapd interactively, letting user set password via dpkg-reconfigure prompt
sudo debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string $DOMAIN
slapd shared/organization string $ORG_NAME
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
sudo dpkg-reconfigure slapd

# Create base.ldif file (without userPassword, as password is set by dpkg-reconfigure)
cat <<EOF > base.ldif
dn: $DC_STRING
objectClass: top
objectClass: dcObject
objectClass: organization
o: $ORG_NAME
dc: ${DC[0]}

dn: cn=admin,$DC_STRING
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP administrator
EOF

# Apply LDIF file
sudo ldapadd -x -D "cn=admin,$DC_STRING" -W -f base.ldif

# Test LDAP client
ldapsearch -x -LLL -H ldap://localhost -b "$DC_STRING"

# Clean up
rm base.ldif

# ----------------------------------------------------
# ubuntu 22.04
# nano setup_ldap.sh
# chmod +x setup_ldap.sh
# sudo ./setup_ldap.sh manojjx.shop