ARG DMARC_SRG_VERSION=v2.3

# Composer deps in their own stage; composer never lands in the final image.
# --ignore-platform-reqs: extensions exist only in the runtime image.
FROM composer:2 AS vendor
ARG DMARC_SRG_VERSION
WORKDIR /app
ADD https://github.com/liuch/dmarc-srg/archive/refs/tags/${DMARC_SRG_VERSION}.tar.gz /app/src.tar.gz
RUN tar xzf src.tar.gz --strip-components=1 && rm src.tar.gz \
    && composer install --no-dev --no-interaction --no-progress --ignore-platform-reqs

# PHP extension build stage. php:8-apache-trixie floats to the newest PHP 8,
# so the weekly CI rebuild picks up security releases (cf. --pull in CI).
FROM php:8-apache-trixie AS php-ext
ENV DEBIAN_FRONTEND=noninteractive
# pkg-config: required on trixie, zip's configure cannot find libzip without it.
# libssl-dev/libpam0g-dev: deps of the bookworm c-client -dev deb installed below.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        pkg-config libzip-dev libkrb5-dev libssl-dev libpam0g-dev \
        sgml-base libpam-modules libkrb5-3 libgssapi-krb5-2 && \
    rm -rf /var/lib/apt/lists/*
RUN docker-php-ext-install pdo_mysql zip

# ext-imap: required by dmarc-srg v2.3 for mailbox fetching (ImapEngine only
# arrives with 3.0). PHP >= 8.4 dropped the imap build files -> install via
# PIE (sirlouen/imap PECL fork); trixie dropped c-client/mlock -> fetch the
# last bookworm debs (arch resolves natively in the emulated build container,
# so the arm64 matrix is intact). See HANDOVER.md.
RUN set -eux; \
    mkdir -p /tmp/cclient && cd /tmp/cclient; \
    printf 'deb http://deb.debian.org/debian bookworm main\n' > /etc/apt/sources.list.d/bookworm.list; \
    apt-get update -qq; \
    apt-get download -t bookworm libc-client2007e libc-client2007e-dev mlock; \
    dpkg -i libc-client2007e_*.deb libc-client2007e-dev_*.deb mlock_*.deb; \
    rm /etc/apt/sources.list.d/bookworm.list; rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/php/pie:bin /pie /usr/local/bin/pie
RUN pie install --skip-enable-extension sirlouen/imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-enable imap

# Runtime stage: build tools stay behind; no autoremove step to trip over.
# libzip5 + the rest are runtime libs of the copied extensions / c-client.
FROM php:8-apache-trixie
ARG DMARC_SRG_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libzip5 sgml-base libpam-modules libkrb5-3 libgssapi-krb5-2 && \
    rm -rf /var/lib/apt/lists/*
COPY --from=php-ext /tmp/cclient/libc-client2007e_*.deb /tmp/cclient/mlock_*.deb /tmp/cclient/
RUN dpkg -i /tmp/cclient/*.deb && rm -rf /tmp/cclient
COPY --from=php-ext /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# App stays at /var/www/html so existing config volumes keep working.
WORKDIR /var/www/html
ADD https://github.com/liuch/dmarc-srg/archive/refs/tags/${DMARC_SRG_VERSION}.tar.gz /var/www/html/src.tar.gz
RUN tar xzf src.tar.gz --strip-components=1 && rm src.tar.gz

# Downstream hotfixes (see the preambles inside patches/). Fail the build if
# one no longer applies: that means upstream has absorbed the fix (move to a
# newer release) or moved the code and the patch needs review.
COPY patches/ /tmp/patches/
RUN set -eu; \
    cd /var/www/html; \
    for p in /tmp/patches/*.patch; do \
        echo "applying $(basename "$p")"; \
        patch -p1 --no-backup-if-mismatch -i "$p"; \
    done; \
    rm -rf /tmp/patches; \
    php -l classes/Report/ReportData.php > /dev/null
COPY --from=vendor /app/vendor /var/www/html/vendor

# Serve public/ only; the stock <Directory /var/www/> block covers access.
RUN sed -ri 's|^(\s*)DocumentRoot .*|\1DocumentRoot /var/www/html/public|' \
        /etc/apache2/sites-available/000-default.conf \
    && a2enmod rewrite \
    && chown -R www-data:www-data /var/www/html/config

EXPOSE 80
