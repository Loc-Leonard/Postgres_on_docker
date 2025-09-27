#!/usr/bin/env bash
set -euo pipefail

# Ожидаем, что docker-compose прокинет эти переменные из .env
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${MIGRATOR_USER:?MIGRATOR_USER is required}"
: "${MIGRATOR_PASSWORD:?MIGRATOR_PASSWORD is required}"
: "${APP_USER:?APP_USER is required}"
: "${APP_USER_PASSWORD:?APP_USER_PASSWORD is required}"

# Скрипт исполняется внутри контейнера под root-скриптом entrypoint'а.
# psql коннектится как суперпользователь $POSTGRES_USER к базе $POSTGRES_DB.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
-- 1) Роли: создаём при отсутствии, выставляем/обновляем пароли
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${MIGRATOR_USER}') THEN
    CREATE ROLE ${MIGRATOR_USER} LOGIN NOSUPERUSER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${APP_USER}') THEN
    CREATE ROLE ${APP_USER} LOGIN NOSUPERUSER;
  END IF;
END
\$\$;

ALTER ROLE ${MIGRATOR_USER} WITH PASSWORD '${MIGRATOR_PASSWORD}';
ALTER ROLE ${APP_USER}     WITH PASSWORD '${APP_USER_PASSWORD}';

-- 2) Схема приложения и базовые права
CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION ${MIGRATOR_USER};

ALTER ROLE ${APP_USER} SET search_path TO app, public;

GRANT USAGE ON SCHEMA app TO ${APP_USER};
GRANT CREATE, USAGE ON SCHEMA app TO ${MIGRATOR_USER};

-- 3) Default privileges для будущих объектов, создаваемых ИМЕННО migrator
ALTER DEFAULT PRIVILEGES FOR ROLE ${MIGRATOR_USER} IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${APP_USER};

ALTER DEFAULT PRIVILEGES FOR ROLE ${MIGRATOR_USER} IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO ${APP_USER};

-- 4) Гигиена прав: урезаем PUBLIC и выдаём CONNECT app_user на текущую БД
DO \$\$
DECLARE
  db text := current_database();
BEGIN
  EXECUTE format('REVOKE CREATE ON SCHEMA public FROM PUBLIC;');
  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC;', db);
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO ${APP_USER};', db);
END
\$\$;
SQL
