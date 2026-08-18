#!/bin/sh
# Laravel container entrypoint.
#
# PHP CLI ships with variables_order="GPCS" - no "E" - so $_ENV is empty
# and Laravel's env() cannot see container environment variables. It
# falls back to the .env file composer create-project wrote, which sets
# DB_CONNECTION=mysql.
#
# The symptom is a 500 from Eloquent reporting "could not find driver"
# for MySQL on a container carrying only pdo_pgsql: a config precedence
# problem that presents as a missing extension. This writes the database
# settings into .env at boot.
#
# So: project the environment into .env before booting, keeping the
# APP_KEY that was generated at build time.
set -e

cd /opt/app

set_env() {
    key="$1"
    value="$2"
    if grep -q "^${key}=" .env 2>/dev/null; then
        sed -i "s#^${key}=.*#${key}=${value}#" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

set_env DB_CONNECTION "${DB_CONNECTION:-pgsql}"
set_env DB_HOST       "${DB_HOST:-postgres}"
set_env DB_PORT       "${DB_PORT:-5432}"
set_env DB_DATABASE   "${DB_DATABASE:-smk}"
set_env DB_USERNAME   "${DB_USERNAME:-jkdm}"
set_env DB_PASSWORD   "${DB_PASSWORD:-jkdm_poc}"
set_env APP_DEBUG     "${APP_DEBUG:-true}"

php artisan config:clear >/dev/null 2>&1 || true

exec php artisan serve --host=0.0.0.0 --port=8080
