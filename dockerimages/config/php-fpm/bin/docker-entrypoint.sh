#!/usr/bin/env bash
# Fix ownership on the named volume Docker created as root:root. Bind
# mounts (/var/www/html, /var/www/db_dumps) are deliberately left alone:
# www-data is built with the host UID/GID, so they already match, and
# chowning them would rewrite ownership on the host.
set -e

if [[ -d /var/www/.composer ]]; then
    chown www-data:www-data /var/www/.composer 2>/dev/null || true
fi

# Hand off to the original CMD
exec "$@"
