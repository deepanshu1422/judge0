#!/bin/bash

# Judge0 DigitalOcean Deployment Script
# This script automates the deployment of Judge0 on DigitalOcean

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root"
        exit 1
    fi
}

# Function to check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    apt update
    apt install -y curl wget git ufw nginx certbot python3-certbot-nginx openssl htop
    
    print_success "Dependencies installed successfully"
}

# Function to setup firewall
setup_firewall() {
    print_status "Setting up firewall..."
    
    ufw --force enable
    ufw allow ssh
    ufw allow 80
    ufw allow 443
    ufw allow 2358
    
    print_success "Firewall configured successfully"
}

# Function to create application directory and copy files
setup_application() {
    print_status "Setting up application..."
    
    # Create application directory
    mkdir -p /opt/judge0
    
    # Copy all deployment files
    if [ -d "./deploy" ]; then
        cp deploy/docker-compose.prod.yml /opt/judge0/docker-compose.yml
        cp deploy/judge0.prod.conf /opt/judge0/judge0.conf
        cp deploy/postgresql.conf /opt/judge0/postgresql.conf
    else
        print_error "Deploy directory not found. Please run this script from the project root."
        exit 1
    fi
    
    # Copy application files if they exist
    if [ -f "./docker-compose.yml" ]; then
        print_warning "Found existing docker-compose.yml, backing it up..."
        cp docker-compose.yml /opt/judge0/docker-compose.original.yml
    fi
    
    print_success "Application files copied successfully"
}

# Function to generate secure configuration
generate_secure_config() {
    print_status "Generating secure configuration..."
    
    cd /opt/judge0
    
    # Generate secure passwords
    REDIS_PASSWORD=$(generate_password)
    POSTGRES_PASSWORD=$(generate_password)
    AUTHN_TOKEN=$(generate_password)
    AUTHZ_TOKEN=$(generate_password)
    SECRET_KEY_BASE=$(openssl rand -hex 64)
    
    # Replace placeholders in configuration file
    sed -i "s/CHANGE_THIS_REDIS_PASSWORD_TO_SOMETHING_SECURE/$REDIS_PASSWORD/g" judge0.conf
    sed -i "s/CHANGE_THIS_DATABASE_PASSWORD_TO_SOMETHING_SECURE/$POSTGRES_PASSWORD/g" judge0.conf
    sed -i "s/CHANGE_THIS_TO_RANDOM_SECRET_TOKEN_FOR_AUTHENTICATION/$AUTHN_TOKEN/g" judge0.conf
    sed -i "s/CHANGE_THIS_TO_RANDOM_SECRET_TOKEN_FOR_AUTHORIZATION/$AUTHZ_TOKEN/g" judge0.conf
    sed -i "s/SECRET_KEY_BASE=/SECRET_KEY_BASE=$SECRET_KEY_BASE/g" judge0.conf
    
    # Save credentials to secure file
    cat > /opt/judge0/credentials.txt << EOF
# Judge0 Deployment Credentials
# Generated on: $(date)
# KEEP THIS FILE SECURE!

REDIS_PASSWORD=$REDIS_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
AUTHN_TOKEN=$AUTHN_TOKEN
AUTHZ_TOKEN=$AUTHZ_TOKEN
SECRET_KEY_BASE=$SECRET_KEY_BASE

# API Usage:
# Authentication: Add header 'X-Auth-Token: $AUTHN_TOKEN'
# Authorization: Add header 'X-Auth-User: $AUTHZ_TOKEN'
EOF
    
    chmod 600 /opt/judge0/credentials.txt
    
    print_success "Secure configuration generated"
    print_warning "Credentials saved to /opt/judge0/credentials.txt - KEEP THIS FILE SECURE!"
}

# Function to setup nginx reverse proxy
setup_nginx() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        print_warning "No domain provided, skipping nginx setup"
        return
    fi
    
    print_status "Setting up nginx reverse proxy for $domain..."
    
    cat > /etc/nginx/sites-available/judge0 << EOF
server {
    listen 80;
    server_name $domain www.$domain;

    client_max_body_size 10M;
    client_body_timeout 60s;
    client_header_timeout 60s;

    location / {
        proxy_pass http://localhost:2358;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Increase timeout for long-running code executions
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        
        # Add security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://localhost:2358/system_info;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/judge0 /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    nginx -t
    systemctl reload nginx
    
    print_success "Nginx configured successfully"
}

# Function to setup SSL certificate
setup_ssl() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        print_warning "No domain provided, skipping SSL setup"
        return
    fi
    
    print_status "Setting up SSL certificate for $domain..."
    
    # Get SSL certificate
    certbot --nginx -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "admin@$domain"
    
    print_success "SSL certificate configured successfully"
}

