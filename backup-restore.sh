#!/bin/bash

# OpenMRS 3.0 Backup and Restore Script
# This script provides convenient commands for managing OpenMRS backups using Restic

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

# Function to check backup environment variables
check_backup_env() {
    if [ ! -f ".env" ] && [ ! -f ".env.backup" ]; then
        print_error "No .env or .env.backup file found"
        print_status "Please copy .env.backup to .env and configure your backup settings"
        return 1
    fi

    # Load backup environment variables
    if [ -f ".env" ]; then
        source .env
    elif [ -f ".env.backup" ]; then
        source .env.backup
    fi

    if [ -z "$RESTIC_REPOSITORY" ] || [ "$RESTIC_REPOSITORY" = "/path/to/your/backup/repository" ]; then
        print_error "RESTIC_REPOSITORY is not configured"
        print_status "Please set RESTIC_REPOSITORY in your .env file"
        return 1
    fi

    if [ -z "$RESTIC_PASSWORD" ] || [ "$RESTIC_PASSWORD" = "your_secure_password_here" ]; then
        print_error "RESTIC_PASSWORD is not configured"
        print_status "Please set RESTIC_PASSWORD in your .env file"
        return 1
    fi

    return 0
}

# Function to initialize a new backup repository
backup_init() {
    print_header "Initialize Backup Repository"
    check_docker
    check_docker_compose

    if ! check_backup_env; then
        exit 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)

    print_warning "This will initialize a new Restic backup repository at: $RESTIC_REPOSITORY"
    print_warning "If a repository already exists at this location, this will fail"
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi

    print_status "Initializing backup repository..."
    $compose_cmd -f docker-compose-backup.yml run --rm backup init

    print_status "Backup repository initialized successfully"
}

# Function to create a backup
backup_create() {
    print_header "Create Backup"
    check_docker
    check_docker_compose

    if ! check_backup_env; then
        exit 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)

    print_status "Creating backup..."
    print_status "Repository: $RESTIC_REPOSITORY"
    echo

    $compose_cmd -f docker-compose-backup.yml run --rm backup backup

    print_status "Backup completed successfully"
}

# Function to list backup snapshots
backup_list() {
    print_header "List Backup Snapshots"
    check_docker
    check_docker_compose

    if ! check_backup_env; then
        exit 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)

    print_status "Listing snapshots from: $RESTIC_REPOSITORY"
    echo

    $compose_cmd -f docker-compose-backup.yml run --rm backup snapshots
}

# Function to restore from backup
backup_restore() {
    print_header "Restore from Backup"
    check_docker
    check_docker_compose

    if ! check_backup_env; then
        exit 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)

    # List snapshots first
    print_status "Available snapshots:"
    echo
    $compose_cmd -f docker-compose-backup.yml run --rm backup snapshots
    echo

    read -p "Enter snapshot ID to restore (leave empty for latest): " snapshot_id

    if [ -n "$snapshot_id" ]; then
        export RESTIC_RESTORE_SNAPSHOT="$snapshot_id"
    else
        unset RESTIC_RESTORE_SNAPSHOT
    fi

    print_warning "This will restore the database and volumes from the selected snapshot"
    print_warning "All current data will be replaced with the backup data"
    print_warning "The application will be stopped during restore"
    echo
    read -p "Are you sure you want to restore? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled"
        exit 0
    fi

    print_status "Stopping application..."
    $compose_cmd down

    print_status "Starting restore process..."
    $compose_cmd -f docker-compose.yml -f docker-compose-restore.yml up -d restore

    print_status "Restore process started. Monitor with: docker compose logs -f restore"
    print_status "After restore completes, start the application with: docker compose up -d"
}

# Function to start with backup service
start_with_backup() {
    print_header "Start OpenMRS with Backup Service"
    check_docker
    check_docker_compose

    if ! check_backup_env; then
        exit 1
    fi

    local compose_cmd=$(get_docker_compose_cmd)

    print_status "Starting containers with backup service..."
    $compose_cmd -f docker-compose.yml -f docker-compose-backup.yml up -d

    print_status "Application is starting with backup service..."
    print_status "OpenMRS 3.x UI: http://localhost/openmrs/spa"
    print_status "OpenMRS Legacy UI: http://localhost/openmrs"
    print_status "Backup will run according to schedule: ${BACKUP_CRON_SCHEDULE:-0 1 * * *}"
}

# Function to show help
show_help() {
    print_header "OpenMRS Backup and Restore Script Help"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  init               Initialize a new backup repository"
    echo "  create             Create a manual backup"
    echo "  list               List available backup snapshots"
    echo "  restore            Restore from a backup snapshot"
    echo "  start              Start OpenMRS with automatic backup service"
    echo "  help               Show this help message"
    echo
    echo "Environment Variables (in .env file):"
    echo "  RESTIC_REPOSITORY  Backup repository path (e.g., /path/to/backup or s3:bucket)"
    echo "  RESTIC_PASSWORD    Password to encrypt/decrypt backups"
    echo "  BACKUP_CRON_SCHEDULE Backup schedule in cron format (default: 0 1 * * *)"
    echo "  RESTIC_KEEP_DAILY  Number of daily backups to keep (default: 7)"
    echo "  RESTIC_KEEP_WEEKLY Number of weekly backups to keep (default: 4)"
    echo "  RESTIC_KEEP_MONTHLY Number of monthly backups to keep (default: 12)"
    echo "  RESTIC_KEEP_YEARLY Number of yearly backups to keep (default: 3)"
    echo
    echo "Examples:"
    echo "  $0 init                                    # Initialize backup repository"
    echo "  $0 create                                  # Create manual backup"
    echo "  $0 list                                    # List backup snapshots"
    echo "  $0 restore                                 # Restore from backup"
    echo "  $0 start                                   # Start with automatic backups"
    echo
    echo "For more information, see README.md"
}

# Main script logic
case "${1:-help}" in
    init)
        backup_init
        ;;
    create)
        backup_create
        ;;
    list)
        backup_list
        ;;
    restore)
        backup_restore
        ;;
    start)
        start_with_backup
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
