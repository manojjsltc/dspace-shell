#!/bin/bash

# Exit on critical errors
set -e

# Ensure script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo -e "\033[0;31mError: This script must be run with bash, not sh.\033[0m"
    echo "Run it as: bash Dspace_7.x_live.sh or ./Dspace_7.x_live.sh"
    exit 1
fi

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
if ! apt update; then
    echo -e "${RED}Error: Failed to update package lists${NC}"
    exit 1
fi
if ! apt upgrade -y; then
    echo -e "${RED}Error: Failed to upgrade packages${NC}"
    exit 1
fi

# Install prerequisites
echo "Installing Java, Maven, Ant, PostgreSQL, and other dependencies..."
if ! apt install -y openjdk-11-jdk maven ant postgresql-"$POSTGRES_VERSION" postgresql-contrib-"$POSTGRES_VERSION" curl unzip; then
    echo -e "${RED}Error: Failed to install prerequisites${NC}"
    exit 1
fi

# Install Tomcat
echo "Installing Apache Tomcat $TOMCAT_VERSION..."
cd /opt
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-9/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
TOMCAT_FILE="apache-tomcat-$TOMCAT_VERSION.tar.gz"
echo "Downloading Tomcat from: $TOMCAT_URL"
if ! curl -L -O "$TOMCAT_URL"; then
    echo -e "${RED}Error: Failed to download Tomcat from $TOMCAT_URL${NC}"
    exit 1
fi
FILE_SIZE=$(stat -c%s "$TOMCAT_FILE")
if [ "$FILE_SIZE" -lt 10000000 ]; then
    echo -e "${RED}Error: Downloaded file is too small ($FILE_SIZE bytes), expected ~10MB+. Download failed.${NC}"
    exit 1
fi
if ! tar -xzf "$TOMCAT_FILE"; then
    echo -e "${RED}Error: Failed to extract $TOMCAT_FILE. File may be corrupt.${NC}"
    exit 1
fi
if ! mv "apache-tomcat-$TOMCAT_VERSION" tomcat9; then
    echo -e "${RED}Error: Failed to rename Tomcat directory${NC}"
    exit 1
fi
rm "$TOMCAT_FILE"

# Set Tomcat permissions
echo "Setting Tomcat permissions..."
groupadd -f tomcat || echo "Group tomcat already exists, skipping..."
if id "tomcat" >/dev/null 2>&1; then
    echo "User tomcat already exists, skipping creation..."
else
    if ! useradd -s /bin/false -g tomcat -d /opt/tomcat9 tomcat; then
        echo -e "${RED}Error: Failed to create tomcat user${NC}"
        exit 1
    fi
fi
if ! chown -R tomcat:tomcat /opt/tomcat9; then
    echo -e "${RED}Warning: Failed to set ownership for /opt/tomcat9, continuing...${NC}"
fi
if ! chmod -R 750 /opt/tomcat9; then
    echo -e "${RED}Warning: Failed to set permissions for /opt/tomcat9, continuing...${NC}"
fi

# Configure Tomcat memory
echo "Configuring Tomcat memory settings..."
echo "JAVA_OPTS=\"-Xms512m -Xmx2048m\"" > /opt/tomcat9/bin/setenv.sh
if ! chmod +x /opt/tomcat9/bin/setenv.sh; then
    echo -e "${RED}Error: Failed to set executable permissions for setenv.sh${NC}"
    exit 1
fi

# Create systemd service for Tomcat
echo "Creating systemd service for Tomcat..."
cat <<EOL > /etc/systemd/system/tomcat9.service
[Unit]
Description=Apache Tomcat 9 Web Application Server
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
Environment="CATALINA_PID=/opt/tomcat9/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat9"
Environment="CATALINA_BASE=/opt/tomcat9"
Environment="CATALINA_OPTS=-Xms512m -Xmx2048m -server -XX:+UseParallelGC"
ExecStart=/opt/tomcat9/bin/startup.sh
ExecStop=/opt/tomcat9/bin/shutdown.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# Set permissions for the service file
if ! chmod 644 /etc/systemd/system/tomcat9.service; then
    echo -e "${RED}Error: Failed to set permissions for tomcat9.service${NC}"
    exit 1
