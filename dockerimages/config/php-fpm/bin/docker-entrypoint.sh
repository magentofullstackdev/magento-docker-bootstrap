#!/usr/bin/env bash
# Fix ownership on mounted volumes that Docker created as root:root.
# Idempotent: only chowns if the directory exists.
set -e

for dir in /var/www/.composer /var/www/html /var/www/db_dumps; do
    if [[ -d "$dir" ]]; then
        chown www-data:www-data "$dir" 2>/dev/null || true
    fi
done

# Hand off to the original CMD
exec "$@"
