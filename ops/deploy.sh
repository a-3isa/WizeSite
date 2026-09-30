#!/usr/bin/env bash
# Deploy / update the WizeSite backend stack on the VPS (tasks.md T090).
#
#   bash ops/deploy.sh --build        # build the API image on this host from /srv/wizesite/app/server
#   bash ops/deploy.sh <image-ref>    # use a CI-built image, e.g. ghcr.io/<owner>/wizesite-server:<sha>
#
# Steps: build/pull -> postgres up -> migrations (one-off container) -> powersync + api up ->
# health check. On a failed health check with <image-ref>, redeploys the previous image
# recorded in /srv/wizesite/state/last_image.
set -euo pipefail

ROOT=/srv/wizesite
APP="$ROOT/app/server"
ENV_FILE="$ROOT/.env"
STATE="$ROOT/state"
cd "$APP"

COMPOSE_FILES=(-f compose.yml)
# Cloudflare Tunnel: included only once a token is configured (compose.tunnel.yml).
if grep -qE '^CLOUDFLARE_TUNNEL_TOKEN=.+' "$ENV_FILE"; then
  COMPOSE_FILES+=(-f compose.tunnel.yml)
fi
dc() { docker compose "${COMPOSE_FILES[@]}" --env-file "$ENV_FILE" "$@"; }

MODE="${1:?usage: deploy.sh --build | <image-ref>}"
PREVIOUS_IMAGE="$(cat "$STATE/last_image" 2>/dev/null || true)"
if [[ "$MODE" == "--build" ]]; then
  export API_IMAGE="wizesite-server:local"
  echo "==> building API image on host"
  dc build api
else
  export API_IMAGE="$MODE"
  echo "==> pulling $API_IMAGE"
  dc pull api
fi

# The API (and the migrator, same image) write attachments here as the image's non-root user.
APP_IDS="$(docker run --rm --entrypoint sh "$API_IMAGE" -c 'echo "$(id -u app):$(id -g app)"')"
chown "$APP_IDS" "$ROOT/files"

echo "==> postgres"
dc up -d postgres
for _ in $(seq 1 45); do
  if dc exec -T postgres pg_isready -U wizesite -d wizesite >/dev/null 2>&1; then break; fi
  sleep 2
done
dc exec -T postgres pg_isready -U wizesite -d wizesite

echo "==> migrations"
dc run --rm --no-deps api npm run migrate

echo "==> powersync + api + reconciler${COMPOSE_FILES[2]:+ + cloudflared}"
if [[ ${#COMPOSE_FILES[@]} -gt 2 ]]; then
  dc up -d powersync api reconciler cloudflared
else
  dc up -d powersync api reconciler
fi

echo "==> health check"
healthy=false
for _ in $(seq 1 30); do
  if dc exec -T api node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>r.json()).then(b=>{console.log(JSON.stringify(b));process.exit(b.status==='ok'?0:1)}).catch(()=>process.exit(1))" 2>/dev/null; then
    healthy=true
    break
  fi
  sleep 2
done

if [[ "$healthy" == true ]]; then
  echo "$API_IMAGE" > "$STATE/last_image"
  echo "==> deployed $API_IMAGE"
  dc ps --format '{{.Service}}\t{{.Status}}'
  exit 0
fi

echo "!! health check failed" >&2
dc logs --tail 40 api >&2 || true
if [[ "$MODE" != "--build" && -n "$PREVIOUS_IMAGE" && "$PREVIOUS_IMAGE" != "$API_IMAGE" ]]; then
  echo "==> rolling back to $PREVIOUS_IMAGE" >&2
  export API_IMAGE="$PREVIOUS_IMAGE"
  dc up -d api
fi
exit 1
