#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# analytics.sh – Generate a visitor analytics report from
#                the remote nginx access logs.
#
# Usage:
#   ./analytics.sh            # uses deploy/.env for connection details
#   ./analytics.sh 30         # override: show last N days (default 14)
#
# Prerequisites:
#   - deploy/.env with SERVER_IP, SSH_USER, SSH_KEY
#   - SSH access to the server
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deploy/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy deploy/.env.example and fill in your values." >&2
  exit 1
fi

# Load connection details
export $(grep -v '^#' "$ENV_FILE" | xargs)

DAYS="${1:-14}"
SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${SSH_USER}@${SERVER_IP}"

echo "═══════════════════════════════════════════════════════════"
echo " 📊  Website Analytics Report – ${DOMAIN_NAME}"
echo " 📅  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 📆  Showing last ${DAYS} days"
echo "═══════════════════════════════════════════════════════════"
echo ""

${SSH_CMD} "bash -s" <<REMOTE_SCRIPT
set -u

# ── Combine all rotated log files ──────────────────────────
ALL_LOGS=\$(mktemp)
trap "rm -f \$ALL_LOGS" EXIT

{
  cat /var/log/nginx/profile_website_access.log 2>/dev/null || true
  cat /var/log/nginx/profile_website_access.log.1 2>/dev/null || true
  for f in /var/log/nginx/profile_website_access.log.*.gz; do
    [ -f "\$f" ] && zcat "\$f" 2>/dev/null || true
  done
} > "\$ALL_LOGS"

# ── Filter to last N days ──────────────────────────────────
VALID_DATES=""
for i in \$(seq 0 \$((${DAYS} - 1))); do
  VALID_DATES="\${VALID_DATES}\$(date -d "\$i days ago" '+%d/%b/%Y')|"
done
VALID_DATES="\${VALID_DATES%|}"

