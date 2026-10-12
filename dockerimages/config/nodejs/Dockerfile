FROM node:22-bookworm

LABEL org.opencontainers.image.authors="Sergiu Ro. <sergiu.ro@magentofullstack.dev>"
LABEL org.opencontainers.image.source="https://magentofullstack.dev"
LABEL org.opencontainers.image.title="magento-docker-bootstrap / nodejs"
LABEL org.opencontainers.image.licenses="MIT"

ARG USER_UID=1000
ARG USER_GID=1000
ARG SITE_HOST=magento.local
ARG SITE_NAME=Magento

RUN apt-get update && apt-get install -y --no-install-recommends git bash \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /bin/bash /bin/sh

# Remap the node user to the host UID/GID so files written by frontend
# tooling into httpdocs/ belong to the host user. `-o` tolerates ids that
# already exist in the image (macOS gid 20).
RUN set -eux; \
    groupmod -o -g "${USER_GID}" node; \
    usermod -o -u "${USER_UID}" -g "${USER_GID}" node; \
    chown -R node:node /home/node; \
    id node

WORKDIR /var/www/html
USER node:node

CMD ["tail", "-f", "/dev/null"]
