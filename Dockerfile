FROM php:apache

ARG DMARC_SRG_VERSION=v2.3
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /var/www/html
ADD https://github.com/liuch/dmarc-srg/archive/refs/tags/${DMARC_SRG_VERSION}.tar.gz /var/www/html/

RUN \
    apt-get update && \
    apt-get install -y \
        curl \
        libzip-dev

RUN docker-php-ext-install pdo pdo_mysql zip

RUN \
    tar xzf ${DMARC_SRG_VERSION}.tar.gz --strip-components 1 \
    && rm ${DMARC_SRG_VERSION}.tar.gz \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && ls -al . \
    && composer install --no-dev --optimize-autoloader

RUN \
    sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/html/public|' /etc/apache2/sites-available/000-default.conf \
    && sed -i 's|<Directory /var/www/>|<Directory /var/www/html/public>|' /etc/apache2/apache2.conf \
    && sed -i 's|<Directory /var/www/>|<Directory /var/www/html/public>|' /etc/apache2/conf-enabled/docker-php.conf \
    && rm -rf /tmp/* /var/cache/* /var/lib/apt/lists/*