FILTERED=\$(mktemp)
awk -v dates="\$VALID_DATES" '
  BEGIN { n=split(dates,d,"|"); for(i=1;i<=n;i++) valid[d[i]]=1 }
  { split(\$4,dt,":"); gsub(/\[/,"",dt[1]); if(dt[1] in valid) print }
' "\$ALL_LOGS" > "\$FILTERED"
mv "\$FILTERED" "\$ALL_LOGS"

TOTAL=\$(wc -l < "\$ALL_LOGS")

if [ "\$TOTAL" -eq 0 ]; then
  echo "No log entries found."
  exit 0
fi

# ── Compute date range (logs may be concatenated out of order) ──
# Extract unique dates only (few lines) to avoid SIGPIPE with pipefail
SORTED_DATES=\$(awk '{d=\$4; gsub(/\[/,"",d); split(d,p,":"); print p[1]}' "\$ALL_LOGS" | \
  sort -u | \
  awk -F/ '{m=index("JanFebMarAprMayJunJulAugSepOctNovDec",\$2);
    printf "%s-%02d-%s %s/%s/%s\n", \$3, (m+2)/3, \$1, \$1, \$2, \$3}' | \
  sort -k1)
FIRST_DATE=\$(echo "\$SORTED_DATES" | head -1 | awk '{print \$2}')
LAST_DATE=\$(echo "\$SORTED_DATES" | tail -1 | awk '{print \$2}')

# ── Helper: bot detection pattern (user-agent based) ───────
BOT_PATTERN='(bot|Bot|spider|Spider|crawl|Crawl|zgrab|scanner|Scanner|masscan|Nuclei|curl|wget|python|Go-http|Jakarta|Expanse|CensysInspect|Amazonbot|GPTBot|ClaudeBot|Bytespider|Googlebot|bingbot|YandexBot|Baiduspider|DotBot|SemrushBot|AhrefsBot|MJ12bot|PetalBot|HubSpot|l9explore|NetcraftSurveyAgent|OAI-SearchBot|SERanking)'

# ── Helper: attack/scan path pattern (catches scanners with normal UAs)
SCAN_PATH_PATTERN='[.](php|env|asp|aspx|cgi|bak|sql|config|ini|log|yml|yaml|git|svn|htaccess|htpasswd|DS_Store)|/wp-|/wordpress|/admin|/phpmyadmin|/cPanel|/manager|/shell|/setup|/install|/debug|/console|/actuator|/solr|/struts|/jenkins|/jmx|/telescope|/vendor/|/owa|/autodiscover|/remote/|/[.]git|/[.]env|/xmlrpc|/backup|/database|/dbadmin'

# ═══════════════════════════════════════════════════════════
echo "── OVERVIEW ──────────────────────────────────────────────"
echo "  Total requests:      \$TOTAL"
echo "  Date range:          \$FIRST_DATE → \$LAST_DATE"

UNIQUE_IPS=\$(awk '{print \$1}' "\$ALL_LOGS" | sort -u | wc -l)
echo "  Unique IPs (total):  \$UNIQUE_IPS"

BOT_COUNT=\$(awk -F'"' -v pat="\$BOT_PATTERN" '\$6 ~ pat' "\$ALL_LOGS" | wc -l)
# Scanners: 404 on attack paths, NOT already counted as bot by UA
SCANNER_COUNT=\$(awk -F'"' -v bpat="\$BOT_PATTERN" -v spat="\$SCAN_PATH_PATTERN" '
  \$6 !~ bpat {
    split(\$1, a, " ");
    status = a[length(a)];
    # rebuild request field and extract path
    split(\$2, req, " ");
    path = req[2];
    if (path ~ spat) print
  }' "\$ALL_LOGS" | wc -l)
HUMAN_COUNT=\$(( TOTAL - BOT_COUNT - SCANNER_COUNT ))
if [ "\$TOTAL" -gt 0 ]; then
  BOT_PCT=\$(( BOT_COUNT * 100 / TOTAL ))
  SCAN_PCT=\$(( SCANNER_COUNT * 100 / TOTAL ))
  HUMAN_PCT=\$(( HUMAN_COUNT * 100 / TOTAL ))
else
  BOT_PCT=0; SCAN_PCT=0; HUMAN_PCT=0
fi
echo "  Human requests:      \$HUMAN_COUNT (\${HUMAN_PCT}%)"
echo "  Bot requests (UA):   \$BOT_COUNT (\${BOT_PCT}%)"
echo "  Scanner requests:    \$SCANNER_COUNT (\${SCAN_PCT}%) – non-bot UA hitting attack paths"
echo ""

OK_COUNT=\$(awk '\$9 == 200' "\$ALL_LOGS" | awk -F'"' -v pat="\$BOT_PATTERN" '\$6 !~ pat' | wc -l)
echo "  ✅ Human 200s:       \$OK_COUNT (genuine page views)"
echo ""

# ═══════════════════════════════════════════════════════════
echo "── HTTP STATUS CODES ────────────────────────────────────"
awk '{print \$9}' "\$ALL_LOGS" | grep -E '^[0-9]+$' | sort | uniq -c | sort -rn | head -10 | \
  while read count code; do
    printf "  %-6s  %s\n" "\$code" "\$count"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── TOP PAGES (excluding assets & attack paths) ──────────"
awk '\$9 == 200 && \$7 !~ /\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)/ {print \$7}' "\$ALL_LOGS" | \
  sort | uniq -c | sort -rn | head -15 | \
  while read count path; do
    printf "  %6d  %s\n" "\$count" "\$path"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── ARTICLE PAGES ────────────────────────────────────────"
awk '\$7 ~ /^\/articles\/.+\// && \$9 == 200 {print \$7}' "\$ALL_LOGS" | \
  sort | uniq -c | sort -rn | head -15 | \
  while read count path; do
    printf "  %6d  %s\n" "\$count" "\$path"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── UNIQUE VISITORS PER DAY (last ${DAYS} days) ──────────"
awk '{split(\$4,d,":"); gsub(/\[/,"",d[1]); print d[1], \$1}' "\$ALL_LOGS" | \
  sort -u | awk '{print \$1}' | sort | uniq -c | \
  awk '{
    split(\$2,d,"/");
    m=index("JanFebMarAprMayJunJulAugSepOctNovDec",d[2]);
    printf "%s-%02d-%s %d %s\n", d[3], (m+2)/3, d[1], \$1, \$2
  }' | sort -k1 | tail -${DAYS} | \
  while read sortkey count day; do
    bar=\$(printf '%*s' \$(( count / 5 )) '' | tr ' ' '#')
    printf "  %-12s %4d  %s\n" "\$day" "\$count" "\$bar"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── REQUESTS PER DAY (last ${DAYS} days) ─────────────────"
awk '{print \$4}' "\$ALL_LOGS" | cut -d: -f1 | tr -d '[' | \
  sort | uniq -c | \
  awk '{
    split(\$2,d,"/");
    m=index("JanFebMarAprMayJunJulAugSepOctNovDec",d[2]);
    printf "%s-%02d-%s %d %s\n", d[3], (m+2)/3, d[1], \$1, \$2
  }' | sort -k1 | tail -${DAYS} | \
  while read sortkey count day; do
    bar=\$(printf '%*s' \$(( count / 20 )) '' | tr ' ' '#')
    printf "  %-12s %5d  %s\n" "\$day" "\$count" "\$bar"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── REQUESTS PER HOUR (UTC, all time) ────────────────────"
