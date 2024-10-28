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
        if ! yum install "$package" -y; then
            echo "Loi: Khong the cai dat goi $package. Vui long kiem tra lai."
            return
        fi
    fi
}

# Ensure essential dependencies are installed
ensure_dependencies() {
    for package in httpd bind bind-utils epel-release; do
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

regex_zone() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ ! "$domain" =~ \. ]] || [[ "$domain" =~ \.$ ]]; then
        echo "Ten mien khong hop le. Vui long nhap lai."
        return 1
    fi
    return 0
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
    if ! regex_zone "$domain"; then
        return
    fi
    folder_name=${folder_name:-$domain}

    mkdir -p /var/www/html/$folder_name
    check_command_success "Dang tao thu muc website"
    chown -R apache:apache /var/www/html/$folder_name
    chmod 755 /var/www /var/www/html
    
    backup_file /etc/httpd/conf.d/$domain.conf


            cat << EOF > /etc/httpd/conf.d/$domain.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$domain
    DocumentRoot /var/www/html/$folder_name
    ServerName $domain
    ServerAlias $domain
</VirtualHost>
EOF
            log_action "Da cau hinh web tinh cho $domain."
    
    if [ ! -f /var/www/html/$folder_name/index.html ]; then
        echo "<html><body><h1>Welcome to $domain</h1></body></html>" > /var/www/html/$folder_name/index.html
        chmod +x /var/www/html/$folder_name/index.html
        log_action "Da tao file index.html cho web tinh $domain."
    fi
    
    restart_service httpd
    log_action "Da thiet lap hosting cho $domain trong thu muc /var/www/html/$folder_name"
}

setup_https() {
    read -p "Enter the domain name to configure HTTPS: " domain
    local conf_file="/etc/httpd/conf.d/$domain.conf"

    if grep -q "443" "$conf_file"; then
        echo "HTTPS is already configured for $domain."
    else
        yum install mod_ssl openssl -y
        
        # Generate SSL certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/tls/private/$domain.key -out /etc/pki/tls/certs/$domain.crt
        
        # Configure Virtual Host for HTTPS
        cat << EOF >> "$conf_file"
<VirtualHost *:443>
    ServerAdmin webmaster@$domain
    DocumentRoot /var/www/html/$domain
    ServerName $domain
    ServerAlias $domain
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/$domain.crt
    SSLCertificateKeyFile /etc/pki/tls/private/$domain.key
</VirtualHost>
EOF

        # Restart Apache service
        systemctl restart httpd
        echo "HTTPS setup completed for $domain."
    fi
}

# Function to add a new domain and DNS zone
add_domain_and_zone() {
    read -p "Nhap domain name: " domain
    read -p "Nhap IP address cho server: " ip_address
    if zone_exists "$domain"; then
        echo "Domain da ton tai trong cau hinh."
        return
    fi
    if ! regex_zone "$domain"; then
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
    echo "Quan ly Web Server va DNS"
    echo "1. Dam bao cac dependency da duoc cai dat"
    echo "2. Them domain moi va vung DNS"
    echo "3. Them hosting cho domain"
    echo "4. Liet ke cac domain dang hoat dong"
    echo "5. Go bo may chu web"
    echo "6. Tat tuong lua"
    echo "7. Them HTTPS Local"
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
            add_hosting
            ;;
        4)
            list_active_domains
            ;;
        5)
            remove_web_server
            ;;
        6)
            echo "Tat tuong lua..."
            systemctl stop firewalld
            systemctl disable firewalld
            echo "Firewall da duoc tat."
            ;;   
        7)
            setup_https
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