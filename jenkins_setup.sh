#!/bin/bash

set -e

# =========================
# GLOBAL VARIABLES
# =========================
JAVA_PACKAGE="openjdk-17-jdk"
JENKINS_KEY_URL="https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key"
JENKINS_KEY_PATH="/usr/share/keyrings/jenkins-keyring.asc"
JENKINS_REPO_FILE="/etc/apt/sources.list.d/jenkins.list"

# =========================
# STEP 1: INSTALL JENKINS
# =========================
install_jenkins() {
  echo "=== STEP 1: Installing Jenkins ==="

  apt update -y
  apt install -y ${JAVA_PACKAGE}

  curl -fsSL "${JENKINS_KEY_URL}" | tee "${JENKINS_KEY_PATH}" > /dev/null
  echo "deb [signed-by=${JENKINS_KEY_PATH}] https://pkg.jenkins.io/debian-stable binary/" \
    | tee "${JENKINS_REPO_FILE}" > /dev/null

  apt update -y
  apt install -y jenkins

  systemctl enable jenkins
  systemctl start jenkins

  echo "Jenkins installed and running on port 8080"
}

# =========================
# STEP 2: ENABLE SSL
# =========================
configure_ssl() {
  read -p "Do you want to enable SSL (yes/no)? " ENABLE_SSL

  if [[ "$ENABLE_SSL" != "yes" ]]; then
    echo "Skipping SSL configuration"
    return
  fi

  read -p "Enter your domain name (example: jenkins.example.com): " DOMAIN
  read -p "Choose certificate type (letsencrypt/selfsigned): " CERT_TYPE

  apt install -y nginx

  if [[ "$CERT_TYPE" == "letsencrypt" ]]; then
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d "$DOMAIN"

    SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

  elif [[ "$CERT_TYPE" == "selfsigned" ]]; then
    mkdir -p /etc/nginx/ssl

    openssl req -x509 -nodes -days 365 \
      -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/jenkins.key \
      -out /etc/nginx/ssl/jenkins.crt

    SSL_CERT="/etc/nginx/ssl/jenkins.crt"
    SSL_KEY="/etc/nginx/ssl/jenkins.key"

  else
    echo "Unsupported certificate type"
    return
  fi

  cat <<EOF > /etc/nginx/sites-available/jenkins
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
  nginx -t
  systemctl restart nginx

  echo "SSL enabled for Jenkins at https://${DOMAIN}"
}

# =========================
# STEP 3: ENABLE SSO
# =========================
configure_sso() {
  read -p "Do you want to enable SSO (yes/no)? " ENABLE_SSO

  if [[ "$ENABLE_SSO" != "yes" ]]; then
    echo "Skipping SSO configuration"
    return
  fi

  read -p "Choose SSO type (oidc/saml): " SSO_TYPE

  apt install -y curl

  if [[ "$SSO_TYPE" == "oidc" ]]; then
    echo "OIDC selected"
    echo "Required details:"
    echo "- Client ID"
    echo "- Client Secret"
    echo "- Issuer URL"
    echo "Configure via Jenkins UI → Manage Jenkins → Security → OIDC"

  elif [[ "$SSO_TYPE" == "saml" ]]; then
    echo "SAML selected"
    echo "Required details:"
    echo "- IdP Metadata XML"
    echo "- Assertion Consumer Service URL"
    echo "Configure via Jenkins UI → Manage Jenkins → Security → SAML"

  else
    echo "Unsupported SSO type"
  fi
}

# =========================
# SCRIPT EXECUTION
# =========================
install_jenkins
configure_ssl
configure_sso

echo "=== Jenkins setup completed ==="
echo "Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword
