FROM php:8.2-cli

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip libpq-dev curl \
    && docker-php-ext-install pdo pdo_pgsql \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /opt

# Pinned to Laravel 10: routes/web.php always present, no install:api
# step needed, predictable directory structure.
#
# Laravel 10 is EOL, so every 10.x framework release carries advisories and
# Composer 2.9+ refuses to install them. This is a local PoC that is never
# exposed, so turn the block off rather than move off the pinned version.
RUN composer config --global policy.advisories.block false \
    && composer create-project --no-interaction --prefer-dist \
        laravel/laravel:^10.0 app

WORKDIR /opt/app

COPY app/Http/Controllers/DutyController.php     app/Http/Controllers/DutyController.php
COPY app/Http/Controllers/ManifestController.php app/Http/Controllers/ManifestController.php
COPY app/Models/                             app/Models/
COPY routes/web.php                          routes/web.php

# IRIS posts without a session token; CSRF verification would reject it.
RUN sed -i 's#\\App\\Http\\Middleware\\VerifyCsrfToken::class,##' app/Http/Kernel.php

RUN php artisan key:generate --no-interaction

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080

CMD ["/usr/local/bin/entrypoint.sh"]