# Function to deploy Judge0
deploy_judge0() {
    print_status "Deploying Judge0..."
    
    cd /opt/judge0
    
    # Pull latest images
    docker compose pull
    
    # Start services
    docker compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 60
    
    # Initialize database
    print_status "Initializing database..."
    docker compose exec -T server bundle exec rails db:create db:migrate db:seed
    
    print_success "Judge0 deployed successfully"
}

# Function to create maintenance scripts
create_maintenance_scripts() {
    print_status "Creating maintenance scripts..."
    
    # Backup script
    cat > /opt/judge0/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/judge0/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
docker compose exec -T db pg_dump -U judge0 judge0 > $BACKUP_DIR/db_backup_$DATE.sql

# Backup configuration
cp judge0.conf $BACKUP_DIR/judge0_conf_$DATE.conf
cp credentials.txt $BACKUP_DIR/credentials_$DATE.txt

# Backup Docker volumes
docker run --rm -v judge0_postgres_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/postgres_volume_$DATE.tar.gz -C /data .
docker run --rm -v judge0_redis_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/redis_volume_$DATE.tar.gz -C /data .

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.conf" -mtime +7 -delete
find $BACKUP_DIR -name "*.txt" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF
    
    # Update script
    cat > /opt/judge0/update.sh << 'EOF'
#!/bin/bash
cd /opt/judge0

echo "Updating Judge0..."
docker compose pull
docker compose up -d
docker image prune -f

echo "Update completed!"
EOF
    
    # Health check script
    cat > /opt/judge0/health-check.sh << 'EOF'
#!/bin/bash
cd /opt/judge0

echo "=== Judge0 Health Check ==="
echo "Services status:"
docker compose ps

echo -e "\nService health:"
curl -s http://localhost:2358/system_info | jq '.' || echo "API not responding"

echo -e "\nResource usage:"
docker stats --no-stream

echo -e "\nDisk usage:"
df -h /opt/judge0
EOF
    
    chmod +x /opt/judge0/*.sh
    
    # Setup cron jobs
    cat > /etc/cron.d/judge0 << EOF
# Judge0 maintenance tasks
0 2 * * * root /opt/judge0/backup.sh >> /var/log/judge0-backup.log 2>&1
0 3 * * 0 root /opt/judge0/update.sh >> /var/log/judge0-update.log 2>&1
*/5 * * * * root /opt/judge0/health-check.sh > /tmp/judge0-health.log 2>&1
EOF
    
    print_success "Maintenance scripts created"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Check if services are running
    cd /opt/judge0
    if ! docker compose ps | grep -q "Up"; then
        print_error "Some services are not running"
        docker compose ps
        return 1
    fi
    
    # Test API endpoint
    sleep 10
    if curl -s http://localhost:2358/system_info > /dev/null; then
        print_success "API is responding"
    else
        print_error "API is not responding"
        return 1
    fi
    
    print_success "Deployment verified successfully"
}

# Main deployment function
main() {
    print_status "Starting Judge0 deployment on DigitalOcean..."
    
    # Parse command line arguments
    DOMAIN=""
    SKIP_SSL=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --domain DOMAIN    Setup nginx reverse proxy and SSL for domain"
                echo "  --skip-ssl         Skip SSL certificate setup"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    check_root
    check_docker
    install_dependencies
    setup_firewall
    setup_application
    generate_secure_config
    
    if [ -n "$DOMAIN" ]; then
        setup_nginx "$DOMAIN"
        if [ "$SKIP_SSL" = false ]; then
            setup_ssl "$DOMAIN"
        fi
    fi
    
    deploy_judge0
    create_maintenance_scripts
    verify_deployment
    
    print_success "Judge0 deployment completed successfully!"
    echo
    print_status "=== Deployment Summary ==="
    echo "• Application directory: /opt/judge0"
    echo "• Configuration file: /opt/judge0/judge0.conf"
    echo "• Credentials file: /opt/judge0/credentials.txt"
    echo "• API endpoint: http://localhost:2358"
    
    if [ -n "$DOMAIN" ]; then
        echo "• Domain: https://$DOMAIN"
    fi
    
    echo
    print_status "=== Next Steps ==="
    echo "1. Test the API: curl http://localhost:2358/system_info"
    echo "2. Review credentials: cat /opt/judge0/credentials.txt"
    echo "3. Monitor logs: docker compose logs -f"
    echo "4. Setup monitoring: docker compose --profile monitoring up -d"
    echo
    print_warning "Make sure to backup the credentials file and keep it secure!"
}

# Run main function
main "$@" 