#!/usr/bin/env bash
# One-time VPS preparation for the WizeSite backend (research R8, tasks.md T008).
# Run as root on a fresh Debian/Ubuntu server:  sudo bash ops/bootstrap.sh <ssh-public-key-file>
# Idempotent: safe to re-run.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

PUBKEY_FILE="${1:-}"
DEPLOY_USER="wizesite"
ROOT_DIR="/srv/wizesite"

echo "==> Packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg ufw unattended-upgrades fail2ban

echo "==> Automatic security updates"
dpkg-reconfigure -f noninteractive unattended-upgrades
systemctl enable --now unattended-upgrades

echo "==> fail2ban (SSH brute-force protection)"
systemctl enable --now fail2ban

echo "==> Firewall: only SSH, HTTP, HTTPS"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Docker Engine + compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  . /etc/os-release
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

echo "==> 2 GB swap (safety net for the 4 GB box)"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> journald retention 14 days"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/wizesite.conf <<'CONF'
[Journal]
SystemMaxRetentionSec=14d
SystemMaxUse=1G
CONF
systemctl restart systemd-journald

echo "==> Deploy user"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
if [[ -n "$PUBKEY_FILE" ]]; then
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$PUBKEY_FILE" "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi

echo "==> Directories"
for d in pgdata files caddy caddy/data caddy/config backups state secrets; do
  install -d -m 700 "$ROOT_DIR/$d"
done
# Postgres container runs as uid 999.
chown 999:999 "$ROOT_DIR/pgdata"

echo "==> SSH: keys only, no root password login"
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-wizesite.conf
cat > "$SSHD_DROPIN" <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
if [[ -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]] || [[ -s /root/.ssh/authorized_keys ]]; then
  systemctl reload ssh || systemctl reload sshd
else
  echo "WARNING: no authorized_keys found; SSH hardening written but sshd NOT reloaded to avoid lock-out." >&2
fi

echo "Done. Next: put /srv/wizesite/.env and secrets/firebase-service-account.json in place, then run ops/deploy.sh."
