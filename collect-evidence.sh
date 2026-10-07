#!/usr/bin/env bash
# Usage: sudo bash collect-evidence.sh yourdomain.tld
# Saves server and TLS evidence for the report to ./evidence-<timestamp>.txt (no passwords included).
DOMAIN="${1:?usage: sudo bash collect-evidence.sh yourdomain.tld}"
OUT="evidence-$(date -u +%Y%m%dT%H%M%SZ).txt"
run(){ echo; echo "### $*"; "$@" 2>&1 || true; }
{
  echo "Evidence for $DOMAIN collected $(date -u +%FT%TZ)"
  run hostname
  run lsb_release -ds
  run uname -r
  run nginx -v
  run php -v
  run mariadb --version
  run wp core version --path="/var/www/$DOMAIN" --allow-root
  run ufw status
  run systemctl is-active nginx mariadb
  run dig +short NS "$DOMAIN"
  run dig +short A "$DOMAIN" @1.1.1.1
  run curl -sI "http://$DOMAIN"
  run curl -sI "https://$DOMAIN"
  run certbot certificates
  echo; echo "### TLS certificate dates"
  echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -issuer -dates 2>&1 || true
} | tee "$OUT"
echo; echo "Saved to $(pwd)/$OUT"
