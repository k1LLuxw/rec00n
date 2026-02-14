#!/usr/bin/env bash
set -euo pipefail

# reconm0nster v2.3 (+ crt.sh HTML fallback)
# passive recon + live verification + param risk scoring (NO exploit)
# Adds: verbose progress + line counters
# Fix: crt.sh JSON returns 0 -> HTML fallback scrape

# ---------------- Colors ----------------
if [[ -t 1 ]]; then
  C0=$'\033[0m'
  C1=$'\033[38;5;45m'   # cyan
  C2=$'\033[38;5;141m'  # purple
  C3=$'\033[38;5;82m'   # green
  C4=$'\033[38;5;214m'  # orange
  C5=$'\033[38;5;196m'  # red
  CB=$'\033[1m'
  CD=$'\033[2m'
else
  C0=""; C1=""; C2=""; C3=""; C4=""; C5=""; CB=""; CD=""
fi

banner() {
  # Tool name: if you renamed the script, it shows that name
  local TOOL_NAME="${TOOL_NAME:-$(basename "$0")}"
  local tagline="passive recon + live verify + risk scoring"
  local sub="No exploitation • No brute-force • Educational output"

  # terminal width (fallback 90)
  local W
  W="$(tput cols 2>/dev/null || echo 90)"
  (( W < 60 )) && W=60
  (( W > 140 )) && W=140

  # helpers
  hr() { printf "%*s\n" "$W" "" | tr ' ' '─'; }
  padline() {
    # prints a line trimmed/padded to width W (no box sides => never breaks)
    local s="$1"
    # trim to width
    if (( ${#s} > W )); then s="${s:0:W}"; fi
    printf "%-*s\n" "$W" "$s"
  }

  echo
  printf "${C2}${CB}"; hr; printf "${C0}"
  padline "${C1}${CB}${TOOL_NAME}${C0} ${C4}${CB}— ${tagline}${C0}"
  padline "${CD}${sub}${C0}"
  printf "${C2}${CB}"; hr; printf "${C0}"

  # ASCII art: show only if wide enough
  if (( W >= 90 )); then
    cat <<'ART'
                 ___   ___        
                / _ \ / _ \       
  _ __ ___  ___| | | | | | |_ __  
 | '__/ _ \/ __| | | | | | | '_ \ 
 | | |  __/ (__| |_| | |_| | | | |
 |_|  \___|\___|\___/ \___/|_| |_|
                                  
                                  
ART
  else
    padline "${C1}${CB}[banner]${C0} (terminal narrow: hiding ascii art)"
  fi

  printf "${C2}${CB}"; hr; printf "${C0}"
  echo
}
has(){ command -v "$1" >/dev/null 2>&1; }
normalize_domain(){ local x="$1"; x="${x#http://}"; x="${x#https://}"; x="${x%%/*}"; echo "$x"; }
ts_now(){ date +%Y%m%d_%H%M%S; }

log(){ printf "${C1}[+]${C0} %s\n" "$*"; }
ok(){  printf "${C3}[✓]${C0} %s\n" "$*"; }
warn(){ printf "${C4}[!]${C0} %s\n" "$*" | tee -a "$OUT/WARNINGS.txt" >/dev/null; }
err(){ printf "${C5}[x]${C0} %s\n" "$*" >&2; }

count_lines(){ [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo "0"; }

escape_html(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"; }

pick_httpx() { has httpx-toolkit && { echo "httpx-toolkit"; return; }; has httpx && { echo "httpx"; return; }; echo ""; }
get_help() { local tool="$1"; "$tool" --help 2>&1 || "$tool" -h 2>&1 || true; }

extract_urls_any() { grep -Eo 'https?://[^"[:space:]]+' | sed 's/[),]$//' | sed '/^$/d' | sort -u; }

is_jsonl_file() {
  local f="$1"
  local first
  first="$(grep -m1 -v '^[[:space:]]*$' "$f" 2>/dev/null || true)"
  [[ "$first" == \{* ]]
}

tsv_to_table() {
  local file="$1" limit="${2:-80}"
  [[ ! -f "$file" ]] && { echo "<div class='muted'>Missing file.</div>"; return 0; }
  local rows; rows="$(wc -l < "$file" | tr -d ' ')"
  if (( rows <= 1 )); then echo "<div class='muted'>No data.</div>"; return 0; fi

  echo "<table><thead><tr>"
  head -n 1 "$file" | awk -F'\t' '{for(i=1;i<=NF;i++) printf "<th>%s</th>", $i; print ""}'
  echo "</tr></thead><tbody>"

  tail -n +2 "$file" | head -n "$limit" | while IFS=$'\t' read -r a b c d e f; do
    echo "<tr>"
    for val in "${a:-}" "${b:-}" "${c:-}" "${d:-}" "${e:-}" "${f:-}"; do
      if [[ -z "$val" ]]; then echo "<td></td>"
      elif [[ "$val" =~ ^https?:// ]]; then
        esc="$(printf "%s" "$val" | escape_html)"
        echo "<td><a href='${esc}' target='_blank' rel='noreferrer'>${esc}</a></td>"
      else
        echo "<td>$(printf "%s" "$val" | escape_html)</td>"
      fi
    done
    echo "</tr>"
  done
  echo "</tbody></table>"
  if (( rows-1 > limit )); then echo "<div class='muted'>Showing first ${limit} rows out of ${rows}.</div>"; fi
}

step() {
  local n="$1" title="$2"
  echo
  echo "${C2}${CB}══ Step ${n} ══${C0} ${CB}${title}${C0}"
}

progress_line() {
  local i="$1" total="$2" msg="$3"
  printf "\r${C1}[~]${C0} (%d/%d) %s" "$i" "$total" "$msg"
}

# ---------------- Input ----------------
banner
IN="${1:-}"
[[ -z "$IN" ]] && { err "Usage: $0 example.com"; exit 1; }

TARGET="$(normalize_domain "$IN")"
TS="$(ts_now)"
OUT="out/${TARGET}/${TS}"
mkdir -p "$OUT/logs"
: > "$OUT/WARNINGS.txt"

UA="reconm0nster/2.3 (passive; edu project)"

# ---------------- Tool check ----------------
step 0 "Tool check"
for t in subfinder curl; do
  if ! has "$t"; then err "Missing: $t"; exit 2; else ok "$t: OK"; fi
done

HTTPX_BIN="$(pick_httpx)"
[[ -z "$HTTPX_BIN" ]] && { err "Missing: httpx-toolkit or httpx"; exit 2; }
ok "httpx: $HTTPX_BIN"

JQ_OK="no"; has jq && JQ_OK="yes"
WAY_TOOL=""; has gau && WAY_TOOL="gau"; [[ -z "$WAY_TOOL" ]] && has waybackurls && WAY_TOOL="waybackurls"
ok "jq: $JQ_OK"
ok "wayback tool: ${WAY_TOOL:-none}"

TIMEOUT_BIN=""; has timeout && TIMEOUT_BIN="timeout 600" || warn "timeout not found (ok but long tasks may hang)"

HTTPX_HELP="$(get_help "$HTTPX_BIN")"
H_SILENT="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-silent([,[:space:]]|$)" && echo "-silent" || echo "")"
H_FOLLOW="$(echo "$HTTPX_HELP" | grep -q -- "-follow-redirects" && echo "-follow-redirects" || echo "")"
H_TITLE="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-title([,[:space:]]|$)" && echo "-title" || echo "")"
H_SERVER="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-server([,[:space:]]|$)" && echo "-server" || echo "")"
H_TECH="$(echo "$HTTPX_HELP" | grep -q -- "-tech-detect" && echo "-tech-detect" || echo "")"
H_CLEN="$(echo "$HTTPX_HELP" | grep -q -- "-content-length" && echo "-content-length" || echo "")"
H_THREADS="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-threads([,[:space:]]|$)" && echo "-threads 80" || echo "")"
H_TIMEOUT="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-timeout([,[:space:]]|$)" && echo "-timeout 10" || echo "")"
H_RETRY="$(echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-retries([,[:space:]]|$)" && echo "-retries 1" || echo "")"
H_STATUS=""; echo "$HTTPX_HELP" | grep -q -- "-status-code" && H_STATUS="-status-code"
[[ -z "$H_STATUS" ]] && echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-sc([,[:space:]]|$)" && H_STATUS="-sc"
H_JSON=""; echo "$HTTPX_HELP" | grep -qE "(^|[[:space:]])-json([,[:space:]]|$)" && H_JSON="-json"

# ---------------- Files ----------------
SUBS="$OUT/subdomains.txt"
CRT_JSON="$OUT/crt.json"
CRT_SUBS="$OUT/crt_subs.txt"
SEED="$OUT/seed_origins.txt"

ALIVE_RAW="$OUT/alive_origins.raw"
ALIVE_JSONL="$OUT/alive_origins.jsonl"
ALIVE_ORIGINS="$OUT/alive_origins.txt"
ALIVE_TSV="$OUT/alive_origins.tsv"

WB_ALL="$OUT/wayback_urls_all.txt"
WB_RAW="$OUT/alive_wayback_urls.raw"
WB_ALIVE="$OUT/alive_wayback_urls.txt"
WB_ALIVE_TSV="$OUT/alive_wayback_urls.tsv"

PARAM_FIND="$OUT/param_findings.tsv"
TOP_URLS="$OUT/top_urls.tsv"
PARAM_STATS="$OUT/param_stats.tsv"

# ---------------- 1) subfinder ----------------
step 1 "Subfinder: subdomain discovery → subdomains.txt"
SF_HELP="$(subfinder --help 2>&1 || true)"
SF_SILENT=""; echo "$SF_HELP" | grep -qE "(^|[[:space:]])-silent([,[:space:]]|$)" && SF_SILENT="-silent"
: > "$SUBS"
${TIMEOUT_BIN} subfinder -d "$TARGET" $SF_SILENT \
  | sed '/^$/d' | awk '{print tolower($0)}' | sort -u > "$SUBS" || true
{ echo "$TARGET"; cat "$SUBS"; } | sed '/^$/d' | sort -u > "$OUT/_tmp" && mv "$OUT/_tmp" "$SUBS"
ok "wrote: $SUBS ($(count_lines "$SUBS") lines)"

# ---------------- 2) crt.sh ----------------
step 2 "crt.sh (curl): merge + dedupe (with HTML fallback)"
: > "$CRT_SUBS"
curl -sS -A "$UA" "https://crt.sh/?q=%25.${TARGET}&output=json" > "$CRT_JSON" || true

if [[ -s "$CRT_JSON" ]]; then
  if [[ "$JQ_OK" == "yes" ]]; then
    jq -r '.[].name_value' "$CRT_JSON" 2>/dev/null \
      | tr '\r' '\n' \
      | sed 's/\*\.\?//g' \
      | awk '{print tolower($0)}' \
      | sed '/^$/d' | sort -u > "$CRT_SUBS" || true
  else
    grep -oE '"name_value":"[^"]+"' "$CRT_JSON" \
      | sed 's/"name_value":"//;s/"$//' \
      | tr '\r' '\n' \
      | sed 's/\*\.\?//g' \
      | awk '{print tolower($0)}' \
      | sed '/^$/d' | sort -u > "$CRT_SUBS" || true
  fi
fi

# --- HTML fallback if JSON produced 0 ---
if [[ ! -s "$CRT_SUBS" || "$(count_lines "$CRT_SUBS")" == "0" ]]; then
  warn "crt.sh JSON returned 0. Trying HTML fallback scrape..."
  CRT_HTML="$OUT/crt.html"
  curl -sS -A "$UA" "https://crt.sh/?q=%25.${TARGET}" > "$CRT_HTML" || true
  grep -Eoi "([a-z0-9-]+\.)+$(printf "%s" "$TARGET" | sed 's/\./\\./g')" "$CRT_HTML" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^\*\.\?//g' \
    | sed '/^$/d' \
    | sort -u > "$CRT_SUBS" || true
fi

cat "$CRT_SUBS" >> "$SUBS" || true
{ echo "$TARGET"; cat "$SUBS"; } | sed '/^$/d' | sort -u > "$OUT/_tmp" && mv "$OUT/_tmp" "$SUBS"
ok "crt subs: $(count_lines "$CRT_SUBS") | merged total: $(count_lines "$SUBS")"

# ---------------- 3) httpx probe origins ----------------
step 3 "httpx: probe origins (https/http) → alive_origins.txt"
: > "$SEED"
while read -r h; do
  [[ -z "$h" ]] && continue
  echo "https://$h"
  echo "http://$h"
done < "$SUBS" | sort -u > "$SEED"
ok "seed origins: $(count_lines "$SEED")"

: > "$ALIVE_RAW"; : > "$ALIVE_JSONL"; : > "$ALIVE_ORIGINS"
log "running: $HTTPX_BIN (raw output capture)"
${TIMEOUT_BIN} "$HTTPX_BIN" $H_SILENT -l "$SEED" \
  $H_FOLLOW $H_STATUS $H_TITLE $H_SERVER $H_TECH $H_CLEN \
  $H_THREADS $H_TIMEOUT $H_RETRY \
  | tee "$ALIVE_RAW" >/dev/null || true
cat "$ALIVE_RAW" | extract_urls_any > "$ALIVE_ORIGINS" || true
ok "alive origins: $(count_lines "$ALIVE_ORIGINS")"

if [[ -n "$H_JSON" ]]; then
  log "running: $HTTPX_BIN (jsonl capture; optional)"
  ${TIMEOUT_BIN} "$HTTPX_BIN" $H_SILENT -l "$SEED" \
    $H_FOLLOW $H_STATUS $H_TITLE $H_SERVER $H_TECH $H_CLEN \
    $H_THREADS $H_TIMEOUT $H_RETRY $H_JSON \
    | tee "$ALIVE_JSONL" >/dev/null || true
  ok "jsonl lines: $(count_lines "$ALIVE_JSONL")"
fi

echo -e "URL\tSTATUS\tTITLE\tTECH\tSERVER\tLEN" > "$ALIVE_TSV"
if [[ "$JQ_OK" == "yes" && -s "$ALIVE_JSONL" ]] && is_jsonl_file "$ALIVE_JSONL"; then
  jq -r 'select(.url!=null) | [.url, (.status_code//""), (.title//""), ((.tech//[])|join(";")), (.server//""), (.content_length//"")] | @tsv' \
    "$ALIVE_JSONL" 2>/dev/null >> "$ALIVE_TSV" || warn "jq parse failed for alive_origins.jsonl (kept URL-only)"
else
  while read -r u; do echo -e "${u}\t\t\t\t\t"; done < "$ALIVE_ORIGINS" >> "$ALIVE_TSV" || true
fi
ok "wrote: $ALIVE_TSV ($(count_lines "$ALIVE_TSV") lines)"

# ---------------- 4) Wayback/CDX URLs ----------------
step 4 "Wayback/CDX: collect historical URLs → wayback_urls_all.txt"
: > "$WB_ALL"

fetch_cdx_origin() {
  local origin="$1"
  local host="${origin#*//}"; host="${host%%/*}"
  curl -sS -A "$UA" "https://web.archive.org/cdx/search/cdx?url=${host}/*&output=text&fl=original&collapse=urlkey" \
    | sed '/^$/d' || true
}

fetch_way_tool() {
  local origin="$1"
  local host="${origin#*//}"; host="${host%%/*}"
  if [[ "$WAY_TOOL" == "gau" ]]; then
    gau --subs "$host" 2>/dev/null | sed '/^$/d' || true
  elif [[ "$WAY_TOOL" == "waybackurls" ]]; then
    printf "%s\n" "$host" | waybackurls 2>/dev/null | sed '/^$/d' || true
  fi
}

aliveN="$(count_lines "$ALIVE_ORIGINS")"
if [[ "$aliveN" == "0" ]]; then
  warn "No alive origins → skipping wayback collection (Step 4/5/6 will be empty)."
else
  i=0
  while read -r origin; do
    [[ -z "$origin" ]] && continue
    i=$((i+1))
    progress_line "$i" "$aliveN" "collecting URLs for ${origin}"
    [[ -n "$WAY_TOOL" ]] && fetch_way_tool "$origin" >> "$WB_ALL" || true
    fetch_cdx_origin "$origin" >> "$WB_ALL" || true
    (( i % 25 == 0 )) && sleep 0.2
  done < "$ALIVE_ORIGINS"
  echo
fi

sed '/^$/d' "$WB_ALL" | sort -u > "$OUT/_tmp" && mv "$OUT/_tmp" "$WB_ALL"
ok "wayback URLs: $(count_lines "$WB_ALL")"
[[ "$(count_lines "$WB_ALL")" -lt 10 ]] && warn "Wayback URL count is low (could be normal or rate-limited)."

# ---------------- 5) httpx probe wayback URLs ----------------
step 5 "httpx: probe wayback URLs → alive_wayback_urls.txt"
: > "$WB_RAW"; : > "$WB_ALIVE"
if [[ -s "$WB_ALL" ]]; then
  ${TIMEOUT_BIN} "$HTTPX_BIN" $H_SILENT -l "$WB_ALL" \
    $H_FOLLOW $H_STATUS $H_TITLE $H_SERVER $H_TECH $H_CLEN \
    $H_THREADS $H_TIMEOUT $H_RETRY \
    | tee "$WB_RAW" >/dev/null || true
  cat "$WB_RAW" | extract_urls_any > "$WB_ALIVE" || true
fi
ok "alive wayback URLs: $(count_lines "$WB_ALIVE")"

echo -e "URL\tSTATUS\tTITLE\tTECH\tSERVER\tLEN" > "$WB_ALIVE_TSV"
while read -r u; do echo -e "${u}\t\t\t\t\t"; done < "$WB_ALIVE" >> "$WB_ALIVE_TSV" || true
ok "wrote: $WB_ALIVE_TSV ($(count_lines "$WB_ALIVE_TSV") lines)"

# ---------------- 6) Param scoring ----------------
step 6 "Risk parameter scoring (A+B+C) → param_findings.tsv + top_urls.tsv"
echo -e "SCORE\tCATEGORY\tPARAM\tVALUE_HINT\tURL\tWHY" > "$PARAM_FIND"
echo -e "SCORE_SUM\tTOP_CATEGORY\tURL\tWHY\tPARAMS_COUNT" > "$TOP_URLS"
echo -e "PARAM\tCOUNT\tCATEGORY_GUESS\tEXAMPLE_URL" > "$PARAM_STATS"

declare -A CAT_REGEX=(
  [REDIRECT]='(^|_)(next|url|uri|return|redirect|dest|destination|continue|callback|cb|goto|to|r|ret|returnto|return_url|redirect_uri|redir|target)($|_)'
  [FILEPATH]='(^|_)(file|path|page|template|include|inc|download|doc|document|folder|dir|attachment|name)($|_)'
  [SECRET]='(^|_)(token|access|apikey|api_key|key|secret|jwt|session|sid|sso|code|auth|password|pass|signature|sig|bearer)($|_)'
  [IDOR]='(^|_)(id|uid|user|user_id|account|acct|order|invoice|payment|profile|role|group|tenant|org|customer|member)($|_)'
  [REFLECT]='(^|_)(q|query|search|keyword|term|s|filter|sort|ref|message|comment|text)($|_)'
  [DEBUG]='(^|_)(debug|dbg|test|staging|internal|admin|config|env|dev|preview|trace|verbose)($|_)'
  [SSRF_HINT]='(^|_)(url|uri|host|domain|endpoint|webhook|feed|fetch|proxy|dest|target|callback|remote)($|_)'
  [TRACKING]='(^|_)(utm_|gclid|fbclid|msclkid|source|campaign|channel|referrer)($|_)'
)
guess_category() {
  local p="$1" lp; lp="$(echo "$p" | tr '[:upper:]' '[:lower:]')"
  for k in "${!CAT_REGEX[@]}"; do
    echo "$lp" | grep -Eq "${CAT_REGEX[$k]}" && { echo "$k"; return 0; }
  done
  echo "UNKNOWN"
}

is_urlish(){ echo "$1" | grep -Eq '^(https?:)?//'; }
is_internal_host(){ echo "$1" | grep -Eq '(^|[^0-9])(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' || echo "$1" | grep -Eq '(localhost|0\.0\.0\.0)'; }
is_pathish(){ echo "$1" | grep -Eq '(\.\./|%2e%2e|\\|/etc/|/proc/|/windows/|c:%5c|c:\\)'; }
has_sensitive_ext(){ echo "$1" | grep -Eqi '\.(pdf|zip|bak|sql|env|pem|key|p12|pfx|log|tar|gz|7z|rar|db|sqlite)(\b|$)'; }
looks_random(){ local v="$1"; [[ "${#v}" -ge 20 ]] && echo "$v" | grep -Eq '[A-Za-z]' && echo "$v" | grep -Eq '[0-9]'; }
is_jwt(){ [[ "$1" =~ ^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; }

: > "$OUT/_param_counts.tsv"
if [[ -s "$WB_ALIVE" ]]; then
  awk -F'\\?' 'NF>1{print $2"\t"$0}' "$WB_ALIVE" \
  | awk -F'\t' '
    { qs=$1; url=$2; gsub(/#.*/, "", qs);
      n=split(qs, parts, "&");
      for(i=1;i<=n;i++){ split(parts[i], kv, "="); k=kv[1];
        if(k!=""){cnt[k]++; if(!(k in ex)) ex[k]=url;}
      }
    }
    END{ for(k in cnt) print k"\t"cnt[k]"\t"ex[k]; }
  ' | sort -t$'\t' -k2,2nr > "$OUT/_param_counts.tsv"
fi

declare -A PCNT
if [[ -s "$OUT/_param_counts.tsv" ]]; then
  while IFS=$'\t' read -r p c ex; do
    [[ -z "$p" ]] && continue
    PCNT["$p"]="$c"
    echo -e "${p}\t${c}\t$(guess_category "$p")\t${ex}" >> "$PARAM_STATS"
  done < "$OUT/_param_counts.tsv"
fi

if [[ -s "$WB_ALIVE" ]]; then
  while read -r url; do
    [[ "$url" != *"?"* ]] && continue
    qs="${url#*\?}"; qs="${qs%%#*}"
    IFS='&' read -ra parts <<< "$qs"
    for part in "${parts[@]}"; do
      key="${part%%=*}"; val=""; [[ "$part" == *"="* ]] && val="${part#*=}"
      [[ -z "$key" ]] && continue
      lkey="$(echo "$key" | tr '[:upper:]' '[:lower:]')"
      lval="$(echo "$val" | tr '[:upper:]' '[:lower:]')"
      catg="$(guess_category "$lkey")"
      score=0; why=()

      case "$catg" in
        SECRET) score=$((score+30)); why+=("secret-name");;
        REDIRECT) score=$((score+24)); why+=("redirect-name");;
        FILEPATH) score=$((score+20)); why+=("file/path-name");;
        SSRF_HINT) score=$((score+14)); why+=("url/host-name");;
        DEBUG) score=$((score+18)); why+=("debug-name");;
        IDOR) score=$((score+14)); why+=("idor-name");;
        REFLECT) score=$((score+10)); why+=("reflect-name");;
        *) ;;
      esac

      is_urlish "$lval" && { score=$((score+26)); why+=("url-like-value"); }
      is_internal_host "$lval" && { score=$((score+38)); why+=("internal-target"); }
      is_pathish "$lval" && { score=$((score+32)); why+=("path/traversal-ish"); }
      has_sensitive_ext "$lval" && { score=$((score+26)); why+=("sensitive-ext"); }
      is_jwt "$val" && { score=$((score+42)); why+=("jwt-looking"); }
      looks_random "$val" && { score=$((score+16)); why+=("high-entropy"); }

      c="${PCNT[$key]:-0}"
      if [[ "$c" -gt 0 && "$c" -le 2 ]]; then
        echo "$lkey" | grep -Eq '^(x_|dbg_|debug_|internal_|admin_|redirect_)' && { score=$((score+20)); why+=("rare+prefix"); }
        [[ "${#key}" -ge 18 ]] && { score=$((score+10)); why+=("rare+long-param"); }
      fi

      if [[ "$score" -ge 25 ]]; then
        hint="$val"; [[ "${#hint}" -gt 60 ]] && hint="${hint:0:60}..."
        why_s="$(IFS=','; echo "${why[*]}")"
        echo -e "${score}\t${catg}\t${key}\t${hint}\t${url}\t${why_s}" >> "$PARAM_FIND"
      fi
    done
  done < "$WB_ALIVE"
