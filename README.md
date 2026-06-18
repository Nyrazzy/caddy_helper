# Caddy 反代助手使用教程

这是一个适合放在 GitHub Gist 里的 Caddy 一键安装和反代管理脚本。

第一次安装后，以后只需要在服务器里输入：

```bash
fd
```

就会打开中文菜单。你按提示输入自己的域名和想反代的网站即可。

> 本教程默认你已经是 `root` 用户。如果你不是 root，请在命令前加 `sudo`，或者先执行 `sudo -i` 切换到 root。

## 一、脚本地址

你的 Gist Raw 地址是：

```bash
https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh
```

后面的命令可以直接复制使用。

## 二、第一次安装

在 root 用户下执行：

```bash
bash <(curl -q -fsSL "https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh?$(date +%s)") \
  --install-shortcut \
  --self-url "https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh"
```

这一步会做几件事：

- 安装 `fd` 快捷命令
- 打开中文菜单
- 以后运行 `fd` 时自动拉取 Gist 最新版脚本

安装完成后，以后直接输入：

```bash
fd
```

## 三、菜单功能

运行：

```bash
fd
```

会看到类似菜单：

```text
========================================
  Caddy 反代助手
========================================
  1. 安装 / 更新 Caddy
  2. 新增 / 修改反代网站
  3. 查看当前配置
  4. 检查 Caddy 状态
  5. 重载 Caddy 配置
  6. 查看最近日志
  7. 安装/修复 fd 快捷命令
  0. 退出
========================================
```

最常用的是选：

```text
2. 新增 / 修改反代网站
```

然后按中文提示输入。

## 四、配置一个反代网站

假设你想用：

```text
proxy.example.com
```

反代：

```text
https://www.example.com
```

运行：

```bash
fd
```

选择 `2`，然后按提示填写：

```text
请输入你要对外访问的域名，例如 proxy.example.com: proxy.example.com
请输入你想反代的目标，例如 https://www.example.com 或 http://127.0.0.1:3000: https://www.example.com
是否自动申请 HTTPS 证书？输入 y 或 n [y]: y
请输入证书邮箱，可直接回车跳过: admin@example.com
确认执行？输入 y 继续 [y]: y
```

配置完成后，访问：

```text
https://proxy.example.com
```

就会转发到：

```text
https://www.example.com
```

## 五、反代 Google 示例

如果你确实有合规授权和使用场景，可以这样填：

```text
请输入你要对外访问的域名，例如 proxy.example.com: google-proxy.example.com
请输入你想反代的目标，例如 https://www.example.com 或 http://127.0.0.1:3000: https://www.google.com
是否自动申请 HTTPS 证书？输入 y 或 n [y]: y
请输入证书邮箱，可直接回车跳过: admin@example.com
确认执行？输入 y 继续 [y]: y
```

然后访问：

```text
https://google-proxy.example.com
```

注意：Google 这类大型网站通常有跳转、Cookie、登录、风控、地区策略和内容安全策略，简单反代不保证稳定。更推荐反代你自己的网站、API、对象存储、面板、内网服务，或者明确允许代理的上游。

## 六、自动 HTTPS 前的准备

如果你选择自动 HTTPS，请先确认：

- 域名已经解析到这台服务器 IP
- 服务器 80 端口开放
- 服务器 443 端口开放
- 云服务器安全组已经放行 80 和 443
- 服务器所在地网络可以正常访问 Let's Encrypt / ZeroSSL 等证书服务

如果 DNS 还没生效，可以先选择不申请 HTTPS，或者用命令模式加 `--http-only` 临时测试。

## 七、只安装 Caddy

如果你只想安装 Caddy，不配置反代：

```bash
fd --install-only
```

或者第一次就只安装：

```bash
bash <(curl -q -fsSL "https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh?$(date +%s)") --install-only
```

## 八、不进菜单，直接命令配置

如果你已经熟悉参数，也可以直接一条命令完成反代：

```bash
fd \
  --domain proxy.example.com \
  --upstream https://www.example.com \
  --email admin@example.com
```

DNS 没生效时，先用 HTTP：

```bash
fd \
  --domain proxy.example.com \
  --upstream https://www.example.com \
  --http-only
```

等 DNS 生效后，再去掉 `--http-only` 重新运行一次。

## 九、常用管理

查看 Caddy 状态：

```bash
systemctl status caddy
```

查看配置文件：

```bash
cat /etc/caddy/Caddyfile
```

检查配置是否正确：

```bash
caddy validate --config /etc/caddy/Caddyfile
```

重载配置：

```bash
systemctl reload caddy
```

重启 Caddy：

```bash
systemctl restart caddy
```

查看日志：

```bash
journalctl -u caddy -f
```

## 十、配置文件和备份

Caddy 配置文件位置：

```bash
/etc/caddy/Caddyfile
```

每次用脚本修改反代配置前，都会自动备份旧配置：

```bash
/etc/caddy/Caddyfile.bak.时间戳
```

如果配置错了，可以手动恢复备份。

## 十一、支持的系统

脚本会自动判断系统并选择安装方式：

- Debian / Ubuntu / Raspbian
- Fedora / RHEL / CentOS / Rocky / Alma
- Arch / Manjaro
- Alpine
- openSUSE
- 其他常见 systemd Linux

如果系统包管理器不支持，脚本会尝试安装 Caddy 官方静态二进制。

## 十二、常见问题

### 1. 输入 `fd` 没反应或找不到命令

重新安装快捷命令：

```bash
bash <(curl -q -fsSL "https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh?$(date +%s)") \
  --install-shortcut \
  --self-url "https://gist.githubusercontent.com/Nyrazzy/019e6d147b7e69fa82fe08f783a52af7/raw/install-caddy.sh"
```

然后检查：

```bash
which fd
```

正常应该看到：

```text
/usr/local/bin/fd
```

### 2. 证书申请失败

优先检查：

- 域名是否解析到当前服务器
- 80 和 443 端口是否开放
- 云厂商安全组是否放行
- 是否有其他程序占用了 80 或 443

查看端口占用：

```bash
ss -lntp | grep -E ':80|:443'
```

### 3. 反代后打不开

检查 Caddy 状态和日志：

```bash
systemctl status caddy
journalctl -u caddy -n 100 --no-pager
```

也可以在菜单里选：

```text
4. 检查 Caddy 状态
6. 查看最近日志
```

### 4. 想更新脚本

如果你是用 `--self-url` 安装的快捷命令，以后直接运行：

```bash
fd
```

就会自动拉取 Gist 最新版。

### 5. 不建议用管道方式运行交互菜单

不要这样运行交互菜单：

```bash
curl -fsSL "脚本地址" | bash
```

这种方式可能导致中文菜单输入异常。

推荐使用：

```bash
bash <(curl -q -fsSL "脚本地址?$(date +%s)")
```
