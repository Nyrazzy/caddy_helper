#!/usr/bin/env bash
set -Eeuo pipefail

# One-file Caddy installer and reverse proxy helper.
# Supports common Linux distributions and optional one-command reverse proxy setup.

DEFAULT_SELF_URL="https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh"
SCRIPT_VERSION="1.0.0"#当前版本号
DOMAIN=""
UPSTREAM=""
EMAIL=""
HTTP_ONLY=0
INSTALL_ONLY=0
FORCE_STATIC=0
INSTALL_SHORTCUT=0
SELF_URL=""

log() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
err() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }
danger() { printf '\033[1;31m%s\033[0m\n' "$*" >/dev/tty; }
die() { err "$*"; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }
green_text() { printf '\033[1;32m%s\033[0m' "$*"; }
red_text() { printf '\033[1;31m%s\033[0m' "$*"; }

usage() {
  cat <<'EOF'
Usage:
  bash install-caddy.sh [options]

Options:
  --domain DOMAIN       Domain served by Caddy, e.g. example.com
  --upstream URL        Reverse proxy target, e.g. https://www.example.com
  --email EMAIL         ACME email for automatic HTTPS certificates
  --http-only           Listen on port 80 only, useful before DNS is ready
  --install-only        Install Caddy without changing Caddyfile
  --install-shortcut    Install this script as /usr/local/bin/fd
  --self-url URL        URL used by the fd shortcut to update itself
  --force-static        Skip package managers and install official static binary
  -h, --help            Show this help

Examples:
  bash install-caddy.sh --install-only
  bash install-caddy.sh --install-shortcut
  bash install-caddy.sh --domain proxy.example.com --upstream https://www.example.com --email admin@example.com
  bash install-caddy.sh --domain proxy.example.com --upstream https://www.example.com --http-only
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --upstream) UPSTREAM="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --http-only) HTTP_ONLY=1; shift ;;
    --install-only) INSTALL_ONLY=1; shift ;;
    --install-shortcut) INSTALL_SHORTCUT=1; shift ;;
    --self-url) SELF_URL="${2:-}"; shift 2 ;;
    --force-static) FORCE_STATIC=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

prompt() {
  local text default answer
  text="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$text" "$default" >/dev/tty
  else
    printf "%s: " "$text" >/dev/tty
  fi
  IFS= read -r answer </dev/tty || true
  if [ -z "$answer" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$answer"
  fi
}

pause() {
  printf '\n按回车继续...' >/dev/tty
  IFS= read -r _ </dev/tty || true
}

install_shortcut() {
  local target source_path
  target="/usr/local/bin/fd"
  mkdir -p /usr/local/bin
  [ -n "$SELF_URL" ] || SELF_URL="$DEFAULT_SELF_URL"

  if [ -n "$SELF_URL" ]; then
    cat >"$target" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
URL='${SELF_URL}'
if command -v curl >/dev/null 2>&1; then
  exec bash <(curl -q -fsSL "\${URL}?\$(date +%s)") "\$@"
elif command -v wget >/dev/null 2>&1; then
  tmp="\$(mktemp)"
  wget -qO "\$tmp" "\${URL}?\$(date +%s)"
  exec bash "\$tmp" "\$@"
else
  echo "需要先安装 curl 或 wget" >&2
  exit 1
fi
EOF
  else
    source_path="${BASH_SOURCE[0]:-}"
    [ -n "$source_path" ] && [ -r "$source_path" ] || die "无法复制脚本本体。请用：bash <(curl -fsSL ${DEFAULT_SELF_URL}) --install-shortcut --self-url ${DEFAULT_SELF_URL}"
    cp "$source_path" "$target"
  fi

  chmod +x "$target"
  log "快捷命令已安装：fd"
}

[ "$(id -u)" -eq 0 ] || die "请使用 root 用户运行，例如：bash <(curl -fsSL ${DEFAULT_SELF_URL}) --install-shortcut"

if [ "$INSTALL_SHORTCUT" -eq 0 ] && [ "$INSTALL_ONLY" -eq 0 ] && [ -n "$DOMAIN$UPSTREAM" ]; then
  [ -n "$DOMAIN" ] || die "--domain is required unless --install-only is used"
  [ -n "$UPSTREAM" ] || die "--upstream is required unless --install-only is used"
fi

export DEBIAN_FRONTEND=noninteractive
CADDYFILE="/etc/caddy/Caddyfile"
FD_DB="/etc/caddy/fd-proxies.tsv"

pm_update_install() {
  if has apt-get; then
    apt-get update
    apt-get install -y "$@"
  elif has dnf; then
    dnf install -y "$@"
  elif has yum; then
    yum install -y "$@"
  elif has pacman; then
    pacman -Sy --noconfirm "$@"
  elif has apk; then
    apk add --no-cache "$@"
  elif has zypper; then
    zypper --non-interactive install "$@"
  else
    return 1
  fi
}

install_prereqs() {
  if has apt-get; then
    apt-get update
    apt-get install -y ca-certificates curl gpg tar gzip debian-keyring debian-archive-keyring apt-transport-https
  elif has dnf; then
    dnf install -y ca-certificates curl tar gzip
  elif has yum; then
    yum install -y ca-certificates curl tar gzip
  elif has pacman; then
    pacman -Sy --noconfirm ca-certificates curl tar gzip
  elif has apk; then
    apk add --no-cache ca-certificates curl tar gzip
  elif has zypper; then
    zypper --non-interactive install ca-certificates curl tar gzip
  else
    has curl || die "curl is required and no supported package manager was found"
  fi
}

install_with_apt() {
  install_prereqs
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
}

install_with_dnf() {
  install_prereqs
  if has dnf; then
    dnf install -y 'dnf-command(copr)' || dnf install -y dnf-plugins-core || dnf install -y dnf5-plugins
    dnf -y copr enable @caddy/caddy
    dnf install -y caddy
  else
    yum install -y yum-plugin-copr || yum install -y dnf-plugins-core
    yum -y copr enable @caddy/caddy
    yum install -y caddy
  fi
}

install_with_pacman() {
  install_prereqs
  pacman -Syu --noconfirm caddy
}

install_with_apk() {
  install_prereqs
  apk add --no-cache caddy
}

install_with_zypper() {
  install_prereqs
  zypper --non-interactive install caddy
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7*) echo "armv7" ;;
    armv6l|armv6*) echo "armv6" ;;
    i386|i686) echo "386" ;;
    *) die "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

