#!/bin/bash
set -eu

if [ ! -f /run/secrets/postgres_password ]; then
  echo "Missing secret: /run/secrets/postgres_password" >&2
  exit 1
fi

DATABASE_PASSWORD="$(cat /run/secrets/postgres_password)"
export DATABASE_URL="postgresql://${DB_USER}:${DATABASE_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

exec /bin/bash /usr/local/bin/docker-entrypoint.sh
