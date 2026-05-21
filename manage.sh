#!/bin/bash

# OpenMRS 3.0 Reference Application Management Script
# This script provides convenient commands for managing the OpenMRS application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Function to check if docker-compose is available
check_docker_compose() {
    if ! command -v docker compose > /dev/null 2>&1 && ! command -v docker-compose > /dev/null 2>&1; then
        print_error "docker-compose is not installed or not in PATH"
        exit 1
    fi
}

# Function to get the correct docker-compose command
get_docker_compose_cmd() {
    if command -v docker compose > /dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# Function to create .env file for SSL
create_ssl_env() {
    local mode=$1
    local domains=$2
    local email=$3
    
    print_status "Creating SSL configuration..."
    
    cat > .env << EOF
COMPOSE_FILE=docker-compose.yml:docker-compose.ssl.yml
SSL_MODE=$mode
EOF

    if [ "$mode" = "prod" ]; then
        echo "CERT_WEB_DOMAINS=$domains" >> .env
        echo "CERT_CONTACT_EMAIL=$email" >> .env
        
        if [ -n "$SSL_STAGING" ]; then
            echo "SSL_STAGING=$SSL_STAGING" >> .env
        fi
        
        if [ -n "$CERT_PROFILE" ]; then
            echo "CERT_PROFILE=$CERT_PROFILE" >> .env
        fi
    fi
    
    print_status "SSL configuration created in .env file"
}

# Function to start the application
start_app() {
    print_header "Starting OpenMRS Application"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Starting containers..."
    $compose_cmd up -d
    
    print_status "Application is starting..."
    print_status "OpenMRS 3.x UI: http://localhost/openmrs/spa"
    print_status "OpenMRS Legacy UI: http://localhost/openmrs"
    
    if [ -f ".env" ] && grep -q "SSL_MODE=prod" .env; then
        print_status "SSL/HTTPS is enabled in production mode"
    elif [ -f ".env" ] && grep -q "docker-compose.ssl.yml" .env; then
        print_status "SSL/HTTPS is enabled in development mode"
        print_status "Access via HTTPS: https://localhost/openmrs/spa"
    fi
}

# Function to stop the application
stop_app() {
    print_header "Stopping OpenMRS Application"
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Stopping containers..."
    $compose_cmd down
    
    print_status "Application stopped"
}

# Function to restart the application
restart_app() {
    print_header "Restarting OpenMRS Application"
    stop_app
    sleep 2
    start_app
}

# Function to view logs
view_logs() {
    local service=$1
    local compose_cmd=$(get_docker_compose_cmd)
    
    if [ -n "$service" ]; then
        print_status "Showing logs for service: $service"
        $compose_cmd logs -f "$service"
    else
        print_status "Showing logs for all services"
        $compose_cmd logs -f
    fi
}

# Function to setup SSL development mode
setup_ssl_dev() {
    print_header "Setting up SSL Development Mode"
    create_ssl_env "dev" "" ""
    start_app
}

# Function to setup SSL production mode
setup_ssl_prod() {
    print_header "Setting up SSL Production Mode"
    
    if [ -z "$CERT_WEB_DOMAINS" ]; then
        print_error "CERT_WEB_DOMAINS environment variable is required"
        print_error "Usage: CERT_WEB_DOMAINS=example.com CERT_CONTACT_EMAIL=admin@example.com $0 ssl-prod"
        exit 1
    fi
    
    if [ -z "$CERT_CONTACT_EMAIL" ]; then
        print_error "CERT_CONTACT_EMAIL environment variable is required"
        print_error "Usage: CERT_WEB_DOMAINS=example.com CERT_CONTACT_EMAIL=admin@example.com $0 ssl-prod"
        exit 1
    fi
    
    create_ssl_env "prod" "$CERT_WEB_DOMAINS" "$CERT_CONTACT_EMAIL"
    start_app
}

# Function to force certificate renewal
renew_certificates() {
    print_header "Forcing Certificate Renewal"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Forcing certificate renewal..."
    $compose_cmd exec certbot certbot renew --force-renewal --webroot -w /var/www/certbot
    
    print_status "Reloading nginx..."
    $compose_cmd exec gateway nginx -s reload
    
    print_status "Certificate renewal completed"
}

# Function to check certificate status
check_certificates() {
    print_header "Checking Certificate Status"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    if $compose_cmd ps certbot | grep -q "Up"; then
        print_status "Checking certificates (certbot container is running)..."
        $compose_cmd exec certbot certbot certificates
    else
        print_status "Checking certificates (certbot container is stopped)..."
        $compose_cmd run --rm --entrypoint certbot certbot certificates
    fi
}

# Function to regenerate certificates
regenerate_certificates() {
    print_header "Regenerating Certificates"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_warning "This will remove all existing certificates and create new ones"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping application..."
        $compose_cmd down
        
        print_status "Removing letsencrypt volume..."
        local volume_name="$($compose_cmd config | awk '/^name:/{print $2}')_letsencrypt-data"
        docker volume rm "$volume_name" 2>/dev/null || print_warning "Volume $volume_name not found or already removed"
        
        print_status "Starting application with new certificates..."
        $compose_cmd up -d
        
        print_status "Certificate regeneration completed"
    else
        print_status "Operation cancelled"
    fi
}

# Function to start with Grafana
start_with_grafana() {
    print_header "Starting OpenMRS with Grafana"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Starting containers with Grafana..."
    $compose_cmd -f docker-compose.yml -f docker-compose.grafana.yml up -d
    
    print_status "Application is starting with Grafana..."
    print_status "OpenMRS 3.x UI: http://localhost/openmrs/spa"
    print_status "OpenMRS Legacy UI: http://localhost/openmrs"
    print_status "Grafana: http://localhost/grafana"
    print_status "Grafana username: admin"
    print_status "Check docker-compose.grafana.yml for the initial password"
}

# Function to show application status
show_status() {
    print_header "OpenMRS Application Status"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Container status:"
    $compose_cmd ps
    
    echo
    print_status "Application URLs:"
    print_status "OpenMRS 3.x UI: http://localhost/openmrs/spa"
    print_status "OpenMRS Legacy UI: http://localhost/openmrs"
    
    if [ -f ".env" ] && grep -q "docker-compose.ssl.yml" .env; then
        if grep -q "SSL_MODE=prod" .env; then
            print_status "SSL Mode: Production (Let's Encrypt)"
        else
            print_status "SSL Mode: Development (Self-signed)"
            print_status "HTTPS URLs: https://localhost/openmrs/spa"
        fi
    fi
    
    if $compose_cmd ps | grep -q "grafana"; then
        print_status "Grafana: http://localhost/grafana"
    fi
}

# Function to clean up resources
cleanup() {
    print_header "Cleaning Up OpenMRS Resources"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_warning "This will stop and remove all containers, networks, and volumes"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping and removing containers..."
        $compose_cmd down -v --remove-orphans
        
        print_status "Removing unused Docker resources..."
        docker system prune -f
        
        print_status "Cleanup completed"
    else
        print_status "Operation cancelled"
    fi
}

# Function to show interactive menu
show_interactive_menu() {
    while true; do
        clear
        print_header "OpenMRS 3.0 Management Console"
        echo
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                    APPLICATION MANAGEMENT                    │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│  1) Start Application        2) Stop Application             │"
        echo "│  3) Restart Application      4) Show Status                  │"
        echo "│  5) View Logs                6) Live Logs                    │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                    CONTAINER MANAGEMENT                     │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│  7) Stop Container           8) Restart Container           │"
        echo "│  9) Delete Container        10) Delete Image                │"
        echo "│ 11) Prune Docker System                                          │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                    SSL/HTTPS MANAGEMENT                      │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 12) SSL Development Mode      13) SSL Production Mode       │"
        echo "│ 14) Renew Certificates        15) Check Certificates          │"
        echo "│ 16) Regenerate Certificates                                       │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                      BUILD & DEPLOY                          │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 17) Build Custom Image        18) Build Without Cache       │"
        echo "│ 19) Build with Distro Config 20) Push to Docker Hub          │"
        echo "│ 21) Rebuild Frontend Config 22) Copy Frontend Assets         │"
        echo "│ 23) Build in Background      24) Build Status                │"
        echo "│ 25) Build Log                26) Cancel Background Build     │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│                      UTILITIES                               │"
        echo "├─────────────────────────────────────────────────────────────┤"
        echo "│ 27) Start with Grafana         28) Full Cleanup               │"
        echo "│ 29) Show Help                  30) Exit                        │"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo
        echo -n "Enter option number [1-30]: "
        read -r choice
        
        # Clear any extra whitespace and validate input
        choice=$(echo "$choice" | tr -d ' ')
        
        case $choice in
            1) start_app; pause ;;
            2) stop_app; pause ;;
            3) restart_app; pause ;;
            4) show_status; pause ;;
            5) select_logs; pause ;;
            6) select_live_logs; pause ;;
            7) stop_container; pause ;;
            8) restart_container; pause ;;
            9) delete_container; pause ;;
            10) delete_image; pause ;;
            11) prune_docker; pause ;;
            12) setup_ssl_dev; pause ;;
            13) setup_ssl_prod_interactive; pause ;;
            14) renew_certificates; pause ;;
            15) check_certificates; pause ;;
            16) regenerate_certificates; pause ;;
            17) build_custom_image; pause ;;
            18) build_without_cache; pause ;;
            19) build_with_distro_config; pause ;;
            20) push_to_docker_hub; pause ;;
            21) rebuild_frontend_config; pause ;;
            22) copy_frontend_assets; pause ;;
            23) build_background; pause ;;
            24) build_status; pause ;;
            25) build_log; pause ;;
            26) build_cancel; pause ;;
            27) start_with_grafana; pause ;;
            28) cleanup; pause ;;
            29) show_help; pause ;;
            30) print_status "Goodbye!"; exit 0 ;;
            *) print_error "Invalid option '$choice'. Please enter a number between 1-30."; pause ;;
        esac
    done
}

