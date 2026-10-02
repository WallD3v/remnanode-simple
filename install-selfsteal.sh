#!/usr/bin/env bash

set -e

REMNANODE_DIR="/opt/remnanode"
TEMPLATES_DIR="$REMNANODE_DIR/templates"

INDEX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/index.html"
NGINX_URL="https://raw.githubusercontent.com/WallD3v/remnanode-simple/refs/heads/main/templates/default"

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

    apt install -y \
        curl \
        wget \
        nginx \
        nano

    if ! command -v docker >/dev/null 2>&1; then
        info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
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
        error "docker-compose.yml is empty."
    fi

    info "Checking docker-compose.yml..."

    cd "$REMNANODE_DIR"

    if ! docker compose config >/dev/null; then
        error "docker-compose.yml contains errors."
    fi

    info "Starting RemnaNode..."

    docker compose up -d

    info "RemnaNode installed successfully."
}

install_template() {
    echo
    title "======================================"
    title "        Installing Template"
    title "======================================"
    echo

    while true; do
        read -r -p "Enter node domain (example: nl.wumvpn.cc): " DOMAIN

        DOMAIN=$(echo "$DOMAIN" | tr -d '[:space:]')

        if [[ "$DOMAIN" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]; then
            break
        fi

        warn "Invalid domain."
    done

    info "Using domain: $DOMAIN"

    mkdir -p "$TEMPLATES_DIR"

    info "Downloading index.html..."

    wget -q \
        -O "$TEMPLATES_DIR/index.html" \
        "$INDEX_URL"

    info "Downloading nginx config..."

    wget -q \
        -O "$NGINX_CONFIG" \
        "$NGINX_URL"

    info "Replacing nl.wumvpn.cc with $DOMAIN..."

    sed -i "s/nl\.wumvpn\.cc/$DOMAIN/g" "$NGINX_CONFIG"

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

    systemctl restart nginx

    info "Template installed successfully for:"
    echo
    echo "    https://$DOMAIN"
    echo
}

reinstall_node() {
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
    warn "Reinstalling template..."

    rm -rf "$TEMPLATES_DIR"
    rm -f "$NGINX_CONFIG"

    install_template
}

show_menu() {
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
            info "Restarting RemnaNode..."

            cd "$REMNANODE_DIR"

            docker compose down
            docker compose up -d

            info "RemnaNode restarted."
            ;;

        5)
            info "Restarting nginx..."

            nginx -t
            systemctl restart nginx

            info "Nginx restarted."
            ;;

        6)
            cd "$REMNANODE_DIR"

            docker compose logs -f -t
            ;;

        7)
            info "Bye!"
            exit 0
            ;;

        *)
            warn "Invalid option."
            show_menu
            ;;

    esac
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

    if [ -d "$REMNANODE_DIR" ]; then
        NODE_INSTALLED=true
        info "RemnaNode installation detected."
    else
        warn "RemnaNode is not installed."
    fi

    if [ -d "$TEMPLATES_DIR" ]; then
        TEMPLATE_INSTALLED=true
        info "Template installation detected."
    else
        warn "Template is not installed."
    fi

    echo

    # Nothing installed
    if [ "$NODE_INSTALLED" = false ] && [ "$TEMPLATE_INSTALLED" = false ]; then

        install_node
        install_template

    # Node missing
    elif [ "$NODE_INSTALLED" = false ]; then

        install_node

    # Template missing
    elif [ "$TEMPLATE_INSTALLED" = false ]; then

        install_template

    # Everything installed
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
