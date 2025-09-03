# Dockerized dmarc-srg

[![Build Status](https://github.com/h3po/docker-dmarc-srg/actions/workflows/docker-image.yml/badge.svg)](https://github.com/h3po/docker-dmarc-srg/actions/workflows/docker-image.yml)

This is just a simple dockerfile plus github workflow to create a docker image for [liuch/dmarc-srg](https://github.com/liuch/dmarc-srg)  

Also check out my prometheus exporter: [h3po/prometheus-dmarc_srg_exporter](https://github.com/h3po/prometheus-dmarc_srg_exporter)

## Running the dmarc-srg container

create a docker network for dmarc-srg and its database
```bash
docker network create dmarc-srg
```

create the database container
```bash
docker run -d --name dmarc-srg-mariadb \
  --net dmarc-srg \
  -v dmarc-srg-mariadb:/var/lib/mysql \
  -e MARIADB_ROOT_PASSWORD=password \
  -e MARIADB_DATABASE=dmarc-srg \
  -e MARIADB_AUTO_UPGRADE=1 \
  mariadb
```

create the dmarc-srg container
```bash
docker run -d --name dmarc-srg \
  --hostname $(hostname -f) \
  --net dmarc-srg \
  -v dmarc-srg-config:/var/www/html/config \
  ghcr.io/h3po/dmarc-srg:latest
```

edit `conf.php` in the config volume, the database section will be:
```php
$database = [
    'host'         => 'dmarc-srg-mariadb.dmarc-srg',
    'type'         => 'mysql',
    'name'         => 'dmarc-srg',
    'user'         => 'root',
    'password'     => 'password',
    'table_prefix' => ''
];
```

tell dmarc-srg to initialize the database
```bash
docker exec -it dmarc-srg php -f utils/database_admin.php init
```

## Fetch reports

To regularly fetch dmarc reports from an imap mailbox, create a cronjob or systemd timer that runs

```bash
docker exec -t dmarc-srg php utils/fetch_reports.php
```