# Function to pause for user input
pause() {
    echo
    echo -n "Press Enter to continue..."
    read -r
}

# Function to select logs service
select_logs() {
    print_header "Select Service for Logs"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      AVAILABLE SERVICES                       │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) backend                   2) frontend                     │"
    echo "│  3) gateway                   4) db                           │"
    echo "│  5) certbot                   6) grafana                       │"
    echo "│  7) All services                                                   │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter service number [1-7]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    case $choice in
        1) view_logs "backend" ;;
        2) view_logs "frontend" ;;
        3) view_logs "gateway" ;;
        4) view_logs "db" ;;
        5) view_logs "certbot" ;;
        6) view_logs "grafana" ;;
        7) view_logs "" ;;
        *) print_error "Invalid option '$choice'. Please enter a number between 1-7." ;;
    esac
}

# Function to select live logs
select_live_logs() {
    print_header "Select Service for Live Logs"
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      AVAILABLE SERVICES                       │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) backend                   2) frontend                     │"
    echo "│  3) gateway                   4) db                           │"
    echo "│  5) certbot                   6) grafana                       │"
    echo "│  7) All services                                                   │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter service number [1-7]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    case $choice in
        1) live_logs "backend" ;;
        2) live_logs "frontend" ;;
        3) live_logs "gateway" ;;
        4) live_logs "db" ;;
        5) live_logs "certbot" ;;
        6) live_logs "grafana" ;;
        7) live_logs "" ;;
        *) print_error "Invalid option '$choice'. Please enter a number between 1-7." ;;
    esac
}

