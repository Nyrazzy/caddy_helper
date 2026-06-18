#!/usr/bin/env bash
set -Eeuo pipefail

# One-file Caddy installer for GitHub Gist.
# Supports common Linux distributions and optional one-command reverse proxy setup.

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
die() { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

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
    [ -n "$source_path" ] && [ -r "$source_path" ] || die "无法复制脚本本体。请用：bash <(curl -fsSL RAW_GIST_URL) --install-shortcut --self-url RAW_GIST_URL"
    cp "$source_path" "$target"
  fi

  chmod +x "$target"
  log "快捷命令已安装：fd"
}

[ "$(id -u)" -eq 0 ] || die "Please run as root, for example: bash <(curl -fsSL RAW_GIST_URL) --install-shortcut"

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
  local i mode
  for i in "${!PROXY_DOMAINS[@]}"; do
    if [ "${PROXY_HTTP_ONLY[$i]}" = "1" ]; then
      mode="HTTP"
    else
      mode="HTTPS"
    fi
    printf '  %s. %s  ->  %s  [%s]\n' "$((i + 1))" "${PROXY_DOMAINS[$i]}" "${PROXY_UPSTREAMS[$i]}" "$mode" >/dev/tty
  done
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
  backup_caddyfile

  local global_email
  global_email="$(awk -F '\t' '$4 != "" { print $4; exit }' "$FD_DB")"

  {
    printf '# This Caddyfile is managed by fd Caddy reverse proxy helper.\n'
    printf '# Edit with: nano /etc/caddy/Caddyfile\n'
    printf '# After manual changes, run: caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy\n\n'
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
  } >"$CADDYFILE"

  caddy fmt --overwrite "$CADDYFILE" || true
  caddy validate --config "$CADDYFILE"
}

write_caddyfile() {
  upsert_proxy_db
  render_caddyfile
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
  write_caddyfile
  open_firewall_ports
  restart_caddy
  log "反代已配置：${DOMAIN} -> ${UPSTREAM}"
  log "配置文件：/etc/caddy/Caddyfile"
}

show_caddyfile() {
  if ! print_proxy_list; then
    printf '\n配置文件位置：%s\n' "$CADDYFILE" >/dev/tty
    printf '如果需要手动编辑：nano %s\n' "$CADDYFILE" >/dev/tty
    printf '修改完成后重载：caddy validate --config %s && systemctl reload caddy\n' "$CADDYFILE" >/dev/tty
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
  printf '修改完成后记得重载：caddy validate --config %s && systemctl reload caddy\n' "$CADDYFILE" >/dev/tty
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
    if caddy validate --config "$CADDYFILE" >/tmp/fd-caddy-validate.log 2>&1; then
      printf '  - 配置：语法正确。\n' >/dev/tty
    else
      printf '  - 配置：有错误，请执行下面命令查看原因：\n' >/dev/tty
      printf '    caddy validate --config %s\n' "$CADDYFILE" >/dev/tty
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
      printf '  - 最近日志：有警告或错误。可在菜单选 6 查看最近日志。\n' >/dev/tty
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
  caddy validate --config "$CADDYFILE"
  if has systemctl; then
    systemctl reload caddy || systemctl restart caddy
  else
    service caddy reload || service caddy restart
  fi
  log "Caddy 已重载"
}

menu_add_proxy() {
  DOMAIN="$(prompt '请输入你要对外访问的域名，例如 proxy.example.com')"
  [ -n "$DOMAIN" ] || die "域名不能为空"

  UPSTREAM="$(prompt '请输入你想反代的目标，例如 https://www.example.com 或 http://127.0.0.1:3000')"
  [ -n "$UPSTREAM" ] || die "反代目标不能为空"
  case "$UPSTREAM" in
    http://*|https://*) ;;
    *) UPSTREAM="https://${UPSTREAM}" ;;
  esac

  local use_https email_answer
  use_https="$(prompt '是否自动申请 HTTPS 证书？输入 y 或 n' 'y')"
  if [ "$use_https" = "n" ] || [ "$use_https" = "N" ]; then
    HTTP_ONLY=1
  else
    HTTP_ONLY=0
    email_answer="$(prompt '请输入证书邮箱，可直接回车跳过')"
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
  [ "$ok" = "y" ] || [ "$ok" = "Y" ] || die "已取消"

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
  [ "$ok" = "y" ] || [ "$ok" = "Y" ] || die "已取消"

  delete_proxy_db_index "$choice"
  render_caddyfile
  reload_caddy
  log "已删除反代：${d}"
}

main_menu() {
  while true; do
    clear >/dev/tty 2>/dev/null || true
    cat >/dev/tty <<'EOF'
========================================
  Caddy 反代助手
========================================
  1. 安装 / 更新 Caddy
  2. 新增 / 修改反代网站
  3. 删除反代网站
  4. 查看当前配置
  5. 检查 Caddy 状态
  6. 重载 Caddy 配置
  7. 查看最近日志
  8. 安装/修复 fd 快捷命令
  0. 退出
========================================
EOF
    local choice
    choice="$(prompt '请输入编号' '2')"
    case "$choice" in
      1)
        install_caddy
        open_firewall_ports
        restart_caddy
        log "Caddy 已安装/启动"
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
      0)
        exit 0
        ;;
      *)
        warn "请输入 0-8 之间的编号"
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
  configure_proxy
  log "Version: $(caddy version 2>/dev/null || true)"
  exit 0
fi

main_menu
