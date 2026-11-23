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
# pg_dump / psql 16 (misma versión que el servidor) + cron para respaldos cada 48 h
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates cron \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends postgresql-client-16 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer_bin /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/app
COPY backend/composer.json backend/composer.lock ./
# Reintenta si GitHub/Packagist fallan momentáneamente (p. ej. HTTP 504)
RUN for i in 1 2 3 4; do composer install --no-dev --prefer-dist --no-interaction --no-scripts --no-autoloader && exit 0; sleep $((i*5)); done; exit 1
COPY backend/ ./
RUN composer dump-autoload --no-dev --optimize \
    && mkdir -p storage/logs storage/backups \
    && chown -R www-data:www-data storage \
    && printf 'SHELL=/bin/sh\nPATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin\n0 3 */2 * * www-data . /etc/canariapp.env && /usr/local/bin/php /var/www/app/bin/auto_backup.php >> /var/www/app/storage/logs/auto_backup.log 2>&1\n' > /etc/cron.d/canariapp-backup \
    && chmod 0644 /etc/cron.d/canariapp-backup
ENV DOCROOT=/var/www/app/public
CMD ["sh", "-c", "mkdir -p /var/www/app/storage/logs /var/www/app/storage/backups && chown -R www-data:www-data /var/www/app/storage && printenv | grep -E '^(DB_|APP_|TZ)' | sed \"s/'/'\\\\''/g; s/=\\(.*\\)/='\\1'/; s/^/export /\" > /etc/canariapp.env && chown root:www-data /etc/canariapp.env && chmod 0640 /etc/canariapp.env && cron && exec apache2-foreground"]

# ---------- WEB (frontend del equipo, desde Figma) ----------
FROM base AS web
WORKDIR /var/www/app
COPY frontend/ ./
ENV DOCROOT=/var/www/app/public