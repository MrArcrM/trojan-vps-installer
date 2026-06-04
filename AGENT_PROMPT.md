# Agent 部署 Prompt（复制 → 填空 → 发给 AI Agent）

把下面这块整段复制，把所有 `<填...>` 替换成你自己的信息，发给 **Claude Code / Cursor / Codex / ChatGPT 任意有终端能力的 Agent**，它就会自动帮你部署。

## ⚠️ 发给 Agent 之前你必须先做完这 3 件事

**这 3 步 Agent 帮不了你**（需要你登录控制台 + 等 DNS 生效），先做完再走下面的 Agent 流程：

1. **买好一台 VPS**（推荐 Ubuntu 22.04 / 24.04，1c1g 起，海外节点）
   - 不要用国内云的境内节点（违法）
   - 不要用国内云的境外节点（IP 易被风控）
   - 推荐：海外小厂独服 / Vultr / DigitalOcean / Hetzner / Racknerd
2. **买好一个域名**（任意 TLD，5-10 元/年的 `.xyz` 也行）
3. **配 DNS A 记录**：到域名控制台添加
   - 类型：A
   - 主机记录 / Name：`proxy`（或任意子域名，根域 `@` 也行）
   - 记录值 / Value：VPS 的公网 IP
   - **如果域名在 Cloudflare**：Proxy status **必须**设成「DNS only」（灰云朵），**不能开橙云朵**（否则 trojan 走不通）
4. **VPS 控制台安全组放行**：放开 **TCP 80** 和 **TCP 443**（SSH 端口默认已开）

配完 DNS 等 **5-10 分钟**生效，本机跑 `dig +short <你的域名> @1.1.1.1` 应该返回 VPS IP。等返回正确了，再走下面 Agent 流程。

---

## Agent Prompt（复制下面整段）

```
我刚买了一台 VPS 和一个域名，想搭一个 trojan 代理服务（用于科学上网 / 访问 Claude）。
请按照 https://github.com/MrArcrM/trojan-vps-installer 这个仓库的 install.sh 脚本帮我部署。

我的部署参数：
- VPS IP：<填，比如 1.2.3.4>
- SSH 登录命令（你自己能登录的方式，必须是 root 或有 sudo 免密的用户）：
  <填，例如：ssh root@1.2.3.4>
  <如果用私钥：ssh -i ~/.ssh/your-key root@1.2.3.4>
  <如果端口非 22：ssh -p 2222 root@1.2.3.4>
- 域名：<填，例如 proxy.example.com>
- Trojan 密码（客户端连接用，自己起一个 16 位以上的强密码）：<填>
- 邮箱（可选；Let's Encrypt 用于发证书到期预警，不填也能装，acme.sh cron 会自动续期）：<填或留空>

请按以下流程执行：

1. SSH 通连测试：用我给你的 SSH 命令登一次，确认能拿到 root shell，不能就停下来告诉我
2. DNS 预检：在 VPS 上跑 `dig +short <域名> @1.1.1.1`，必须返回我给的 VPS IP；
   不一致就停下来告诉我（特别检查 Cloudflare 是不是没关橙云朵）
3. 端口预检：在 VPS 上跑 `ss -tln | grep ':80 '`，必须为空（80 端口空闲，acme.sh 要用）；
   有占用就告诉我哪个进程占着，让我决定是否停掉
4. 安装：在 VPS 上直接跑
   curl -fsSL https://raw.githubusercontent.com/MrArcrM/trojan-vps-installer/main/install.sh | \
     sudo bash -s -- --domain <域名> --password <密码>
   （如果上面我填了邮箱，命令末尾加 --email <邮箱>）
   实时看输出，任何一步红色 [✗] 都停下来告诉我原因，不要继续往下硬装
5. 自检：装完后 SSH 到 VPS 跑 `docker ps | grep trojan`（必须 Up）+
   `docker logs trojan --tail 10`（必须有 "trojan service (server) started"）
6. 把客户端连接参数整理给我：
   - 类型 (type)：trojan
   - 服务器 (server)：<域名>
   - 端口 (port)：443
   - 密码 (password)：<密码>
   - SNI / peer：<域名>
   - 跳过证书验证 (skip-cert-verify)：false

整个流程预计 3-5 分钟。中途任何环节失败请停下来告诉我具体报错和你的判断，不要瞎搞或硬绕过。
```

---

## 装完之后

在本地客户端（Mac: Clash Verge / ClashX Pro；iOS: Shadowrocket；Win: Clash Verge / Nekobox）添加 trojan 节点，参数用 Agent 最后给你的。

测试：浏览器打开 `https://google.com`，能开就完事。

## 出了问题怎么办

把 Agent 报的错（包括 `docker logs trojan --tail 30` 的输出）粘回去问它，或者照 README.md 的「故障排查」表自检。

最常见的 3 个坑：
1. **Cloudflare 没关橙云朵** → trojan 完全走不通，acme.sh 也签不了证书
2. **VPS 安全组没放 80/443** → acme.sh 报 timeout；自检命令：本机 `nc -zv <VPS IP> 80`
3. **DNS 没生效** → 等 10 分钟，或换 DNS 服务商试试
