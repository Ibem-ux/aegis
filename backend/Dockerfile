# Build stage
FROM node:20-alpine AS builder

WORKDIR /usr/src/app

COPY package*.json ./
COPY tsconfig.json ./

RUN npm ci

COPY src ./src

RUN npm run build

# Production stage
FROM node:20-alpine

WORKDIR /usr/src/app

# Install postgresql-client for pg_dump backups and openssl for JWT key generation
RUN apk add --no-cache postgresql-client openssl

COPY package*.json ./

RUN npm ci --only=production

COPY --from=builder /usr/src/app/dist ./dist

# Copy the entrypoint script that auto-generates JWT keys if missing
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Create directories for persistent data
RUN mkdir -p keys uploads data backups

EXPOSE 3000

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["node", "dist/server.js"]
