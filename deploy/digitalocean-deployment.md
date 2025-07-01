# Judge0 DigitalOcean Deployment Guide

This guide will help you deploy Judge0 on DigitalOcean using Docker Compose.

## Prerequisites

1. DigitalOcean account
2. Domain name (optional but recommended)
3. Basic knowledge of Docker and Linux

## Step 1: Create DigitalOcean Droplet

### Recommended Specifications:
- **Minimum**: 2 vCPUs, 4GB RAM, 80GB SSD (Basic $24/month)
- **Recommended**: 4 vCPUs, 8GB RAM, 160GB SSD (General Purpose $48/month)
- **Production**: 8 vCPUs, 16GB RAM, 320GB SSD (General Purpose $96/month)

### Setup Steps:
1. Go to DigitalOcean Control Panel
2. Click "Create Droplet"
3. Choose "Ubuntu 22.04 (LTS) x64"
4. Select your preferred plan size
5. Choose a datacenter region close to your users
6. Add your SSH key or create a new one
7. Give your droplet a hostname (e.g., `judge0-server`)
8. Click "Create Droplet"

## Step 2: Initial Server Setup

Connect to your droplet via SSH:
```bash
ssh root@your_droplet_ip
```

Update the system and install Docker:
```bash
# Update package lists
apt update && apt upgrade -y

# Install required packages
apt install -y curl wget git ufw

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
mkdir -p ~/.docker/cli-plugins/
curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose

# Start and enable Docker
systemctl start docker
systemctl enable docker
```

## Step 3: Setup Firewall

Configure UFW firewall:
```bash
# Enable UFW
ufw enable

# Allow SSH
ufw allow ssh

# Allow HTTP and HTTPS
ufw allow 80
ufw allow 443

# Allow Judge0 API port
ufw allow 2358

# Check status
ufw status
```

## Step 4: Clone and Configure Judge0

```bash
# Create application directory
mkdir -p /opt/judge0
cd /opt/judge0

# Clone the repository (or upload your files)
git clone https://github.com/judge0/judge0.git .
# OR if you're uploading from your local machine:
# scp -r /path/to/your/judge0/* root@your_droplet_ip:/opt/judge0/
```

## Step 5: Create Production Configuration

Create a production-ready configuration file:
```bash
cp judge0.conf judge0.conf.backup
```

## Step 6: Setup SSL (Recommended)

Install and configure nginx with SSL:
```bash
# Install nginx
apt install -y nginx certbot python3-certbot-nginx

# Create nginx configuration
cat > /etc/nginx/sites-available/judge0 << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;

    location / {
        proxy_pass http://localhost:2358;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Increase timeout for long-running code executions
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOF

# Enable the site
ln -s /etc/nginx/sites-available/judge0 /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t

# Start nginx
systemctl start nginx
systemctl enable nginx

# Get SSL certificate (replace with your domain)
certbot --nginx -d your-domain.com -d www.your-domain.com
```

## Step 7: Deploy Judge0

```bash
cd /opt/judge0

# Start the services
docker compose up -d

# Check if services are running
docker compose ps

# View logs
docker compose logs -f
```

## Step 8: Initialize Database

```bash
# Wait for services to start (about 30 seconds)
sleep 30

# Initialize the database
docker compose exec server bundle exec rails db:create db:migrate db:seed
```

## Step 9: Test Deployment

Test your deployment:
```bash
# Test local connection
curl -X GET "http://localhost:2358/system_info"

# Test external connection (replace with your domain/IP)
curl -X GET "https://your-domain.com/system_info"
```

You should see a JSON response with system information.

## Step 10: Setup Monitoring and Maintenance

### Create backup script:
```bash
cat > /opt/judge0/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/judge0/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
docker compose exec -T db pg_dump -U judge0 judge0 > $BACKUP_DIR/db_backup_$DATE.sql

# Backup configuration
cp judge0.conf $BACKUP_DIR/judge0_conf_$DATE.conf

# Keep only last 7 days of backups
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.conf" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x /opt/judge0/backup.sh

# Add to crontab for daily backups at 2 AM
echo "0 2 * * * /opt/judge0/backup.sh >> /var/log/judge0-backup.log 2>&1" | crontab -
```

### Setup log rotation:
```bash
cat > /etc/logrotate.d/judge0 << 'EOF'
/opt/judge0/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0644 root root
}
EOF
```

## Step 11: Performance Optimization

### For high-traffic deployments:

1. **Increase worker count** in `judge0.conf`:
```bash
COUNT=4  # Increase based on your CPU cores
```

2. **Optimize PostgreSQL** by adding to `docker-compose.yml`:
```yaml
db:
  # ... existing configuration
  command: postgres -c shared_preload_libraries=pg_stat_statements -c pg_stat_statements.track=all -c max_connections=200
```

3. **Scale services**:
```bash
# Scale workers for better performance
docker compose up -d --scale worker=4
```

## Troubleshooting

### Common Issues:

1. **Service won't start**: Check logs with `docker compose logs servicename`
2. **Permission issues**: Ensure Docker has proper permissions
3. **Database connection**: Verify PostgreSQL is running and accessible
4. **Memory issues**: Monitor with `htop` and consider upgrading droplet

### Useful Commands:

```bash
# Restart all services
docker compose restart

# View real-time logs
docker compose logs -f

# Check resource usage
docker stats

# Update Judge0
git pull
docker compose pull
docker compose up -d

# Clean up unused Docker resources
docker system prune -f
```

## Security Best Practices

1. **Change default passwords** in judge0.conf
2. **Enable authentication** with AUTHN_TOKEN
3. **Restrict IP access** with ALLOW_IP if needed
4. **Regular updates**: Keep Docker images and system updated
5. **Monitor logs** for suspicious activity
6. **Use strong SSL certificates**

## Scaling

For high-traffic scenarios:
- Use DigitalOcean Load Balancer with multiple droplets
- Consider DigitalOcean Managed Databases for PostgreSQL
- Use DigitalOcean Spaces for file storage
- Implement Redis clustering for high availability

Your Judge0 instance should now be running at your domain/IP address on port 2358 (or 80/443 if using nginx proxy)! 