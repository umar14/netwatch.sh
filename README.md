# netwatch

A lightweight macOS CLI tool that displays active TCP connections enriched with real-time IP-to-country resolution. No dependencies beyond what ships with every Mac.

![bash](https://img.shields.io/badge/shell-bash-blue) ![macOS](https://img.shields.io/badge/platform-macOS-lightgrey) ![license](https://img.shields.io/badge/license-MIT-green)

## Demo
```
  ⬡ netwatch  2024-01-15 14:32:07
  ────────────────────────────────────────────────────────────────────────────────────────────────────
  STATE                 REMOTE IP          PORT          COUNTRY                    ORGANIZATION               PROCESS
  ────────────────────────────────────────────────────────────────────────────────────────────────────
  ESTABLISHED           142.250.80.46      443/HTTPS     United States              AS15169 Google LLC         1204/chrome
  ESTABLISHED           185.199.108.153    443/HTTPS     United States              AS36459 GitHub, Inc.       2501/git
  ESTABLISHED           91.108.56.181      443/HTTPS     Netherlands                AS62041 Telegram           1568/telegram
  ESTABLISHED           1.1.1.1            443/HTTPS     Australia                  AS13335 Cloudflare         892/firefox
  TIME_WAIT             216.58.212.78      80/HTTP       United States              AS15169 Google LLC         —
  CLOSE_WAIT            52.27.69.240       443/HTTPS     United States              AS16509 Amazon.com         3201/zoom
  ────────────────────────────────────────────────────────────────────────────────────────────────────
  Total: 6  Established: 4  Time-Wait: 1  Close-Wait: 1
```

## Features

- **IP-to-country resolution** — batches all unique public IPs into a single API call via [ip-api.com](http://ip-api.com) (free, no key required)
- **Process names** — maps each connection to its owning process and PID via `lsof`
- **Port labels** — common ports (443, 22, 3306 …) are annotated with their service name
- **Colour-coded states** — `ESTABLISHED` (green), `TIME_WAIT` (yellow), `CLOSE_WAIT` (red), `SYN_SENT` (cyan)
- **Watch mode** — live refresh at a configurable interval, like `top` for connections
- **Filtering** — filter by TCP state or country name
- **No dependencies** — uses only `bash`, `netstat`, `lsof`, and `python3`, all of which ship with macOS
- **CSV export** — pipe with `-n` for clean output suitable for logging or further processing

## Requirements

| Tool | Comes with macOS? |
|---|---|
| `bash` | Yes (3.2+, or install bash 5 via Homebrew) |
| `python3` | Yes (macOS 12.3+) |
| `netstat` | Yes |
| `lsof` | Yes |

> **Note:** Process names require `lsof`, which may prompt for local network access permissions on first run on macOS Ventura and later.

## Installation
```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/netwatch/main/netwatch.sh](https://github.com/umar14/netwatch.sh/blob/main/netwatch.sh
chmod +x netwatch.sh

# Optionally install system-wide
sudo mv netwatch.sh /usr/local/bin/netwatch
```

## Usage
```bash
./netwatch.sh [options]
```

| Option | Description |
|---|---|
| `-s <STATE>` | Filter by TCP state (`ESTABLISHED`, `TIME_WAIT`, `CLOSE_WAIT` …) |
| `-c <STR>` | Filter by country name (case-insensitive substring) |
| `-l` | Include `LISTEN` sockets |
| `-w [N]` | Watch mode — refresh every N seconds (default: 5) |
| `-n` | Disable colour output |
| `-h` | Show help |

### Examples
```bash
# All active connections
./netwatch.sh

# Only established connections
./netwatch.sh -s ESTABLISHED

# Connections to US-based servers
./netwatch.sh -c 'United States'

# Live refresh every 3 seconds
./netwatch.sh -w 3

# Watch only established, refresh every 10s
./netwatch.sh -w 10 -s ESTABLISHED

# No colour — useful for logging
./netwatch.sh -n >> connections.log
```

## How It Works

1. **`netstat -n -p tcp -f inet`** — pulls the raw IPv4 TCP connection table from the macOS network stack
2. **`lsof -nP -iTCP`** — maps each connection's remote address back to a process name and PID
3. **ip-api.com batch API** — all unique public IPs are collected and resolved in a single HTTP POST (up to 100 IPs per request, 45 requests/min on the free tier). The response is parsed entirely in `python3` using only the standard library — no `jq`, no third-party packages
4. Private and loopback addresses (`127.x`, `10.x`, `192.168.x`, `172.16–31.x`) are classified locally without any API call

## Limitations

- **IPv4 only** — `netstat -f inet` is used; IPv6 connections are not currently shown
- **ip-api.com rate limit** — 45 requests/minute on the free tier. Each run counts as 1 request regardless of how many IPs are resolved (batch endpoint). Watch mode with a very short interval on a machine with many connections could approach this limit
- **macOS only** — the `netstat` column layout and address format (`a.b.c.d.PORT`) is macOS-specific. Linux uses a different format

## Contributing

Pull requests are welcome. Some ideas for extensions:

- IPv6 support via `netstat -f inet6`
- `--json` output flag
- Local DNS reverse-lookup option
- Linux compatibility mode

## License

MIT
