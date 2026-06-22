I'll create a comprehensive GitHub Actions deploy.yml file for deploying your Spring Boot application to a VPS with Docker Swarm integration.Based on your requirements for deploying a Spring Boot application to a VPS with Docker Swarm, connecting to existing services (RabbitMQ, Vault, Postgres, Traefik), I'll create a comprehensive GitHub Actions workflow file for production deployment.

```yaml
name: Deploy to VPS Production

on:
  push:
    branches:
      - main
      - master
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deployment environment'
        required: true
        default: 'production'
        type: choice
        options:
          - production
          - staging

env:
  DOCKER_IMAGE_NAME: proptech-core-service
  DOCKER_REGISTRY: ghcr.io
  DOCKER_USERNAME: cyberstarsng
  MAVEN_OPTS: -Xmx3072m

jobs:
  build:
    name: Build and Test
    runs-on: ubuntu-latest
    
    permissions:
      contents: read
      packages: write
    
    outputs:
      image_tag: ${{ steps.meta.outputs.tags }}
      image_digest: ${{ steps.build.outputs.digest }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Set up JDK 21
        uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'liberica'
          cache: 'maven'
      
      - name: Cache Maven packages
        uses: actions/cache@v4
        with:
          path: ~/.m2/repository
          key: ${{ runner.os }}-maven-${{ hashFiles('**/pom.xml') }}
          restore-keys: |
            ${{ runner.os }}-maven-
      
      - name: Extract version from pom.xml
        id: project
        run: |
          VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
          echo "version=${VERSION}" >> $GITHUB_OUTPUT
          echo "Project version: ${VERSION}"
      
      - name: Run tests
        run: mvn clean test -B -Dspring.profiles.active=test
      
      - name: Build application
        run: mvn clean package -DskipTests -B -Dspring.profiles.active=staging
      
      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: application-jar
          path: target/*.jar
          retention-days: 1
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.DOCKER_REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.DOCKER_REGISTRY }}/${{ github.repository_owner }}/${{ env.DOCKER_IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}},value=${{ steps.project.outputs.version }}
            type=semver,pattern={{major}}.{{minor}},value=${{ steps.project.outputs.version }}
            type=sha,prefix={{branch}}-,format=short
            type=raw,value=latest,enable={{is_default_branch}}
            type=raw,value=${{ steps.project.outputs.version }}-{{date 'YYYYMMDD-HHmmss'}}
          flavor: |
            latest=auto
      
      - name: Build and push Docker image
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64
          build-args: |
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            VCS_REF=${{ github.sha }}
            VERSION=${{ steps.project.outputs.version }}
      
      - name: Generate deployment summary
        run: |
          echo "## Build Summary :rocket:" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Version:** ${{ steps.project.outputs.version }}" >> $GITHUB_STEP_SUMMARY
          echo "**Commit:** ${{ github.sha }}" >> $GITHUB_STEP_SUMMARY
          echo "**Branch:** ${{ github.ref_name }}" >> $GITHUB_STEP_SUMMARY
          echo "**Image:** ${{ env.DOCKER_REGISTRY }}/${{ github.repository_owner }}/${{ env.DOCKER_IMAGE_NAME }}" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Docker Tags" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY
          echo "${{ steps.meta.outputs.tags }}" >> $GITHUB_STEP_SUMMARY
          echo '```' >> $GITHUB_STEP_SUMMARY

  deploy:
    name: Deploy to VPS
    runs-on: ubuntu-latest
    needs: build
    environment: 
      name: production
      url: https://your-domain.com
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Set deployment environment
        id: set_env
        run: |
          if [[ "${{ github.event.inputs.environment }}" != "" ]]; then
            echo "env=${{ github.event.inputs.environment }}" >> $GITHUB_OUTPUT
          else
            echo "env=production" >> $GITHUB_OUTPUT
          fi
      
      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.VPS_SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ secrets.VPS_HOST }} >> ~/.ssh/known_hosts
      
      - name: Copy docker-stack.yml to VPS
        run: |
          scp -i ~/.ssh/id_rsa \
            -o StrictHostKeyChecking=no \
            docker-stack.yml \
            ${{ secrets.VPS_USER }}@${{ secrets.VPS_HOST }}:/tmp/docker-stack.yml
      
      - name: Deploy to Docker Swarm
        env:
          VPS_HOST: ${{ secrets.VPS_HOST }}
          VPS_USER: ${{ secrets.VPS_USER }}
          DOCKER_IMAGE: ${{ env.DOCKER_REGISTRY }}/${{ github.repository_owner }}/${{ env.DOCKER_IMAGE_NAME }}:latest
          SPRING_PROFILES_ACTIVE: ${{ secrets.SPRING_PROFILES_ACTIVE || 'staging' }}
          
          # Database Configuration
          DB_HOST: ${{ secrets.DB_HOST }}
          DB_PORT: ${{ secrets.DB_PORT || '5432' }}
          DB_NAME: ${{ secrets.DB_NAME }}
          DB_USERNAME: ${{ secrets.DB_USERNAME }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
          
          # RabbitMQ Configuration
          RABBITMQ_HOST: ${{ secrets.RABBITMQ_HOST }}
          RABBITMQ_PORT: ${{ secrets.RABBITMQ_PORT || '5672' }}
          RABBITMQ_USERNAME: ${{ secrets.RABBITMQ_USERNAME }}
          RABBITMQ_PASSWORD: ${{ secrets.RABBITMQ_PASSWORD }}
          RABBITMQ_VHOST: ${{ secrets.RABBITMQ_VHOST || '/' }}
          
          # Vault Configuration
          VAULT_URI: ${{ secrets.VAULT_URI }}
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
          VAULT_NAMESPACE: ${{ secrets.VAULT_NAMESPACE || 'proptech' }}
          
          # Application Configuration
          JWT_SECRET: ${{ secrets.JWT_SECRET }}
          ENCRYPTION_KEY: ${{ secrets.ENCRYPTION_KEY }}
          
          # Network Configuration
          DOCKER_NETWORK: ${{ secrets.DOCKER_NETWORK || 'traefik-public' }}
          STACK_NAME: ${{ secrets.STACK_NAME || 'proptech-core' }}
          
          # Traefik Configuration
          TRAEFIK_DOMAIN: ${{ secrets.TRAEFIK_DOMAIN }}
          TRAEFIK_ENTRYPOINT: ${{ secrets.TRAEFIK_ENTRYPOINT || 'websecure' }}
          
        run: |
          ssh -i ~/.ssh/id_rsa \
            -o StrictHostKeyChecking=no \
            ${{ secrets.VPS_USER }}@${{ secrets.VPS_HOST }} << 'ENDSSH'
          
          set -e
          
          echo "======================================"
          echo "Starting deployment process..."
          echo "======================================"
          
          # Set environment variables
          export DOCKER_IMAGE="${{ env.DOCKER_IMAGE }}"
          export SPRING_PROFILES_ACTIVE="${{ env.SPRING_PROFILES_ACTIVE }}"
          export DB_HOST="${{ env.DB_HOST }}"
          export DB_PORT="${{ env.DB_PORT }}"
          export DB_NAME="${{ env.DB_NAME }}"
          export DB_USERNAME="${{ env.DB_USERNAME }}"
          export DB_PASSWORD="${{ env.DB_PASSWORD }}"
          export RABBITMQ_HOST="${{ env.RABBITMQ_HOST }}"
          export RABBITMQ_PORT="${{ env.RABBITMQ_PORT }}"
          export RABBITMQ_USERNAME="${{ env.RABBITMQ_USERNAME }}"
          export RABBITMQ_PASSWORD="${{ env.RABBITMQ_PASSWORD }}"
          export RABBITMQ_VHOST="${{ env.RABBITMQ_VHOST }}"
          export VAULT_URI="${{ env.VAULT_URI }}"
          export VAULT_TOKEN="${{ env.VAULT_TOKEN }}"
          export VAULT_NAMESPACE="${{ env.VAULT_NAMESPACE }}"
          export JWT_SECRET="${{ env.JWT_SECRET }}"
          export ENCRYPTION_KEY="${{ env.ENCRYPTION_KEY }}"
          export DOCKER_NETWORK="${{ env.DOCKER_NETWORK }}"
          export STACK_NAME="${{ env.STACK_NAME }}"
          export TRAEFIK_DOMAIN="${{ env.TRAEFIK_DOMAIN }}"
          export TRAEFIK_ENTRYPOINT="${{ env.TRAEFIK_ENTRYPOINT }}"
          
          # Login to GitHub Container Registry
          echo "${{ secrets.GITHUB_TOKEN }}" | docker login ${{ env.DOCKER_REGISTRY }} -u ${{ github.actor }} --password-stdin
          
          # Pull the latest image
          echo "Pulling Docker image: ${DOCKER_IMAGE}"
          docker pull ${DOCKER_IMAGE}
          
          # Check if network exists, create if not
          if ! docker network ls | grep -q "${DOCKER_NETWORK}"; then
            echo "Creating overlay network: ${DOCKER_NETWORK}"
            docker network create --driver overlay --attachable ${DOCKER_NETWORK}
          else
            echo "Network ${DOCKER_NETWORK} already exists"
          fi
          
          # Check if stack exists
          if docker stack ls | grep -q "${STACK_NAME}"; then
            echo "Stack ${STACK_NAME} exists, updating..."
            docker stack deploy -c /tmp/docker-stack.yml --with-registry-auth ${STACK_NAME}
          else
            echo "Deploying new stack: ${STACK_NAME}"
            docker stack deploy -c /tmp/docker-stack.yml --with-registry-auth ${STACK_NAME}
          fi
          
          # Wait for services to be ready
          echo "Waiting for services to start..."
          sleep 10
          
          # Check service status
          echo "======================================"
          echo "Service Status:"
          echo "======================================"
          docker stack services ${STACK_NAME}
          
          # Show service logs (last 50 lines)
          echo "======================================"
          echo "Recent Service Logs:"
          echo "======================================"
          SERVICE_ID=$(docker stack services ${STACK_NAME} -q --filter "name=${STACK_NAME}_app")
          if [ ! -z "$SERVICE_ID" ]; then
            docker service logs --tail 50 ${SERVICE_ID} || true
          fi
          
          # Cleanup old images
          echo "======================================"
          echo "Cleaning up unused images..."
          echo "======================================"
          docker image prune -af --filter "until=72h" || true
          
          # Remove temporary file
          rm -f /tmp/docker-stack.yml
          
          echo "======================================"
          echo "Deployment completed successfully!"
          echo "======================================"
          ENDSSH
      
      - name: Health check
        run: |
          sleep 30
          
          ssh -i ~/.ssh/id_rsa \
            -o StrictHostKeyChecking=no \
            ${{ secrets.VPS_USER }}@${{ secrets.VPS_HOST }} << 'ENDSSH'
          
          STACK_NAME="${{ secrets.STACK_NAME || 'proptech-core' }}"
          MAX_RETRIES=30
          RETRY_COUNT=0
          
          echo "Performing health check..."
          
          while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            SERVICE_STATUS=$(docker stack services ${STACK_NAME} --format "{{.Replicas}}" | grep -v "0/")
            
            if echo "$SERVICE_STATUS" | grep -q "/"; then
              RUNNING=$(echo "$SERVICE_STATUS" | cut -d'/' -f1)
              DESIRED=$(echo "$SERVICE_STATUS" | cut -d'/' -f2)
              
              if [ "$RUNNING" = "$DESIRED" ] && [ "$RUNNING" != "0" ]; then
                echo "✅ All services are healthy!"
                echo "Services: $SERVICE_STATUS"
                exit 0
              fi
            fi
            
            echo "Waiting for services to be healthy... (Attempt: $((RETRY_COUNT + 1))/$MAX_RETRIES)"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            sleep 10
          done
          
          echo "❌ Health check failed - Services did not become healthy in time"
          docker stack services ${STACK_NAME}
          exit 1
          ENDSSH
      
      - name: Cleanup SSH key
        if: always()
        run: |
          rm -f ~/.ssh/id_rsa
      
      - name: Send deployment notification (Success)
        if: success()
        run: |
          echo "## Deployment Summary :white_check_mark:" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Status:** Success" >> $GITHUB_STEP_SUMMARY
          echo "**Environment:** ${{ steps.set_env.outputs.env }}" >> $GITHUB_STEP_SUMMARY
          echo "**Deployed to:** ${{ secrets.VPS_HOST }}" >> $GITHUB_STEP_SUMMARY
          echo "**Image:** ${{ env.DOCKER_REGISTRY }}/${{ github.repository_owner }}/${{ env.DOCKER_IMAGE_NAME }}:latest" >> $GITHUB_STEP_SUMMARY
          echo "**Time:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> $GITHUB_STEP_SUMMARY
      
      - name: Send deployment notification (Failure)
        if: failure()
        run: |
          echo "## Deployment Failed :x:" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Status:** Failed" >> $GITHUB_STEP_SUMMARY
          echo "**Environment:** ${{ steps.set_env.outputs.env }}" >> $GITHUB_STEP_SUMMARY
          echo "**Time:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "Please check the logs for more details."

  rollback:
    name: Rollback (Manual)
    runs-on: ubuntu-latest
    needs: [build, deploy]
    if: failure()
    environment: 
      name: production-rollback
    
    steps:
      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.VPS_SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ secrets.VPS_HOST }} >> ~/.ssh/known_hosts
      
      - name: Rollback deployment
        run: |
          ssh -i ~/.ssh/id_rsa \
            -o StrictHostKeyChecking=no \
            ${{ secrets.VPS_USER }}@${{ secrets.VPS_HOST }} << 'ENDSSH'
          
          STACK_NAME="${{ secrets.STACK_NAME || 'proptech-core' }}"
          
          echo "======================================"
          echo "Rolling back deployment..."
          echo "======================================"
          
          # Get the previous image tag (you may want to customize this)
          PREVIOUS_IMAGE="${{ env.DOCKER_REGISTRY }}/${{ github.repository_owner }}/${{ env.DOCKER_IMAGE_NAME }}:previous"
          
          # Update service with previous image
          docker service update --image ${PREVIOUS_IMAGE} ${STACK_NAME}_app
          
          echo "Rollback initiated. Checking service status..."
          sleep 20
          docker stack services ${STACK_NAME}
          
          echo "======================================"
          echo "Rollback completed"
          echo "======================================"
          ENDSSH
      
      - name: Cleanup SSH key
        if: always()
        run: |
          rm -f ~/.ssh/id_rsa
