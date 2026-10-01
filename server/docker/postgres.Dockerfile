# Postgres 17 with pgBackRest for WAL archiving and base backups (tasks.md T091).
# Same data directory format as the stock postgres:17 image, so it swaps in place.
FROM postgres:17

RUN apt-get update \
 && apt-get install -y --no-install-recommends pgbackrest ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && install -d -m 750 -o postgres -g postgres /var/lib/pgbackrest
