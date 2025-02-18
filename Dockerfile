# Build stage
FROM php:8.3-fpm-alpine AS builder

# Install build dependencies
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    gcc \
    g++ \
    make \
    libxml2-dev \
    oniguruma-dev \
    openldap-dev \
    libzip-dev \
    freetype-dev \
    libpng-dev \
    libjpeg-turbo-dev

# Install and configure PHP extensions
RUN set -ex; \
    # Configure extensions
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    # Install extensions one by one to prevent memory issues
    docker-php-ext-install mysqli && \
    docker-php-ext-install pdo_mysql && \
    docker-php-ext-install bcmath && \
    docker-php-ext-install mbstring && \
    docker-php-ext-install exif && \
    docker-php-ext-install pcntl && \
    docker-php-ext-install opcache && \
    docker-php-ext-install ldap && \
    docker-php-ext-install zip && \
    docker-php-ext-install gd && \
    rm -rf /tmp/* /var/cache/apk/*

# Production stage
FROM php:8.3-fpm-alpine

# Add tini
RUN apk add --no-cache tini

# Add production dependencies
RUN apk add --no-cache \
    nginx \
    mysql-client \
    supervisor \
    freetype \
    libpng \
    libjpeg-turbo \
    libzip \
    openldap \
    icu-libs && \
    rm -rf /var/cache/apk/* /tmp/*

# Copy built extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Add non-root user
ARG PUID=1000
ARG PGID=1000
RUN set -ex; \
    # Modify existing www-data user/group
    deluser www-data; \
    addgroup -g ${PGID} www-data; \
    adduser -u ${PUID} -G www-data -h /home/www-data -s /bin/sh -D www-data; \
    # Create required directories
    mkdir -p /var/www/html/userfiles \
            /var/www/html/public/userfiles \
            /var/www/html/storage/logs \
            /var/www/html/app/Plugins \
            /run /var/log/nginx /var/lib/nginx; \
    chown -R www-data:www-data /var/www/html /run /var/log/nginx /var/lib/nginx && \
    chmod 775 /var/www/html/userfiles /var/www/html/public/userfiles /var/www/html/storage/logs /var/www/html/app/Plugins

# Set working directory
WORKDIR /var/www/html

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Copy configuration files
COPY config/custom.ini /usr/local/etc/php/conf.d/
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Install Leantime
ARG LEAN_VERSION=3.4.0
RUN set -ex; \
    curl -fsSL --retry 3 https://github.com/Leantime/leantime/releases/download/v${LEAN_VERSION}/Leantime-v${LEAN_VERSION}.tar.gz -o leantime.tar.gz && \
    tar xzf leantime.tar.gz --strip-components 1 && \
    rm leantime.tar.gz && \
    chown -R www-data:www-data .

# Switch to non-root user
USER www-data

EXPOSE 80
ENTRYPOINT ["/sbin/tini", "--", "/start.sh"]
