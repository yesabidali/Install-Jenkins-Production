#!/bin/bash
set -e

JAVA_PACKAGE="openjdk-17-jdk"
DOMAIN=""
EMAIL="admin@example.com"

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo "Run as root"
       exit 1
    fi
}

configure_firewall() {
    echo "Opening Ports: 22 (SSH), 80 (HTTP), 443 (HTTPS), 8080 (Jenkins)"
    apt update && apt install -y ufw
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
    ufw allow 8080
    echo "y" | ufw enable
}

install_jenkins() {
    apt update -y
    apt install -y $JAVA_PACKAGE curl gnupg
    curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
    apt update -y
    apt install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins
}

configure_ssl_auto() {
    read -p "Enter domain (must already point to this server): " DOMAIN
    SERVER_IP=$(curl -s ifconfig.me)
    DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

    if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
        echo "DNS NOT POINTING TO SERVER. Expected: $SERVER_IP, Found: $DOMAIN_IP"
        exit 1
    fi

    apt install -y nginx certbot python3-certbot-nginx
    rm -f /etc/nginx/sites-enabled/default

    cat <<EOF > /etc/nginx/sites-available/jenkins
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Support for Jenkins WebSockets
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
    nginx -t
    systemctl restart nginx

    # Run Certbot (it will modify the Nginx file to add SSL automatically)
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect
    
    systemctl restart nginx
}

# --- Execution ---
check_root
configure_firewall
install_jenkins

read -p "Enable SSL? (yes/no): " SSL
[[ "$SSL" == "yes" ]] && configure_ssl_auto

echo "================================="
echo "Jenkins setup complete!"
echo "URL: https://$DOMAIN"
echo "Initial Admin Password:"
cat /var/lib/jenkins/secrets/initialAdminPassword