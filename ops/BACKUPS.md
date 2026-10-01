# Backups (tasks.md T091–T094)

Two encrypted, off-site backups in one S3-compatible bucket (Backblaze B2 or Cloudflare R2):

| What | Tool | How often | Kept |
|------|------|-----------|------|
| Database | pgBackRest (inside the postgres container) | WAL archived within 60 s of activity; full backup daily 03:00 UTC; differential every 6 h | 30 days, any point in time |
| Files (`/srv/wizesite/files`) | restic (official image, no host install) | every 10 min | 30 days |

Both encrypt before upload. **Keep the two passphrases in your password manager**: without them
the backups cannot be read.

## One-time setup

1. Create a bucket and an access key limited to it.
   - B2: endpoint `s3.<region>.backblazeb2.com`, region e.g. `us-west-004`.
   - R2: endpoint `<account-id>.r2.cloudflarestorage.com`, region `auto`.
2. Add to `/srv/wizesite/.env` (root-only, mode 0600; never commit or paste these):
   ```
   PGBACKREST_REPO1_S3_BUCKET=<bucket>
   PGBACKREST_REPO1_S3_ENDPOINT=<endpoint>
   PGBACKREST_REPO1_S3_REGION=<region>
   PGBACKREST_REPO1_S3_KEY=<key id>
   PGBACKREST_REPO1_S3_KEY_SECRET=<secret>
   PGBACKREST_REPO1_CIPHER_PASS=<long random passphrase>
   ```
3. Deploy (`bash /srv/wizesite/app/ops/deploy.sh --build`), then create the repository:
   ```
   docker exec -u postgres wizesite-postgres-1 pgbackrest --stanza=wizesite stanza-create
   ```
4. Turn WAL archiving on: add `PG_ARCHIVE_MODE=on` to `/srv/wizesite/.env` and deploy again
   (postgres restarts once). Then:
   ```
   docker exec -u postgres wizesite-postgres-1 pgbackrest --stanza=wizesite check
   docker exec -u postgres wizesite-postgres-1 pgbackrest --stanza=wizesite --type=full backup
   ```
   Do not turn archiving on before step 3 succeeds: postgres keeps every WAL file it could not
   archive, and the disk fills.
5. Files: copy `ops/restic/restic.env.example` to `/srv/wizesite/secrets/restic.env` (mode 0600),
   fill it in, then `bash /srv/wizesite/app/ops/restic/restic.sh init` and
   `bash /srv/wizesite/app/ops/restic/restic.sh backup`.
6. Timers:
   ```
   cp /srv/wizesite/app/ops/systemd/{pgbackrest-*,restic-*,heartbeat}.{service,timer} /etc/systemd/system/
   systemctl daemon-reload
   systemctl enable --now pgbackrest-full.timer pgbackrest-diff.timer \
     restic-files.timer restic-check.timer restic-forget.timer heartbeat.timer
   ```
7. Check: `bash /srv/wizesite/app/ops/test/backup_lag_check.sh && echo fresh`.

## Restore

`ops/restore.sh` (latest) or `ops/restore.sh --pitr "<timestamp with zone>"` on a prepared host.
It stops the services, moves the old data directory aside, restores the database and the files,
deploys, and prints the elapsed time and the newest restored record. See the header of the
script for what must be in place first. Practise it (T097) before you need it.

## Checked locally

The pgBackRest wiring (this image, `ops/pgbackrest/pgbackrest.conf`, a local repository in place
of S3) was run end to end: stanza, WAL archiving, full backup, point-in-time restore. Rows written
after the target time were gone and earlier rows were back.
