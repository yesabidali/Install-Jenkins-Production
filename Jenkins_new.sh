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

install_jenkins() {
  apt update -y
  apt install -y $JAVA_PACKAGE curl gnupg

  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    | tee /usr/share/keyrings/jenkins-keyring.asc >/dev/null

  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list

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
    echo "DNS NOT POINTING TO SERVER"
    echo "Server IP: $SERVER_IP"
    echo "Domain IP: $DOMAIN_IP"
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
        proxy_set_header X-Forwarded-Proto http;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/jenkins
  nginx -t
  systemctl restart nginx

  certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect

  mkdir -p /etc/systemd/system/jenkins.service.d
  cat <<EOF > /etc/systemd/system/jenkins.service.d/override.conf
[Service]
Environment="JENKINS_OPTS=--httpPort=8080 --prefix=/"
EOF

  systemctl daemon-reexec
  systemctl restart jenkins nginx
}

configure_sso_info() {
  echo "SSO must be configured via Jenkins UI"
  echo "Manage Jenkins → Security → SSO"
}

check_root
install_jenkins

read -p "Enable SSL? (yes/no): " SSL
[[ "$SSL" == "yes" ]] && configure_ssl_auto

read -p "Enable SSO? (yes/no): " SSO
[[ "$SSO" == "yes" ]] && configure_sso_info

echo "================================="
echo "Jenkins URL: https://$DOMAIN"
echo "Admin Password:"
cat /var/lib/jenkins/secrets/initialAdminPassword