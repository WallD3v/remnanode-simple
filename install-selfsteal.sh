#!/usr/bin/env bash

set -e

# ============================================
# Configuration
# ============================================

REMNANODE_DIR="/opt/remnanode"
TEMPLATES_DIR="$REMNANODE_DIR/templates"

INDEX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/index.html"
NGINX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/default"

NGINX_CONFIG="/etc/nginx/sites-available/default"
NGINX_ENABLED="/etc/nginx/sites-enabled/default"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"


# ============================================
# UI
# ============================================

info() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[-]${NC} $1"
    exit 1
}

title() {
    echo -e "${BLUE}$1${NC}"
}

pause() {
    echo
    read -r -p "Press ENTER to continue..."
}


# ============================================
# Basic checks
# ============================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Run this script as root: sudo bash install-selfsteal.sh"
    fi
}


# ============================================
# Dependencies
# ============================================

install_dependencies() {
    info "Checking dependencies..."

    apt update -y

    apt install -y \
        curl \
        wget \
        nginx \
        nano \
        certbot

    if ! command -v docker >/dev/null 2>&1; then

        info "Installing Docker..."

        if ! curl -fsSL https://get.docker.com | sh; then
            error "Failed to install Docker."
        fi

    else
        info "Docker is already installed."
    fi

    systemctl enable --now docker
    systemctl enable nginx
}


# ============================================
# RemnaNode
# ============================================

install_node() {
    echo

    title "======================================"
    title "        Installing RemnaNode"
    title "======================================"

    echo

    mkdir -p "$REMNANODE_DIR"

    warn "docker-compose.yml is required."
    warn "Copy docker-compose.yml from your Remnawave panel."
    warn "Paste it into nano, then press:"
    warn "CTRL+X -> Y -> ENTER"

    pause

    nano "$REMNANODE_DIR/docker-compose.yml"

    if [ ! -s "$REMNANODE_DIR/docker-compose.yml" ]; then
        rm -f "$REMNANODE_DIR/docker-compose.yml"
        error "docker-compose.yml is empty."
    fi

    info "Checking docker-compose.yml..."

    cd "$REMNANODE_DIR"

    if ! docker compose config >/dev/null; then
        error "docker-compose.yml contains errors."
    fi

    info "Starting RemnaNode..."

    if ! docker compose up -d; then
        error "Failed to start RemnaNode."
    fi

    info "RemnaNode installed successfully."
}


# ============================================
# Domain
# ============================================

