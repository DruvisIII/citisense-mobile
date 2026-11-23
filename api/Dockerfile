# CitiSense PHP API for Railway.
# Railway builds this automatically when the service's Root Directory is "api".
FROM php:8.3-apache

# mysqli for the database; curl, fileinfo and openssl ship with the base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip git \
    && docker-php-ext-install mysqli \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY docker/php.ini /usr/local/etc/php/conf.d/citisense.ini

WORKDIR /var/www/html

# Install PHPMailer and google/auth first so code edits don't redo this step.
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts

COPY . .
RUN composer dump-autoload --optimize --no-dev \
    && mkdir -p uploads/reports \
    && chown -R www-data:www-data uploads

# Railway sends traffic to $PORT. Volumes mount as root, so hand the
# uploads folder to Apache's user before starting.
COPY docker/start.sh /usr/local/bin/citisense-start
RUN chmod +x /usr/local/bin/citisense-start
CMD ["citisense-start"]