# Function to show live logs
live_logs() {
    local service=$1
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Showing live logs for ${service:-'all services'} (Ctrl+C to exit)..."
    if [ -n "$service" ]; then
        $compose_cmd logs -f "$service"
    else
        $compose_cmd logs -f
    fi
}

# Function to stop specific container
stop_container() {
    print_header "Stop Specific Container"
    check_docker
    
    echo "Running containers (excluding Portainer):"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v "portainer\|Portainer" || echo "No non-Portainer containers running"
    echo
    read -p "Enter container name to stop: " container_name
    
    if [ -n "$container_name" ]; then
        # Check if it's a Portainer container
        if [[ "$container_name" == *"portainer"* ]] || [[ "$container_name" == *"Portainer"* ]]; then
            print_error "Cannot stop Portainer containers for safety reasons"
            return
        fi
        
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            print_status "Stopping container: $container_name"
            docker stop "$container_name"
            print_status "Container stopped"
        else
            print_error "Container '$container_name' not found or not running"
        fi
    else
        print_error "No container name provided"
    fi
}

# Function to restart specific container
restart_container() {
    print_header "Restart Specific Container"
    check_docker
    
    echo "All containers (running and stopped, excluding Portainer):"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v "portainer\|Portainer" || echo "No non-Portainer containers found"
    echo
    read -p "Enter container name to restart: " container_name
    
    if [ -n "$container_name" ]; then
        # Check if it's a Portainer container
        if [[ "$container_name" == *"portainer"* ]] || [[ "$container_name" == *"Portainer"* ]]; then
            print_error "Cannot restart Portainer containers for safety reasons"
            return
        fi
        
        if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
            print_status "Restarting container: $container_name"
            docker restart "$container_name"
            print_status "Container restarted"
        else
            print_error "Container '$container_name' not found"
        fi
    else
        print_error "No container name provided"
    fi
}

