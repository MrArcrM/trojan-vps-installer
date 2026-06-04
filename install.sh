#!/usr/bin/env bash
# trojan-vps-installer
# One-shot trojan deployment on a fresh Ubuntu/Debian VPS.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MrArcrM/trojan-vps-installer/main/install.sh | \
#     sudo bash -s -- --domain proxy.example.com --password your-pw --email you@example.com

set -euo pipefail

DOMAIN=""
PASSWORD=""
EMAIL=""
PORT=443
SKIP_DNS_CHECK=0

usage() {
  cat <<EOF
trojan-vps-installer

Required:
  --domain <fqdn>      Domain pointing to this VPS (A record, NOT proxied behind CF)
  --password <str>     Trojan client password (16+ chars recommended)

Optional:
  --email <addr>       Email for Let's Encrypt account (gets expiry warnings).
                       Skip it — acme.sh auto-renews via cron so warnings are
                       a nice-to-have, not load-bearing.
  --port <n>           Trojan listen port (default: 443)
  --skip-dns-check     Bypass DNS preflight (use only if you know what you're doing)
  -h | --help          Show this help

Example:
  sudo bash install.sh --domain proxy.example.com --password mySecret123
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)   DOMAIN="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --email)    EMAIL="$2"; shift 2 ;;
    --port)     PORT="$2"; shift 2 ;;
    --skip-dns-check) SKIP_DNS_CHECK=1; shift ;;
    -h|--help)  usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

log() { printf "\033[1;34m[*]\033[0m %s\n" "$*"; }
ok()  { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[✗]\033[0m %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

# --- 0. Preflight: args + root ---
[[ -z "$DOMAIN"   ]] && die "Missing --domain"
[[ -z "$PASSWORD" ]] && die "Missing --password"
[[ $EUID -ne 0 ]] && die "Must run as root (use sudo)"

log "Domain: $DOMAIN"
log "Port: $PORT"
[[ -n "$EMAIL" ]] && log "Email: $EMAIL" || log "Email: (not set; skipping LE expiry-warning subscription — cron will auto-renew)"

# --- 1. OS check ---
. /etc/os-release 2>/dev/null || die "Cannot read /etc/os-release"
case "$ID" in
  ubuntu|debian) ok "OS: $PRETTY_NAME" ;;
  *) die "Only Ubuntu/Debian supported (detected: $ID)" ;;
esac

