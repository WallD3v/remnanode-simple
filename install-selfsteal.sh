#!/usr/bin/env bash

set -e

REMNANODE_DIR="/opt/remnanode"
TEMPLATES_DIR="$REMNANODE_DIR/templates"

INDEX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/index.html?token=GHSAT0AAAAAAELADFACT73GSZKQPW2OAA5K2V7TQVA"
NGINX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/default?token=GHSAT0AAAAAAELADFACHXX2S5H2ODUODHEG2V7TRFQ"

NGINX_CONFIG="/etc/nginx/sites-available/default"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

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

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Run this script as root: sudo bash install-selfsteal.sh"
    fi
}

install_dependencies() {
    info "Checking dependencies..."

    apt update -y
    apt install -y curl wget nginx nano

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

download_file() {
    local url="$1"
    local destination="$2"
    local name="$3"

    rm -f "$destination"

    info "Downloading $name..."

    if ! wget -O "$destination" "$url"; then
        rm -f "$destination"
        error "Failed to download $name from: $url"
    fi

    if [ ! -s "$destination" ]; then
        rm -f "$destination"
        error "$name was downloaded, but file is empty."
    fi
}

install_template() {
    echo
    title "======================================"
    title "        Installing Template"
    title "======================================"
    echo

    ask_domain

    mkdir -p "$TEMPLATES_DIR"

    download_file \
        "$INDEX_URL" \
        "$TEMPLATES_DIR/index.html" \
        "index.html"

    download_file \
        "$NGINX_URL" \
        "$NGINX_CONFIG" \
        "nginx config"

    info "Replacing nl.wumvpn.cc with $DOMAIN..."

    sed -i "s/nl\.wumvpn\.cc/$DOMAIN/g" "$NGINX_CONFIG"

    if ! grep -q "$DOMAIN" "$NGINX_CONFIG"; then
        error "Domain replacement failed."
    fi

    if [ ! -e /etc/nginx/sites-enabled/default ]; then
        info "Enabling nginx config..."

        ln -s \
            /etc/nginx/sites-available/default \
            /etc/nginx/sites-enabled/default
    fi

    info "Checking nginx config..."

    if ! nginx -t; then
        error "Nginx configuration contains errors."
    fi

    info "Restarting nginx..."

    if ! systemctl restart nginx; then
        error "Failed to restart nginx."
    fi

    info "Template installed successfully."
    echo
    echo "Domain: https://$DOMAIN"
}

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

reinstall_template() {
    echo
    warn "Reinstalling template..."

    rm -rf "$TEMPLATES_DIR"
    rm -f "$NGINX_CONFIG"

    install_template
}

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

restart_nginx() {
    info "Checking nginx config..."

    nginx -t || error "Nginx config contains errors."

    info "Restarting nginx..."

    systemctl restart nginx

    info "Nginx restarted."
}

show_logs() {
    if [ ! -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        error "docker-compose.yml not found."
    fi

    cd "$REMNANODE_DIR"

    docker compose logs -f -t
}

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

    if [ -f "$REMNANODE_DIR/docker-compose.yml" ]; then
        NODE_INSTALLED=true
        info "RemnaNode installation detected."
    else
        warn "RemnaNode is not installed."
    fi

    if [ -f "$TEMPLATES_DIR/index.html" ] && [ -f "$NGINX_CONFIG" ]; then
        TEMPLATE_INSTALLED=true
        info "Template installation detected."
    else
        warn "Template is not installed."
    fi

    echo

    if [ "$NODE_INSTALLED" = false ] && [ "$TEMPLATE_INSTALLED" = false ]; then
        install_node
        install_template

    elif [ "$NODE_INSTALLED" = false ]; then
        install_node

    elif [ "$TEMPLATE_INSTALLED" = false ]; then
        install_template

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
