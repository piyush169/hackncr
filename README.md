# hackncr.tech deployment

Scripts to deploy WordPress on an Ubuntu 24.04 VPS (CSET489 Mini-Project, Milestone I).

## Files
- `setup-wordpress.sh`: Nginx, MariaDB, PHP-FPM, WordPress, Let's Encrypt. Checks DNS first; safe to rerun.
- `collect-evidence.sh`: saves versions, firewall, DNS, HTTP headers and certificate details for the report.
- `research/keywords.csv`: keyword list; fill volume, KD, source and date from your keyword tool.

## Push from your local machine
    git init && git add . && git commit -m "Add deployment scripts"
    git branch -M main
    git remote add origin git@github.com:<you>/hackncr-deploy.git
    git push -u origin main

## On the VPS
    git clone https://github.com/<you>/hackncr-deploy.git && cd hackncr-deploy
    dig +short hackncr.tech @1.1.1.1        # must print the VPS IP first
    sudo bash setup-wordpress.sh hackncr.tech you@email.com
    # then in Cloudflare: orange cloud + SSL/TLS Full (strict)
    sudo bash collect-evidence.sh hackncr.tech

## Updating later
Local: edit, `git commit -am "msg" && git push`. VPS: `git pull`.
Never commit `/root/wp-credentials.txt`, evidence files or SSH keys (already in `.gitignore`).