install_static() {
  install_prereqs
  has systemctl || die "Static fallback currently requires systemd. Try your distro package manager manually."

  local arch tmp tarball
  arch="$(detect_arch)"
  tmp="$(mktemp -d)"
  tarball="$tmp/caddy.tar.gz"

  log "Downloading Caddy static binary for linux/${arch}"
  curl -fL "https://caddyserver.com/api/download?os=linux&arch=${arch}" -o "$tarball"
  tar -xzf "$tarball" -C "$tmp"
  install -m 0755 "$tmp/caddy" /usr/bin/caddy

  local nologin
  nologin="/usr/sbin/nologin"
  [ -x "$nologin" ] || nologin="/sbin/nologin"

  groupadd --system caddy 2>/dev/null || true
  id -u caddy >/dev/null 2>&1 || useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell "$nologin" caddy
  mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
  chown -R caddy:caddy /var/lib/caddy /var/log/caddy

  if [ ! -f /etc/caddy/Caddyfile ]; then
    cat >/etc/caddy/Caddyfile <<'EOF'
:80 {
	respond "Caddy is installed and running."
}
EOF
  fi

  cat >/etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now caddy
}

update_static_caddy() {
  install_static
}

update_caddy() {
  if ! has caddy; then
    install_caddy
    return
  fi

  log "当前版本：$(caddy version 2>/dev/null || printf '无法读取')"

  if [ "$FORCE_STATIC" -eq 0 ]; then
    if has apt-get && dpkg -s caddy >/dev/null 2>&1; then
      apt-get update
      local upgradable
      upgradable="$(apt list --upgradable 2>/dev/null | awk -F/ '$1 == "caddy" { print }' || true)"
      if [ -n "$upgradable" ]; then
        log "发现 Caddy 可更新，正在升级..."
        apt-get install --only-upgrade -y caddy
      else
        log "Caddy 已是当前软件源中的最新版本。"
      fi
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    elif has dnf && (rpm -q caddy >/dev/null 2>&1); then
      if dnf check-update caddy >/dev/null 2>&1; then
        log "Caddy 已是当前软件源中的最新版本。"
      else
        case "$?" in
          100)
            log "发现 Caddy 可更新，正在升级..."
            dnf upgrade -y caddy
            ;;
          *)
            warn "无法确认 Caddy 是否有更新，将尝试执行升级。"
            dnf upgrade -y caddy || true
            ;;
        esac
      fi
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    elif has yum && (rpm -q caddy >/dev/null 2>&1); then
      if yum check-update caddy >/dev/null 2>&1; then
        log "Caddy 已是当前软件源中的最新版本。"
      else
        case "$?" in
          100)
            log "发现 Caddy 可更新，正在升级..."
            yum update -y caddy
            ;;
          *)
            warn "无法确认 Caddy 是否有更新，将尝试执行升级。"
            yum update -y caddy || true
            ;;
        esac
      fi
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    elif has pacman && pacman -Q caddy >/dev/null 2>&1; then
      log "正在通过 pacman 同步并更新 Caddy..."
      pacman -Syu --noconfirm caddy
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    elif has apk && apk info -e caddy >/dev/null 2>&1; then
      log "正在通过 apk 检查并更新 Caddy..."
      apk update || true
      apk upgrade caddy || apk add --upgrade caddy
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    elif has zypper && zypper search -i caddy >/dev/null 2>&1; then
      log "正在通过 zypper 检查并更新 Caddy..."
      zypper --non-interactive refresh
      zypper --non-interactive update caddy || true
      log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
      return
    fi
  fi

  warn "无法确认当前 Caddy 是否由系统包管理器安装，将使用官方静态二进制覆盖为最新版。"
  update_static_caddy
  log "更新后版本：$(caddy version 2>/dev/null || printf '无法读取')"
}