fi
if ! chown root:root /etc/systemd/system/tomcat9.service; then
    echo -e "${RED}Error: Failed to set ownership for tomcat9.service${NC}"
    exit 1
fi

# Reload systemd to recognize the new service
echo "Reloading systemd daemon..."
if ! systemctl daemon-reload; then
    echo -e "${RED}Error: Failed to reload systemd daemon${NC}"
    exit 1
fi

# Enable Tomcat to start on boot
echo "Enabling Tomcat to start on boot..."
if ! systemctl enable tomcat9.service; then
    echo -e "${RED}Error: Failed to enable Tomcat service${NC}"
    exit 1
fi

# Set up PostgreSQL
echo "Configuring PostgreSQL $POSTGRES_VERSION..."
if ! systemctl start postgresql; then
    echo -e "${RED}Error: Failed to start PostgreSQL${NC}"
    exit 1
fi
sudo -u postgres psql -c "CREATE USER dspace WITH PASSWORD 'dspace';" || echo "User dspace already exists, skipping..."
sudo -u postgres psql -c "CREATE DATABASE dspace OWNER dspace;" || echo "Database dspace already exists, skipping..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE dspace TO dspace;"
sudo -u postgres psql -d dspace -c "CREATE EXTENSION pgcrypto;" || echo "pgcrypto extension already installed, skipping..."
if ! sed -i "s/#listen_addresses = 'localhost'/listen_addresses = 'localhost'/" /etc/postgresql/"$POSTGRES_VERSION"/main/postgresql.conf; then
    echo -e "${RED}Error: Failed to configure PostgreSQL listen_addresses${NC}"
    exit 1
fi
if ! systemctl restart postgresql; then
    echo -e "${RED}Error: Failed to restart PostgreSQL${NC}"
    exit 1
fi

# Install Solr
echo "Installing Apache Solr $SOLR_VERSION..."
cd /opt
SOLR_URL="https://archive.apache.org/dist/lucene/solr/$SOLR_VERSION/solr-$SOLR_VERSION.tgz"
SOLR_FILE="solr-$SOLR_VERSION.tgz"
echo "Downloading Solr from: $SOLR_URL"
if ! curl -L -O "$SOLR_URL"; then
    echo -e "${RED}Error: Failed to download Solr from $SOLR_URL${NC}"
    exit 1
fi
FILE_SIZE=$(stat -c%s "$SOLR_FILE")
if [ "$FILE_SIZE" -lt 100000000 ]; then
    echo -e "${RED}Error: Downloaded file is too small ($FILE_SIZE bytes), expected ~100MB+. Download failed.${NC}"
    exit 1
fi
if ! tar -xzf "$SOLR_FILE"; then
    echo -e "${RED}Error: Failed to extract $SOLR_FILE. File may be corrupt.${NC}"
    exit 1
fi
if ! mv "solr-$SOLR_VERSION" solr; then
    echo -e "${RED}Error: Failed to rename Solr directory${NC}"
    exit 1
fi
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
    if ! useradd -s /bin/false -g solr -d /opt/solr solr; then
        echo -e "${RED}Error: Failed to create solr user${NC}"
        exit 1
    fi
fi
if ! chown -R solr:solr /opt/solr; then
    echo -e "${RED}Error: Failed to set ownership for /opt/solr${NC}"
    exit 1
fi
if ! mkdir -p /opt/solr/server/logs; then
    echo -e "${RED}Error: Failed to create Solr logs directory${NC}"
    exit 1
fi
if ! chown solr:solr /opt/solr/server/logs; then
    echo -e "${RED}Error: Failed to set ownership for Solr logs${NC}"
    exit 1