# --- 2. Public IP self-detect ---
log "Detecting public IP..."
PUBLIC_IP=$(curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null \
  || curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null \
  || curl -fsS --max-time 5 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
[[ -z "$PUBLIC_IP" ]] && die "Cannot detect public IP; check network"
ok "Public IP: $PUBLIC_IP"

# --- 3. DNS preflight ---
if [[ $SKIP_DNS_CHECK -eq 0 ]]; then
  log "DNS preflight: dig $DOMAIN @1.1.1.1 must return $PUBLIC_IP"
  apt-get install -y -qq dnsutils >/dev/null 2>&1 || true
  RESOLVED=$(dig +short +time=3 +tries=2 "$DOMAIN" @1.1.1.1 | tail -1)
  if [[ "$RESOLVED" != "$PUBLIC_IP" ]]; then
    err "DNS mismatch — $DOMAIN resolves to '$RESOLVED', but this VPS is '$PUBLIC_IP'"
    err "Common causes:"
    err "  - DNS A record not yet propagated (wait 5-30 min and retry)"
    err "  - A record points to wrong IP"
    err "  - Cloudflare proxy (orange cloud) ON — must set to 'DNS only' (grey cloud)"
    die "Fix DNS first, or pass --skip-dns-check to bypass"
  fi
  ok "DNS OK"
fi

# --- 4. Port 80 free (acme.sh standalone needs it) ---
log "Checking port 80 is free..."
if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ':80$'; then
  err "Port 80 is occupied; acme.sh standalone needs it free"
  ss -tlnp 2>/dev/null | grep -E ':80\s' >&2 || true
  die "Stop the process holding port 80 (commonly apache2/nginx) and retry"
fi
ok "Port 80 free"

# --- 5. Install Docker ---
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  ok "Docker already installed: $(docker --version)"
else
  log "Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ok "Docker installed: $(docker --version)"
fi

# --- 6. Install acme.sh ---
if [[ ! -x /root/.acme.sh/acme.sh ]]; then
  log "Installing acme.sh..."
  if [[ -n "$EMAIL" ]]; then
    curl -fsSL https://get.acme.sh | sh -s "email=$EMAIL" >/dev/null
  else
    # acme.sh installer accepts no email; LE registration will use empty account email
    curl -fsSL https://get.acme.sh | sh >/dev/null
  fi
  ok "acme.sh installed"
else
  ok "acme.sh already installed"
fi

# --- 7. Issue cert (root + www SAN if subdomain has www-prefix sibling) ---
log "Issuing Let's Encrypt cert for $DOMAIN..."
ISSUE_ARGS=(--issue -d "$DOMAIN" --standalone --httpport 80 --server letsencrypt)
# Auto-add www SAN if domain looks like apex (no subdomain or just www-stripped apex)
if [[ "$DOMAIN" != www.* ]] && [[ "$(echo "$DOMAIN" | awk -F. '{print NF}')" -eq 2 ]]; then
  log "Apex domain detected — also requesting www.$DOMAIN SAN"
  ISSUE_ARGS+=(-d "www.$DOMAIN")
fi
/root/.acme.sh/acme.sh "${ISSUE_ARGS[@]}" --force || die "acme.sh issue failed — check DNS/port 80 and retry"
ok "Cert issued"

# --- 8. Write trojan config ---
log "Writing /opt/trojan/config/config.json..."
mkdir -p /opt/trojan/config
cat > /opt/trojan/config/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": $PORT,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": [
    "$PASSWORD"
  ],
  "log_level": 1,
  "ssl": {
    "cert": "/config/cert.pem",
    "key": "/config/cert.key",
    "key_password": "",
    "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
    "prefer_server_cipher": true,
    "alpn": ["http/1.1", "h2"],
    "reuse_session": false,
    "session_ticket": false,
    "session_timeout": 600,
    "plain_http_response": "",
    "curves": "",
    "dhparam": ""
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "reuse_port": false,
    "fast_open": false,
    "fast_open_qlen": 20
  }
}
EOF

# --- 9. docker-compose.yml ---
log "Writing /opt/trojan/docker-compose.yml..."
cat > /opt/trojan/docker-compose.yml <<EOF
services:
  trojan:
    image: trojangfw/trojan
    container_name: trojan
    restart: unless-stopped
    ports:
      - "$PORT:443"
    volumes:
      - ./config:/config
    command: trojan /config/config.json
EOF

# --- 10. install-cert with reloadcmd ---
log "Installing cert to /opt/trojan/config and wiring reloadcmd..."
/root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
  --fullchain-file /opt/trojan/config/cert.pem \
  --key-file /opt/trojan/config/cert.key \
  --reloadcmd "cd /opt/trojan && docker compose restart trojan" >/dev/null

# --- 11. Start trojan ---
log "Starting trojan container..."
cd /opt/trojan
docker compose up -d >/dev/null
sleep 2
docker ps --filter name=trojan --format '{{.Names}} {{.Status}}' | grep -q '^trojan Up' \
  || die "trojan container failed to start; check: docker logs trojan"
ok "trojan container running"

# --- 12. Install renewal cron ---
log "Installing acme.sh renewal cron..."
/root/.acme.sh/acme.sh --install-cronjob >/dev/null
crontab -l | grep -q acme.sh || die "Cron install failed"
ok "Renewal cron installed"

# --- 13. TLS self-check ---
log "TLS handshake self-check..."
if echo | openssl s_client -connect "127.0.0.1:$PORT" -servername "$DOMAIN" 2>/dev/null \
   | openssl x509 -noout -subject 2>/dev/null | grep -q "$DOMAIN"; then
  ok "TLS handshake OK; cert matches $DOMAIN"
else
  err "TLS handshake check failed — service is up but cert/SNI may be wrong; inspect manually"
fi

# --- 14. Done ---
cat <<EOF

────────────────────────────────────────────────────────────
$(printf "\033[1;32m✓ Trojan deployment complete\033[0m")
────────────────────────────────────────────────────────────

Client config:
  Type:     trojan
  Server:   $DOMAIN
  Port:     $PORT
  Password: $PASSWORD
  SNI:      $DOMAIN
  Skip-cert-verify: false

Test from the new server:
  docker logs --tail 20 trojan

Renewal: acme.sh cron runs daily; next renewal window is ~60 days before cert expiry.
EOF