install_or_update_caddy() {
  if has caddy; then
    update_caddy
  else
    install_caddy
  fi
}

install_caddy() {
  if has caddy; then
    log "Caddy already exists: $(command -v caddy)"
    return
  fi

  if [ "$FORCE_STATIC" -eq 0 ]; then
    if has apt-get; then
      install_with_apt && return
    elif has dnf || has yum; then
      install_with_dnf && return
    elif has pacman; then
      install_with_pacman && return
    elif has apk; then
      install_with_apk && return
    elif has zypper; then
      install_with_zypper && return
    fi
  fi

  warn "Package install path was unavailable or skipped; using static binary fallback."
  install_static
}

normalize_url_host() {
  printf '%s\n' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*$##; s#:.*$##'
}

normalize_upstream_url() {
  local value scheme rest host
  value="$1"
  case "$value" in
    http://*) scheme="http"; rest="${value#http://}" ;;
    https://*) scheme="https"; rest="${value#https://}" ;;
    *) scheme="https"; rest="$value" ;;
  esac
  host="$(printf '%s\n' "$rest" | sed -E 's#[/?#].*$##')"
  printf '%s://%s' "$scheme" "$host"
}

is_ipv4() {
  local value="$1" part
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a part <<<"$value"
  [ "${#part[@]}" -eq 4 ] || return 1
  local n
  for n in "${part[@]}"; do
    [ "$n" -ge 0 ] 2>/dev/null && [ "$n" -le 255 ] 2>/dev/null || return 1
  done
}