ask_domain() {
    while true; do

        echo

        read -r -p "Enter node domain (example: nl.wumvpn.cc): " DOMAIN

        DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')

        if [[ "$DOMAIN" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
            break
        fi

        warn "Invalid domain."

    done

    info "Using domain: $DOMAIN"
}


# ============================================
# Let's Encrypt
# ============================================

ensure_certificate() {

    local cert_path="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    local key_path="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

    echo

    info "Checking Let's Encrypt certificate..."

    if [ -f "$cert_path" ] && [ -f "$key_path" ]; then

        info "Certificate already exists for $DOMAIN."
        return

    fi

    warn "Certificate not found for $DOMAIN."

    info "Stopping nginx..."

    systemctl stop nginx || true

    # Check whether port 80 is occupied by something else.
    if ss -ltn | grep -q ':80 '; then
        warn "Port 80 is still in use."
        warn "Another service may be listening on port 80."

        systemctl start nginx >/dev/null 2>&1 || true

        error "Port 80 must be free for Certbot standalone validation."
    fi

    info "Requesting Let's Encrypt certificate for $DOMAIN..."

    if certbot certonly \
        --standalone \
        --preferred-challenges http \
        --http-01-port 80 \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --quiet \
        -d "$DOMAIN"; then

        info "Certificate successfully obtained."

    else

        warn "Certbot failed."

        info "Starting nginx again..."
        systemctl start nginx >/dev/null 2>&1 || true

        error "Failed to obtain Let's Encrypt certificate for $DOMAIN."
    fi

    if [ ! -f "$cert_path" ]; then

        systemctl start nginx >/dev/null 2>&1 || true

        error "Certificate fullchain.pem was not created."
    fi

    if [ ! -f "$key_path" ]; then

        systemctl start nginx >/dev/null 2>&1 || true

        error "Certificate privkey.pem was not created."
    fi

    info "Starting nginx..."

    # At this stage nginx may still have an old/broken configuration.
    # Don't abort here because a new config will be installed below.
    systemctl start nginx >/dev/null 2>&1 || true

    echo
    info "Let's Encrypt certificate is ready:"
    echo "    $cert_path"
}


# ============================================
# Downloads
# ============================================

download_file() {

    local url="$1"
    local destination="$2"
    local name="$3"

    rm -f "$destination"

    info "Downloading $name..."

    if ! wget \
        --timeout=30 \
        --tries=3 \
        -O "$destination" \
        "$url"; then

        rm -f "$destination"

        error "Failed to download $name."
    fi

    if [ ! -s "$destination" ]; then

        rm -f "$destination"

        error "$name was downloaded, but file is empty."
    fi

    info "$name downloaded successfully."
}


# ============================================
# Template
# ============================================

install_template() {

    echo

    title "======================================"
    title "        Installing Template"
    title "======================================"

    echo

    ask_domain

    # ========================================
    # SSL certificate
    # ========================================

    ensure_certificate

    # ========================================
    # Templates
    # ========================================

    mkdir -p "$TEMPLATES_DIR"

    download_file \
        "$INDEX_URL" \
        "$TEMPLATES_DIR/index.html" \
        "index.html"

    # ========================================
    # nginx
    # ========================================

    download_file \
        "$NGINX_URL" \
        "$NGINX_CONFIG" \
        "nginx config"

    info "Replacing nl.wumvpn.cc with $DOMAIN..."

    sed -i \
        "s/nl\.wumvpn\.cc/$DOMAIN/g" \
        "$NGINX_CONFIG"

    if ! grep -qF "$DOMAIN" "$NGINX_CONFIG"; then
        error "Domain replacement failed."
    fi

    # ========================================
    # Enable nginx site
    # ========================================

    if [ ! -e "$NGINX_ENABLED" ]; then

        info "Enabling nginx config..."

        ln -s \
            "$NGINX_CONFIG" \
            "$NGINX_ENABLED"
    fi

    # ========================================
    # nginx test
    # ========================================

    info "Checking nginx config..."

    if ! nginx -t; then
        error "Nginx configuration contains errors."
    fi

    # ========================================
    # nginx start
    # ========================================

    info "Restarting nginx..."

    if ! systemctl restart nginx; then
        error "Failed to restart nginx."
    fi

    info "Template installed successfully."

    echo
    echo "Domain: https://$DOMAIN"
    echo
}


# ============================================
# Reinstall node
# ============================================

reinstall_node() {

    echo

    warn "Reinstalling RemnaNode..."

    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then

        cd "$REMNANODE_DIR"

        info "Stopping current containers..."

        docker compose down || true
    fi

    rm -f "$REMNANODE_DIR/docker-compose.yml"

    install_node
}


# ============================================
# Reinstall template
# ============================================

reinstall_template() {

    echo

    warn "Reinstalling template..."

    rm -rf "$TEMPLATES_DIR"
    rm -f "$NGINX_CONFIG"

    install_template
}


# ============================================
# Restart node
# ============================================

restart_node() {

    if [ ! -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        error "docker-compose.yml not found."
    fi

    cd "$REMNANODE_DIR"

    info "Restarting RemnaNode..."

    docker compose down
    docker compose up -d

    info "RemnaNode restarted."
}


# ============================================
# Restart nginx
# ============================================

restart_nginx() {

    info "Checking nginx config..."

    nginx -t || error "Nginx config contains errors."

    info "Restarting nginx..."

    systemctl restart nginx

    info "Nginx restarted."
}


# ============================================
# Logs
# ============================================

show_logs() {

    if [ ! -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        error "docker-compose.yml not found."
    fi

    cd "$REMNANODE_DIR"

    docker compose logs -f -t
}


# ============================================
# Menu
# ============================================

show_menu() {

    while true; do

        echo

        title "======================================"
        title "       RemnaNode already installed"
        title "======================================"

        echo
        echo "1) Reinstall RemnaNode"
        echo "2) Reinstall template"
        echo "3) Reinstall everything"
        echo "4) Restart RemnaNode"
        echo "5) Restart nginx"
        echo "6) Show RemnaNode logs"
        echo "7) Exit"
        echo

        read -r -p "Select option: " CHOICE

        case "$CHOICE" in

            1)
                reinstall_node
                ;;

            2)
                reinstall_template
                ;;

            3)
                reinstall_node
                reinstall_template
                ;;

            4)
                restart_node
                ;;

            5)
                restart_nginx
                ;;

            6)
                show_logs
                ;;

            7)
                info "Bye!"
                exit 0
                ;;

            *)
                warn "Invalid option."
                ;;

        esac

    done
}


# ============================================
# Main
# ============================================

main() {

    clear

    echo

    title "======================================"
    title "        RemnaNode Installer"
    title "======================================"

    echo

    check_root

    install_dependencies

    NODE_INSTALLED=false
    TEMPLATE_INSTALLED=false

    echo

    # ========================================
    # Check RemnaNode
    # ========================================

    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then

        NODE_INSTALLED=true

        info "RemnaNode installation detected."

    else

        warn "RemnaNode is not installed."

    fi

    # ========================================
    # Check template
    # ========================================

    if [ -f "$TEMPLATES_DIR/index.html" ] && \
       [ -f "$NGINX_CONFIG" ]; then

        TEMPLATE_INSTALLED=true

        info "Template installation detected."

    else

        warn "Template is not installed."

    fi

    echo

    # ========================================
    # Nothing installed
    # ========================================

    if [ "$NODE_INSTALLED" = false ] && \
       [ "$TEMPLATE_INSTALLED" = false ]; then

        install_node
        install_template

    # ========================================
    # Only template exists
    # ========================================

    elif [ "$NODE_INSTALLED" = false ]; then

        install_node

    # ========================================
    # Only node exists
    # ========================================

    elif [ "$TEMPLATE_INSTALLED" = false ]; then

        install_template

    # ========================================
    # Everything exists
    # ========================================

    else

        show_menu

    fi

    echo

    title "======================================"
    info "Everything is ready."
    title "======================================"

    echo

    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then

        cd "$REMNANODE_DIR"

        info "Current containers:"

        docker compose ps

    fi
}


main
