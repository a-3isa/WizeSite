-- Runs once on first container start (docker-entrypoint-initdb.d).
-- PowerSync keeps its bucket storage in a separate database from the application data.
CREATE DATABASE powersync_storage;
