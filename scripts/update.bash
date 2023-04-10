PHP_VERSION=$(php -r "echo PHP_VERSION_ID;")
COMPOSER_VERSION=$(yes | composer --version | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")

check_dependencies() {
if (( PHP_VERSION < 80000 )); then
    echo "At the moment you are running php lower than 8.0 once it is upgraded to 8.0 or higher you can continue with this"
    exit 1
else
    echo "This PHP Version is sufficient for the update"
fi

if (( $(echo "${COMPOSER_VERSION//./}") < 200 )); then
    echo "At the moment you are running Composer lower than 2.0 once it is upgraded to 2.0 or higher you can continue with this"
    exit 1
else
    echo "This Composer Version is sufficient for the update."
fi
}

panel_update() {
    cd /var/www/pterodactyl
    php artisan down
    curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv
    chmod -R 755 storage/* bootstrap/cache
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan view:clear
    php artisan config:clear
    php artisan migrate --seed --force
    chown -R www-data:www-data /var/www/pterodactyl/*
    php artisan queue:restart
    php artisan up
}

wings_update() {
    systemctl stop wings
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    systemctl restart wings
}

check_dependencies
panel_update
wings_update