fi

if [[ -s "$PARAM_FIND" ]]; then
  awk -F'\t' 'NR>1{sum[$5]+=$1; cnt[$5]++; if(!(top[$5])) top[$5]=$2}
    END{for(u in sum) print sum[u]"\t"top[u]"\t"u"\tparam signals\t"cnt[u]}
  ' "$PARAM_FIND" | sort -nr -k1,1 | head -n 150 \
    | sed '1iSCORE_SUM\tTOP_CATEGORY\tURL\tWHY\tPARAMS_COUNT' > "$TOP_URLS"
fi

ok "param_findings: $(count_lines "$PARAM_FIND") lines (incl header)"
ok "top_urls: $(count_lines "$TOP_URLS") lines (incl header)"
ok "param_stats: $(count_lines "$PARAM_STATS") lines (incl header)"

# ---------------- 7) HTML report ----------------
step 7 "HTML report → report.html"
REPORT="$OUT/report.html"

sub_count="$(count_lines "$SUBS")"
alive_orig_count="$(count_lines "$ALIVE_ORIGINS")"
wb_all_count="$(count_lines "$WB_ALL")"
wb_alive_count="$(count_lines "$WB_ALIVE")"
param_find_count="$(( $(count_lines "$PARAM_FIND") > 0 ? $(count_lines "$PARAM_FIND")-1 : 0 ))"

