#!/bin/bash

# Function to check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Script phai chay voi quyen root. Vui long chay lai bang sudo hoac voi quyen root."
        exit 1
    fi
}

# Check if script is run as root
check_root

# Function to ask yes/no questions
ask_yes_no() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Nhap lua chon yes hoac no.";;
        esac
    done
}

# Function to ensure dependencies are installed
ensure_installed() {
    local package=$1
    if ! rpm -q "$package" &>/dev/null; then
        echo "Dang cai goi: $package"
        yum install "$package" -y
    fi
}

# Ensure essential dependencies are installed
ensure_dependencies() {
    for package in httpd bind bind-utils; do
        ensure_installed "$package"
    done
}

# Function to check if a zone exists
zone_exists() {
    local zone=$1
    grep -q "zone \"$zone\"" /etc/named.rfc1912.zones
}

# Function to check if a host exists
host_exists() {
    local host=$1
    grep -q "ServerName $host" /etc/httpd/conf.d/*.conf
}

# Logging function
log_action() {
    local message=$1
    logger -t autoscript "$message"
    echo "$message"
}

# Function to check command success
check_command_success() {
    if [ $? -ne 0 ]; then
        echo "Loi: $1 khong thuc thi thanh cong."
        exit 1
    fi
}

# Function to create DNS forward zone file
create_dns_forward_zone() {
    local domain=$1
    local ip_address=$2
    
    backup_file /var/named/forward.$domain
    cat << EOF > /var/named/forward.$domain
\$TTL 86400
@   IN  SOA     server.$domain. root.$domain. (
                $(date +%Y%m%d%H)  ; Serial
                3600        ; Refresh
                1800        ; Retry
                604800      ; Expire
                86400       ; Minimum TTL
)
@       IN  NS      server.$domain.
@       IN  A       $ip_address
server  IN  A       $ip_address
EOF
    
    check_command_success "DNS forward zone da duoc tao"
    log_action "DNS forward zone file da duoc tao cho $domain"
}

# Function to add zone to named.rfc1912.zones
add_zone_to_named_conf() {
    local domain=$1
    
    backup_file /etc/named.rfc1912.zones
    cat << EOF >> /etc/named.rfc1912.zones

zone "$domain" IN {
    type master;
    file "forward.$domain";
    allow-update { none; };
};
EOF
    
    check_command_success "Them zone vao named.rfc1912.zones"
    log_action "Da them zone vao named.rfc1912.zones cho $domain"
}

# Function to list active domains
list_active_domains() {
    echo "Danh sach cac domain dang hoat dong:"
    for conf in /etc/httpd/conf.d/*.conf; do
        if [ -f "$conf" ]; then
            local domain=$(grep ServerName "$conf" | awk '{print $2}')
            if [ -n "$domain" ]; then
                echo "- $domain"
            fi
        fi
    done
}

# Function to backup a file
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "$file.bak.$(date +%F_%T)"
        check_command_success "Tao ban sao luu cho $file"
        echo "Da tao ban sao luu cho $file"
    fi
}

# Function to set up a new hosting with runtime configuration
add_hosting() {
    list_active_domains
    read -p "Nhap domain name: " domain
    read -p "Nhap folder name cho source (mac dinh la domain name): " folder_name
    if host_exists "$domain"; then
        echo "Domain da ton tai trong cau hinh."
        return
    fi
    folder_name=${folder_name:-$domain}

    echo "Cau hinh web runtime cho website:"
    echo "1. Tomcat"
    echo "2. PHP"
    echo "3. Node.js"
    echo "4. Web tinh"
    read -p "Chon mot tuy chon: " runtime_choice

    mkdir -p /var/www/html/$folder_name
    check_command_success "Dang tao thu muc website"
    chown -R apache:apache /var/www/html/$folder_name
    chmod 755 /var/www /var/www/html
    
    backup_file /etc/httpd/conf.d/$domain.conf
    case $runtime_choice in
        1)
            # Tomcat configuration
            cat << EOF > /etc/httpd/conf.d/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    DocumentRoot /var/www/html/$folder_name
    ServerName $domain
    ServerAlias $domain
    ProxyPass / ajp://localhost:8009/
    ProxyPassReverse / ajp://localhost:8009/
</VirtualHost>
EOF
            ensure_installed tomcat
            systemctl start tomcat
            systemctl enable tomcat
            log_action "Da cau hinh runtime Tomcat cho $domain."
            ;;
        2)
            # PHP configuration
            cat << EOF > /etc/httpd/conf.d/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    DocumentRoot /var/www/html/$folder_name
    ServerName $domain
    ServerAlias $domain
</VirtualHost>
EOF
            ensure_installed php
            ensure_installed php-mysql
            restart_service httpd
            log_action "Da cau hinh runtime PHP cho $domain."
            ;;
        3)
            # Node.js configuration
            cat << EOF > /etc/httpd/conf.d/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    ServerName $domain
    ServerAlias $domain
    ProxyRequests off
    <Proxy *>
        Require all granted
    </Proxy>
    ProxyPass / http://localhost:3000/
    ProxyPassReverse / http://localhost:3000/
</VirtualHost>
EOF
            ensure_installed nodejs
            log_action "Da cau hinh runtime Node.js cho $domain."
            ;;
        4)
            cat << EOF > /etc/httpd/conf.d/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    DocumentRoot /var/www/html/$folder_name
    ServerName $domain
    ServerAlias $domain
</VirtualHost>
EOF
            log_action "Da cau hinh web tinh cho $domain."
            ;;
        *)
            echo "Tuy chon khong hop le"
            return
            ;;
    esac
    
    if [ ! -f /var/www/html/$folder_name/index.html ]; then
        echo "<html><body><h1>Welcome to $domain</h1></body></html>" > /var/www/html/$folder_name/index.html
        chmod +x /var/www/html/$folder_name/index.html
        log_action "Da tao file index.html cho web tinh $domain."
    fi
    
    restart_service httpd
    log_action "Da thiet lap hosting cho $domain trong thu muc /var/www/html/$folder_name"
}

# Function to add a new domain and DNS zone
add_domain_and_zone() {
    read -p "Nhap domain name: " domain
    read -p "Nhap IP address cho server: " ip_address
    if zone_exists "$domain"; then
        echo "Domain da ton tai trong cau hinh."
        return
    fi
    # Create DNS forward zone
    create_dns_forward_zone "$domain" "$ip_address"

    # Add zone to named.rfc1912.zones
    add_zone_to_named_conf "$domain"

    # Restart named service
    restart_service named

    log_action "Da them domain $domain voi vung DNS."
}

# Function to install web runtime (Tomcat, PHP, Node.js)
install_web_runtime() {
    echo "Chon web runtime de cai dat:"
    echo "1. Tomcat"
    echo "2. PHP"
    echo "3. Node.js"
    echo "4. Huy"
    read -p "Nhap lua chon: " runtime_choice
    case $runtime_choice in
        1)
            ensure_installed tomcat
            systemctl start tomcat
            systemctl enable tomcat
            log_action "Da cai dat va khoi dong Tomcat."
            ;;
        2)
            ensure_installed php
            ensure_installed php-mysql
            restart_service httpd
            log_action "Da cai dat PHP va khoi dong lai Apache."
            ;;
        3)
            ensure_installed nodejs
            log_action "Da cai dat Node.js."
            ;;
        4)
            echo "Huy bo qua trinh cai dat Web runtime."
            return
            ;;
        *)
            echo "Lua chon khong hop le"
            ;;
    esac
}

# Function to install DBMS (MySQL, PostgreSQL, SQLite)
install_dbms() {
    echo "Chon DBMS de cai dat:"
    echo "1. MySQL"
    echo "2. PostgreSQL"
    echo "3. MongoDB"
    echo "4. Huy"
    read -p "Nhap lua chon: " dbms_choice
    case $dbms_choice in
        1)
            ensure_installed mariadb-server
            systemctl start mariadb
            systemctl enable mariadb
            log_action "Da cai dat va khoi dong MySQL."
            ;;
        2)
            ensure_installed postgresql-server
            postgresql-setup initdb
            systemctl start postgresql
            systemctl enable postgresql
            log_action "Da cai dat va khoi dong PostgreSQL."
            ;;
        3)
            ensure_installed mongodb-org
            systemctl start mongod
            systemctl enable mongod
            log_action "Da cai dat va khoi dong MongoDB."
            ;;
        4)
            echo "Huy bo qua trinh cai dat DBMS."
            return
            ;;
        *)
            echo "Lua chon khong hop le"
            ;;
    esac
}

# Restart a service
restart_service() {
    local service=$1
    echo "Dang khoi dong lai dich vu $service..."
    if systemctl restart "$service"; then
        echo "$service da khoi dong thanh cong."
    else
        echo "Loi khi khoi dong lai dich vu $service."
    fi
}

# Function to remove a web server
remove_web_server() {
    list_active_domains
    echo ""
    read -p "Nhap domain duoc xoa: " domain
    local config_file="/etc/httpd/conf.d/$domain.conf"
    local document_root=$(grep DocumentRoot "$config_file" 2>/dev/null | awk '{print $2}')

    if [ -f "$config_file" ]; then
        echo "Dang go bo may chu web cua $domain"
        
        # Backup before removal
        backup_file "$config_file"
        
        # Remove Apache configuration
        rm -f "$config_file"
        
        # Remove DNS zone files
        backup_file "/var/named/forward.$domain"
        rm -f "/var/named/forward.$domain"
        
        # Remove zone from named.rfc1912.zones
        backup_file /etc/named.rfc1912.zones
        sed -i "/zone \"$domain\" IN {/,/^\}/d" /etc/named.rfc1912.zones
        
        # Remove document root if it exists and is not empty
        if [ -d "$document_root" ] && [ "$(ls -A "$document_root")" ]; then
            if ask_yes_no "Ban co muon xoa document root tai $document_root?"; then
                rm -rf "$document_root"
                echo "Da xoa thu muc document root."
            else
                echo "Thu muc document root duoc giu lai."
            fi
        fi
        
        # Restart services
        restart_service httpd
        restart_service named
        
        log_action "Da go bo may chu web cho $domain."
    else
        echo "Khong tim thay cau hinh cho $domain."
    fi
}

# Main menu
while true; do
    echo "==============================="
    echo "Quan ly Apache Web Server va DNS"
    echo "1. Dam bao cac dependency da duoc cai dat"
    echo "2. Them domain moi va vung DNS"
    echo "3. Liet ke cac domain dang hoat dong"
    echo "4. Them hosting cho domain"
    echo "5. Cai dat Web Runtime (Tomcat, PHP, Node.js)"
    echo "6. Cai dat DBMS (MySQL, PostgreSQL, SQLite)"
    echo "7. Go bo may chu web"
    echo "8. Thoat"
    read -p "Nhap lua chon: " choice

    clear
    case $choice in
        1)
            ensure_dependencies
            ;;
        2)
            add_domain_and_zone
            ;;
        3)
            list_active_domains
            ;;
        4)
            add_hosting
            ;;
        5)
            install_web_runtime
            ;;
        6)
            install_dbms
            ;;
        7)
            remove_web_server
            ;;
        8)
            echo "Dang thoat..."
            exit 0
            ;;
        *)
            echo "Lua chon khong hop le"
            ;;
    esac
done