awk '{split(\$4,d,":"); print d[2]":00"}' "\$ALL_LOGS" | sort | uniq -c | sort -k2 | \
  while read count hour; do
    bar=\$(printf '%*s' \$(( count / 30 )) '' | tr ' ' '#')
    printf "  %s  %5d  %s\n" "\$hour" "\$count" "\$bar"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── TOP BOTS ─────────────────────────────────────────────"
awk -F'"' -v pat="\$BOT_PATTERN" '\$6 ~ pat {print \$6}' "\$ALL_LOGS" | \
  sed -E 's/.*(Googlebot|bingbot|YandexBot|Baiduspider|DotBot|SemrushBot|AhrefsBot|MJ12bot|PetalBot|GPTBot|ClaudeBot|Amazonbot|Bytespider|Applebot|facebookexternalhit|HubSpot|OAI-SearchBot|SERanking|l9explore|zgrab).*/\1/' | \
  sort | uniq -c | sort -rn | head -15 | \
  while read count bot; do
    printf "  %6d  %s\n" "\$count" "\$bot"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── TOP USER AGENTS (non-bot) ────────────────────────────"
awk -F'"' -v pat="\$BOT_PATTERN" '\$6 !~ pat && \$6 != "-" && \$6 != "" {print \$6}' "\$ALL_LOGS" | \
  sort | uniq -c | sort -rn | head -10 | \
  while read count ua; do
    printf "  %6d  %s\n" "\$count" "\$ua"
  done
echo ""

# ═══════════════════════════════════════════════════════════
# Extract all external referrer URLs once, reuse for both views
REF_URLS=\$(mktemp)
awk -F'"' '\$4 != "-" && \$4 != "" && length(\$4) > 1' "\$ALL_LOGS" | \
  awk -F'"' '{
    url = \$4;
    sub(/^https?:\/\//, "", url);
    sub(/^www\./, "", url);
    print tolower(url)
  }' | \
  grep -viE '(remus-software\.org|tomseidel\.com|195\.201\.136\.227)' > "\$REF_URLS"

echo "── TOP REFERRERS BY DOMAIN ────────────────────────────────"
sed 's|/.*||' "\$REF_URLS" | \
  sort | uniq -c | sort -rn | \
  while read count ref; do
    printf "  %6d  %s\n" "\$count" "\$ref"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── TOP REFERRER URLS (full path + query) ──────────────────"
sort "\$REF_URLS" | uniq -c | sort -rn | \
  while read count ref; do
    printf "  %6d  %s\n" "\$count" "\$ref"
  done
echo ""

rm -f "\$REF_URLS"

# ═══════════════════════════════════════════════════════════
echo "── TOP REFERRAL LANDING PAGES ─────────────────────────────"
echo "  (pages visitors arrived at from external sources)"
awk -F'"' '\$4 != "-" && \$4 != "" && length(\$4) > 1 {
  ref = tolower(\$4);
  if (ref !~ /remus-software\.org/ && ref !~ /apps-stage\.site/ && ref !~ /195\.201\.136\.227/) {
    split(\$2, req, " ");
    path = req[2];
    if (path !~ /\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)/)
      print path
  }
}' "\$ALL_LOGS" | \
  sort | uniq -c | sort -rn | head -15 | \
  while read count path; do
    printf "  %6d  %s\n" "\$count" "\$path"
  done
echo ""

# ═══════════════════════════════════════════════════════════
echo "── SECURITY: TOP ATTACK PATHS (404s) ────────────────────"
awk '\$9 == 404 && \$7 !~ /\.(css|js|png|jpg|ico|svg)/ {print \$7}' "\$ALL_LOGS" | \
  sort | uniq -c | sort -rn | head -10 | \
  while read count path; do
    printf "  %6d  %s\n" "\$count" "\$path"
  done
echo ""

REMOTE_SCRIPT

echo "═══════════════════════════════════════════════════════════"
echo " Report complete."
echo "═══════════════════════════════════════════════════════════"