cat > "$REPORT" <<HTML
<!doctype html><html lang="tr"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>reconm0nster Report - ${TARGET} - ${TS}</title>
<style>
:root{--bg:#0b1020;--muted:#93a4c7;--text:#eaf0ff;--a:#7dd3fc;--line:rgba(255,255,255,.08);}
body{margin:0;background:radial-gradient(800px 400px at 20% 0%, rgba(125,211,252,.15), transparent),
radial-gradient(700px 400px at 90% 20%, rgba(167,139,250,.12), transparent),var(--bg);
color:var(--text);font:14px/1.55 system-ui,-apple-system,Segoe UI,Roboto,Arial;}
.wrap{max-width:1200px;margin:0 auto;padding:28px;}
h1{font-size:22px;margin:0 0 8px;} h2{font-size:16px;margin:22px 0 10px;}
.muted{color:var(--muted); margin-top:8px;}
.grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:12px}
.card{background:linear-gradient(180deg, rgba(255,255,255,.06), rgba(255,255,255,.03));
border:1px solid var(--line); border-radius:14px; padding:14px;}
.kpi{font-size:18px;font-weight:700;margin-top:8px}
.label{color:var(--muted);font-size:12px}
a{color:var(--a);text-decoration:none} a:hover{text-decoration:underline}
table{width:100%;border-collapse:collapse;overflow:hidden;border-radius:12px;border:1px solid var(--line)}
th,td{padding:10px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{font-size:12px;color:var(--muted);text-align:left;background:rgba(255,255,255,.03)}
tr:hover td{background:rgba(255,255,255,.02)}
code{background:rgba(255,255,255,.06);padding:2px 6px;border-radius:8px}
</style></head><body><div class="wrap">
<h1>${TARGET} — reconm0nster report (${TS})</h1>
<div class="muted">httpx: <b>$(printf "%s" "$HTTPX_BIN" | escape_html)</b> • jq=${JQ_OK} • wayback-tool=${WAY_TOOL:-none}</div>

<div class="grid" style="margin-top:14px">
  <div class="card"><div class="label">Subdomains</div><div class="kpi">${sub_count}</div></div>
  <div class="card"><div class="label">Alive origins</div><div class="kpi">${alive_orig_count}</div></div>
  <div class="card"><div class="label">Wayback URLs collected</div><div class="kpi">${wb_all_count}</div></div>
  <div class="card"><div class="label">Alive wayback URLs</div><div class="kpi">${wb_alive_count}</div></div>
  <div class="card"><div class="label">Param findings</div><div class="kpi">${param_find_count}</div></div>
  <div class="card"><div class="label">Mode</div><div class="kpi">No Exploit</div></div>
</div>

<div class="card" style="margin-top:12px"><h2>Top URLs to Review (Scored)</h2>
HTML
tsv_to_table "$TOP_URLS" 140 >> "$REPORT"
cat >> "$REPORT" <<HTML
</div>

<div class="card" style="margin-top:12px"><h2>Param Findings (Detailed)</h2>
HTML
tsv_to_table "$PARAM_FIND" 200 >> "$REPORT"
cat >> "$REPORT" <<HTML
</div>

<div class="card" style="margin-top:12px"><h2>Param Stats (Frequency)</h2>
HTML
tsv_to_table "$PARAM_STATS" 180 >> "$REPORT"
cat >> "$REPORT" <<HTML
</div>

<div class="card" style="margin-top:12px"><h2>Alive Origins</h2>
HTML
tsv_to_table "$ALIVE_TSV" 120 >> "$REPORT"
cat >> "$REPORT" <<HTML
</div>

<div class="card" style="margin-top:12px"><h2>Alive Wayback URLs</h2>
HTML
tsv_to_table "$WB_ALIVE_TSV" 140 >> "$REPORT"
cat >> "$REPORT" <<HTML
</div>

<div class="muted" style="margin-top:14px">
Folder: <code>$(printf "%s" "$OUT" | escape_html)</code><br/>
Report: <code>report.html</code><br/>
If some panels are empty: check <code>WARNINGS.txt</code> and raw logs (<code>alive_origins.raw</code>, <code>alive_wayback_urls.raw</code>).
</div>

</div></body></html>
HTML

ok "report: $REPORT"
ok "done: $OUT"
