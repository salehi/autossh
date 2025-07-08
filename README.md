# AutoSSH SOCKS5 Proxy Container

A lightweight Docker container that creates a persistent SOCKS5 proxy tunnel through SSH using AutoSSH. Supports multiple authentication methods with automatic failover and connection recovery.

## Features

- **Multiple Authentication Methods** with priority fallback:
  1. SSH Certificate authentication (highest priority)
  2. SSH Private Key authentication  
  3. SSH Password authentication (lowest priority)
- **Automatic Connection Recovery** using AutoSSH
- **SOCKS5 Proxy** accessible on configurable port
- **Health Monitoring** with built-in health checks
- **Security Hardened** with proper file permissions and cleanup
- **Lightweight** Alpine Linux base image (~30MB)

## Quick Start

### Using Docker Run

```bash
# Certificate authentication
docker run -d \
  --name autossh-proxy \
  -p 1080:1080 \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=username \
  -e SSH_PRIVATE_KEY=$(base64 -w 0 ~/.ssh/id_rsa) \
  -e SSH_CERTIFICATE=$(base64 -w 0 ~/.ssh/id_rsa-cert.pub) \
  --restart unless-stopped \
  s4l3h1/autossh:alpine

# Private key authentication
docker run -d \
  --name autossh-proxy \
  -p 1080:1080 \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=username \
  -e SSH_PRIVATE_KEY=$(base64 -w 0 ~/.ssh/id_rsa) \
  --restart unless-stopped \
  s4l3h1/autossh:alpine

# Password authentication
docker run -d \
  --name autossh-proxy \
  -p 1080:1080 \
  -e SSH_HOST=your-server.com \
  -e SSH_USER=username \
  -e SSH_PASS=your-password \
  --restart unless-stopped \
  s4l3h1/autossh:alpine
```

### Using Docker Compose

Create a `docker-compose.yml` file:

```yaml
version: '3.8'

services:
  autossh-proxy:
    image: s4l3h1/autossh:alpine
    container_name: autossh-socks5-proxy
    restart: unless-stopped
    ports:
      - "1080:1080"
    environment:
      # Required connection details
      - SSH_HOST=${SSH_HOST}
      - SSH_USER=${SSH_USER}
      
      # Optional SSH port (defaults to 22)
      - SSH_PORT=${SSH_PORT:-22}
      
      # Authentication methods (use one or more, priority: certificate > key > password)
      # Certificate authentication (both required)
      - SSH_PRIVATE_KEY=${SSH_PRIVATE_KEY:-}
      - SSH_CERTIFICATE=${SSH_CERTIFICATE:-}
      
      # Password authentication
      - SSH_PASS=${SSH_PASS:-}
      
      # SOCKS5 proxy binding (optional, has defaults)
      - SOCKS_BIND_ADDR=${SOCKS_BIND_ADDR:-0.0.0.0}
      - SOCKS_BIND_PORT=${SOCKS_BIND_PORT:-1080}
    
    # Health check configuration
    healthcheck:
      test: ["CMD", "curl", "--socks5", "${SOCKS_BIND_ADDR:-0.0.0.0}:${SOCKS_BIND_PORT:-1080}", "--max-time", "10", "-s", "ifconfig.io"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    
    # Resource limits (optional)
    deploy:
      resources:
        limits:
          memory: 64M
          cpus: '0.1'
        reservations:
          memory: 32M
          cpus: '0.05'
```

Create a `.env` file with your credentials:

```bash
# .env file
SSH_HOST=your-server.com
SSH_USER=username
SSH_PORT=22

# Choose one authentication method:

# For certificate auth:
SSH_PRIVATE_KEY=LS0tLS1CRUdJTi...  # base64 encoded
SSH_CERTIFICATE=c3NoLXJzYS1jZX...  # base64 encoded

# For key auth:
# SSH_PRIVATE_KEY=LS0tLS1CRUdJTi...  # base64 encoded

# For password auth:
# SSH_PASS=your-password
```

Start the service:

```bash
docker-compose up -d
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SSH_HOST` | Yes | - | SSH server hostname or IP |
| `SSH_USER` | Yes | - | SSH username |
| `SSH_PORT` | No | `22` | SSH server port |
| `SSH_PRIVATE_KEY` | No* | - | Base64 encoded SSH private key |
| `SSH_CERTIFICATE` | No* | - | Base64 encoded SSH certificate |
| `SSH_PASS` | No* | - | SSH password |
| `SOCKS_BIND_ADDR` | No | `0.0.0.0` | SOCKS5 proxy bind address |
| `SOCKS_BIND_PORT` | No | `1080` | SOCKS5 proxy bind port |

*At least one authentication method must be provided.

## Server Configuration

### For SSH Key Authentication

