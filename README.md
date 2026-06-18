# Caddy 反代助手使用教程

这是一个 Caddy 一键安装、反代配置和管理脚本。第一次安装后，以后在服务器里输入：

```bash
fd
```

就会打开中文菜单。

本教程默认你已经是 `root` 用户。如果不是 root，请先执行 `sudo -i` 切换到 root。

## 第一次安装

在 root 用户下执行：

```bash
bash <(curl -q -fsSL "https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh?$(date +%s)") \
  --install-shortcut \
  --self-url "https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh"
```

安装完成后，以后直接运行：

```bash
fd
```

这个快捷命令会从 GitHub 拉取最新版脚本。

## 菜单功能

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
  3. 删除反代网站
  4. 查看当前配置
  5. 检查 Caddy 状态
  6. 重载 Caddy 配置
  7. 查看最近日志
  8. 安装/修复 fd 快捷命令
  9. 恢复 Caddyfile 备份

  91. 更新 fd 脚本
  98. 卸载 Caddy（彻底删除配置和证书）
  99. 卸载 fd 脚本助手
  0. 退出
========================================
```

`98` 和 `99` 是危险操作，脚本里会用红字显示，并要求输入 `DELETE` 才会继续。

## 新增或修改反代

运行：

```bash
fd
```

选择：

```text
2. 新增 / 修改反代网站
```

按提示输入：

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

如果你重新添加同一个对外域名，脚本会覆盖旧配置。

## 输入校验

脚本会检查你输入的内容是否像正常域名或地址。

合法示例：

```text
proxy.example.com
https://www.example.com
http://127.0.0.1:3000
http://localhost:8080
```

不合法示例：

```text
sbisofnb
https://ubifssv
abc
```

如果输入不合法，脚本会提示原因并返回主菜单，不会写入配置。

## 删除反代

运行：

```bash
fd
```

选择：

```text
3. 删除反代网站
```

脚本会列出当前反代：

```text
当前反代列表：
  1. proxy.example.com  ->  https://www.example.com  [HTTPS]
  2. api.example.com    ->  http://127.0.0.1:3000   [HTTPS]
```

输入编号并确认后，脚本会：

- 从脚本记录中删除该反代
- 重新生成 `/etc/caddy/Caddyfile`
- 检查 Caddy 配置
- 自动重载 Caddy

删除前会自动备份旧配置。

## 查看当前配置

选择：

```text
4. 查看当前配置
```

脚本会先显示直观列表：

```text
当前反代列表：
  1. proxy.example.com  ->  https://www.example.com  [HTTPS]
```

然后你可以：

- 输入编号：查看某一个反代的详细 Caddy 配置片段
- 输入 `a`：查看完整 `/etc/caddy/Caddyfile`
- 输入 `0`：返回菜单

如果需要手动修改：

```bash
nano /etc/caddy/Caddyfile
```

修改完成后记得检查并重载：

```bash
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

## 检查 Caddy 状态

选择：

```text
5. 检查 Caddy 状态
```

脚本会用文字告诉你：

- Caddy 是否已安装
- Caddy 是否正在运行
- 是否已开机启动
- 配置语法是否正确
- 当前有几个反代
- 80/443 端口是否有监听
- 最近日志有没有明显警告

不会直接输出一大段 `systemctl status` 原文。

## 恢复备份

选择：

```text
9. 恢复 Caddyfile 备份
```

脚本会列出所有备份：

```text
1. /etc/caddy/Caddyfile.bak.20260619010101
2. /etc/caddy/Caddyfile.bak.20260619005912
```

输入编号后，脚本会恢复该备份、重新识别反代记录，并重载 Caddy。

## 更新脚本

选择：

```text
91. 更新 fd 脚本
```

脚本会从下面这个地址拉取最新版：

```text
https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh
```

更新后重新运行：

```bash
fd
```

即可使用新版。

## 卸载 fd 脚本助手

选择：

```text
99. 卸载 fd 脚本助手
```

这个功能只会删除：

```bash
/usr/local/bin/fd
```

不会卸载 Caddy，也不会删除 Caddy 配置。

脚本会要求输入：

```text
DELETE
```

才会继续。

## 彻底卸载 Caddy

选择：

```text
98. 卸载 Caddy（彻底删除配置和证书）
```

这个功能会尽量删除干净，包括：

- Caddy 程序
- Caddy 服务
- Caddy 配置
- Caddy 自动申请的证书数据
- Caddy 日志
- 脚本保存的反代记录
- `caddy` 系统用户和用户组

常见删除路径：

```bash
/etc/caddy
/var/lib/caddy
/var/log/caddy
/usr/bin/caddy
/usr/local/bin/caddy
/etc/systemd/system/caddy.service
```

脚本会要求输入：

```text
DELETE
```

才会继续。

## 反代 Google 示例

如果你确实有合规授权和使用场景，可以这样填：

```text
请输入你要对外访问的域名，例如 proxy.example.com: google-proxy.example.com
请输入你想反代的目标，例如 https://www.example.com 或 http://127.0.0.1:3000: https://www.google.com
是否自动申请 HTTPS 证书？输入 y 或 n [y]: y
请输入证书邮箱，可直接回车跳过: admin@example.com
确认执行？输入 y 继续 [y]: y
```

注意：Google 这类大型网站通常有跳转、Cookie、登录、风控、地区策略和内容安全策略，简单反代不保证稳定。更推荐反代你自己的网站、API、对象存储、面板、内网服务，或者明确允许代理的上游。

## 自动 HTTPS 前的准备

如果你选择自动 HTTPS，请确认：

- 域名已经解析到这台服务器 IP
- 服务器 80 端口开放
- 服务器 443 端口开放
- 云服务器安全组已经放行 80 和 443
- 服务器所在地网络可以正常访问 Let's Encrypt / ZeroSSL 等证书服务

如果 DNS 还没生效，可以先选择不申请 HTTPS，或者用命令模式加 `--http-only` 临时测试。

## 不进菜单，直接命令配置

安装快捷命令后，可以直接运行：

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

只安装 Caddy：

```bash
fd --install-only
```

## 常用命令

查看配置：

```bash
cat /etc/caddy/Caddyfile
```

检查配置：

```bash
caddy validate --config /etc/caddy/Caddyfile
```

重载配置：

```bash
systemctl reload caddy
```

查看日志：

```bash
journalctl -u caddy -f
```

## 支持的系统

脚本会自动判断系统并选择安装方式：

- Debian / Ubuntu / Raspbian
- Fedora / RHEL / CentOS / Rocky / Alma
- Arch / Manjaro
- Alpine
- openSUSE
- 其他常见 systemd Linux

如果系统包管理器不支持，脚本会尝试安装 Caddy 官方静态二进制。

## 重新安装快捷命令

如果输入 `fd` 提示找不到命令，重新执行：

```bash
bash <(curl -q -fsSL "https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh?$(date +%s)") \
  --install-shortcut \
  --self-url "https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh"
```

然后检查：

```bash
which fd
```

正常应该看到：

```text
/usr/local/bin/fd
```

## 临时运行脚本

如果只是临时打开一次菜单，不安装 `fd`，可以运行：

```bash
bash <(curl -q -fsSL "https://raw.githubusercontent.com/Nyrazzy/caddy_helper/refs/heads/main/install-caddy.sh?$(date +%s)")
```
