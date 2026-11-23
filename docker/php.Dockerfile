# Imagen PHP 8.3 + Apache compartida por la API (backend/) y el frontend (frontend/).
# TARGET=api -> sirve backend/public ; TARGET=web -> sirve frontend/public
FROM composer:2 AS composer_bin

FROM php:8.3-apache-bookworm AS base
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev libonig-dev libzip-dev libcurl4-openssl-dev unzip \
    && docker-php-ext-install pdo_pgsql mbstring zip \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*
ENV TZ=America/Santiago
RUN printf 'date.timezone=America/Santiago\nupload_max_filesize=5M\npost_max_size=6M\nexpose_php=Off\n' > /usr/local/etc/php/conf.d/canariapp.ini
COPY docker/apache-vhost.conf /etc/apache2/sites-available/000-default.conf

# ---------- API (backend) ----------
FROM base AS api
# pg_dump 16 (misma versión que el servidor) para los respaldos de BackupController
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends postgresql-client-16 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer_bin /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/app
COPY backend/composer.json backend/composer.lock ./
# Reintenta si GitHub/Packagist fallan momentáneamente (p. ej. HTTP 504)
RUN for i in 1 2 3 4; do composer install --no-dev --prefer-dist --no-interaction --no-scripts --no-autoloader && exit 0; sleep $((i*5)); done; exit 1
COPY backend/ ./
RUN composer dump-autoload --no-dev --optimize \
    && mkdir -p storage/logs && chown -R www-data:www-data storage
ENV DOCROOT=/var/www/app/public

# ---------- WEB (frontend del equipo, desde Figma) ----------
FROM base AS web
WORKDIR /var/www/app
COPY frontend/ ./
ENV DOCROOT=/var/www/app/public
