# Judge0 DigitalOcean Deployment - Quick Start

This directory contains everything you need to deploy Judge0 on DigitalOcean quickly and securely.

## 🚀 Quick Deployment

### Option 1: Minimal Deployment ($12/month) - NEW! 💸

**Perfect for testing, development, or low-traffic usage**

**Requirements:**
- DigitalOcean droplet: 1 vCPU, 1GB RAM, 25GB SSD ($12/month)
- Docker and Docker Compose installed
- Root access

**Run the minimal deployment script:**

```bash
# Minimal deployment (no domain/SSL)
sudo ./deploy/deploy-minimal.sh

# With domain and SSL  
sudo ./deploy/deploy-minimal.sh --domain yourdomain.com

# With domain but no SSL
sudo ./deploy/deploy-minimal.sh --domain yourdomain.com --skip-ssl
```

**Minimal deployment features:**
- Single worker process
- Reduced memory limits (64MB per execution)
- Queue limit: 10 submissions
- No submission caching
- 1GB swap file automatically created
- System optimizations for low memory

### Option 2: Standard Deployment ($24+ /month)

**For production use with better performance**

**Requirements:**
- DigitalOcean droplet: 2+ vCPUs, 4+ GB RAM, 80+ GB SSD
- Docker and Docker Compose installed
- Root access

**Run the standard deployment script:**

```bash
# Standard deployment (no domain/SSL)
sudo ./deploy/deploy-digitalocean.sh

# With domain and SSL
sudo ./deploy/deploy-digitalocean.sh --domain yourdomain.com

# With domain but no SSL
sudo ./deploy/deploy-digitalocean.sh --domain yourdomain.com --skip-ssl
```

### Option 3: Manual Deployment

If you prefer manual setup, follow the detailed guide in `digitalocean-deployment.md`.

## 📁 Files Included

- **`deploy-minimal.sh`** - Minimal deployment script for $12 droplet
- **`deploy-digitalocean.sh`** - Standard deployment script
- **`digitalocean-deployment.md`** - Detailed manual deployment guide
- **`docker-compose.minimal.yml`** - Minimal resource Docker Compose configuration
- **`docker-compose.prod.yml`** - Production-optimized Docker Compose configuration
- **`judge0.minimal.conf`** - Minimal deployment Judge0 configuration
- **`judge0.prod.conf`** - Production-ready Judge0 configuration
- **`postgresql.minimal.conf`** - Minimal PostgreSQL settings
- **`postgresql.conf`** - Optimized PostgreSQL settings

## 🔧 What the Deployment Includes

- **Judge0 API Server** - Main application serving the REST API
- **Worker Process(es)** - Handle code execution in isolated environments
- **PostgreSQL Database** - Stores submissions, languages, and metadata
- **Redis Cache** - Job queue and caching system
- **Nginx Reverse Proxy** - SSL termination and load balancing (optional)
- **SSL Certificate** - Let's Encrypt certificate (optional)
- **Monitoring Tools** - Health checks and system monitoring (optional)
- **Backup System** - Automated backups (weekly for minimal, daily for standard)
- **Security** - Firewall, secure passwords, and authentication

## 🎯 After Deployment

### Testing Your Installation

```bash
# Test the API
curl http://your-server-ip:2358/system_info

# Or with domain
curl https://yourdomain.com/system_info

# Submit test code execution
curl -X POST "https://yourdomain.com/submissions" \
     -H "Content-Type: application/json" \
     -H "X-Auth-Token: YOUR_AUTH_TOKEN" \
     -d '{
       "source_code": "print(\"Hello, Judge0!\")",
       "language_id": 71
     }'
```

### Important Files

- **Configuration**: `/opt/judge0/judge0.conf`
- **Credentials**: `/opt/judge0/credentials.txt` (KEEP SECURE!)
- **Logs**: `docker compose logs -f`
- **Backups**: `/opt/judge0/backups/`

### Useful Commands