is_valid_hostname() {
  local value="$1" label
  [ "$value" = "localhost" ] && return 0
  is_ipv4 "$value" && return 0
  [[ "$value" == *.* ]] || return 1
  [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  [[ "$value" != .* && "$value" != *. ]] || return 1
  [[ "$value" != *..* ]] || return 1
  local -a labels
  IFS=. read -r -a labels <<<"$value"
  for label in "${labels[@]}"; do
    [ -n "$label" ] || return 1
    [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

is_valid_domain() {
  local value="$1"
  [[ "$value" != http://* && "$value" != https://* ]] || return 1
  [[ "$value" != *"/"* && "$value" != *":"* ]] || return 1
  is_valid_hostname "$value"
}

is_valid_upstream() {
  local value="$1" host port
  [[ "$value" == http://* || "$value" == https://* ]] || return 1
  [[ "$value" != *"/"* || "$value" =~ ^https?://[^/]+/?$ ]] || return 1
  host="$(normalize_url_host "$value")"
  [ -n "$host" ] || return 1
  port="$(printf '%s\n' "$value" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*$##' | awk -F: 'NF > 1 { print $NF }')"
  if [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]]; then
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
  fi
  is_valid_hostname "$host"
}

is_valid_email() {
  local value="$1"
  [ -z "$value" ] && return 0
  [[ "$value" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

backup_caddyfile() {
  mkdir -p /etc/caddy
  if [ -f "$CADDYFILE" ]; then
    cp -a "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

ensure_proxy_db() {
  mkdir -p /etc/caddy
  [ -f "$FD_DB" ] && return
  : >"$FD_DB"

  [ -f "$CADDYFILE" ] || return
  awk '
    function clean_site(value) {
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      sub(/^http:\/\//, "", value)
      sub(/^https:\/\//, "", value)
      split(value, parts, /[, \t]+/)
      return parts[1]
    }
    BEGIN { depth = 0; site = ""; upstream = ""; http_only = 0 }
    /^[ \t]*#/ { next }
    depth == 0 && $0 ~ /^[^ \t{}][^{]*[ \t]*\{[ \t]*$/ && $0 !~ /^\{/ {
      site = $0
      sub(/[ \t]*\{[ \t]*$/, "", site)
      http_only = (site ~ /^http:\/\//) ? 1 : 0
      site = clean_site(site)
      upstream = ""
      depth = 1
      next
    }
    depth > 0 {
      line = $0
      if (line ~ /^[ \t]*reverse_proxy[ \t]+/) {
        split(line, fields, /[ \t]+/)
        upstream = fields[2]
      }
      opens = gsub(/\{/, "{", line)
      closes = gsub(/\}/, "}", line)
      depth += opens - closes
      if (depth == 0) {
        if (site != "" && upstream != "") {
          print site "\t" upstream "\t" http_only "\t"
        }
        site = ""; upstream = ""; http_only = 0
      }
    }
  ' "$CADDYFILE" | awk -F '\t' 'NF >= 3 && !seen[$1]++' >"$FD_DB"
}

load_proxy_arrays() {
  ensure_proxy_db
  normalize_proxy_db
  PROXY_DOMAINS=()
  PROXY_UPSTREAMS=()
  PROXY_HTTP_ONLY=()
  PROXY_EMAILS=()
  while IFS="$(printf '\t')" read -r d u h e; do
    [ -n "${d:-}" ] || continue
    PROXY_DOMAINS+=("$d")
    PROXY_UPSTREAMS+=("$u")
    PROXY_HTTP_ONLY+=("${h:-0}")
    PROXY_EMAILS+=("${e:-}")
  done <"$FD_DB"
}

normalize_proxy_db() {
  [ -f "$FD_DB" ] || return
  local tmp d u h e clean
  tmp="$(mktemp)"
  while IFS="$(printf '\t')" read -r d u h e; do
    [ -n "${d:-}" ] || continue
    clean="$(normalize_upstream_url "$u")"
    if is_valid_domain "$d" && is_valid_upstream "$clean"; then
      awk -F '\t' -v d="$d" '$1 == d { found = 1 } END { exit found ? 0 : 1 }' "$tmp" 2>/dev/null && continue
      printf '%s\t%s\t%s\t%s\n' "$d" "$clean" "${h:-0}" "${e:-}" >>"$tmp"
    fi
  done <"$FD_DB"
  mv "$tmp" "$FD_DB"
}

proxy_count() {
  load_proxy_arrays
  printf '%s' "${#PROXY_DOMAINS[@]}"
}

print_proxy_list() {
  load_proxy_arrays
  if [ "${#PROXY_DOMAINS[@]}" -eq 0 ]; then
    printf '\n当前还没有脚本管理的反代配置。\n' >/dev/tty
    return 1
  fi

  printf '\n当前反代列表：\n' >/dev/tty
  local i mode status
  for i in "${!PROXY_DOMAINS[@]}"; do
    if [ "${PROXY_HTTP_ONLY[$i]}" = "1" ]; then
      mode="HTTP"
    else
      mode="HTTPS"
    fi
    if proxy_is_success "${PROXY_DOMAINS[$i]}" "${PROXY_UPSTREAMS[$i]}"; then
      status="$(green_text 成功)"
    else
      status="$(red_text 失败)"
    fi
    printf '  %s. %s  ->  %s  [%s]  %b\n' "$((i + 1))" "${PROXY_DOMAINS[$i]}" "${PROXY_UPSTREAMS[$i]}" "$mode" "$status" >/dev/tty
  done
}

proxy_is_success() {
  local d="$1" u="$2"
  has caddy || return 1
  [ -f "$CADDYFILE" ] || return 1
  caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1 || return 1
  if has systemctl; then
    systemctl is-active --quiet caddy || return 1
  fi
  grep -Fq "$d" "$CADDYFILE" || return 1
  grep -Fq "$u" "$CADDYFILE" || return 1
}

upsert_proxy_db() {
  ensure_proxy_db
  local tmp
  tmp="$(mktemp)"
  awk -F '\t' -v d="$DOMAIN" '$1 != d { print }' "$FD_DB" >"$tmp"
  printf '%s\t%s\t%s\t%s\n' "$DOMAIN" "$UPSTREAM" "$HTTP_ONLY" "$EMAIL" >>"$tmp"
  mv "$tmp" "$FD_DB"
}

delete_proxy_db_index() {
  load_proxy_arrays
  local index tmp
  index="$1"
  tmp="$(mktemp)"
  awk -F '\t' -v n="$index" 'NR != n { print }' "$FD_DB" >"$tmp"
  mv "$tmp" "$FD_DB"
}

render_caddyfile() {
  ensure_proxy_db
  normalize_proxy_db

  local global_email tmp
  global_email="$(awk -F '\t' '$4 != "" { print $4; exit }' "$FD_DB")"
  tmp="$(mktemp)"

  {
    printf '# This Caddyfile is managed by fd Caddy reverse proxy helper.\n'
    printf '# Edit with: nano /etc/caddy/Caddyfile\n'
    printf '# After manual changes, run: caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && systemctl reload caddy\n\n'
    if [ -n "$global_email" ]; then
      printf '{\n\temail %s\n}\n\n' "$global_email"
    fi

    while IFS="$(printf '\t')" read -r d u h e; do
      [ -n "${d:-}" ] || continue
      local site upstream_host
      if [ "${h:-0}" = "1" ]; then
        site="http://${d}"
      else
        site="$d"
      fi
      upstream_host="$(normalize_url_host "$u")"

      printf '# fd-proxy: %s -> %s\n' "$d" "$u"
      printf '%s {\n' "$site"
      printf '\tencode zstd gzip\n'
      printf '\treverse_proxy %s {\n' "$u"
      printf '\t\theader_up Host %s\n' "$upstream_host"
      printf '\t\theader_up X-Forwarded-Host {host}\n'
      case "$u" in
        https://*)
          printf '\t\ttransport http {\n'
          printf '\t\t\ttls_server_name %s\n' "$upstream_host"
          printf '\t\t}\n'
          ;;
      esac
      printf '\t}\n'
      printf '}\n\n'
    done <"$FD_DB"
  } >"$tmp"

  if has caddy; then
    caddy fmt --overwrite "$tmp" || true
    if ! caddy validate --config "$tmp" --adapter caddyfile; then
      rm -f "$tmp"
      warn "Caddy 配置校验失败，正式配置未修改。"
      return 1
    fi
  fi

  backup_caddyfile
  install -m 0644 "$tmp" "$CADDYFILE"
  rm -f "$tmp"
}

write_caddyfile() {
  local old_db
  ensure_proxy_db
  old_db="$(mktemp)"
  cp -a "$FD_DB" "$old_db"
  upsert_proxy_db
  if ! render_caddyfile; then
    cp -a "$old_db" "$FD_DB"
    rm -f "$old_db"
    return 1
  fi
  rm -f "$old_db"
}

open_firewall_ports() {
  if has ufw; then
    ufw allow 80/tcp || true
    [ "$HTTP_ONLY" -eq 1 ] || ufw allow 443/tcp || true
  fi
  if has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service=http || true
    [ "$HTTP_ONLY" -eq 1 ] || firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
  fi
}

restart_caddy() {
  if has systemctl; then
    systemctl enable caddy >/dev/null 2>&1 || true
    systemctl restart caddy
  else
    service caddy restart || service caddy start || die "Caddy installed, but could not start service automatically"
  fi
}

configure_proxy() {
  install_caddy
  if ! write_caddyfile; then
    warn "配置没有写入成功，已返回主菜单。"
    return
  fi
  open_firewall_ports
  restart_caddy
  log "反代已配置：${DOMAIN} -> ${UPSTREAM}"
  log "配置文件：/etc/caddy/Caddyfile"
}

show_caddyfile() {
  if ! print_proxy_list; then
    printf '\n配置文件位置：%s\n' "$CADDYFILE" >/dev/tty
    printf '如果需要手动编辑：nano %s\n' "$CADDYFILE" >/dev/tty
    printf '修改完成后重载：caddy validate --config %s --adapter caddyfile && systemctl reload caddy\n' "$CADDYFILE" >/dev/tty
    return
  fi

  printf '\n输入编号查看对应详细配置；输入 a 查看完整 Caddyfile；输入 0 返回。\n' >/dev/tty
  local choice
  choice="$(prompt '请选择' '0')"
  case "$choice" in
    0|"")
      return
      ;;
    a|A)
      if [ -f "$CADDYFILE" ]; then
        printf '\n========== %s ==========\n' "$CADDYFILE" >/dev/tty
        cat "$CADDYFILE" >/dev/tty
        printf '==========================================\n' >/dev/tty
      else
        warn "还没有找到 $CADDYFILE"
      fi
      ;;
    *)
      load_proxy_arrays
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#PROXY_DOMAINS[@]}" ]; then
        warn "编号无效"
        return
      fi
      local idx d u h site upstream_host
      idx=$((choice - 1))
      d="${PROXY_DOMAINS[$idx]}"
      u="${PROXY_UPSTREAMS[$idx]}"
      h="${PROXY_HTTP_ONLY[$idx]}"
      if [ "$h" = "1" ]; then
        site="http://${d}"
      else
        site="$d"
      fi
      upstream_host="$(normalize_url_host "$u")"
      printf '\n%s  ->  %s\n\n' "$d" "$u" >/dev/tty
      printf '对应配置片段：\n' >/dev/tty
      printf '%s {\n' "$site" >/dev/tty
      printf '\tencode zstd gzip\n' >/dev/tty
      printf '\treverse_proxy %s {\n' "$u" >/dev/tty
      printf '\t\theader_up Host %s\n' "$upstream_host" >/dev/tty
      printf '\t\theader_up X-Forwarded-Host {host}\n' >/dev/tty
      case "$u" in
        https://*)
          printf '\t\ttransport http {\n' >/dev/tty
          printf '\t\t\ttls_server_name %s\n' "$upstream_host" >/dev/tty
          printf '\t\t}\n' >/dev/tty
          ;;
      esac
      printf '\t}\n}\n\n' >/dev/tty
      ;;
  esac

  printf '\n如果要修改，推荐直接回菜单选 2 重新添加同一个域名，脚本会覆盖旧配置。\n' >/dev/tty
  printf '也可以手动编辑：nano %s\n' "$CADDYFILE" >/dev/tty
  printf '修改完成后记得重载：caddy validate --config %s --adapter caddyfile && systemctl reload caddy\n' "$CADDYFILE" >/dev/tty
}

show_status() {
  printf '\nCaddy 状态检查：\n' >/dev/tty

  if ! has caddy; then
    printf '  - Caddy：未安装。请先在菜单选择 1 安装。\n' >/dev/tty
    return
  fi

  printf '  - 版本：%s\n' "$(caddy version 2>/dev/null || printf '无法读取')" >/dev/tty

  if has systemctl; then
    if systemctl is-active --quiet caddy; then
      printf '  - 服务：正在运行。\n' >/dev/tty
    else
      printf '  - 服务：没有运行。可以执行：systemctl restart caddy\n' >/dev/tty
    fi

    if systemctl is-enabled --quiet caddy 2>/dev/null; then
      printf '  - 开机启动：已启用。\n' >/dev/tty
    else
      printf '  - 开机启动：未启用。可以执行：systemctl enable caddy\n' >/dev/tty
    fi
  elif has service; then
    if service caddy status >/dev/null 2>&1; then
      printf '  - 服务：正在运行。\n' >/dev/tty
    else
      printf '  - 服务：没有运行。可以执行：service caddy restart\n' >/dev/tty
    fi
  else
    printf '  - 服务：当前系统没有 systemctl/service，脚本无法判断守护进程状态。\n' >/dev/tty
  fi

  if [ -f "$CADDYFILE" ]; then
    if caddy validate --config "$CADDYFILE" --adapter caddyfile >/tmp/fd-caddy-validate.log 2>&1; then
      printf '  - 配置：语法正确。\n' >/dev/tty
    else
      printf '  - 配置：有错误，请执行下面命令查看原因：\n' >/dev/tty
      printf '    caddy validate --config %s --adapter caddyfile\n' "$CADDYFILE" >/dev/tty
    fi
  else
    printf '  - 配置：还没有找到 %s。\n' "$CADDYFILE" >/dev/tty
  fi

  printf '  - 反代数量：%s 个。\n' "$(proxy_count)" >/dev/tty

  if has ss; then
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq '(:80|:443)$'; then
      printf '  - 端口：80 或 443 已有监听。\n' >/dev/tty
    else
      printf '  - 端口：没有看到 80/443 监听；如果要公网 HTTPS，需要检查 Caddy 是否启动。\n' >/dev/tty
    fi
  fi

  if has journalctl && has systemctl && systemctl is-active --quiet caddy; then
    if journalctl -u caddy -p warning -n 5 --no-pager >/tmp/fd-caddy-warnings.log 2>&1 && [ -s /tmp/fd-caddy-warnings.log ]; then
      printf '  - 最近日志：有警告或错误。可在菜单选 7 查看最近日志。\n' >/dev/tty
    else
      printf '  - 最近日志：没有看到明显警告。\n' >/dev/tty
    fi
  fi
}

show_logs() {
  if has journalctl; then
    journalctl -u caddy -n 80 --no-pager || true
  else
    warn "当前系统没有 journalctl，请手动查看 Caddy 日志。"
  fi
}

reload_caddy() {
  if ! has caddy; then
    warn "Caddy 未安装，无法重载。"
    return
  fi
  if ! caddy validate --config "$CADDYFILE" --adapter caddyfile; then
    warn "配置校验失败，已取消重载。可以执行：nano $CADDYFILE"
    return
  fi
  if has systemctl; then
    systemctl reload caddy || systemctl restart caddy
  else
    service caddy reload || service caddy restart
  fi
  log "Caddy 已重载"
}

menu_restore_backup() {
  local backups=()
  while IFS= read -r file; do
    backups+=("$file")
  done < <(ls -1t "${CADDYFILE}".bak.* 2>/dev/null || true)

  if [ "${#backups[@]}" -eq 0 ]; then
    warn "没有找到 Caddyfile 备份。"
    return
  fi

  printf '\n可恢复的备份：\n' >/dev/tty
  local i
  for i in "${!backups[@]}"; do
    printf '  %s. %s\n' "$((i + 1))" "${backups[$i]}" >/dev/tty
  done
  printf '  0. 返回\n' >/dev/tty

  local choice ok
  choice="$(prompt '请选择要恢复的备份' '0')"
  [ "$choice" = "0" ] && return
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
    warn "编号无效，已返回主菜单。"
    return
  fi

  printf '\n即将恢复：%s\n' "${backups[$((choice - 1))]}" >/dev/tty
  ok="$(prompt '确认恢复？输入 y 继续' 'n')"
  if [ "$ok" != "y" ] && [ "$ok" != "Y" ]; then
    warn "已取消，返回主菜单。"
    return
  fi

  backup_caddyfile
  cp -a "${backups[$((choice - 1))]}" "$CADDYFILE"
  rm -f "$FD_DB"
  ensure_proxy_db
  if caddy validate --config "$CADDYFILE" --adapter caddyfile; then
    reload_caddy
    log "备份已恢复。"
  else
    warn "备份已复制，但配置校验失败。请查看配置后手动处理：nano $CADDYFILE"
  fi
}

update_script() {
  local url tmp
  url="${SELF_URL:-$DEFAULT_SELF_URL}"
  tmp="$(mktemp)"

  if has curl; then
    curl -q -fsSL "${url}?$(date +%s)" -o "$tmp" || { rm -f "$tmp"; warn "下载脚本失败。"; return; }
  elif has wget; then
    wget -qO "$tmp" "${url}?$(date +%s)" || { rm -f "$tmp"; warn "下载脚本失败。"; return; }
  else
    warn "需要先安装 curl 或 wget。"
    return
  fi

  if ! bash -n "$tmp"; then
    rm -f "$tmp"
    warn "下载到的脚本语法检查失败，已取消更新。"
    return
  fi

  install -m 0755 "$tmp" /usr/local/bin/fd
  rm -f "$tmp"
  log "脚本已更新到 /usr/local/bin/fd。请重新运行 fd 使用新版。"
  exit 0
}

uninstall_script() {
  danger "危险操作：卸载 fd 脚本助手。"
  printf '这只会删除 /usr/local/bin/fd，不会卸载 Caddy，也不会删除 Caddy 配置。\n' >/dev/tty
  local ok
  ok="$(prompt '确认卸载脚本？输入 DELETE 继续' 'n')"
  if [ "$ok" != "DELETE" ]; then
    warn "已取消，返回主菜单。"
    return
  fi
  rm -f /usr/local/bin/fd
  log "fd 脚本助手已卸载。"
  exit 0
}

remove_caddy_package() {
  if has apt-get; then
    apt-get purge -y caddy || true
    apt-get autoremove -y || true
    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    apt-get update || true
  elif has dnf; then
    dnf remove -y caddy || true
    dnf -y copr disable @caddy/caddy || true
  elif has yum; then
    yum remove -y caddy || true
    yum -y copr disable @caddy/caddy || true
  elif has pacman; then
    pacman -Rns --noconfirm caddy || true
  elif has apk; then
    apk del caddy || true
  elif has zypper; then
    zypper --non-interactive remove caddy || true
  fi
}

uninstall_caddy_clean() {
  danger "危险操作：彻底卸载 Caddy。"
  danger "这会删除 Caddy 程序、服务、配置、证书数据、日志、脚本记录和 caddy 用户。"
  printf '将删除的常见路径：/etc/caddy /var/lib/caddy /var/log/caddy /usr/bin/caddy /etc/systemd/system/caddy.service\n' >/dev/tty
  local ok
  ok="$(prompt '确认彻底卸载 Caddy？输入 DELETE 继续' 'n')"
  if [ "$ok" != "DELETE" ]; then
    warn "已取消，返回主菜单。"
    return
  fi

  if has systemctl; then
    systemctl stop caddy >/dev/null 2>&1 || true
    systemctl disable caddy >/dev/null 2>&1 || true
  elif has service; then
    service caddy stop >/dev/null 2>&1 || true
  fi

  remove_caddy_package
  rm -f /usr/bin/caddy /usr/local/bin/caddy /etc/systemd/system/caddy.service
  rm -rf /etc/caddy /var/lib/caddy /var/log/caddy
  if has systemctl; then
    systemctl daemon-reload || true
    systemctl reset-failed caddy >/dev/null 2>&1 || true
  fi
  if id -u caddy >/dev/null 2>&1; then
    userdel -r caddy >/dev/null 2>&1 || userdel caddy >/dev/null 2>&1 || true
  fi
  if getent group caddy >/dev/null 2>&1; then
    groupdel caddy >/dev/null 2>&1 || true
  fi

  log "Caddy 已尽量彻底卸载。"
}

menu_add_proxy() {
  DOMAIN="$(prompt '请输入你要对外访问的域名，例如 proxy.example.com')"
  if ! is_valid_domain "$DOMAIN"; then
    warn "访问域名不合法。示例：proxy.example.com。已返回主菜单。"
    return
  fi

  UPSTREAM="$(prompt '请输入你想反代的目标，例如 https://www.example.com 或 http://127.0.0.1:3000')"
  [ -n "$UPSTREAM" ] || { warn "反代目标不能为空，已返回主菜单。"; return; }
  case "$UPSTREAM" in
    http://*|https://*) ;;
    *) UPSTREAM="https://${UPSTREAM}" ;;
  esac
  if ! is_valid_upstream "$UPSTREAM"; then
    warn "反代目标不合法。示例：https://www.example.com 或 http://127.0.0.1:3000。已返回主菜单。"
    return
  fi
  UPSTREAM="$(normalize_upstream_url "$UPSTREAM")"

  local use_https email_answer
  use_https="$(prompt '是否自动申请 HTTPS 证书？输入 y 或 n' 'y')"
  if [ "$use_https" = "n" ] || [ "$use_https" = "N" ]; then
    HTTP_ONLY=1
  else
    HTTP_ONLY=0
    email_answer="$(prompt '请输入证书邮箱，可直接回车跳过')"
    if ! is_valid_email "$email_answer"; then
      warn "邮箱格式不合法，已返回主菜单。"
      return
    fi
    EMAIL="$email_answer"
  fi

  printf '\n即将配置：%s -> %s\n' "$DOMAIN" "$UPSTREAM" >/dev/tty
  if [ "$HTTP_ONLY" -eq 1 ]; then
    printf '模式：仅 HTTP，适合 DNS 未生效或临时测试\n' >/dev/tty
  else
    printf '模式：自动 HTTPS，请确认域名已解析到本机且 80/443 已放行\n' >/dev/tty
  fi
  local ok
  ok="$(prompt '确认执行？输入 y 继续' 'y')"
  if [ "$ok" != "y" ] && [ "$ok" != "Y" ]; then
    warn "已取消，返回主菜单。"
    return
  fi

  configure_proxy
}

menu_delete_proxy() {
  if ! print_proxy_list; then
    return
  fi

  printf '\n输入要删除的编号；输入 0 返回。\n' >/dev/tty
  local choice
  choice="$(prompt '请选择要删除的反代' '0')"
  [ "$choice" = "0" ] || [ -n "$choice" ] || return
  load_proxy_arrays
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#PROXY_DOMAINS[@]}" ]; then
    warn "编号无效"
    return
  fi

  local idx d u ok
  idx=$((choice - 1))
  d="${PROXY_DOMAINS[$idx]}"
  u="${PROXY_UPSTREAMS[$idx]}"
  printf '\n即将删除：%s -> %s\n' "$d" "$u" >/dev/tty
  printf '会从脚本记录和 %s 中一起清理，并自动重载 Caddy。\n' "$CADDYFILE" >/dev/tty
  ok="$(prompt '确认删除？输入 y 继续' 'n')"
  if [ "$ok" != "y" ] && [ "$ok" != "Y" ]; then
    warn "已取消，返回主菜单。"
    return
  fi

  delete_proxy_db_index "$choice"
  if ! render_caddyfile; then
    warn "删除后重新生成配置失败，请检查 $CADDYFILE。"
    return
  fi
  reload_caddy
  log "已删除反代：${d}"
}

main_menu() {
  while true; do
    clear >/dev/tty 2>/dev/null || true
    cat >/dev/tty <<EOF
========================================
  Caddy 反代助手 v${SCRIPT_VERSION}
========================================
  1. 安装 / 更新 Caddy
  2. 新增 / 修改反代网站
  3. 删除反代网站
  4. 查看当前配置
  5. 检查 Caddy 状态
  6. 重载 Caddy 配置
  7. 查看最近日志
  8. 安装/修复 fd 快捷命令
  9. 恢复 Caddyfile 备份

  91. 更新 fd 脚本
EOF
    danger "  98. 卸载 Caddy（彻底删除配置和证书）"
    danger "  99. 卸载 fd 脚本助手"
    cat >/dev/tty <<'EOF'
  0. 退出
========================================
EOF
    local choice
    choice="$(prompt '请输入编号' '2')"
    case "$choice" in
      1)
        install_or_update_caddy
        open_firewall_ports
        restart_caddy
        log "Caddy 已安装/更新并启动"
        pause
        ;;
      2)
        menu_add_proxy
        pause
        ;;
      3)
        menu_delete_proxy
        pause
        ;;
      4)
        show_caddyfile
        pause
        ;;
      5)
        show_status
        pause
        ;;
      6)
        reload_caddy
        pause
        ;;
      7)
        show_logs
        pause
        ;;
      8)
        install_shortcut
        pause
        ;;
      9)
        menu_restore_backup
        pause
        ;;
      91)
        update_script
        pause
        ;;
      98)
        uninstall_caddy_clean
        pause
        ;;
      99)
        uninstall_script
        pause
        ;;
      0)
        exit 0
        ;;
      *)
        warn "请输入菜单里显示的编号"
        pause
        ;;
    esac
  done
}

if [ "$INSTALL_SHORTCUT" -eq 1 ]; then
  install_shortcut
  printf '\n以后直接输入：fd\n' >/dev/tty
  printf '现在为你打开中文菜单。\n' >/dev/tty
  pause
  main_menu
fi

if [ "$INSTALL_ONLY" -eq 1 ]; then
  install_caddy
  open_firewall_ports
  restart_caddy
  log "Caddy 已安装。以后可以运行：fd"
  log "Version: $(caddy version 2>/dev/null || true)"
  log "Config: /etc/caddy/Caddyfile"
  exit 0
fi

if [ -n "$DOMAIN$UPSTREAM" ]; then
  [ -n "$DOMAIN" ] || die "--domain is required"
  [ -n "$UPSTREAM" ] || die "--upstream is required"
  is_valid_domain "$DOMAIN" || die "访问域名不合法，示例：proxy.example.com"
  case "$UPSTREAM" in
    http://*|https://*) ;;
    *) UPSTREAM="https://${UPSTREAM}" ;;
  esac
  is_valid_upstream "$UPSTREAM" || die "反代目标不合法，示例：https://www.example.com 或 http://127.0.0.1:3000"
  UPSTREAM="$(normalize_upstream_url "$UPSTREAM")"
  is_valid_email "$EMAIL" || die "邮箱格式不合法"
  configure_proxy
  log "Version: $(caddy version 2>/dev/null || true)"
  exit 0
fi

main_menu
