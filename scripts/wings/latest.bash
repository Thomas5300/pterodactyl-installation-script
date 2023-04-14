USE_SSL=false
USE_DOMAIN=false
IP=$(curl -s https://ip.thomas07.eu)
FQDN_IP=$(dig +short $FQDN)
WAIT_TIME=200
echo "By using this script with SSL, you automatically agree to the terms and conditions of Let's Encrypt."

email_usage() {
    echo "What is your email address?"
    read EMAIL
}

cerbot_usage() {
    sudo apt update
    sudo apt install -y certbot
    if dpkg -s nginx &>/dev/null; then
        sudo apt install -y python3-certbot-nginx
        certbot certonly --non-interactive --agree-tos --email $EMAIL --nginx -d $FQDN
    elif dpkg -s apache2 &>/dev/null; then
        sudo apt install -y python3-certbot-apache
        certbot certonly --non-interactive --agree-tos --email $EMAIL --apache -d $FQDN
    else
        certbot certonly --non-interactive --agree-tos --email $EMAIL --standalone -d $FQDN
    fi
}

setup_ssl() {
    if [ "$IP" == "$FQDN_IP" ]; then
        cerbot_usage
    else
        echo "The domain ($FQDN) is not the same as the IPv4 address ($IP). We will try in more than 2 minutes. In the meantime, you can check again if the record is correct. Below is what it should be."
        echo "A | $FQDN | $IP"
        echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
        for i in $(seq $WAIT_TIME -1 1); do
            echo -ne "Wait another $i seconds before trying again \r"
            sleep 1
        done
        echo "We're going to try again"
        if [ "$IP" == "$FQDN_IP" ]; then
            cerbot_usage
        else
            echo "Unfortunately it still doesn't work try again later it can take up to 24 hours before the A records are updated with your provider"
            exit 1
        fi
    fi
}

domain_usage() {
    read -rp "Do you want wings installed on a domain (y/n): " USE_DOMAIN_CHOICE
    if [[ "$USE_DOMAIN_CHOICE" =~ ^[Yy]$ ]]; then
        USE_DOMAIN=true
        echo "On which domain name should this wings be installed? (FQDN)"
        read FQDN
        setup_ssl
    elif [[ "$USE_DOMAIN_CHOICE" =~ ^[Nn]$ ]]; then
        USE_DOMAIN=false
    else
        echo "Answer not found, no domain will be used."
        USE_DOMAIN=false
    fi
}

installing_docker() {
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
}

start_docker_on_boot() {
    systemctl enable docker
}

installing_wings() {
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
}

daemonizing() {
    curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomas5300/pterodactyl-installation-script/main/configurations/wings/wings.service
    systemctl enable --now wings
}

email_usage
domain_usage
installing_docker
start_docker_on_boot
installing_wings
daemonizing