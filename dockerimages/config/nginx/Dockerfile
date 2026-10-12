FROM nginx:1.30-alpine

LABEL org.opencontainers.image.authors="Sergiu Ro. <sergiu.ro@magentofullstack.dev>"
LABEL org.opencontainers.image.source="https://magentofullstack.dev"
LABEL org.opencontainers.image.title="magento-docker-bootstrap / nginx"
LABEL org.opencontainers.image.licenses="MIT"

ARG SITE_HOST=magento.local
ARG SITE_NAME=Magento
# Host UID/GID for the nginx worker user, so static files in httpdocs/ are
# read with the same identity that owns them on the host (works with a
# restrictive umask too). The master process stays root.
ARG USER_UID=1000
ARG USER_GID=1000

ENV SITE_HOST=${SITE_HOST}
ENV SITE_NAME=${SITE_NAME}

EXPOSE 80 443

RUN apk add --no-cache openssl gettext bash

# Remap the nginx user/group in place (busybox has no usermod -o; editing
# passwd/group directly tolerates an id that already exists, e.g. gid 20).
RUN set -eux; \
    sed -i "s/^nginx:x:[0-9]*:[0-9]*:/nginx:x:${USER_UID}:${USER_GID}:/" /etc/passwd; \
    sed -i "s/^nginx:x:[0-9]*:/nginx:x:${USER_GID}:/" /etc/group; \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx; \
    id nginx

# Self-signed certificate so https://SITE_HOST works out of the box.
RUN mkdir -p /etc/nginx/certs/magento_site/ \
    && openssl req \
        -subj "/CN=${SITE_HOST}/O=${SITE_NAME}/C=US" \
        -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 \
        -keyout /etc/nginx/certs/magento_site/server.key \
        -out    /etc/nginx/certs/magento_site/server.crt

# Substitute env vars into vhost template at container start, then run nginx.
COPY entrypoint.sh /docker-entrypoint.d/40-render-vhost.sh
RUN chmod +x /docker-entrypoint.d/40-render-vhost.sh

USER root
CMD ["nginx", "-g", "daemon off;"]
