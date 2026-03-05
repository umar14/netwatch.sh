#!/usr/bin/env bash
# netwatch.sh — Active TCP connections with IP→country resolution
# macOS · requires: python3 (built-in on macOS)

set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

FILTER_STATE=""; FILTER_COUNTRY=""; SHOW_LISTEN=0
WATCH_MODE=0; WATCH_INTERVAL=5; NO_COLOR=0

usage() {
  echo -e "${BOLD}Usage:${RESET} $(basename "$0") [options]"
  echo "  -s <STATE>    Filter by TCP state (ESTABLISHED, TIME_WAIT …)"
  echo "  -c <STR>      Filter by country name (case-insensitive)"
  echo "  -l            Include LISTEN sockets"
  echo "  -w [N]        Watch mode, refresh every N seconds (default 5)"
  echo "  -n            No colour"
  echo "  -h            Help"
  echo ""
  echo "  Examples:"
  echo "    $(basename "$0") -s ESTABLISHED"
  echo "    $(basename "$0") -c 'United States'"
  echo "    $(basename "$0") -w 3"
  exit 0
}

while getopts "s:c:lw:nh" opt; do
  case $opt in
    s) FILTER_STATE="$OPTARG"   ;;
    c) FILTER_COUNTRY="$OPTARG" ;;
    l) SHOW_LISTEN=1 ;;
    w) WATCH_MODE=1; [[ "$OPTARG" =~ ^[0-9]+$ ]] && WATCH_INTERVAL="$OPTARG" ;;
    n) NO_COLOR=1   ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ $NO_COLOR -eq 1 ]] && {
  RED=''; YELLOW=''; GREEN=''; CYAN=''; BLUE=''; MAGENTA=''; BOLD=''; DIM=''; RESET=''
}

is_private() {
  local ip="$1"
  [[ "$ip" =~ ^(127\.|10\.|192\.168\.|169\.254\.) ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]       && return 0
  [[ "$ip" =~ ^(::1$|fe80|fc|fd) ]]                   && return 0
  return 1
}

state_color() {
  case "$1" in
    ESTABLISHED) printf '%b' "${GREEN}${BOLD}$1${RESET}" ;;
    TIME_WAIT)   printf '%b' "${YELLOW}$1${RESET}"       ;;
    CLOSE_WAIT)  printf '%b' "${RED}$1${RESET}"          ;;
    SYN_SENT)    printf '%b' "${CYAN}$1${RESET}"         ;;
    FIN_WAIT*)   printf '%b' "${MAGENTA}$1${RESET}"      ;;
    *)           printf '%b' "${DIM}$1${RESET}"          ;;
  esac
}

port_label() {
  case "$1" in
    80)    echo "HTTP"      ;; 443)   echo "HTTPS"     ;;
    22)    echo "SSH"       ;; 21)    echo "FTP"       ;;
    25)    echo "SMTP"      ;; 587)   echo "SMTP"      ;;
    993)   echo "IMAPS"     ;; 995)   echo "POP3S"     ;;
    53)    echo "DNS"       ;; 3306)  echo "MySQL"     ;;
    5432)  echo "Postgres"  ;; 6379)  echo "Redis"     ;;
    27017) echo "MongoDB"   ;; 8080)  echo "HTTP-Alt"  ;;
    8443)  echo "HTTPS-Alt" ;; 3389)  echo "RDP"       ;;
    5900)  echo "VNC"       ;; 1194)  echo "OpenVPN"   ;;
    123)   echo "NTP"       ;; *)     echo ""          ;;
  esac
}

declare -a CONNS=()
declare -A GEO=()

get_connections() {
  CONNS=()

  declare -A LSOF_MAP=()
  if command -v lsof &>/dev/null; then
    while IFS= read -r ln; do
      local proc pid conn_col raddr
      proc=$(awk '{print $1}' <<<"$ln")
      pid=$(awk  '{print $2}' <<<"$ln")
      conn_col=$(awk '{print $9}' <<<"$ln")
      raddr="${conn_col##*->}"
      [[ -n "$raddr" && "$raddr" != "$conn_col" ]] && LSOF_MAP["$raddr"]="${pid}/${proc}"
    done < <(lsof -nP -iTCP 2>/dev/null | tail -n +2 || true)
  fi

  local raw
  raw=$(netstat -n -p tcp -f inet 2>/dev/null || true)

  while IFS= read -r line; do
    [[ "$line" =~ ^tcp ]] || continue

    local state local_raw remote_raw
    state=$(     awk '{print $6}' <<<"$line")
    local_raw=$( awk '{print $4}' <<<"$line")
    remote_raw=$(awk '{print $5}' <<<"$line")

    [[ "$state" == "LISTEN" && $SHOW_LISTEN -eq 0 ]] && continue
    [[ "$remote_raw" =~ \*$  || -z "$remote_raw"  ]] && continue
    [[ -n "$FILTER_STATE" && "$state" != "$FILTER_STATE" ]] && continue

    local rip rport
    rport="${remote_raw##*.}"
    rip="${remote_raw%.*}"

    [[ -z "$rip" || "$rip" == "*" ]] && continue
    [[ ! "$rport" =~ ^[0-9]+$ ]]     && continue

    local proc="${LSOF_MAP[${rip}:${rport}]:-—}"
    CONNS+=("${state}|${rip}|${rport}|${proc}")
  done <<<"$raw"
}

