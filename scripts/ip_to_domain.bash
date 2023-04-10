IP=$(curl -s https://ip.thomas07.eu)
WAIT_TIME=200

## Toevoegen dat die ook in de .env file het domein aanpast voor op een panel

echo "By using this script with SSL, you automatically agree to the terms and conditions of Let's Encrypt."

webserver_check() {
    if pgrep -x "nginx" > /dev/null; then
        WEBSERVER=nginx
    elif pgrep -x "apache2" > /dev/null; then
        WEBSERVER=apache2
    else
        WEBSERVER=none
    fi
}

panel_check() {
    if sudo systemctl is-enabled --quiet pteroq.service >/dev/null 2>&1 && sudo systemctl is-active --quiet pteroq.service >/dev/null 2>&1; then
        PANEL=on
    else
        PANEL=off
    fi
}

wings_check() {
    if sudo systemctl is-enabled --quiet wings >/dev/null 2>&1 && sudo systemctl is-active --quiet wings >/dev/null 2>&1; then
        WINGS=on
    else
        WINGS=off
    fi
}

domain_check() {
    local FQDN=$1
    FQDN_IP=$(dig +short $FQDN)
    if [ "$IP" == "$FQDN_IP" ]; then
            echo "The domain is correctly linked to the IP address"
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
            echo "The domain is correctly linked to the IP address"
        else
            echo "Unfortunately it still doesn't work try again later it can take up to 24 hours before the A records are updated with your provider"
            exit 1
        fi
    fi
}

ssl_create() {
    local FQDN=$1
    if [ "$PANEL" == "on" ]; then
        EMAIL=$(grep -oP "(?<=APP_SERVICE_AUTHOR=\")[^\"]+" /var/www/pterodactyl/.env)
    else
        echo "What is your email address? (This is used for SSL & your panel account)"
        read EMAIL
    fi
    if [ "$WEBSERVER" == "nginx" ]; then
        sudo apt install -y certbot
        sudo apt install -y python3-certbot-nginx
        certbot certonly --non-interactive --agree-tos --email $EMAIL --nginx -d $FQDN
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart nginx\"" >> mycron && crontab mycron && rm mycron
    elif [ "$WEBSERVER" == "apache2" ]; then
        sudo apt install -y certbot
        sudo apt install -y python3-certbot-apache
        certbot certonly --non-interactive --agree-tos --email $EMAIL --apache2 -d $FQDN
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart apache2\"" >> mycron && crontab mycron && rm mycron
    else
        if [[ "$PANEL" == "off" && "$WINGS" == "on" ]]; then
            certbot certonly --non-interactive --agree-tos --email $EMAIL --standalone -d $FQDN
        else
            read -rp  "We have not found a web server if you can enter it manually you can do so here if you do not know which web server you are running then stop (n/a): " WEBSERVER_CHOICE
            if [[ "$WEBSERVER_CHOICE" == "n" || "$WEBSERVER_CHOICE" == "N" ]]; then
                WEBSERVER=nginx
            elif [[ "$WEBSERVER_CHOICE" == "nginx" || "$WEBSERVER_CHOICE" == "Nginx" ]]; then
                WEBSERVER=nginx
            elif [[ "$WEBSERVER_CHOICE" == "a" || "$WEBSERVER_CHOICE" == "A" ]]; then
                WEBSERVER=apache2
            elif [[ "$WEBSERVER_CHOICE" == "apache2" || "$WEBSERVER_CHOICE" == "Apache2" ]]; then
                WEBSERVER=apache2
            else
                echo "Answer not found, nginx will be used."
                WEBSERVER=nginx
            fi
            ssl_create
        fi
    fi
}

panel_configuration() {
    if [ "$DOMAIN_CHOICE" == "one" ]; then FQDN=$DOMAIN elif [ "$DOMAIN_CHOICE" == "specifically" ]; then FQDN=$DOMAIN_PANEL fi
    if [ "$WEBSERVER" == "nginx" ]; then
        sudo service stop nginx
        rm -f /etc/nginx/sites-available/pterodactyl.conf
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/nginx/ssl_pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
        sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl restart nginx
    elif [ "$WEBSERVER" == "apache2" ]; then
        sudo service stop apache2
        rm -f /etc/apache2/sites-available/pterodactyl.conf
        rm -f /etc/apache2/sites-enabled/pterodactyl.conf
        a2dissite 000-default.conf
        curl -o /etc/apache2/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/apache2/ssl_pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/apache2/sites-available/pterodactyl.conf
        sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
        sudo a2enmod rewrite
        sudo a2enmod ssl
        sudo systemctl restart apache2
    fi
    sed -i "s#APP_URL=.*#APP_URL=https://$FQDN#" /var/www/pterodactyl/.env
}

node_configuration() {
    if [ "$DOMAIN_CHOICE" == "one" ]; then FQDN=$DOMAIN elif [ "$DOMAIN_CHOICE" == "specifically" ]; then FQDN=$DOMAIN_NODE fi
    mysql -u root -e "UPDATE panel.nodes SET fqdn = '${FQDN}' WHERE fqdn = '${IP}';"
    mysql -u root -e "UPDATE panel.nodes SET scheme = 'https' WHERE fqdn = '${FQDN}';"
    sed -i "s|/etc/letsencrypt/live/$IP|/etc/letsencrypt/live/$FQDN|" /etc/pterodactyl/config.yml
    sed -i "s|remote: http://$IP|remote: https://$FQDN|" /etc/pterodactyl/config.yml
    sed -i "s|enabled: false|enabled: true|" /etc/pterodactyl/config.yml
    service wings restart
}

installer() {
    if [[ "$PANEL" == "on" && "$WINGS" == "on" ]]; then
        read -rp "Do you want to use the same domain as for your panel for your node? (y/n): " DOMAIN_BOTH
        if [[ "$DOMAIN_BOTH" =~ ^[Yy]$ ]]; then
            DOMAIN_CHOICE=one
            read -rp "What domain name do you want to use for your pterodactyl panel and node? " DOMAIN
            domain_check $DOMAIN
            ssl_create $DOMAIN
            panel_configuration
            node_configuration
        elif [[ "$DOMAIN_BOTH" =~ ^[Nn]$ ]]; then
            DOMAIN_CHOICE=specifically
            read -rp "What domain name do you want to use for your pterodactyl panel? " DOMAIN_PANEL
            clear
            read -rp "What domain name do you want to use for your pterodactyl node? " DOMAIN_NODE
            domain_check $DOMAIN_PANEL
            ssl_create $DOMAIN_PANEL
            domain_check $DOMAIN_NODE
            ssl_create $DOMAIN_NODE
            panel_configuration
            node_configuration
        else
            DOMAIN_CHOICE=one
            echo "Your answer was not clear so it automatically goes to that your domain for the panel & the node is the same"
            read -rp "What domain name do you want to use for your panel and node? " DOMAIN
            domain_check $DOMAIN
            ssl_create $DOMAIN
            panel_configuration
            node_configuration
        fi
    elif [[ "$PANEL" == "on" && "$WINGS" == "off" ]]; then
        DOMAIN_CHOICE=specifically
        read -rp "What domain name do you want to use for your pterodactyl panel? " DOMAIN_PANEL
        domain_check $DOMAIN_PANEL
        ssl_create $DOMAIN_PANEL
        panel_configuration
    elif [[ "$PANEL" == "off" && "$WINGS" == "on" ]]; then
        DOMAIN_CHOICE=specifically
        read -rp "What domain name do you want to use for your pterodactyl node? " DOMAIN_NODE
        domain_check $DOMAIN_NODE
        ssl_create $DOMAIN_NODE
        node_configuration
    else
        echo "We have mentioned that both the wings and pteroq.service are offline or not found, make sure these are active and only then can we continue for you"
    fi
}

webserver_check
panel_check
wings_check
installer