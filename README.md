# trojan-vps-installer

一键在新 VPS 上部署 trojan 代理（自动签 Let's Encrypt 证书、装续期 cron）。专为 **AI Agent 驱动部署**而设计——把 [AGENT_PROMPT.md](./AGENT_PROMPT.md) 复制给 Claude Code / Cursor / 任意 Agent，它会自动帮你装好。

## 适用场景

- 你想搭一个能稳定访问 Claude / ChatGPT 的代理
- 你不想手动装 Docker、签证书、配 cron
- 你想给朋友一个无痛部署方案

## 快速开始

### 推荐：让 AI Agent 帮你装

复制 [AGENT_PROMPT.md](./AGENT_PROMPT.md) 里的 Prompt，填入你的 VPS / 域名 / 密码，发给 Claude Code（或任何能跑 SSH 的 Agent），3-5 分钟搞定。

### 进阶：自己 SSH 进去跑

```bash
curl -fsSL https://raw.githubusercontent.com/MrArcrM/trojan-vps-installer/main/install.sh | \
  sudo bash -s -- \
    --domain proxy.example.com \
    --password your-strong-password \
    --email you@example.com
```

## 前置条件（脚本帮不了你这部分）

| 步骤 | 说明 |
|---|---|
| 买 VPS | Ubuntu 22.04 / 24.04 / Debian 12，1c1g 起 |
| 买域名 | 任意 TLD，5-10 元/年的 `.xyz` 也行 |
| 配 DNS A 记录 | 主机记录指向 VPS IP；**Cloudflare 必须 DNS only 灰云朵**，不能开橙云朵代理 |
| 安全组放行 | TCP 80（acme 用）+ TCP 443（trojan 用） |

DNS 配完等 5-10 分钟生效，本机 `dig +short <你的域名> @1.1.1.1` 应该返回 VPS IP，再开装。

## 脚本干了什么

1. 检查 OS（仅支持 Ubuntu/Debian）
2. 检测公网 IP，与传入域名的 DNS 解析对比，不匹配直接停（含 Cloudflare 橙云朵提示）
3. 检查 80 端口空闲（acme.sh standalone 用）
4. 装 Docker CE + Compose plugin
5. 装 acme.sh
6. Let's Encrypt 申请证书（apex 域名会自动加 `www.` SAN）
7. 写 `/opt/trojan/config/config.json` 和 `/opt/trojan/docker-compose.yml`
8. `acme.sh --install-cert` 装证书 + reloadcmd 自动重启容器
9. `docker compose up -d` 启动
10. `acme.sh --install-cronjob` 装每日续期 cron
11. openssl 自检 TLS 握手
12. 打印客户端配置参数

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `--domain` | ✅ | 已指向本 VPS 的域名（A 记录已配） |
| `--password` | ✅ | Trojan 客户端密码，建议 16+ 字符 |
| `--email` | ✅ | Let's Encrypt 注册邮箱 |
| `--port` | ❌ | trojan 监听端口，默认 443 |
| `--skip-dns-check` | ❌ | 跳过 DNS 预检（DNS 接管特殊场景用） |

## 客户端

| 平台 | 推荐客户端 |
|---|---|
| Mac | Clash Verge / ClashX Pro / Stash |
| iOS | Shadowrocket / Stash |
| Windows | Clash Verge / Nekobox |
| Android | Clash for Android / NekoBox |

节点参数：

```
类型 (type):       trojan
服务器 (server):   <你的域名>
端口 (port):       443
密码 (password):   <你设置的密码>
SNI / peer:        <你的域名>
跳过证书验证:      false
传输:              none / 直接 TLS
```

## 故障排查

| 现象 | 可能原因 | 排查 |
|---|---|---|
| `DNS mismatch` | DNS 未生效 / Cloudflare 橙云朵开着 | 等 10 分钟；CF 控制台改成 DNS only |
| `Port 80 occupied` | apache2 / nginx 占着 80 | `systemctl stop apache2 nginx && systemctl disable apache2 nginx` |
| `acme.sh issue failed` | 安全组没开 80 / DNS 还未生效 | 本机 `nc -zv <VPS IP> 80` 验证可达 |
| 客户端连不上 | 安全组没开 443 / SNI 错 / 密码错 | 检查防火墙、SNI 字段、密码 |
| Claude 提示 "Unable to verify your account" | VPS IP 被风控 | 换更干净的 IP（家宽 IP 最稳） |
| 看不到 `authenticated` 日志 | 客户端流量没送到 | 检查客户端规则，确认目标走 trojan |

## 续期

acme.sh 装好后每天会自动跑 `--cron`，到了 Let's Encrypt 建议的续期窗口（约证书到期前 30 天）自动续期 + 重启 trojan 容器。手动验证：

```bash
crontab -l | grep acme  # 应看到一行 cron 任务
/root/.acme.sh/acme.sh --list  # 看下次续期日期
```

## 卸载

```bash
cd /opt/trojan && docker compose down
rm -rf /opt/trojan
crontab -r  # 清 acme.sh cron
rm -rf /root/.acme.sh
```

## License

MIT
