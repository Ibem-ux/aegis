#!/bin/sh
set -e

# Generate JWT RSA key pair if they don't exist
if [ ! -f keys/private.pem ] || [ ! -f keys/public.pem ]; then
  echo "[entrypoint] JWT keys not found — generating new RSA-2048 key pair..."
  mkdir -p keys
  openssl genrsa -out keys/private.pem 2048
  openssl rsa -in keys/private.pem -pubout -out keys/public.pem
  echo "[entrypoint] JWT keys generated successfully."
else
  echo "[entrypoint] JWT keys found — skipping generation."
fi

# Execute the main command (node dist/server.js)
exec "$@"