# Function to delete container
delete_container() {
    print_header "Delete Container"
    check_docker
    
    echo "All containers (excluding Portainer):"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -v "portainer\|Portainer" || echo "No non-Portainer containers found"
    echo
    read -p "Enter container name to delete: " container_name
    
    if [ -n "$container_name" ]; then
        # Check if it's a Portainer container
        if [[ "$container_name" == *"portainer"* ]] || [[ "$container_name" == *"Portainer"* ]]; then
            print_error "Cannot delete Portainer containers for safety reasons"
            return
        fi
        
        if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
            print_warning "This will permanently delete container '$container_name'"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Stopping and removing container: $container_name"
                docker stop "$container_name" 2>/dev/null || true
                docker rm "$container_name"
                print_status "Container deleted"
            else
                print_status "Operation cancelled"
            fi
        else
            print_error "Container '$container_name' not found"
        fi
    else
        print_error "No container name provided"
    fi
}

# Function to delete image
delete_image() {
    print_header "Delete Docker Image"
    check_docker
    
    echo "Available images (excluding Portainer):"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep -v "portainer\|Portainer" || echo "No non-Portainer images found"
    echo
    read -p "Enter image name (e.g., openmrs/backend:latest) or image ID: " image_name
    
    if [ -n "$image_name" ]; then
        # Check if it's a Portainer image
        if [[ "$image_name" == *"portainer"* ]] || [[ "$image_name" == *"Portainer"* ]]; then
            print_error "Cannot delete Portainer images for safety reasons"
            return
        fi
        
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$" || docker images --format "{{.ID}}" | grep -q "^${image_name}$"; then
            print_warning "This will permanently delete image '$image_name'"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Deleting image: $image_name"
                docker rmi "$image_name" -f
                print_status "Image deleted"
            else
                print_status "Operation cancelled"
            fi
        else
            print_error "Image '$image_name' not found"
        fi
    else
        print_error "No image name provided"
    fi
}

# Function to prune Docker system
prune_docker() {
    print_header "Prune Docker System"
    check_docker
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      PRUNING OPTIONS                          │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) Prune containers only     2) Prune images only             │"
    echo "│  3) Prune networks only       4) Prune volumes only             │"
    echo "│  5) Prune everything (safe)   6) Full system prune (aggressive) │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo "│  All options exclude Portainer containers and images           │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter option number [1-6]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    case $choice in
        1)
            print_status "Pruning stopped containers (excluding Portainer)..."
            # Stop and remove non-Portainer containers first
            docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker stop 2>/dev/null || true
            docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker rm 2>/dev/null || true
            docker container prune -f
            ;;
        2)
            print_status "Pruning dangling images (excluding Portainer)..."
            # Remove non-Portainer dangling images
            docker images --format "{{.ID}}" | grep -v "portainer\|Portainer" | xargs -r docker rmi -f 2>/dev/null || true
            docker image prune -f
            ;;
        3)
            print_status "Pruning unused networks..."
            docker network prune -f
            ;;
        4)
            print_status "Pruning unused volumes..."
            docker volume prune -f
            ;;
        5)
            print_status "Pruning unused resources (safe, excludes Portainer)..."
            # Stop and remove non-Portainer containers first
            docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker stop 2>/dev/null || true
            docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker rm 2>/dev/null || true
            # Remove non-Portainer images
            docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "portainer\|Portainer" | xargs -r docker rmi -f 2>/dev/null || true
            docker system prune -f
            ;;
        6)
            print_warning "This will remove all unused containers, networks, images (both dangling and unused), and build cache (excluding Portainer)"
            echo -n "Are you sure? (y/N): "
            read -r confirmation
            if [[ $confirmation =~ ^[Yy]$ ]]; then
                print_status "Running full system prune (excluding Portainer)..."
                # Stop and remove non-Portainer containers first
                docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker stop 2>/dev/null || true
                docker ps -a --format "{{.Names}}" | grep -v "portainer\|Portainer" | xargs -r docker rm 2>/dev/null || true
                # Remove non-Portainer images
                docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "portainer\|Portainer" | xargs -r docker rmi -f 2>/dev/null || true
                docker system prune -a -f --volumes
            else
                print_status "Operation cancelled"
            fi
            ;;
        *)
            print_error "Invalid option '$choice'. Please enter a number between 1-6."
            return
            ;;
    esac
    
    print_status "Pruning completed (Portainer containers and images preserved)"
}

