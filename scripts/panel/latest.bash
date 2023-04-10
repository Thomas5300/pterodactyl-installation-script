OS=$(lsb_release -i | awk '{print $3}')
VERSION=$(lsb_release -rs)
IP=$(curl -s https://ip.thomas07.eu)
FQDN=$(curl -s https://ip.thomas07.eu)
FQDN_IP=$(dig +short $FQDN)
USE_SSL=false
WAIT_TIME=200
USE_DOMAIN=false
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
DATABASE_HOST_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
USER_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
disk_space=$(df -B MB / | tail -n 1 | awk '{print $2}')
CONFIG_FILE=$(find /etc -iname "my.cnf" -print -quit)

echo "By using this script with SSL, you automatically agree to the terms and conditions of Let's Encrypt."

domain_usage() {
    read -rp "Do you want pterodactyl installed on a domain (y/n)" USE_DOMAIN_CHOICE
    if [[ "$USE_DOMAIN_CHOICE" =~ ^[Yy]$ ]]; then
        USE_DOMAIN=true
        read -rp "On which domain name should this panel be installed? (FQDN): " FQDN
        read -rp "Do you want SSL on this domain? (IPs cannot have SSL!) (y/n): " USE_SSL_CHOICE

        if [[ "$USE_SSL_CHOICE" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
            USE_SSL=true
        else
            USE_SSL=false
        fi

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
    elif [[ "$USE_DOMAIN_CHOICE" =~ ^[Nn]$ ]]; then
        USE_DOMAIN=false
    else
        echo "Answer not found, no domain will be used."
        USE_DOMAIN=false
    fi
}

email_usage() {
    read -rp "What is your email address? (This is used for SSL & your panel account): " EMAIL
}

phpmyadmin_usage() {
    read -rp "Do you want phpmyadmin installed? (y/n): "PHPMYADMIN_CHOICE
    if [[ "$PHPMYADMIN_CHOICE" =~ ^[Yy]$ ]]; then
        PHPMYADMIN=true
    elif [[ "$PHPMYADMIN_CHOICE" =~ ^[Nn]$ ]]; then
        PHPMYADMIN=false
    else
        echo "Answer not found, no phpmyadmin will be installed."
        PHPMYADMIN=false
    fi
}

webserver_configuration() {
    read -rp "Do you want to use nginx or apache2? (n/a): " WEBSERVER_CHOICE
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
}

dependency_installation() {
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    if [ "$OS" = "Ubuntu" ]; then
        if [ "$VERSION" = "22.04" ]; then
                curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
        fi
    fi
    apt update
    if [ "$OS" = "Ubuntu" ]; then
        if [ "$VERSION" = "18.04" ]; then
            apt-add-repository universe
        fi
    fi
    apt -y install php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
}

installing_composer() {
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

download_files() {
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
}

database_configuration() {
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"
}

installation() {
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan key:generate --force
}

environment_configuration() {
    if [ "$USE_SSL" == true ]; then
        php artisan p:environment:setup --author=$EMAIL --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled
    elif [ "$USE_SSL" == false ]; then
        php artisan p:environment:setup --author=$EMAIL --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled 
    fi
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password=$MYSQL_PASSWORD
}

database_setup() {
    php artisan migrate --seed --force
}

add_the_first_user() {
    php artisan p:user:make --email=$EMAIL --username=admin --name-first=admin --name-last=admin --password=$USER_PASSWORD --admin=1 
}

set_permissions() {
    chown -R www-data:www-data /var/www/pterodactyl/*
}

crontab_configuration() {
    (sudo crontab -l; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -
}

create_queue_worker() {
    curl -o /etc/systemd/system/pteroq.service https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/pteroq.service
    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service
}

nginx_certbot() {
    sudo apt update
    sudo apt install -y certbot
    sudo apt install -y python3-certbot-nginx
    certbot certonly --non-interactive --agree-tos --email $EMAIL --nginx -d $FQDN
}

nginx_configuration() {
    rm /etc/nginx/sites-enabled/default
    if [ "$USE_SSL" == true ]; then
        nginx_certbot
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/nginx/ssl_pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
        sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl restart nginx
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart nginx\"" >> mycron && crontab mycron && rm mycron
    elif [ "$USE_SSL" == false ]; then
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/nginx/pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
        sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl restart nginx
    fi
}

apache2_certbot() {
    sudo apt update
    sudo apt install -y certbot
    sudo apt install -y python3-certbot-apache
    certbot certonly --non-interactive --agree-tos --email $EMAIL --apache -d $FQDN
}

apache2_configuration() {
    a2dissite 000-default.conf
    if [ "$USE_SSL" == true ]; then
        apache2_certbot
        curl -o /etc/apache2/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/apache2/ssl_pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/apache2/sites-available/pterodactyl.conf
        sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
        sudo a2enmod rewrite
        sudo a2enmod ssl
        sudo systemctl restart apache2
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart apache2\"" >> mycron && crontab mycron && rm mycron
    elif [ "$USE_SSL" == false ]; then
        curl -o /etc/apache2/sites-available/pterodactyl.conf https://github.com/Thomas5300/pterodactyl-installation-script/configurations/panel/webserver/apache2/pterodactyl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/apache2/sites-available/pterodactyl.conf
        sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
        sudo a2enmod rewrite
        sudo systemctl restart apache2
    fi
}

phpmyadmin_installation() {
    cd /var/www/pterodactyl/public 
    mkdir phpmyadmin
    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-english.tar.gz
    tar xvzf phpMyAdmin-latest-english.tar.gz
    mv phpMyAdmin-*-english/* phpmyadmin
    rm -rf phpMyAdmin-*-english
    rm -rf phpMyAdmin-latest-english.tar.gz
}

information_message() {
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Your Pterodactyl panel has been successfully installed and should be fully functional. If you encounter any issues or problems with the panel, please do not hesitate to reach out to the creator of this script for assistance."
    echo "Here are your login credentials:"
    echo "Username: admin"
    echo "Password: $USER_PASSWORD"
    if [ "$USE_SSL" == true ]; then
        echo "URL: https://$FQDN"
        if [ "$PHPMYADMIN" == true ]; then
            echo "phpMyAdmin URL: https://$FQDN/phpmyadmin"
        fi
    elif [ "$USE_SSL" == false ]; then
        echo "URL: http://$FQDN"
        if [ "$PHPMYADMIN" == true ]; then
            echo "phpMyAdmin URL: http://$FQDN/phpmyadmin"
        fi
    fi
    echo "-=-=-=-=-=-=-=( Database information )-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Database Host: 127.0.0.1:3306"
    echo "Database Name: panel"
    echo "Database User: pterodactyl"
    echo "Database Password: $MYSQL_PASSWORD"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
}

install_pterodactyl() {
    domain_usage
    email_usage
    phpmyadmin_usage
    webserver_configuration
    dependency_installation
    installing_composer
    download_files
    database_configuration
    installation
    environment_configuration
    database_setup
    add_the_first_user
    set_permissions
    crontab_configuration
    create_queue_worker
    if [ "$WEBSERVER" == "nginx" ]; then
        nginx_configuration
    elif [ "$WEBSERVER" == "apache2" ]; then
        apache2_configuration
    fi
    if [ "$PHPMYADMIN" == true ]; then
        phpmyadmin_installation
    fi
    information_message
}

install_pterodactyl