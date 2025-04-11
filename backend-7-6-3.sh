#!/bin/bash

# Exit on critical errors
set -e

# Define versions
DSPACE_VERSION="7.6.3"
TOMCAT_VERSION="9.0.102"
POSTGRES_VERSION="14"
SOLR_VERSION="8.11.4"

# Colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run this script as root (use sudo).${NC}"
    exit 1
fi

echo -e "${GREEN}Starting DSpace $DSPACE_VERSION installation with Solr $SOLR_VERSION on Ubuntu 22.04...${NC}"

# Update system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install prerequisites
echo "Installing Java, Maven, Ant, PostgreSQL, and other dependencies..."
apt install -y openjdk-11-jdk maven ant postgresql-"$POSTGRES_VERSION" postgresql-contrib-"$POSTGRES_VERSION" curl unzip

# Install Tomcat
echo "Installing Apache Tomcat $TOMCAT_VERSION..."
cd /opt
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_FILE="apache-tomcat-$TOMCAT_VERSION.tar.gz"
echo "Downloading Tomcat from: $TOMCAT_URL"
curl -L -O "$TOMCAT_URL" || {
    echo -e "${RED}Error: Failed to download Tomcat from $TOMCAT_URL${NC}"
    exit 1
}
FILE_SIZE=$(stat -c%s "$TOMCAT_FILE")
if [ "$FILE_SIZE" -lt 10000000 ]; then
    echo -e "${RED}Error: Downloaded file is too small ($FILE_SIZE bytes), expected ~10MB+. Download failed.${NC}"
    exit 1
fi
tar -xzf "$TOMCAT_FILE" || {
    echo -e "${RED}Error: Failed to extract $TOMCAT_FILE. File may be corrupt.${NC}"
    exit 1
}
mv "apache-tomcat-$TOMCAT_VERSION" tomcat9
rm "$TOMCAT_FILE"

# Set Tomcat permissions
echo "Setting Tomcat permissions..."
groupadd -f tomcat || echo "Group tomcat already exists, skipping..."
if id "tomcat" >/dev/null 2>&1; then
    echo "User tomcat already exists, skipping creation..."
else
    useradd -s /bin/false -g tomcat -d /opt/tomcat9 tomcat
fi
chown -R tomcat:tomcat /opt/tomcat9 || {
    echo -e "${RED}Warning: Failed to set ownership for /opt/tomcat9, continuing...${NC}"
}
chmod -R 750 /opt/tomcat9 || {
    echo -e "${RED}Warning: Failed to set permissions for /opt/tomcat9, continuing...${NC}"
}

# Configure Tomcat memory
echo "Configuring Tomcat memory settings..."
echo "JAVA_OPTS=\"-Xms512m -Xmx2048m\"" > /opt/tomcat9/bin/setenv.sh
chmod +x /opt/tomcat9/bin/setenv.sh

# Set up PostgreSQL
echo "Configuring PostgreSQL $POSTGRES_VERSION..."
systemctl start postgresql || {
    echo -e "${RED}Error: Failed to start PostgreSQL${NC}"
    exit 1
}
sudo -u postgres psql -c "CREATE USER dspace WITH PASSWORD 'dspace';" || echo "User dspace already exists, skipping..."
sudo -u postgres psql -c "CREATE DATABASE dspace OWNER dspace;" || echo "Database dspace already exists, skipping..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE dspace TO dspace;"
sudo -u postgres psql -d dspace -c "CREATE EXTENSION pgcrypto;" || echo "pgcrypto extension already installed, skipping..."
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" /etc/postgresql/"$POSTGRES_VERSION"/main/postgresql.conf
systemctl restart postgresql

# Install Solr
echo "Installing Apache Solr $SOLR_VERSION..."
cd /opt
SOLR_URL="https://archive.apache.org/dist/lucene/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz"
SOLR_FILE="solr-$SOLR_VERSION.tgz"
echo "Downloading Solr from: $SOLR_URL"
curl -L -O "$SOLR_URL" || {
    echo -e "${RED}Error: Failed to download Solr from $SOLR_URL${NC}"
    exit 1
}
FILE_SIZE=$(stat -c%s "$SOLR_FILE")
if [ "$FILE_SIZE" -lt 100000000 ]; then
    echo -e "${RED}Error: Downloaded file is too small ($FILE_SIZE bytes), expected ~100MB+. Download failed.${NC}"
    exit 1
