#!/bin/bash

# Judge0 Minimal DigitalOcean Deployment Script
# Optimized for $12/month droplet (1 vCPU, 1GB RAM, 25GB SSD)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root"
        exit 1
    fi
}

check_system_requirements() {
    print_status "Checking system requirements..."
    
    # Check available memory
    AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$AVAILABLE_MEM" -lt 400 ]; then
        print_error "Insufficient memory available. Need at least 400MB free."
        print_error "Current available: ${AVAILABLE_MEM}MB"
        exit 1
    fi
    
    # Check disk space
    AVAILABLE_DISK=$(df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_DISK" -lt 10485760 ]; then  # 10GB in KB
        print_error "Insufficient disk space. Need at least 10GB free."
        exit 1
    fi
    
    print_success "System requirements check passed"
}

optimize_system() {
    print_status "Optimizing system for minimal deployment..."
    
    # Create swap file if none exists (important for 1GB RAM)
    if [ ! -f /swapfile ]; then
        print_status "Creating 1GB swap file..."
        fallocate -l 1G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        print_success "Swap file created"
    fi
    
    # Optimize swappiness for low memory
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl vm.swappiness=10
    
    # Disable unnecessary services to save memory
    systemctl disable snapd --now 2>/dev/null || true
    systemctl disable accounts-daemon --now 2>/dev/null || true
    systemctl disable bluetooth --now 2>/dev/null || true
    
    print_success "System optimized for minimal deployment"
}

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

install_minimal_dependencies() {
    print_status "Installing minimal dependencies..."
    
    # Update package lists
    apt update
    
    # Install only essential packages
    apt install -y curl wget git ufw openssl
    
    # Install nginx only if domain is provided
    if [ -n "$DOMAIN" ]; then
        apt install -y nginx certbot python3-certbot-nginx
    fi
    
    print_success "Minimal dependencies installed"
}

setup_firewall() {
    print_status "Setting up firewall..."
    
    ufw --force enable
    ufw allow ssh
    ufw allow 2358
    
    if [ -n "$DOMAIN" ]; then
        ufw allow 80
        ufw allow 443
    fi
    
    print_success "Firewall configured"
}

setup_application() {
    print_status "Setting up minimal application..."
    
    mkdir -p /opt/judge0
    
    if [ -d "./deploy" ]; then
        cp deploy/docker-compose.minimal.yml /opt/judge0/docker-compose.yml
        cp deploy/judge0.minimal.conf /opt/judge0/judge0.conf
        cp deploy/postgresql.minimal.conf /opt/judge0/postgresql.conf
    else
        print_error "Deploy directory not found. Please run this script from the project root."
        exit 1
    fi
    
    print_success "Application files copied"
}

generate_secure_config() {
    print_status "Generating secure configuration..."
    
    cd /opt/judge0
    
    REDIS_PASSWORD=$(generate_password)
    POSTGRES_PASSWORD=$(generate_password)
    AUTHN_TOKEN=$(generate_password)
    AUTHZ_TOKEN=$(generate_password)
    SECRET_KEY_BASE=$(openssl rand -hex 64)
    
    sed -i "s/CHANGE_THIS_REDIS_PASSWORD_TO_SOMETHING_SECURE/$REDIS_PASSWORD/g" judge0.conf
    sed -i "s/CHANGE_THIS_DATABASE_PASSWORD_TO_SOMETHING_SECURE/$POSTGRES_PASSWORD/g" judge0.conf
    sed -i "s/CHANGE_THIS_TO_RANDOM_SECRET_TOKEN_FOR_AUTHENTICATION/$AUTHN_TOKEN/g" judge0.conf
    sed -i "s/CHANGE_THIS_TO_RANDOM_SECRET_TOKEN_FOR_AUTHORIZATION/$AUTHZ_TOKEN/g" judge0.conf
    sed -i "s/SECRET_KEY_BASE=/SECRET_KEY_BASE=$SECRET_KEY_BASE/g" judge0.conf
    
    cat > /opt/judge0/credentials.txt << EOF
# Judge0 Minimal Deployment Credentials
# Generated on: $(date)
# Server: 1 vCPU, 1GB RAM (\$12/month DigitalOcean)

REDIS_PASSWORD=$REDIS_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
AUTHN_TOKEN=$AUTHN_TOKEN
AUTHZ_TOKEN=$AUTHZ_TOKEN
SECRET_KEY_BASE=$SECRET_KEY_BASE

# API Usage:
# Authentication: Add header 'X-Auth-Token: $AUTHN_TOKEN'
# Authorization: Add header 'X-Auth-User: $AUTHZ_TOKEN'

# Performance Notes:
# - Single worker process
# - Reduced memory limits
# - Queue limit: 10 submissions
# - No submission caching
EOF
    
    chmod 600 /opt/judge0/credentials.txt
    
    print_success "Secure configuration generated"
}

setup_nginx_minimal() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        return
    fi
    
    print_status "Setting up minimal nginx for $domain..."
    
    cat > /etc/nginx/sites-available/judge0 << EOF
server {
    listen 80;
    server_name $domain www.$domain;

    client_max_body_size 1M;
    client_body_timeout 30s;
    client_header_timeout 30s;

    location / {
        proxy_pass http://localhost:2358;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_read_timeout 120s;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/judge0 /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    nginx -t && systemctl reload nginx
    
    print_success "Minimal nginx configured"
}

deploy_judge0_minimal() {
    print_status "Deploying Judge0 (minimal)..."
    
    cd /opt/judge0
    
    # Pull images one by one to avoid memory issues
    print_status "Pulling Docker images..."
    docker pull postgres:16.2-alpine
    docker pull redis:7.2.4-alpine
    docker pull judge0/judge0:latest
    
    # Start services with explicit memory limits
    print_status "Starting services..."
    docker compose up -d --remove-orphans
    
    # Wait longer for services on minimal hardware
    print_status "Waiting for services to start (this may take a few minutes)..."
    sleep 90
    
    # Initialize database
    print_status "Initializing database..."
    docker compose exec -T server bundle exec rails db:create db:migrate db:seed
    
    print_success "Judge0 minimal deployment completed"
}

create_minimal_maintenance() {
    print_status "Creating minimal maintenance scripts..."
    
    cat > /opt/judge0/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/judge0/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Database backup only (no volume backups to save space)
docker compose exec -T db pg_dump -U judge0 judge0 > $BACKUP_DIR/db_backup_$DATE.sql
cp judge0.conf $BACKUP_DIR/judge0_conf_$DATE.conf

# Keep only last 3 days of backups
find $BACKUP_DIR -name "*.sql" -mtime +3 -delete
find $BACKUP_DIR -name "*.conf" -mtime +3 -delete

echo "Minimal backup completed: $DATE"
EOF
    
    cat > /opt/judge0/health-check.sh << 'EOF'
#!/bin/bash
cd /opt/judge0

echo "=== Judge0 Minimal Health Check ==="
echo "Memory usage:"
free -h

echo -e "\nServices:"
docker compose ps

echo -e "\nAPI status:"
curl -s --max-time 10 http://localhost:2358/system_info > /dev/null && echo "API OK" || echo "API DOWN"

echo -e "\nDisk usage:"
df -h /opt/judge0
EOF
    
    chmod +x /opt/judge0/*.sh
    
    # Minimal cron job (backup only weekly)
    cat > /etc/cron.d/judge0-minimal << EOF
# Judge0 minimal maintenance
0 3 * * 0 root /opt/judge0/backup.sh >> /var/log/judge0-backup.log 2>&1
0 */6 * * * root /opt/judge0/health-check.sh > /tmp/judge0-health.log 2>&1
EOF
    
    print_success "Minimal maintenance scripts created"
}

verify_minimal_deployment() {
    print_status "Verifying minimal deployment..."
    
    cd /opt/judge0
    
    # Check memory usage
    MEMORY_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    print_status "Memory usage: ${MEMORY_USAGE}%"
    
    if [ "$MEMORY_USAGE" -gt 90 ]; then
        print_warning "High memory usage detected: ${MEMORY_USAGE}%"
    fi
    
    # Test API
    sleep 15
    if curl -s --max-time 10 http://localhost:2358/system_info > /dev/null; then
        print_success "API is responding"
    else
        print_error "API is not responding"
        return 1
    fi
    
    print_success "Minimal deployment verified"
}

main() {
    print_status "Starting Judge0 minimal deployment for \$12 DigitalOcean droplet..."
    
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
                echo ""
                echo "Optimized for \$12 DigitalOcean droplet (1 vCPU, 1GB RAM, 25GB SSD)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_root
    check_system_requirements
    optimize_system
    check_docker
    install_minimal_dependencies
    setup_firewall
    setup_application
    generate_secure_config
    
    if [ -n "$DOMAIN" ]; then
        setup_nginx_minimal "$DOMAIN"
        if [ "$SKIP_SSL" = false ]; then
            print_status "Setting up SSL..."
            certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || print_warning "SSL setup failed, continuing..."
        fi
    fi
    
    deploy_judge0_minimal
    create_minimal_maintenance
    verify_minimal_deployment
    
    print_success "Judge0 minimal deployment completed!"
    echo
    print_status "=== Minimal Deployment Summary ==="
    echo "• Server: 1 vCPU, 1GB RAM (\$12/month)"
    echo "• Single worker process"
    echo "• Reduced resource limits"
    echo "• Queue limit: 10 submissions"
    echo "• API endpoint: http://localhost:2358"
    
    if [ -n "$DOMAIN" ]; then
        echo "• Domain: https://$DOMAIN"
    fi
    
    echo
    print_status "=== Performance Notes ==="
    echo "• Expect slower execution due to resource constraints"
    echo "• Recommended for light testing/development only"
    echo "• Consider upgrading for production workloads"
    echo "• Monitor memory usage regularly"
    echo
    print_warning "Credentials saved to /opt/judge0/credentials.txt - keep it secure!"
}

main "$@" 