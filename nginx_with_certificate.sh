#!/bin/bash

colored_text(){
  local color=$1
  local text=$2
  echo -e "\e[${color}m$text\e[0m"
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    colored_text "31" "Please run as root (sudo)."
    exit 1
fi

# If nginx is installed, remove its current installation and configuration files
if [ -x "$(command -v nginx)" ]; then
    colored_text "32" "Nginx is installed. Purging existing installation and configuration files..."

    colored_text "32" "Stopping nginx service..."
    systemctl stop nginx 2>/dev/null
    colored_text "32" "Purging nginx..."
    apt-get purge -y nginx
    colored_text "32" "Autoremoving packages..."
    apt-get autoremove -y
    colored_text "32" "Removing nginx directory..."
    rm -rf /etc/nginx
fi

# Update the package list
colored_text "32" "Updating package list..."
apt-get update -y

# Install nginx
colored_text "32" "Installing nginx..."
apt-get install nginx -y

########################################
# Domain and SSL Certificate Settings
########################################

DOMAIN="hyperrio.site"

# Directly assign the content of your certificate, private key, and chain file (if applicable)
CERTIFICATE_CONTENT="-----BEGIN CERTIFICATE-----
... Your certificate content goes here ...
-----END CERTIFICATE-----"

PRIVATE_KEY_CONTENT="-----BEGIN PRIVATE KEY-----
... Your private key content goes here ...
-----END PRIVATE KEY-----"

# If you have an intermediate chain file, assign its content here; otherwise, leave this empty
CHAIN_CONTENT="-----BEGIN CERTIFICATE-----
... Your chain file content goes here ...
-----END CERTIFICATE-----"

# Paths where the certificate files will be saved
CERT_PATH="/etc/ssl/certs/your_cert.crt"
KEY_PATH="/etc/ssl/private/your_key.key"
CHAIN_PATH="/etc/ssl/certs/your_chain.pem"

# Create necessary directories if they do not exist
mkdir -p /etc/ssl/certs
mkdir -p /etc/ssl/private

# Save the certificate, private key, and chain file contents to their respective paths
echo "$CERTIFICATE_CONTENT" > "$CERT_PATH"
echo "$PRIVATE_KEY_CONTENT" > "$KEY_PATH"
if [ -n "$CHAIN_CONTENT" ]; then
    echo "$CHAIN_CONTENT" > "$CHAIN_PATH"
fi

########################################
# Nginx Configuration for Reverse Proxy with SSL
########################################

CONFIG_FILE="/etc/nginx/conf.d/load_balancer.conf"
colored_text "32" "Creating configuration file for reverse proxy: $CONFIG_FILE"

cat > "$CONFIG_FILE" <<EOF
# Define an upstream block for the backend server(s)
upstream load_balancer {
    server 195.177.255.230:8000;
}

# HTTP block: Redirect all HTTP traffic to HTTPS
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

# HTTPS block: SSL configuration and reverse proxy settings
server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${CERT_PATH};
    ssl_certificate_key ${KEY_PATH};
EOF

# Add chain file configuration if chain content exists
if [ -n "$CHAIN_CONTENT" ]; then
cat >> "$CONFIG_FILE" <<EOF
    ssl_trusted_certificate ${CHAIN_PATH};
EOF
fi

cat >> "$CONFIG_FILE" <<EOF

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Reverse proxy settings: forward all requests to the backend server(s)
    location / {
        proxy_pass http://load_balancer;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Remove default site configuration files if they exist
if [ -f /etc/nginx/sites-enabled/default ]; then
    colored_text "32" "Removing default configuration at /etc/nginx/sites-enabled/default"
    rm -f /etc/nginx/sites-enabled/default
fi

if [ -f /etc/nginx/conf.d/default.conf ]; then
    colored_text "32" "Removing default configuration at /etc/nginx/conf.d/default.conf"
    rm -f /etc/nginx/conf.d/default.conf
fi

# Test the nginx configuration
colored_text "32" "Testing nginx configuration..."
nginx -t
if [ $? -ne 0 ]; then
    colored_text "31" "Error in nginx configuration. Please check the config files."
    exit 1
fi

# Reload nginx to apply changes
colored_text "32" "Reloading nginx..."
systemctl reload nginx

# Enable nginx to start automatically on boot
colored_text "32" "Enabling nginx service to automatically start after reboot..."
systemctl enable nginx

colored_text "36" "Reverse proxy and Load balancer installation and configuration completed successfully."

########################################
# Firewall (ufw) Setup
########################################

colored_text "32" "Installing firewall..."
apt-get install -y ufw

colored_text "32" "Allowing SSH on port 22 and web traffic on ports 80, 443..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Enable ufw (this may prompt for confirmation)
ufw --force enable

colored_text "36" "All is done."
