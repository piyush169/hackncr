#!/usr/bin/env bash
# Usage: sudo bash setup-wordpress.sh yourdomain.tld you@email.com
# Fresh Ubuntu 24.04 VPS -> Nginx + MariaDB + PHP-FPM + WordPress + Let's Encrypt.
# Before running: Cloudflare A records for the domain and www must point to this
# server and be DNS-only (grey cloud) so the certificate can be issued.
# Set SKIP_DNS_CHECK=1 to bypass the DNS pre-flight check.
set -euo pipefail
DOMAIN="${1:?usage: sudo bash setup-wordpress.sh yourdomain.tld you@email.com}"
EMAIL="${2:?usage: sudo bash setup-wordpress.sh yourdomain.tld you@email.com}"
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }
exec > >(tee -a /var/log/wp-setup.log) 2>&1
echo "== $(date -u +%FT%TZ) starting setup for $DOMAIN"
export DEBIAN_FRONTEND=noninteractive

apt-get update -y && apt-get upgrade -y
apt-get install -y nginx mariadb-server php-fpm php-mysql php-curl php-gd php-mbstring \
  php-xml php-zip php-intl php-imagick curl unzip ufw dnsutils certbot python3-certbot-nginx

# Pre-flight: the domain must already resolve to this server, or certbot will fail.
if [ "${SKIP_DNS_CHECK:-0}" != "1" ]; then
  SERVER_IP="$(curl -fsS https://api.ipify.org || true)"
  for H in "$DOMAIN" "www.$DOMAIN"; do
    RESOLVED="$(dig +short A "$H" @1.1.1.1 | tail -n1)"
    echo "DNS check: $H -> ${RESOLVED:-nothing} (server IP: ${SERVER_IP:-unknown})"
    if [ -z "$RESOLVED" ] || [ "$RESOLVED" != "$SERVER_IP" ]; then
      echo "ERROR: $H does not resolve to this server yet. Fix the Cloudflare A record (grey cloud) and wait, or rerun with SKIP_DNS_CHECK=1."
      exit 1
    fi
  done
fi

ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable

WEBROOT="/var/www/${DOMAIN}"
PHPV="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"

if [ ! -f "$WEBROOT/wp-config.php" ]; then
  DB_NAME=wordpress; DB_USER=wpuser
  DB_PASS="$(openssl rand -hex 16)"; WP_ADMIN_PASS="$(openssl rand -hex 12)"
  mysql <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
  [ -x /usr/local/bin/wp ] || {
    curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /usr/local/bin/wp
  }
  mkdir -p "$WEBROOT"
  wp core download --path="$WEBROOT" --allow-root
  wp config create --path="$WEBROOT" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --allow-root
  wp core install --path="$WEBROOT" --url="https://${DOMAIN}" --title="${DOMAIN}" \
    --admin_user=siteadmin --admin_password="$WP_ADMIN_PASS" --admin_email="$EMAIL" --skip-email --allow-root
  wp rewrite structure '/%postname%/' --hard --path="$WEBROOT" --allow-root
  chown -R www-data:www-data "$WEBROOT"
  ( umask 077
    printf 'URL: https://%s/wp-admin\nUser: siteadmin\nPassword: %s\nDB user: %s\nDB pass: %s\n' \
      "$DOMAIN" "$WP_ADMIN_PASS" "$DB_USER" "$DB_PASS" > /root/wp-credentials.txt )
else
  echo "WordPress already present at $WEBROOT; skipping install."
fi

cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WEBROOT};
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$args; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/run/php/php${PHPV}-fpm.sock; }
    location ~* \.(jpg|jpeg|png|gif|webp|css|js|ico|svg|woff2)\$ { expires 30d; access_log off; }
    location ~ /\.ht { deny all; }
}
NGINX
ln -sf "/etc/nginx/sites-available/${DOMAIN}" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

certbot --nginx -d "$DOMAIN" -d "www.${DOMAIN}" -m "$EMAIL" --agree-tos --no-eff-email \
  --redirect --non-interactive --keep-until-expiring

echo "== Done. Admin login details: /root/wp-credentials.txt (keep out of screenshots)."
echo "== Next: turn the Cloudflare records to orange cloud, set SSL/TLS to Full (strict), then run: sudo bash collect-evidence.sh ${DOMAIN}"
