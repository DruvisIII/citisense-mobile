#!/bin/sh
set -e

PORT="${PORT:-8080}"
sed -i "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf

UPLOADS="${UPLOAD_ROOT:-/var/www/html/uploads}"
mkdir -p "${UPLOADS}/reports"
chown -R www-data:www-data "${UPLOADS}"

exec apache2-foreground
