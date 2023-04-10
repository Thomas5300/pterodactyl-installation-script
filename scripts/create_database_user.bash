#!/bin/bash
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
CONFIG_FILE=$(find /etc -iname "my.cnf" -print -quit)
SERVER_IP=$(curl -s https://ip.thomas07.eu)

external_database_access() {
    if ! grep -q "^bind-address" "$CONFIG_FILE"; then
        echo -e "[mysqld]\nbind-address=0.0.0.0" >> "$CONFIG_FILE"
    fi
    service mysql restart
    service mysqld restart
}

manually_database() {
    echo "What do you want to set as username?"
    read USERNAME
    echo "What do you want as a password? Click enter to automatically generate one"
    read PASSWORD
    if [[ -z "$PASSWORD" ]]; then
        PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 ; echo '')
    fi
    echo "If you use a different server than the one on which your panel of wings is located, enter the ip address of your pterodactyl panel here"
    echo "Do you want to change the remote access ip address? By default it is set to 127.0.0.1 (y/n)"
    read REMOTE_ACCESS_ADDRESS
    if [[ "$REMOTE_ACCESS_ADDRESS" =~ ^[Yy]$ ]]; then
        echo "What do you want to set as remote access ip address?"
        read IP_ADRES
    elif [[ "$REMOTE_ACCESS_ADDRESS" =~ ^[Nn]$ ]]; then
        echo "The standard remote access ip is used so 127.0.0.1"
        IP_ADRES = "127.0.0.1"
    else
        echo "No answer found the default remote access ip is used so 127.0.0.1"
        IP_ADRES = "127.0.0.1"
    fi
    read -rp "Do you want to enable external database access? (y/n)" MANUALLY_DATABASE_ACCESS
    if [[ "$MANUALLY_DATABASE_ACCESS" =~ ^[Yy]$ ]]; then
        external_database_access
    elif [[ "$MANUALLY_DATABASE_ACCESS" =~ ^[Nn]$ ]]; then
        echo "External database is not enabled"
    else
        echo "No answer found we don't enable external database access"
        external_database_access
    fi
    mysql -u root -e "CREATE USER '${USERNAME}'@'${IP_ADRES}' IDENTIFIED BY '${PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${USERNAME}'@'${IP_ADRES}' WITH GRANT OPTION;"
    clear
    echo "The host/user database has been successfully created, all you have to do now is add it to your pterodactyl panel"
    echo "If you don't run the database on your panel, enter this in host when you create a database in pterodactyl: $SERVER_IP"
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo "Remote Access Adres: $IP_ADRES"

}

setup_database() {
    mysql -u root -e "CREATE USER 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;"
    external_database_access
    echo "The host/user database has been successfully created, all you have to do now is add it to your pterodactyl panel"
    echo "Host: 127.0.0.1"
    echo "Username: pterodactyluser"
    echo "Password: $MYSQL_PASSWORD"
}

manually_question() {
    echo "Do you want to compile all information manually? we recommend doing this if you are not running the database on your pterodactyl panel (y/n)"
    read MANUALLY
    if [[ "$MANUALLY" =~ ^[Yy]$ ]]; then
        manually_database
    elif [[ "$MANUALLY" =~ ^[Nn]$ ]]; then
        setup_database
    else
        echo "No answer found, we fill in everything automatically"
        setup_database
    fi
}

manually_question