fi
tar -xzf "$SOLR_FILE" || {
    echo -e "${RED}Error: Failed to extract $SOLR_FILE. File may be corrupt.${NC}"
    exit 1
}
mv "solr-$SOLR_VERSION" solr
rm "$SOLR_FILE"

# Set Solr permissions
# Note: For production, ensure /etc/security/limits.conf includes:
# solr soft nofile 65000
# solr hard nofile 65000
# solr soft nproc 65000
# solr hard nproc 65000
echo "Setting Solr permissions..."
groupadd -f solr || echo "Group solr already exists, skipping..."
if id "solr" >/dev/null 2>&1; then
    echo "User solr already exists, skipping creation..."
else
    useradd -s /bin/false -g solr -d /opt/solr solr
fi
chown -R solr:solr /opt/solr
mkdir -p /opt/solr/server/logs
chown solr:solr /opt/solr/server/logs
chmod 750 /opt/solr/server/logs

# Start Solr
echo "Starting Solr..."
sudo -u solr /opt/solr/bin/solr stop -all  # Clear any stale instances
sudo -u solr /opt/solr/bin/solr start -p 8983 || {
    echo -e "${RED}Error: Failed to start Solr${NC}"
    exit 1
}
echo "Waiting for Solr to initialize..."
sleep 30  # Wait for Solr to fully start
if ! curl -s http://localhost:8983/solr/ >/dev/null; then
    echo -e "${RED}Error: Solr is not responding on port 8983${NC}"
    cat /opt/solr/server/logs/solr.log || echo "No Solr log available"
    exit 1
else
    echo "Solr is running on port 8983"
fi

# Download and install DSpace
echo "Downloading and installing DSpace $DSPACE_VERSION..."
cd /usr/local/src
DSPACE_URL="https://github.com/DSpace/DSpace/archive/refs/tags/dspace-$DSPACE_VERSION.tar.gz"
DSPACE_FILE="dspace-$DSPACE_VERSION.tar.gz"
echo "Downloading DSpace from: $DSPACE_URL"
curl -L -O "$DSPACE_URL" || {
    echo -e "${RED}Error: Failed to download DSpace from $DSPACE_URL${NC}"
    exit 1
}
FILE_SIZE=$(stat -c%s "$DSPACE_FILE")
if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo -e "${RED}Error: Downloaded file is too small ($FILE_SIZE bytes), expected ~1MB+. Download failed.${NC}"
    exit 1
fi
tar -xzf "$DSPACE_FILE" || {
    echo -e "${RED}Error: Failed to extract $DSPACE_FILE. File may be corrupt.${NC}"
    exit 1
}
mv "DSpace-dspace-$DSPACE_VERSION" "dspace-$DSPACE_VERSION-src-release"
cd "dspace-$DSPACE_VERSION-src-release"

# Build DSpace with Maven
echo "Building DSpace with Maven..."
mvn -U package -Dmirage2.on=true -Dmirage2.deps.included=true

# Deploy DSpace with Ant
echo "Deploying DSpace..."
cd dspace/target/dspace-installer
if [ ! -f lib/postgresql-*.jar ]; then
    echo "Downloading PostgreSQL JDBC driver..."
    POSTGRES_JDBC_URL="https://jdbc.postgresql.org/download/postgresql-42.7.3.jar"
    echo "Downloading PostgreSQL JDBC driver from: $POSTGRES_JDBC_URL"
    curl -L -O "$POSTGRES_JDBC_URL"
    mv postgresql-42.7.3.jar lib/
fi
mkdir -p /dspace/log
chown tomcat:tomcat /dspace/log
chmod 750 /dspace/log
export DSPACE_HOME=/dspace
ant fresh_install -Ddspace.dir=/dspace -logfile /dspace/log/ant_install.log || {
    echo -e "${RED}Error: Ant build failed. Check /dspace/log/ant_install.log for details.${NC}"
    exit 1
}

