FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    autossh \
    openssh-client \
    curl \
    bash

# Create ssh directory
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment variables with defaults (non-sensitive only)
ENV SSH_PORT="22"
ENV SOCKS_BIND_ADDR="0.0.0.0"
ENV SOCKS_BIND_PORT="1080"

# Expose SOCKS5 port
EXPOSE 1080

# Health check - test SOCKS5 proxy by calling ifconfig.io through it
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl --socks5 ${SOCKS_BIND_ADDR}:${SOCKS_BIND_PORT} --max-time 10 -s ifconfig.io > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