# Function to setup SSL production mode interactively
setup_ssl_prod_interactive() {
    print_header "Setup SSL Production Mode"
    
    echo "Please provide the following information:"
    echo
    read -p "Domain name(s) (comma-separated, e.g., example.com,www.example.com): " domains
    read -p "Contact email for Let's Encrypt: " email
    
    if [ -z "$domains" ] || [ -z "$email" ]; then
        print_error "Both domains and email are required"
        return
    fi
    
    echo
    echo "Optional settings (press Enter to skip):"
    read -p "Use staging environment? (y/N): " staging_choice
    read -p "Certificate profile (classic/tlsserver/shortlived): " profile
    
    # Set environment variables
    export CERT_WEB_DOMAINS="$domains"
    export CERT_CONTACT_EMAIL="$email"
    
    if [[ $staging_choice =~ ^[Yy]$ ]]; then
        export SSL_STAGING="true"
    else
        unset SSL_STAGING
    fi
    
    if [ -n "$profile" ]; then
        export CERT_PROFILE="$profile"
    else
        unset CERT_PROFILE
    fi
    
    setup_ssl_prod
}

# Background build directory
BUILD_LOG_DIR=".build"
BUILD_PID_FILE="$BUILD_LOG_DIR/build.pid"
BUILD_LOG_FILE="$BUILD_LOG_DIR/build.log"
BUILD_STATUS_FILE="$BUILD_LOG_DIR/build.status"

# Function to run a build in the background
run_build_in_background() {
    local build_cmd="$1"
    local description="$2"
    
    mkdir -p "$BUILD_LOG_DIR"
    
    # Check if a build is already running
    if [ -f "$BUILD_PID_FILE" ]; then
        local existing_pid=$(cat "$BUILD_PID_FILE")
        if kill -0 "$existing_pid" 2>/dev/null; then
            print_error "A build is already running (PID: $existing_pid)"
            print_status "Use './manage.sh build-status' to check progress or './manage.sh build-cancel' to cancel it"
            return 1
        fi
    fi
    
    # Start the build in background
    print_status "Starting background build: $description"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $description" > "$BUILD_LOG_FILE"
    echo "running" > "$BUILD_STATUS_FILE"
    echo "$description" > "$BUILD_LOG_DIR/build.description"
    
    (
        set +e
        eval "$build_cmd" >> "$BUILD_LOG_FILE" 2>&1
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "success" > "$BUILD_STATUS_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Build completed successfully" >> "$BUILD_LOG_FILE"
        else
            echo "failed" > "$BUILD_STATUS_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Build FAILED (exit code: $exit_code)" >> "$BUILD_LOG_FILE"
        fi
        rm -f "$BUILD_PID_FILE"
    ) &
    
    local build_pid=$!
    echo "$build_pid" > "$BUILD_PID_FILE"
    
    print_status "Build running in background (PID: $build_pid)"
    print_status "Log file: $BUILD_LOG_FILE"
    print_status "Check status: ./manage.sh build-status"
    print_status "View logs:    ./manage.sh build-log"
    print_status "Cancel:       ./manage.sh build-cancel"
}

# Function to build in background
build_background() {
    print_header "Background Build"
    check_docker
    check_docker_compose
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                 SELECT SERVICE TO BUILD                       │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) backend                   2) frontend                     │"
    echo "│  3) gateway                   4) All services                 │"
    echo "│  5) backend (no cache)        6) All (no cache)              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter option number [1-6]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    local build_cmd=""
    local description=""
    
    case $choice in
        1)
            build_cmd="$compose_cmd build backend"
            description="Build backend"
            ;;
        2)
            build_cmd="$compose_cmd build frontend"
            description="Build frontend"
            ;;
        3)
            build_cmd="$compose_cmd build gateway"
            description="Build gateway"
            ;;
        4)
            build_cmd="$compose_cmd build"
            description="Build all services"
            ;;
        5)
            build_cmd="$compose_cmd build --no-cache backend"
            description="Build backend (no cache)"
            ;;
        6)
            build_cmd="$compose_cmd build --no-cache"
            description="Build all services (no cache)"
            ;;
        *)
            print_error "Invalid option '$choice'. Please enter a number between 1-6."
            return
            ;;
    esac
    
    run_build_in_background "$build_cmd" "$description"
}

