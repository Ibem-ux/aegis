# Build stage
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

# Install build tools required for native C++ compilation (better-sqlite3, sharp, etc.)
RUN apk add --no-cache python3 make g++ gcc

COPY package*.json ./
COPY tsconfig.json ./

RUN npm ci

COPY src ./src

RUN npm run build

# Remove devDependencies to keep the production node_modules small
RUN npm prune --production

# Production stage
FROM node:20-alpine

WORKDIR /usr/src/app

# Install postgresql-client for pg_dump backups and openssl for JWT key generation
RUN apk add --no-cache postgresql-client openssl

COPY package*.json ./

# Copy compiled files and pruned node_modules from the builder stage
COPY --from=builder /usr/src/app/dist ./dist
COPY --from=builder /usr/src/app/node_modules ./node_modules

# Copy the entrypoint script and convert line endings from CRLF (Windows) to LF (Linux)
COPY docker-entrypoint.sh ./
RUN sed -i 's/\r$//' docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

# Create directories for persistent data
RUN mkdir -p keys uploads data backups

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["node", "dist/server.js"]