```bash
cd /opt/judge0

# View service status
docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Update Judge0
./update.sh

# Manual backup
./backup.sh

# Health check
./health-check.sh

# Scale workers (standard deployment only)
docker compose up -d --scale worker=4
```

## 🔐 Security

The deployment automatically:
- Generates secure random passwords
- Enables authentication tokens
- Configures firewall rules
- Sets up SSL certificates (if domain provided)
- Restricts network access for code execution

**Important:** Always keep the `/opt/judge0/credentials.txt` file secure!

## 📊 Monitoring (Optional)

Enable monitoring services (standard deployment only):

```bash
cd /opt/judge0
docker compose --profile monitoring up -d
```

This starts:
- **Node Exporter** (port 9100) - System metrics
- **Redis Exporter** (port 9121) - Redis metrics  
- **PostgreSQL Exporter** (port 9187) - Database metrics

## 🔧 Server Requirements & Costs

| Deployment Type | vCPUs | RAM | Storage | DigitalOcean Cost | Use Case |
|-----------------|-------|-----|---------|-------------------|----------|
| **Minimal** ⭐   | 1     | 1GB | 25GB    | **$12/month**     | Testing, light dev |
| **Minimum**     | 2     | 4GB | 80GB    | $24/month         | Small production |
| **Recommended** | 4     | 8GB | 160GB   | $48/month         | Medium production |
| **High-Traffic** | 8     | 16GB| 320GB   | $96/month         | Large production |

## 🆘 Troubleshooting

### Common Issues

1. **Services won't start**: Check logs with `docker compose logs servicename`
2. **API not responding**: Verify firewall allows port 2358
3. **SSL issues**: Ensure domain DNS points to your server
4. **Permission errors**: Run as root or with sudo
5. **Out of memory (minimal)**: Check `free -h`, restart services, or upgrade

### Getting Help

- Check the logs: `docker compose logs -f`
- Monitor resources: `htop` or `docker stats`
- Test connectivity: `curl http://localhost:2358/system_info`
- Review configuration: `cat /opt/judge0/judge0.conf`
- Check memory usage: `free -h` (especially important for minimal deployment)

## 🚀 Performance Tuning

### For Minimal Deployment ($12):
- Monitor memory usage regularly: `free -h`
- Keep queue small (max 10 submissions)
- Use smaller input files
- Consider upgrading if hitting limits frequently

### For Standard Deployments:
1. **Scale workers**: `docker compose up -d --scale worker=6`
2. **Adjust resources** in `docker-compose.yml`
3. **Optimize PostgreSQL** settings in `postgresql.conf`
4. **Use DigitalOcean Load Balancer** for multiple droplets
5. **Consider managed databases** for high availability

## 📝 API Usage Examples

### Authentication

All API requests require authentication headers:

```bash
curl -H "X-Auth-Token: YOUR_AUTH_TOKEN" \
     -H "X-Auth-User: YOUR_AUTHZ_TOKEN" \
     "https://yourdomain.com/languages"
```

### Code Execution

```bash
# Python
curl -X POST "https://yourdomain.com/submissions" \
     -H "Content-Type: application/json" \
     -H "X-Auth-Token: YOUR_TOKEN" \
     -d '{
       "source_code": "print(\"Hello World\")",
       "language_id": 71,
       "stdin": ""
     }'

# JavaScript
curl -X POST "https://yourdomain.com/submissions" \
     -H "Content-Type: application/json" \
     -H "X-Auth-Token: YOUR_TOKEN" \
     -d '{
       "source_code": "console.log(\"Hello World\")",
       "language_id": 63
     }'
```

## 💡 Deployment Recommendations

### Choose Minimal ($12) if you:
- Are testing or learning Judge0
- Have light traffic (< 100 submissions/day)
- Want to minimize costs
- Don't need high performance

### Choose Standard ($24+) if you:
- Need production reliability
- Have moderate to high traffic
- Require faster execution times
- Want monitoring and better backup features

## 🎉 Success!

Your Judge0 instance is now ready to execute code in 60+ programming languages! 

Visit the API documentation at `https://yourdomain.com/docs` to explore all available features. 