1. **Generate SSH key pair** (if you don't have one):
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/tunnel_key
   ```

2. **Copy public key to server**:
   ```bash
   ssh-copy-id -i ~/.ssh/tunnel_key.pub user@your-server.com
   ```

3. **Restrict the key for tunnel-only access** (recommended):
   ```bash
   # Edit ~/.ssh/authorized_keys on the server
   no-pty,no-shell,no-agent-forwarding,no-X11-forwarding,command="echo 'Tunnel only'" ssh-rsa AAAAB3NzaC1yc2E...
   ```

4. **Encode the private key for the container**:
   ```bash
   base64 -w 0 ~/.ssh/tunnel_key
   ```

### For SSH Certificate Authentication

#### 1. Create Certificate Authority (CA)

```bash
# Generate CA key pair
ssh-keygen -t rsa -b 4096 -f ca_key -C "SSH CA"

# Copy CA public key to server
scp ca_key.pub user@your-server.com:/etc/ssh/ca_key.pub
```

#### 2. Configure SSH Server

Add to `/etc/ssh/sshd_config` on your server:

```bash
# Trust the CA for user certificates
TrustedUserCAKeys /etc/ssh/ca_key.pub

# Optional: Force certificate authentication only
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
```

Restart SSH service:
```bash
sudo systemctl restart sshd
```

#### 3. Generate User Certificate

```bash
# Generate user key pair
ssh-keygen -t rsa -b 4096 -f user_key -C "tunnel-user"

# Sign the certificate with restrictions for port forwarding only
ssh-keygen -s ca_key \
  -I "tunnel-user@$(date +%Y%m%d)" \
  -n username \
  -V +1d \
  -O no-pty \
  -O no-shell \
  -O no-agent-forwarding \
  -O no-X11-forwarding \
  -O no-user-rc \
  -O permit-port-forwarding \
  user_key.pub
```

This creates `user_key-cert.pub` with the following restrictions:
- **no-pty**: No pseudo-terminal allocation
- **no-shell**: No shell access
- **no-agent-forwarding**: No SSH agent forwarding
- **no-X11-forwarding**: No X11 forwarding
- **no-user-rc**: No user RC file execution
- **permit-port-forwarding**: Only allow port forwarding

#### 4. Prepare for Container

```bash
# Encode private key
base64 -w 0 user_key

# Encode certificate
base64 -w 0 user_key-cert.pub
```

## Usage Examples

### Testing the SOCKS5 Proxy

```bash
# Test with curl
curl --socks5 localhost:1080 http://ifconfig.io

# Test with wget
wget --proxy-user="" --proxy-password="" \
     --proxy=on --proxy-type=socks5 \
     --proxy-host=localhost --proxy-port=1080 \
     -qO- http://ifconfig.io

# Configure applications to use SOCKS5 proxy
# Proxy: localhost:1080 (no authentication required)
```

### Monitoring

```bash
# View logs
docker logs -f autossh-proxy

# Check health status
docker ps
# or with docker-compose
docker-compose ps

# Monitor connection
docker exec autossh-proxy ps aux | grep autossh
```

## Health Check

The container includes a built-in health check that:
- Tests the SOCKS5 proxy by making a request to `ifconfig.io`
- Fails if no response within 10 seconds
- Runs every 30 seconds with 3 retries
- Confirms both SSH tunnel and SOCKS5 proxy are working

## Security Best Practices

1. **Use certificate authentication** when possible for better security and management
2. **Restrict SSH keys** in `authorized_keys` to tunnel-only access
3. **Use short-lived certificates** (1 day or less) for temporary access
4. **Rotate credentials** regularly
5. **Monitor logs** for connection attempts and failures
6. **Use strong SSH key algorithms** (RSA 4096, Ed25519, or ECDSA)
7. **Disable password authentication** on SSH servers when using keys/certificates

## Troubleshooting

### Connection Issues

```bash
# Check container logs
docker logs autossh-proxy

# Test SSH connection manually
docker exec -it autossh-proxy ssh -vvv -F /root/.ssh/config target

# Verify authentication method priority
docker exec autossh-proxy cat /root/.ssh/config
```

### Common Problems

1. **"All authentication methods failed"**
   - Verify credentials are correctly base64 encoded
   - Check SSH server configuration
   - Ensure user exists on target server

2. **"Connection refused"**
   - Verify SSH_HOST and SSH_PORT
   - Check firewall rules
   - Ensure SSH service is running

3. **"Permission denied"**
   - Verify SSH_USER exists on target server
   - Check SSH key permissions
   - Verify certificate is properly signed

4. **Health check failing**
   - Verify SOCKS5 proxy is accessible
   - Check if target server allows outbound connections
   - Ensure ifconfig.io is reachable from target server

## Technical Details

- **Base Image**: Alpine Linux (minimal footprint)
- **SSH Client**: OpenSSH
- **AutoSSH**: Automatic SSH tunnel recovery
- **Architecture**: Multi-arch support (amd64, arm64)
- **SSH Settings**:
  - ServerAliveInterval: 10 seconds
  - ServerAliveCountMax: 3 attempts
  - ConnectTimeout: 5 seconds

## License

This project is open source. Feel free to use, modify, and distribute.

## Contributing

Issues and pull requests are welcome at the project repository.