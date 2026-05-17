# =====================================================================
# PHP-FPM image for Magento / MageOS development.
# Version chosen at build time via PHP_VERSION ARG (default 8.3).
# Includes: composer 2, n98-magerun2, xdebug 3, mhsendmail, ImageMagick,
# bash-completion for n98 + m2install, sudoers for www-data.
# =====================================================================
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-fpm-bookworm
# Re-declared so ${PHP_VERSION} is readable inside RUN steps.
ARG PHP_VERSION

LABEL org.opencontainers.image.authors="Sergiu Ro. <sergiu.ro@magentofullstack.dev>"
LABEL org.opencontainers.image.source="https://magentofullstack.dev"
LABEL org.opencontainers.image.title="magento-docker-bootstrap / php-fpm"
LABEL org.opencontainers.image.description="PHP-FPM image for Magento / MageOS development with Composer, n98-magerun2, Xdebug 3 (zero-config) and ImageMagick."
LABEL org.opencontainers.image.licenses="MIT"

ENV XDEBUG_PORT=9001
ENV MAGENTO_ROOT=/var/www/html
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        apt-utils ca-certificates curl \
        cron git gzip sudo zip unzip vim less \
        mariadb-client \
        rsyslog sendmail sendmail-bin \
        bash-completion \
        libbz2-dev libmcrypt-dev libjpeg62-turbo-dev libonig-dev \
        libwebp-dev libpng-dev libfreetype6-dev libavif-dev libsodium-dev \
        libssh2-1-dev libgmp-dev libmagickwand-dev libmagickcore-dev \
        libc-client-dev libkrb5-dev libicu-dev libldap2-dev \
        libtidy-dev libxslt1-dev libyaml-dev libzip-dev \
        lsof procps \
    && if dpkg --compare-versions "${PHP_VERSION}" lt "8.4"; then \
           apt-get install -y --no-install-recommends libpspell-dev ; \
       fi \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------
# 2. PHP extensions
# ---------------------------------------------------------------------
# pspell was removed from PHP core in 8.4.
RUN set -eux; \
    EXT="bcmath ftp intl mbstring pdo_mysql soap sockets xsl zip"; \
    EXT="$EXT bz2 calendar exif gettext gmp mysqli shmop sysvmsg sysvsem sysvshm tidy pcntl"; \
    if dpkg --compare-versions "${PHP_VERSION}" lt "8.4"; then \
        EXT="$EXT pspell"; \
    fi; \
    docker-php-ext-install -j"$(nproc)" $EXT

# ---------------------------------------------------------------------
# 3. GD / LDAP / opcache
# ---------------------------------------------------------------------
RUN docker-php-ext-configure gd --with-freetype --with-webp --with-jpeg --with-avif \
    && docker-php-ext-install gd

RUN docker-php-ext-configure ldap --with-libdir=lib/$(uname -m)-linux-gnu \
    && docker-php-ext-install ldap

# opcache is statically built into PHP 8.5+ (no separate source / module).
RUN if dpkg --compare-versions "${PHP_VERSION}" lt "8.5"; then \
        docker-php-ext-install opcache ; \
    fi

# ---------------------------------------------------------------------
# 4. PECL extensions
# ---------------------------------------------------------------------
# Note: imagick on PHP 8.3+ requires the github master tarball until a
# stable PECL release lands; we fall back gracefully if pecl install fails.
# `redis` (phpredis) is optional for Magento — without it Magento falls
# back to Predis (pure PHP) — but the C extension is significantly faster
# and is what production stacks usually run, so we install it for parity.
RUN pecl install -o -f igbinary msgpack mailparse oauth yaml redis || true \
    && (pecl install imagick \
        || pecl install imagick-3.7.0 \
        || (curl -sSL https://github.com/Imagick/imagick/archive/refs/heads/master.tar.gz \
            | tar -xz -C /tmp \
            && cd /tmp/imagick-master && phpize && ./configure && make && make install)) \
    && docker-php-ext-enable igbinary msgpack mailparse oauth yaml redis imagick || true

# ---------------------------------------------------------------------
# 5. Xdebug 3 (works with PHP 8.0+; on PHP 8.4 use latest)
# ---------------------------------------------------------------------
RUN pecl channel-update pecl.php.net \
    && pecl install xdebug \
    && docker-php-ext-enable xdebug

# ---------------------------------------------------------------------
# 6. Composer 2 + n98-magerun2 + mhsendmail
# ---------------------------------------------------------------------
# Pin Composer to 2.9 — MageOS requires 2.7+ and recommends 2.9.3+.
COPY --from=composer:2.9 /usr/bin/composer /usr/local/bin/composer

RUN curl -sS -L -o /usr/local/bin/n98-magerun2.phar \
        https://files.magerun.net/n98-magerun2-latest.phar \
    && chmod +x /usr/local/bin/n98-magerun2.phar

RUN curl -sSL -o /usr/local/bin/mhsendmail \
        https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64 \
    && chmod +x /usr/local/bin/mhsendmail

# ---------------------------------------------------------------------
# 7. Bash completion for n98 + m2install
# ---------------------------------------------------------------------
RUN curl -sSL -o /etc/bash_completion.d/n98-magerun2.phar.bash \
        https://raw.githubusercontent.com/netz98/n98-magerun2/master/res/autocompletion/bash/n98-magerun2.phar.bash \
    && curl -sSL -o /etc/bash_completion.d/m2install-bash-completion \
        https://raw.githubusercontent.com/yvoronoy/m2install/master/m2install-bash-completion \
    && echo "source /etc/bash_completion" >> /root/.bashrc \
    && echo "source /etc/bash_completion" >> /var/www/.bashrc.system

# ---------------------------------------------------------------------
# 8. Helper scripts + sudoers + permissions
# ---------------------------------------------------------------------
COPY bin/* /usr/local/bin/
COPY users/.bash_history /var/www/.bash_history
COPY users/env.sample.php /var/www/env.sample.php

RUN chmod +x /usr/local/bin/install.sh /usr/local/bin/user-sudoers \
    && /usr/local/bin/user-sudoers \
    && usermod -a -G root www-data \
    && usermod -u 1000 www-data 2>/dev/null || true \
    && chown -Rf www-data:www-data /var/www \
    && chsh -s /bin/bash www-data

USER root

# Entrypoint that fixes ownership on mounted volumes before php-fpm starts.
# Necessary because Docker named volumes are owned by root:root on first
# creation, but composer runs as www-data inside the container.
COPY bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["php-fpm", "-R"]