# Set up DSpace directories
echo "Setting up DSpace directories and permissions..."
cp -r ./* /dspace/
chown -R tomcat:tomcat /dspace || {
    echo -e "${RED}Warning: Failed to set ownership for /dspace, continuing...${NC}"
}
chmod -R 750 /dspace || {
    echo -e "${RED}Warning: Failed to set permissions for /dspace, continuing...${NC}"
}

# Configure Solr cores for DSpace
echo "Configuring Solr cores for DSpace..."
cp -r /dspace/solr/* /opt/solr/server/solr/configsets/
chown -R solr:solr /opt/solr/server/solr/configsets/
sudo -u solr /opt/solr/bin/solr create_core -c search -d /opt/solr/server/solr/configsets/search || {
    echo -e "${RED}Error: Failed to create search core${NC}"
    exit 1
}
sudo -u solr /opt/solr/bin/solr create_core -c statistics -d /opt/solr/server/solr/configsets/statistics || {
    echo -e "${RED}Error: Failed to create statistics core${NC}"
    exit 1
}
sudo -u solr /opt/solr/bin/solr create_core -c oai -d /opt/solr/server/solr/configsets/oai || {
    echo -e "${RED}Error: Failed to create oai core${NC}"
    exit 1
}
sudo -u solr /opt/solr/bin/solr create_core -c authority -d /opt/solr/server/solr/configsets/authority || {
    echo -e "${RED}Error: Failed to create authority core${NC}"
    exit 1
}

# Configure DSpace database settings
echo "Configuring DSpace database settings..."
cat <<EOL > /dspace/config/local.cfg
db.url = jdbc:postgresql://localhost:5432/dspace
db.username = dspace
db.password = dspace
dspace.dir = /dspace
dspace.hostname = localhost
dspace.port = 8080
solr.server = http://localhost:8983/solr
EOL

# Initialize database
echo "Initializing DSpace database..."
/dspace/bin/dspace database migrate || {
    echo -e "${RED}Error: Database migration failed. Check logs at /dspace/log/.${NC}"
    exit 1
}

# Deploy webapps to Tomcat
echo "Deploying DSpace webapps to Tomcat..."
cp -r /dspace/webapps/* /opt/tomcat9/webapps/
chown -R tomcat:tomcat /opt/tomcat9/webapps/ || {
    echo -e "${RED}Warning: Failed to set ownership for Tomcat webapps, continuing...${NC}"
}

# Fix dspace.dir in server webapp's application.properties
echo "Fixing dspace.dir in server webapp configuration..."
sed -i "s|dspace.dir=\${dspace.dir}|dspace.dir=/dspace|" /opt/tomcat9/webapps/server/WEB-INF/classes/application.properties || {
    echo -e "${RED}Error: Failed to update application.properties${NC}"
    exit 1
}
chown tomcat:tomcat /opt/tomcat9/webapps/server/WEB-INF/classes/application.properties

# Start Tomcat
echo "Starting Tomcat..."
/opt/tomcat9/bin/startup.sh

# Verify installation
echo "Verifying DSpace installation..."
sleep 10  # Give Tomcat time to deploy webapps
if curl -s http://localhost:8080/xmlui >/dev/null && curl -s http://localhost:8080/server/api/status >/dev/null; then
    echo -e "${GREEN}DSpace $DSPACE_VERSION installation completed successfully!${NC}"
    echo "Access it at: http://localhost:8080/xmlui or http://localhost:8080/server/api"
else
    echo -e "${RED}Warning: DSpace web interface not accessible. Check Tomcat logs.${NC}"
fi
echo "Tomcat logs: /opt/tomcat9/logs/"
echo "DSpace logs: /dspace/log/"
echo "Solr logs: /opt/solr/server/logs/"

# Create admin user
echo "Creating initial DSpace administrator..."
/dspace/bin/dspace create-administrator || {
    echo -e "${RED}Warning: Failed to create admin user. Run '/dspace/bin/dspace create-administrator' manually.${NC}"
}

exit 0