fi
if ! chmod 750 /opt/solr/server/logs; then
    echo -e "${RED}Error: Failed to set permissions for Solr logs${NC}"
    exit 1
fi

# Start Solr
echo "Starting Solr..."
sudo -u solr /opt/solr/bin/solr stop -all  # Clear any stale instances
if ! sudo -u solr /opt/solr/bin/solr start -p 8983; then
    echo -e "${RED}Error: Failed to start Solr${NC}"
    exit 1
fi
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
# Clone DSpace from your GitHub repository
echo "Cloning DSpace from your GitHub repository..."
cd /usr/local/src

# Replace with your actual GitHub repository URL
REPO_URL="git@github.com:manojjsltc/DSpace-dspace-7.6.3.git"
REPO_DIR="DSpace-dspace-7.6.3"

echo "Cloning repository from: $REPO_URL"
if ! git clone "$REPO_URL" "$REPO_DIR"; then
    echo -e "${RED}Error: Failed to clone repository from $REPO_URL${NC}"
    exit 1
fi

cd "$REPO_DIR"

# Switch to the production branch
echo "Switching to sltc-live branch..."
if ! git checkout sltc-live; then
    echo -e "${RED}Error: Failed to switch to production branch. Ensure the branch exists.${NC}"
    exit 1
fi

echo "Successfully cloned and switched to production branch in $REPO_DIR"

# Build DSpace with Maven
echo "Building DSpace with Maven..."
if ! mvn -U package -Dmirage2.on=true -Dmirage2.deps.included=true; then
    echo -e "${RED}Error: Maven build failed${NC}"
    exit 1
fi

# Deploy DSpace with Ant
echo "Deploying DSpace..."
cd dspace/target/dspace-installer
if [ ! -f lib/postgresql-*.jar ]; then
    echo "Downloading PostgreSQL JDBC driver..."
    POSTGRES_JDBC_URL="https://jdbc.postgresql.org/download/postgresql-42.7.3.jar"
    echo "Downloading PostgreSQL JDBC driver from: $POSTGRES_JDBC_URL"
    if ! curl -L -O "$POSTGRES_JDBC_URL"; then
        echo -e "${RED}Error: Failed to download PostgreSQL JDBC driver${NC}"
        exit 1
    fi
    if ! mv postgresql-42.7.3.jar lib/; then
        echo -e "${RED}Error: Failed to move PostgreSQL JDBC driver${NC}"
        exit 1
    fi
fi
if ! mkdir -p /dspace/log; then
    echo -e "${RED}Error: Failed to create DSpace log directory${NC}"
    exit 1
fi
if ! chown tomcat:tomcat /dspace/log; then
    echo -e "${RED}Error: Failed to set ownership for DSpace log${NC}"
    exit 1
fi
if ! chmod 750 /dspace/log; then
    echo -e "${RED}Error: Failed to set permissions for DSpace log${NC}"
    exit 1
fi
export DSPACE_HOME=/dspace
if ! ant fresh_install -Ddspace.dir=/dspace -logfile /dspace/log/ant_install.log; then
    echo -e "${RED}Error: Ant build failed. Check /dspace/log/ant_install.log for details.${NC}"
    exit 1
fi