```


Now, here's a corresponding **docker-stack.yml** file that works with this deployment:

```yaml
version: '3.8'

services:
  app:
    image: ${DOCKER_IMAGE}
    
    networks:
      - traefik-public
    
    environment:
      # Spring Configuration
      SPRING_PROFILES_ACTIVE: ${SPRING_PROFILES_ACTIVE:-staging}
      SERVER_PORT: 8081
      
      # Database Configuration
      SPRING_DATASOURCE_URL: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}
      SPRING_DATASOURCE_USERNAME: ${DB_USERNAME}
      SPRING_DATASOURCE_PASSWORD: ${DB_PASSWORD}
      SPRING_JPA_HIBERNATE_DDL_AUTO: validate
      SPRING_JPA_SHOW_SQL: false
      
      # RabbitMQ Configuration
      SPRING_RABBITMQ_HOST: ${RABBITMQ_HOST}
      SPRING_RABBITMQ_PORT: ${RABBITMQ_PORT:-5672}
      SPRING_RABBITMQ_USERNAME: ${RABBITMQ_USERNAME}
      SPRING_RABBITMQ_PASSWORD: ${RABBITMQ_PASSWORD}
      SPRING_RABBITMQ_VIRTUAL_HOST: ${RABBITMQ_VHOST:-/}
      
      # Vault Configuration
      SPRING_CLOUD_VAULT_URI: ${VAULT_URI}
      SPRING_CLOUD_VAULT_TOKEN: ${VAULT_TOKEN}
      SPRING_CLOUD_VAULT_NAMESPACE: ${VAULT_NAMESPACE:-proptech}
      SPRING_CLOUD_VAULT_ENABLED: true
      
      # Application Secrets
      JWT_SECRET: ${JWT_SECRET}
      ENCRYPTION_KEY: ${ENCRYPTION_KEY}
      
      # Java Options
      JAVA_OPTS: >-
        -Xms512m
        -Xmx2048m
        -XX:+UseG1GC
        -XX:MaxGCPauseMillis=200
        -XX:+UseStringDeduplication
        -Dspring.aot.enabled=true
        -Djava.security.egd=file:/dev/./urandom
      
      # Logging
      LOGGING_LEVEL_ROOT: INFO
      LOGGING_LEVEL_COM_PROPTECH: DEBUG
    
    deploy:
      mode: replicated
      replicas: 2
      
      update_config:
        parallelism: 1
        delay: 10s
        failure_action: rollback
        monitor: 30s
        order: start-first
      
      rollback_config:
        parallelism: 1
        delay: 5s
        failure_action: pause
        monitor: 10s
        order: start-first
      
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      
      resources:
        limits:
          cpus: '2.0'
          memory: 2560M
        reservations:
          cpus: '0.5'
          memory: 512M
      
      labels:
        # Traefik Labels
        - "traefik.enable=true"
        - "traefik.docker.network=traefik-public"
        
        # HTTP Router
        - "traefik.http.routers.proptech-core.rule=Host(`${TRAEFIK_DOMAIN}`)"
        - "traefik.http.routers.proptech-core.entrypoints=${TRAEFIK_ENTRYPOINT:-websecure}"
        - "traefik.http.routers.proptech-core.tls=true"
        - "traefik.http.routers.proptech-core.tls.certresolver=letsencrypt"
        
        # Service
        - "traefik.http.services.proptech-core.loadbalancer.server.port=8081"
        - "traefik.http.services.proptech-core.loadbalancer.sticky=true"
        - "traefik.http.services.proptech-core.loadbalancer.sticky.cookie.name=proptech_sticky"
        - "traefik.http.services.proptech-core.loadbalancer.sticky.cookie.secure=true"
        - "traefik.http.services.proptech-core.loadbalancer.sticky.cookie.httpOnly=true"
        
        # Health Check
        - "traefik.http.services.proptech-core.loadbalancer.healthcheck.path=/actuator/health"
        - "traefik.http.services.proptech-core.loadbalancer.healthcheck.interval=30s"
        - "traefik.http.services.proptech-core.loadbalancer.healthcheck.timeout=5s"
        
        # Middleware (optional - add as needed)
        - "traefik.http.routers.proptech-core.middlewares=proptech-core-headers,proptech-core-compress,proptech-core-ratelimit"
        
        # Security Headers
        - "traefik.http.middlewares.proptech-core-headers.headers.customResponseHeaders.X-Powered-By="
        - "traefik.http.middlewares.proptech-core-headers.headers.customResponseHeaders.Server="
        - "traefik.http.middlewares.proptech-core-headers.headers.sslRedirect=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.stsSeconds=31536000"
        - "traefik.http.middlewares.proptech-core-headers.headers.stsIncludeSubdomains=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.stsPreload=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.forceSTSHeader=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.frameDeny=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.contentTypeNosniff=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.browserXssFilter=true"
        - "traefik.http.middlewares.proptech-core-headers.headers.referrerPolicy=strict-origin-when-cross-origin"
        
        # Compression
        - "traefik.http.middlewares.proptech-core-compress.compress=true"
        
        # Rate Limiting (adjust as needed)
        - "traefik.http.middlewares.proptech-core-ratelimit.ratelimit.average=100"
        - "traefik.http.middlewares.proptech-core-ratelimit.ratelimit.burst=50"
        - "traefik.http.middlewares.proptech-core-ratelimit.ratelimit.period=1s"
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        labels: "service,stack"