# Function to check background build status
build_status() {
    print_header "Background Build Status"
    
    if [ ! -d "$BUILD_LOG_DIR" ]; then
        print_status "No builds have been run yet"
        return
    fi
    
    if [ -f "$BUILD_LOG_DIR/build.description" ]; then
        local description=$(cat "$BUILD_LOG_DIR/build.description")
        print_status "Build: $description"
    fi
    
    if [ -f "$BUILD_STATUS_FILE" ]; then
        local status=$(cat "$BUILD_STATUS_FILE")
        case $status in
            running)
                if [ -f "$BUILD_PID_FILE" ]; then
                    local pid=$(cat "$BUILD_PID_FILE")
                    if kill -0 "$pid" 2>/dev/null; then
                        echo -e "${YELLOW}Status: RUNNING${NC} (PID: $pid)"
                        echo
                        print_status "Last 5 lines of build log:"
                        tail -5 "$BUILD_LOG_FILE" 2>/dev/null
                    else
                        echo -e "${RED}Status: DIED${NC} (process no longer running)"
                        echo "failed" > "$BUILD_STATUS_FILE"
                        rm -f "$BUILD_PID_FILE"
                    fi
                fi
                ;;
            success)
                echo -e "${GREEN}Status: SUCCESS${NC}"
                echo
                print_status "Last 3 lines of build log:"
                tail -3 "$BUILD_LOG_FILE" 2>/dev/null
                ;;
            failed)
                echo -e "${RED}Status: FAILED${NC}"
                echo
                print_status "Last 10 lines of build log:"
                tail -10 "$BUILD_LOG_FILE" 2>/dev/null
                ;;
        esac
    else
        print_status "No build status available"
    fi
}

# Function to view background build log
build_log() {
    local follow=${1:-false}
    
    if [ ! -f "$BUILD_LOG_FILE" ]; then
        print_error "No build log found. Run a background build first."
        return
    fi
    
    if [ "$follow" = "true" ] || [ "$follow" = "-f" ]; then
        print_status "Following build log (Ctrl+C to stop)..."
        tail -f "$BUILD_LOG_FILE"
    else
        print_status "Build log contents:"
        cat "$BUILD_LOG_FILE"
    fi
}

# Function to cancel a running background build
build_cancel() {
    print_header "Cancel Background Build"
    
    if [ ! -f "$BUILD_PID_FILE" ]; then
        print_status "No background build is currently running"
        return
    fi
    
    local pid=$(cat "$BUILD_PID_FILE")
    
    if kill -0 "$pid" 2>/dev/null; then
        print_warning "Cancelling build (PID: $pid)..."
        kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null
        echo "cancelled" > "$BUILD_STATUS_FILE"
        rm -f "$BUILD_PID_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Build CANCELLED by user" >> "$BUILD_LOG_FILE"
        print_status "Build cancelled"
    else
        print_status "Build process already finished"
        rm -f "$BUILD_PID_FILE"
    fi
}

# Function to build custom image
build_custom_image() {
    print_header "Build Custom Docker Image"
    check_docker
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      SELECT SERVICE                          │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) backend                   2) frontend                     │"
    echo "│  3) gateway                   4) certbot                       │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter service number [1-4]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    local service_name=""
    case $choice in
        1) service_name="backend" ;;
        2) service_name="frontend" ;;
        3) service_name="gateway" ;;
        4) service_name="certbot" ;;
        *) print_error "Invalid option '$choice'. Please enter a number between 1-4."; return ;;
    esac
    
    read -p "Enter image tag (e.g., myrepo/openmrs-backend:v1.0) [default: openmrs-${service_name}:custom]: " image_tag
    
    if [ -z "$image_tag" ]; then
        image_tag="openmrs-${service_name}:custom"
    fi
    
    print_status "Building $service_name image as $image_tag..."
    
    local compose_cmd=$(get_docker_compose_cmd)
    $compose_cmd build "$service_name" --tag "$image_tag"
    
    print_status "Build completed. Image tagged as: $image_tag"
}

# Function to build without cache
build_without_cache() {
    print_header "Build Without Cache"
    check_docker
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      SELECT SERVICE                          │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) backend                   2) frontend                     │"
    echo "│  3) gateway                   4) certbot                       │"
    echo "│  5) All services                                                   │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter service number [1-5]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    case $choice in
        1)
            print_status "Building backend without cache..."
            $compose_cmd build --no-cache backend
            ;;
        2)
            print_status "Building frontend without cache..."
            $compose_cmd build --no-cache frontend
            ;;
        3)
            print_status "Building gateway without cache..."
            $compose_cmd build --no-cache gateway
            ;;
        4)
            print_status "Building certbot without cache..."
            $compose_cmd build --no-cache certbot
            ;;
        5)
            print_status "Building all services without cache..."
            $compose_cmd build --no-cache
            ;;
        *)
            print_error "Invalid option '$choice'. Please enter a number between 1-5."
            return
            ;;
    esac
    
    print_status "Build completed"
}

