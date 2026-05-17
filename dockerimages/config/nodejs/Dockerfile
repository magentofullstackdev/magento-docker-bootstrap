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

WORKDIR /var/www/html
USER node:node

CMD ["tail", "-f", "/dev/null"]