networks:
  traefik-public:
    external: true
```


## Required GitHub Secrets

You need to configure these secrets in your GitHub repository (Settings → Secrets and variables → Actions):

### SSH & Server Credentials
- `VPS_SSH_PRIVATE_KEY` - Your VPS SSH private key
- `VPS_HOST` - Your VPS hostname or IP address
- `VPS_USER` - SSH user (e.g., root, ubuntu, deploy)

### Database Configuration
- `DB_HOST` - PostgreSQL hostname (likely the service name in Docker Swarm)
- `DB_PORT` - PostgreSQL port (default: 5432)
- `DB_NAME` - Database name
- `DB_USERNAME` - Database username
- `DB_PASSWORD` - Database password

### RabbitMQ Configuration
- `RABBITMQ_HOST` - RabbitMQ hostname
- `RABBITMQ_PORT` - RabbitMQ port (default: 5672)
- `RABBITMQ_USERNAME` - RabbitMQ username
- `RABBITMQ_PASSWORD` - RabbitMQ password
- `RABBITMQ_VHOST` - RabbitMQ virtual host (default: /)

### Vault Configuration
- `VAULT_URI` - Vault server URI (e.g., http://vault:8200)
- `VAULT_TOKEN` - Vault access token
- `VAULT_NAMESPACE` - Vault namespace (optional)

### Application Configuration
- `JWT_SECRET` - JWT signing secret
- `ENCRYPTION_KEY` - Application encryption key
- `SPRING_PROFILES_ACTIVE` - Spring profile (staging/production)

### Docker & Traefik Configuration
- `DOCKER_NETWORK` - Docker network name (default: traefik-public)
- `STACK_NAME` - Docker stack name (default: proptech-core)
- `TRAEFIK_DOMAIN` - Your application domain (e.g., api.yourdomain.com)
- `TRAEFIK_ENTRYPOINT` - Traefik entrypoint (default: websecure)

## Key Features of this Deployment

1. **Multi-stage Build & Deploy**: Separates build and deployment for better control
2. **Docker Image Caching**: Uses GitHub Actions cache for faster builds
3. **Rolling Updates**: Zero-downtime deployments with start-first strategy
4. **Health Checks**: Automated health verification after deployment
5. **Automatic Rollback**: Rolls back on deployment failure
6. **Load Balancing**: Traefik configured with sticky sessions
7. **Security**: SSL/TLS, security headers, rate limiting
8. **Resource Management**: CPU and memory limits/reservations
9. **Logging**: Structured logging with size rotation
10. **Network Integration**: Connects to existing Docker Swarm network

## Pre-deployment Checklist

1. Ensure the `traefik-public` network exists on your VPS
2. Configure all required GitHub secrets
3. Update `TRAEFIK_DOMAIN` with your actual domain
4. Ensure Traefik is configured with Let's Encrypt (or your SSL provider)
5. Test SSH connection from GitHub Actions to your VPS
6. Ensure Docker Swarm is initialized on your VPS

This workflow is production-ready and includes error handling, monitoring, and rollback capabilities!