# Function to push to Docker Hub
push_to_docker_hub() {
    print_header "Push Image to Docker Hub"
    check_docker
    
    echo "Available local images (excluding Portainer):"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep -v "portainer\|Portainer" || echo "No non-Portainer images found"
    echo
    read -p "Enter image name to push (e.g., myrepo/openmrs-backend:latest): " image_name
    
    if [ -z "$image_name" ]; then
        print_error "No image name provided"
        return
    fi
    
    # Check if it's a Portainer image
    if [[ "$image_name" == *"portainer"* ]] || [[ "$image_name" == *"Portainer"* ]]; then
        print_error "Cannot push Portainer images through this script for safety reasons"
        return
    fi
    
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"; then
        print_error "Image '$image_name' not found locally"
        return
    fi
    
    print_status "Pushing image to Docker Hub: $image_name"
    print_status "Make sure you're logged in with 'docker login'"
    echo
    
    read -p "Continue with push? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker push "$image_name"
        print_status "Image pushed successfully"
    else
        print_status "Push cancelled"
    fi
}

# Function to rebuild frontend configurations
rebuild_frontend_config() {
    print_header "Rebuild Frontend Configurations"
    check_docker
    
    if [ ! -d "frontend" ]; then
        print_error "frontend directory not found"
        return
    fi
    
    print_status "Rebuilding frontend configurations from frontend folder..."
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    # Stop frontend container
    print_status "Stopping frontend container..."
    $compose_cmd stop frontend
    
    # Rebuild frontend image
    print_status "Rebuilding frontend image..."
    $compose_cmd build --no-cache frontend
    
    # Start frontend container
    print_status "Starting frontend container..."
    $compose_cmd up -d frontend
    
    print_status "Frontend configurations rebuilt successfully"
}

# Function to copy frontend assets directly to container
copy_frontend_assets() {
    print_header "Copy Frontend Assets to Container"
    check_docker
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    # Check if frontend container is running
    if ! $compose_cmd ps frontend | grep -q "Up"; then
        print_error "Frontend container is not running. Please start the application first."
        return
    fi
    
    print_status "Applying frontend assets..."
    
    # Verify files exist locally before proceeding
    [ -f "frontend/config-core_demo.json" ] && print_status "Found: config-core_demo.json" || print_warning "Missing: config-core_demo.json"
    [ -f "frontend/logo.png" ]              && print_status "Found: logo.png"              || print_warning "Missing: logo.png"
    [ -f "frontend/bwongo-logo.png" ]       && print_status "Found: bwongo-logo.png"       || print_warning "Missing: bwongo-logo.png"
    
    # Assets are volume-mounted; recreate the container to pick up changes
    print_status "Recreating frontend container to apply changes (no rebuild)..."
    $compose_cmd up -d --force-recreate --no-build frontend
    
    print_status "Frontend assets copied successfully!"
    print_status "Assets copied to container without rebuilding"
}

# Function to build and start with custom distro configs
build_with_distro_config() {
    print_header "Build and Start with Custom Distro Configuration"
    check_docker
    check_docker_compose
    
    # Check if distro directory exists
    if [ ! -d "distro" ]; then
        print_error "distro directory not found"
        return
    fi
    
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      SELECT DISTRO CONFIG                     │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  1) distro.properties (with demo data)                       │"
    echo "│  2) distro-no-demo.properties (without demo data)            │"
    echo "│  3) Custom properties file                                    │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo
    echo -n "Enter option number [1-3]: "
    read -r choice
    
    choice=$(echo "$choice" | tr -d ' ')
    
    local distro_file=""
    case $choice in
        1) 
            distro_file="distro.properties"
            print_status "Using distro.properties (with demo data)"
            ;;
        2) 
            distro_file="distro-no-demo.properties"
            print_status "Using distro-no-demo.properties (without demo data)"
            ;;
        3)
            echo
            read -p "Enter custom properties file path (e.g., distro/custom.properties): " distro_file
            if [ -z "$distro_file" ]; then
                print_error "No file path provided"
                return
            fi
            ;;
        *) 
            print_error "Invalid option '$choice'. Please enter a number between 1-3."
            return 
            ;;
    esac
    
    # Check if the selected distro file exists
    if [ ! -f "$distro_file" ]; then
        print_error "Distro file '$distro_file' not found"
        return
    fi
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    print_status "Stopping existing application..."
    $compose_cmd down
    
    print_status "Building application with custom distro config: $distro_file"
    
    # Set environment variable for custom distro config
    export DISTRO_CONFIG_FILE="$distro_file"
    
    # Build backend with custom distro configuration
    print_status "Building backend image with custom distro configuration..."
    $compose_cmd build --no-cache backend
    
    # Start the application
    print_status "Starting application with custom distro configuration..."
    $compose_cmd up -d
    
    print_status "Application started successfully with custom distro configuration!"
    print_status "OpenMRS 3.x UI: http://localhost/openmrs/spa"
    print_status "OpenMRS Legacy UI: http://localhost/openmrs"
    
    # Unset the environment variable
    unset DISTRO_CONFIG_FILE
}

