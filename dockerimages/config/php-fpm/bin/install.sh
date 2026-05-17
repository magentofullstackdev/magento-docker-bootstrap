#!/usr/bin/env bash
# =====================================================================
# Fresh Magento setup:install — runs only once per checkout (flag file).
# Reads SITE_HOST, MYSQL_*, ADMIN_* from environment (compose sets them).
# =====================================================================
set -euo pipefail

FLAGFILE=/var/www/html/.install-done
cd /var/www/html

if [[ -e "$FLAGFILE" ]]; then
    echo "✓ install already done — delete $FLAGFILE to re-run"
    exit 0
fi

if [[ ! -f composer.json ]]; then
    echo "✗ /var/www/html has no composer.json — drop your Magento codebase here first." >&2
    exit 1
fi

echo ">> composer install"
composer install --no-interaction

echo ">> bin/magento setup:install"
php -d memory_limit=-1 bin/magento setup:install \
    --base-url="https://${SITE_HOST}/" \
    --base-url-secure="https://${SITE_HOST}/" \
    --db-host=db \
    --db-name="${MYSQL_DATABASE}" \
    --db-user="${MYSQL_USER}" \
    --db-password="${MYSQL_PASSWORD}" \
    --admin-firstname="${ADMIN_FIRSTNAME:-Admin}" \
    --admin-lastname="${ADMIN_LASTNAME:-User}" \
    --admin-email="${ADMIN_EMAIL}" \
    --admin-user="${ADMIN_USER:-admin}" \
    --admin-password="${ADMIN_PASSWORD:-admin123}" \
    --backend-frontname=admin \
    --currency=EUR \
    --timezone=Europe/Rome \
    --use-rewrites=1 \
    --search-engine=opensearch \
    --opensearch-host=opensearch \
    --opensearch-port=9200 \
    --opensearch-enable-auth=0 \
    --session-save=redis \
    --session-save-redis-host=redis \
    --session-save-redis-port=6379 \
    --session-save-redis-db=2 \
    --cache-backend=redis \
    --cache-backend-redis-server=redis \
    --cache-backend-redis-db=0 \
    --page-cache=redis \
    --page-cache-redis-server=redis \
    --page-cache-redis-db=1 \
    --cleanup-database

bin/magento deploy:mode:set developer
bin/magento module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth || true
bin/magento setup:upgrade
bin/magento cache:flush

touch "$FLAGFILE"
echo "✓ Magento installed. Visit https://${SITE_HOST}/  (admin: ${ADMIN_USER:-admin} / ${ADMIN_PASSWORD:-admin123})"