# Set up DSpace directories
echo "Setting up DSpace directories and permissions..."
if ! cp -r ./* /dspace/; then
    echo -e "${RED}Error: Failed to copy DSpace files${NC}"
    exit 1
fi
if ! chown -R tomcat:tomcat /dspace; then
    echo -e "${RED}Warning: Failed to set ownership for /dspace, continuing...${NC}"
fi
if ! chmod -R 750 /dspace; then
    echo -e "${RED}Warning: Failed to set permissions for /dspace, continuing...${NC}"
fi

# Configure Solr cores for DSpace
echo "Configuring Solr cores for DSpace..."
if ! cp -r /dspace/solr/* /opt/solr/server/solr/configsets/; then
    echo -e "${RED}Error: Failed to copy Solr configsets${NC}"
    exit 1
fi
if ! chown -R solr:solr /opt/solr/server/solr/configsets/; then
    echo -e "${RED}Error: Failed to set ownership for Solr configsets${NC}"
    exit 1
fi
if ! sudo -u solr /opt/solr/bin/solr create_core -c search -d /opt/solr/server/solr/configsets/search; then
    echo -e "${RED}Error: Failed to create search core${NC}"
    exit 1
fi
if ! sudo -u solr /opt/solr/bin/solr create_core -c statistics -d /opt/solr/server/solr/configsets/statistics; then
    echo -e "${RED}Error: Failed to create statistics core${NC}"
    exit 1
fi
if ! sudo -u solr /opt/solr/bin/solr create_core -c oai -d /opt/solr/server/solr/configsets/oai; then
    echo -e "${RED}Error: Failed to create oai core${NC}"
    exit 1
fi
if ! sudo -u solr /opt/solr/bin/solr create_core -c authority -d /opt/solr/server/solr/configsets/authority; then
    echo -e "${RED}Error: Failed to create authority core${NC}"
    exit 1
fi

# Initialize database
echo "Initializing DSpace database..."
if ! /dspace/bin/dspace database migrate; then
    echo -e "${RED}Error: Database migration failed. Check logs at /dspace/log/.${NC}"
    exit 1
fi

# Deploy webapps to Tomcat
echo "Deploying DSpace webapps to Tomcat..."
if ! cp -r /dspace/webapps/* /opt/tomcat9/webapps/; then
    echo -e "${RED}Error: Failed to copy DSpace webapps${NC}"
    exit 1
fi
if ! chown -R tomcat:tomcat /opt/tomcat9/webapps/; then
    echo -e "${RED}Warning: Failed to set ownership for Tomcat webapps, continuing...${NC}"
fi

# Fix dspace.dir in server webapp's application.properties
echo "Fixing dspace.dir in server webapp configuration..."
if ! sed -i "s|dspace.dir=\${dspace.dir}|dspace.dir=/dspace|" /opt/tomcat9/webapps/server/WEB-INF/classes/application.properties; then
    echo -e "${RED}Error: Failed to update application.properties${NC}"
    exit 1
fi
if ! chown tomcat:tomcat /opt/tomcat9/webapps/server/WEB-INF/classes/application.properties; then
    echo -e "${RED}Error: Failed to set ownership for application.properties${NC}"
    exit 1
fi

# Start Tomcat
echo "Starting Tomcat service..."
if ! systemctl start tomcat9.service; then
    echo -e "${RED}Error: Failed to start Tomcat service${NC}"
    systemctl status tomcat9.service
    exit 1
fi

# Verify installation
echo "Verifying DSpace installation..."
sleep 30  # Increased sleep to ensure Tomcat fully deploys webapps
if systemctl is-active --quiet tomcat9.service && curl -s http://localhost:8080/xmlui >/dev/null && curl -s http://localhost:8080/server/api/status >/dev/null; then
    echo -e "${GREEN}DSpace $DSPACE_VERSION installation completed successfully!${NC}"
    echo "Access it at: http://localhost:8080/xmlui or http://localhost:8080/server/api"
else
    echo -e "${RED}Warning: DSpace web interface not accessible or Tomcat not running.${NC}"
    echo "Tomcat service status:"
    systemctl status tomcat9.service
fi
echo "Tomcat logs: /opt/tomcat9/logs/"
echo "DSpace logs: /dspace/log/"
echo "Solr logs: /opt/solr/server/logs/"

# Create admin user
echo "Creating initial DSpace administrator..."
if ! /dspace/bin/dspace create-administrator; then
    echo -e "${RED}Warning: Failed to create admin user. Run '/dspace/bin/dspace create-administrator' manually.${NC}"
fi

exit 0