# Function to show help
show_help() {
    print_header "OpenMRS Management Script Help"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  start              Start the OpenMRS application"
    echo "  stop               Stop the OpenMRS application"
    echo "  restart            Restart the OpenMRS application"
    echo "  status             Show application status and URLs"
    echo "  logs [service]     Show logs (all services or specific service)"
    echo "  ssl-dev            Setup and start with SSL development mode (self-signed)"
    echo "  ssl-prod           Setup and start with SSL production mode (Let's Encrypt)"
    echo "  renew-certs        Force certificate renewal (production mode only)"
    echo "  check-certs        Check certificate status"
    echo "  regenerate-certs   Regenerate certificates (removes existing ones)"
    echo "  grafana            Start application with Grafana monitoring"
    echo "  cleanup            Clean up all Docker resources"
    echo "  interactive        Launch interactive management console"
    echo "  help               Show this help message"
    echo
    echo "Container Management Commands:"
    echo "  stop-container     Stop a specific container"
    echo "  restart-container  Restart a specific container"
    echo "  delete-container   Delete a specific container"
    echo "  delete-image       Delete a Docker image"
    echo "  prune              Prune Docker system resources"
    echo
    echo "Build Commands:"
    echo "  build-image        Build custom Docker image"
    echo "  build-no-cache     Build without cache"
    echo "  build-distro       Build and start with custom distro configuration"
    echo "  build-bg           Build in background (non-blocking)"
    echo "  build-status       Check background build status"
    echo "  build-log [-f]     View background build log (-f to follow)"
    echo "  build-cancel       Cancel a running background build"
    echo "  push               Push image to Docker Hub"
    echo "  rebuild-frontend   Rebuild frontend configurations"
    echo "  copy-assets        Copy frontend assets to container without rebuilding"
    echo
    echo "Interactive Mode:"
    echo "  Run './manage.sh interactive' to launch the interactive console"
    echo "  The console provides a user-friendly menu for all operations"
    echo
    echo "SSL Production Mode Environment Variables:"
    echo "  CERT_WEB_DOMAINS   Your domain name(s) (e.g., example.com,www.example.com)"
    echo "  CERT_CONTACT_EMAIL Email for Let's Encrypt notifications"
    echo "  SSL_STAGING        Use Let's Encrypt staging environment (true/false)"
    echo "  CERT_PROFILE       Certificate profile: classic, tlsserver, shortlived"
    echo
    echo "Examples:"
    echo "  $0 start                                    # Start basic application"
    echo "  $0 ssl-dev                                  # Start with self-signed SSL"
    echo "  CERT_WEB_DOMAINS=example.com CERT_CONTACT_EMAIL=admin@example.com $0 ssl-prod"
    echo "  $0 logs backend                            # Show backend logs"
    echo "  $0 grafana                                 # Start with Grafana"
}

# Main script logic
case "${1:-help}" in
    start)
        start_app
        ;;
    stop)
        stop_app
        ;;
    restart)
        restart_app
        ;;
    status)
        show_status
        ;;
    logs)
        view_logs "$2"
        ;;
    ssl-dev)
        setup_ssl_dev
        ;;
    ssl-prod)
        setup_ssl_prod
        ;;
    renew-certs)
        renew_certificates
        ;;
    check-certs)
        check_certificates
        ;;
    regenerate-certs)
        regenerate_certificates
        ;;
    grafana)
        start_with_grafana
        ;;
    cleanup)
        cleanup
        ;;
    interactive)
        show_interactive_menu
        ;;
    stop-container)
        stop_container
        ;;
    restart-container)
        restart_container
        ;;
    delete-container)
        delete_container
        ;;
    delete-image)
        delete_image
        ;;
    prune)
        prune_docker
        ;;
    build-image)
        build_custom_image
        ;;
    build-no-cache)
        build_without_cache
        ;;
    build-distro)
        build_with_distro_config
        ;;
    push)
        push_to_docker_hub
        ;;
    rebuild-frontend)
        rebuild_frontend_config
        ;;
    copy-assets)
        copy_frontend_assets
        ;;
    build-bg)
        build_background
        ;;
    build-status)
        build_status
        ;;
    build-log)
        build_log "$2"
        ;;
    build-cancel)
        build_cancel
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo
        show_help
        exit 1
        ;;
esac