lookup_countries() {
  local -a todo=()
  for c in "${CONNS[@]}"; do
    local ip
    ip=$(cut -d'|' -f2 <<<"$c")
    is_private "$ip" && continue
    [[ -n "${GEO[$ip]+x}" ]] && continue
    local dup=0
    for x in "${todo[@]:-}"; do [[ "$x" == "$ip" ]] && dup=1 && break; done
    [[ $dup -eq 0 ]] && todo+=("$ip")
  done

  [[ ${#todo[@]} -eq 0 ]] && return

  printf '%b' "  ${DIM}Looking up ${#todo[@]} IP(s) via ip-api.com...${RESET}\r"

  local result
  result=$(python3 - "${todo[@]}" <<'PYEOF'
import sys, json, urllib.request

ips = sys.argv[1:]
payload = json.dumps(ips).encode()
req = urllib.request.Request(
    "http://ip-api.com/batch?fields=query,country,countryCode,org",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST"
)
try:
    with urllib.request.urlopen(req, timeout=12) as r:
        data = json.loads(r.read())
    for entry in data:
        q  = entry.get("query", "")
        c  = entry.get("country", "Unknown")
        cc = entry.get("countryCode", "??")
        o  = entry.get("org", "")
        print(f"{q}\t{c}\t{cc}\t{o}")
except Exception as e:
    sys.stderr.write(f"lookup failed: {e}\n")
PYEOF
  )

  while IFS=$'\t' read -r ip country cc org; do
    [[ -n "$ip" ]] && GEO["$ip"]="${country}|${cc}|${org}"
  done <<<"$result"

  printf '%b' "                                                  \r"
}

print_table() {
  local hr; hr=$(printf '─%.0s' {1..100})
  echo ""
  echo -e "${BOLD}${BLUE}  ⬡ netwatch${RESET}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${RESET}"
  echo -e "${DIM}  ${hr}${RESET}"
  printf "${BOLD}  %-20s  %-17s  %-12s  %-26s  %-26s  %s${RESET}\n" \
    STATE "REMOTE IP" PORT COUNTRY ORGANIZATION PROCESS
  echo -e "${DIM}  ${hr}${RESET}"

  local total=0 est=0 tw=0 cw=0

  for c in "${CONNS[@]:-}"; do
    [[ -z "$c" ]] && continue
    IFS='|' read -r state rip rport proc <<<"$c"

    local country="" cc="" org=""
    if is_private "$rip"; then
      country="Local / Private"; cc=""; org=""
    else
      local geo="${GEO[$rip]:-}"
      if [[ -n "$geo" ]]; then
        IFS='|' read -r country cc org <<<"$geo"
      else
        country="Unknown"; cc=""; org=""
      fi
    fi

    if [[ -n "$FILTER_COUNTRY" ]]; then
      python3 -c "
import sys
sys.exit(0 if sys.argv[2].lower() in sys.argv[1].lower() else 1)
" "$country" "$FILTER_COUNTRY" 2>/dev/null || continue
    fi

    local svc; svc=$(port_label "$rport")
    local plabel="$rport"
    [[ -n "$svc" ]] && plabel="${rport}/${svc}"

    local scol; scol=$(state_color "$state")
    local pad=$(( 20 - ${#state} ))
    local spaces; spaces=$(printf "%${pad}s" "")

    printf "  %b%s  ${CYAN}%-17s${RESET}  ${YELLOW}%-12s${RESET}  %-26s  ${DIM}%-26s${RESET}  ${MAGENTA}%s${RESET}\n" \
      "$scol" "$spaces" \
      "$rip" "$plabel" \
      "${country:0:25}" "${org:0:25}" "${proc:0:20}"

    total=$((total+1))
    [[ "$state" == "ESTABLISHED" ]] && est=$((est+1))
    [[ "$state" == "TIME_WAIT"   ]] && tw=$((tw+1))
    [[ "$state" == "CLOSE_WAIT"  ]] && cw=$((cw+1))
  done

  echo -e "${DIM}  ${hr}${RESET}"
  echo -e "  ${BOLD}Total: $total${RESET}  ${GREEN}Established: $est${RESET}  ${YELLOW}Time-Wait: $tw${RESET}  ${RED}Close-Wait: $cw${RESET}"
  echo ""
}

run_once() {
  get_connections
  lookup_countries
  print_table
}

if [[ $WATCH_MODE -eq 1 ]]; then
  echo -e "${DIM}Watch mode — Ctrl-C to quit${RESET}"
  while true; do
    clear
    run_once
    sleep "$WATCH_INTERVAL"
  done
else
  run_once
fi
