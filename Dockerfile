FROM php:7.3-fpm-alpine AS php-base

RUN apk add --no-cache \
        git \
    ;

RUN set -eux; \
	apk add --no-cache --virtual .build-deps \
		$PHPIZE_DEPS \
		icu-dev \
    ; \
    docker-php-ext-install -j$(nproc) \
        intl \
        pdo_mysql \
        bcmath \
    ; \
    pecl install \
        apcu \
        redis \
    ; \
    pecl clear-cache; \
    docker-php-ext-enable \
        apcu \
        opcache \
        redis \
    ; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .api-phpexts-rundeps $runDeps; \
    apk del .build-deps

RUN ln -s $PHP_INI_DIR/php.ini-production $PHP_INI_DIR/php.ini
COPY php/conf.d/90-overrides.ini $PHP_INI_DIR/conf.d/90-overrides.ini

RUN sed -i 's/^\;ping/ping/' /usr/local/etc/php-fpm.d/www.conf

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1
# install Symfony Flex globally to speed up download of Composer packages (parallelized prefetching)
RUN set -eux; \
	composer global require "symfony/flex" --prefer-dist --no-progress --no-suggest --classmap-authoritative; \
	composer clear-cache
ENV PATH="${PATH}:/root/.composer/vendor/bin"

WORKDIR /srv/api

CMD ["php-fpm"]

FROM php-base as php-prod

COPY php/conf.d/91-overrides-prod.ini $PHP_INI_DIR/conf.d/91-overrides-prod.ini

FROM php-base AS php-dev

ARG XDEBUG_VERSION=2.7.2
RUN set -eux; \
	apk add --no-cache --virtual .build-deps $PHPIZE_DEPS; \
	apk add nano; \
	pecl install xdebug-$XDEBUG_VERSION; \
	docker-php-ext-enable xdebug; \
	apk del .build-deps

RUN ln -fs $PHP_INI_DIR/php.ini-development $PHP_INI_DIR/php.ini
COPY php/conf.d/91-overrides-dev.ini $PHP_INI_DIR/conf.d/91-overrides-dev.ini

CMD ["php-fpm"]
