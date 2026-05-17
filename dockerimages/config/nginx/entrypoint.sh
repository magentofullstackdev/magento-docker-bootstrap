#!/usr/bin/env bash
# Picks the correct vhost template based on USE_VARNISH and substitutes
# ${SITE_HOST} / ${SITE_NAME} placeholders.
set -e

USE_VARNISH="${USE_VARNISH:-no}"
SRC_DIR="/etc/nginx/sites-available"
DST="/etc/nginx/conf.d/default.conf"

if [[ "$USE_VARNISH" == "yes" ]] && [[ -f "${SRC_DIR}/with-varnish.conf" ]]; then
    SRC="${SRC_DIR}/with-varnish.conf"
else
    SRC="${SRC_DIR}/direct.conf"
fi

# Substitute SITE_HOST / SITE_NAME — leave $variables nginx itself uses alone.
envsubst '${SITE_HOST} ${SITE_NAME}' < "$SRC" > "$DST"

echo ">> nginx vhost: $(basename "$SRC") → $DST  (SITE_HOST=$SITE_HOST USE_VARNISH=$USE_VARNISH)"
