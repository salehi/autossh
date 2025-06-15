#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to cleanup on exit
cleanup() {
    log "Cleaning up..."
    pkill -f autossh || true
    rm -f /tmp/ssh_private_key /tmp/ssh_certificate 2>/dev/null || true
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Validate required environment variables
if [[ -z "$SSH_HOST" ]]; then
    log "ERROR: SSH_HOST environment variable is required"
    exit 1
fi

if [[ -z "$SSH_USER" ]]; then
    log "ERROR: SSH_USER environment variable is required"
    exit 1
fi

# Create SSH config
cat > /root/.ssh/config << EOF
Host target
    HostName ${SSH_HOST}
    Port ${SSH_PORT}
    User ${SSH_USER}
    ServerAliveInterval 10
    ServerAliveCountMax 3
    ConnectTimeout 5
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF



# Function to setup certificate authentication
setup_certificate_auth() {
    if [[ -n "$SSH_PRIVATE_KEY" && -n "$SSH_CERTIFICATE" ]]; then
        log "Setting up certificate authentication..."
        
        # Decode and save private key
        echo "$SSH_PRIVATE_KEY" | base64 -d > /tmp/ssh_private_key
        chmod 600 /tmp/ssh_private_key
        
        # Decode and save certificate
        echo "$SSH_CERTIFICATE" | base64 -d > /tmp/ssh_certificate
        chmod 644 /tmp/ssh_certificate
        
        # Add to SSH config
        cat >> /root/.ssh/config << EOF
    IdentityFile /tmp/ssh_private_key
    CertificateFile /tmp/ssh_certificate
    IdentitiesOnly yes
EOF
        return 0
    fi
    return 1
}

# Function to setup private key authentication
setup_key_auth() {
    if [[ -n "$SSH_PRIVATE_KEY" ]]; then
        log "Setting up private key authentication..."
        
        # Decode and save private key
        echo "$SSH_PRIVATE_KEY" | base64 -d > /tmp/ssh_private_key
        chmod 600 /tmp/ssh_private_key
        
        # Add to SSH config
        cat >> /root/.ssh/config << EOF
    IdentityFile /tmp/ssh_private_key
    IdentitiesOnly yes
EOF
        return 0
    fi
    return 1
}

# Function to setup password authentication
setup_password_auth() {
    if [[ -n "$SSH_PASS" ]]; then
        log "Setting up password authentication..."
        
        # Add to SSH config
        cat >> /root/.ssh/config << EOF
    PasswordAuthentication yes
    PubkeyAuthentication no
    IdentitiesOnly yes
EOF
        
        # Install sshpass for password authentication
        if ! command -v sshpass &> /dev/null; then
            apk add --no-cache sshpass
        fi
        
        return 0
    fi
    return 1
}

# Try authentication methods in priority order
auth_successful=false
auth_method=""

# 1. Certificate authentication (highest priority)
if setup_certificate_auth; then
    auth_successful=true
    auth_method="certificate"
elif setup_key_auth; then
    auth_successful=true
    auth_method="private key"
elif setup_password_auth; then
    auth_successful=true
    auth_method="password"
fi

if [[ "$auth_successful" == "false" ]]; then
    log "ERROR: No authentication method provided"
    exit 1
fi

log "Configured $auth_method authentication"

# Set up AutoSSH environment variables
export AUTOSSH_GATETIME=30
export AUTOSSH_POLL=60
export AUTOSSH_FIRST_POLL=30
export AUTOSSH_PORT=0  # Disable monitoring port

# Build the SSH command based on authentication method
if [[ "$auth_method" == "password" ]]; then
    SSH_CMD="sshpass -e ssh -F /root/.ssh/config"
    export SSHPASS="$SSH_PASS"
else
    SSH_CMD="ssh -F /root/.ssh/config"
fi

# Build the complete AutoSSH command
AUTOSSH_CMD="autossh -M 0 -N -D ${SOCKS_BIND_ADDR}:${SOCKS_BIND_PORT} -o ExitOnForwardFailure=yes"

if [[ "$auth_method" == "password" ]]; then
    AUTOSSH_CMD="$AUTOSSH_CMD -o PasswordAuthentication=yes -o PubkeyAuthentication=no"
fi

AUTOSSH_CMD="$AUTOSSH_CMD target"

log "Starting AutoSSH with SOCKS5 proxy on ${SOCKS_BIND_ADDR}:${SOCKS_BIND_PORT}"
log "Tunneling through $SSH_USER@$SSH_HOST:$SSH_PORT using $auth_method authentication"

# Start AutoSSH
if [[ "$auth_method" == "password" ]]; then
    exec env SSHPASS="$SSH_PASS" $AUTOSSH_CMD
else
    exec $AUTOSSH_CMD
fi
