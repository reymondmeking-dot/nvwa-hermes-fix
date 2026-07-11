# nvwa-hermes-fix

修复 **Hermes Agent** 常见的 `API call failed after 3 retries: Connection error` 错误的一键工具。

**跨平台**：Windows（`.bat` 双击 / `.ps1` CLI）、macOS / Linux（`.sh` CLI）。

当前版本：**1.1.1**

---

## 现象

在 Hermes 桌面版里发消息，模型返回：

```
API call failed after 3 retries: Connection error
```

后端日志能看到 httpx 在往 `127.0.0.1:<某端口>`（比如 `19828`）连接，但那个端口根本没有服务在监听。

## 根因

Python 的 `httpx` 客户端启动时会**一次性读取代理配置并缓存**到 HTTP client 对象里，之后所有请求都用这份缓存值。如果代理配置指向一个死端口，所有 API 请求都会被路由到那里 → 连不上 → 重试 3 次报错。

代理"幽灵值"来自不同的位置：

| 平台 | 幽灵值来源 |
|---|---|
| **Windows** | WinInet 注册表：`HKCU\...\Internet Settings\ProxyServer` / `ProxyEnable` / `AutoConfigURL`（VPN / Clash / v2rayN 等留下的） |
| **macOS**   | ① `~/.zshrc` 等里的 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量；② 系统偏好设置 → 网络 → 高级 → 代理里遗留的开关（`scutil --proxy` 可见） |
| **Linux**   | ① `HTTP_PROXY` / `HTTPS_PROXY` 环境变量；② 桌面环境的代理设置 |

即便你手动清理了代理值，**已经在跑的 Hermes 进程**还是保留旧值——必须**重启后端**才能读到干净的配置。

## 这个仓库做什么（4 步，跨平台一致）

1. **打印**当前代理状态，便于事后核对。
2. **清空**幽灵代理（Windows: WinInet 注册表；macOS: 环境变量 + `networksetup` 关掉每个网络服务的代理；Linux: 当前 shell 的环境变量）。
3. **停掉 Hermes 后端**：`Hermes` / `Hermes.exe`（Electron 壳）、`gateway` / `tui_gateway` / `slash_worker` 等 Python 进程。
4. **通知系统**（仅 Windows）：广播 `WinInet INTERNET_OPTION_SETTINGS_CHANGED / REFRESH`，让活着的 WinInet 消费者立刻感知变化。

**范围：** 只影响当前用户，**不需要管理员 / sudo**，**不影响真正在用的代理软件**——如果你之后重新打开闪连 VPN / Clash 等，它们启动时会自动把设置改回去，本脚本只清"死"的、被丢下的值。

---

## Windows

### 双击方式（最简单）

下载 [`Fix-Hermes-Proxy.bat`](./Fix-Hermes-Proxy.bat) 到桌面 → 遇到错误时双击。

一行下载到桌面：
```powershell
iwr -useb https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/Fix-Hermes-Proxy.bat -OutFile "$env:USERPROFILE\Desktop\Fix-Hermes-Proxy.bat"
```

批处理也支持无改动预览和自动化运行：

```powershell
.\Fix-Hermes-Proxy.bat --dry-run --no-kill --no-pause
```

### CLI 方式（PowerShell）

**下载、检查后执行**：
```powershell
iwr -useb https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/Fix-Hermes-Proxy.ps1 -OutFile Fix-Hermes-Proxy.ps1
Get-Content .\Fix-Hermes-Proxy.ps1
.\Fix-Hermes-Proxy.ps1
```

**下载后本地跑**：
```powershell
iwr -useb https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/Fix-Hermes-Proxy.ps1 -OutFile Fix-Hermes-Proxy.ps1
.\Fix-Hermes-Proxy.ps1              # 正常运行
.\Fix-Hermes-Proxy.ps1 -DryRun      # 只打印要做什么，不改动
.\Fix-Hermes-Proxy.ps1 -NoKill      # 只清代理，不杀 Hermes 进程
```

如果 PowerShell 执行策略挡了：`powershell -ExecutionPolicy Bypass -File .\Fix-Hermes-Proxy.ps1`。

## macOS / Linux

**下载、检查后本地运行**：
```bash
curl --fail --show-error --location --remote-name https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/fix-hermes-proxy.sh
less fix-hermes-proxy.sh
chmod +x fix-hermes-proxy.sh
./fix-hermes-proxy.sh              # 正常运行
./fix-hermes-proxy.sh --dry-run    # 只打印，不改动
./fix-hermes-proxy.sh --no-kill    # 只清代理，不杀 Hermes 进程
```

**注意**（macOS/Linux）：作为子进程运行的脚本无法修改父 shell。脚本会清理自身环境并打印一条固定的 `unset` 命令；如需清理当前终端，请在脚本结束后执行该命令。持久生效仍需移除 `~/.zshrc` / `~/.bashrc` 里的相关 `export` 行。

## 使用后

重新打开 Hermes：

| 平台 | 命令 / 操作 |
|---|---|
| Windows | 双击桌面 / 开始菜单的 Hermes 图标 |
| macOS   | `open -a Hermes`，或从 Launchpad / Spotlight 打开 |
| Linux   | 你安装 Hermes 时用的启动方式（.desktop 快捷方式 / `hermes` CLI） |

新进程会读到干净的代理配置。

---

## 兼容性

| 项目 | 说明 |
|---|---|
| Windows | 10 1607+ / 11（含 24H2）。系统自带 PowerShell 5.1+、`reg`、`taskkill`。**不依赖 wmic**（Win11 24H2 已移除）。 |
| macOS   | 12+（Monterey 及以上）。用系统自带 `bash` / `zsh` + `scutil` + `networksetup` + `pgrep`。 |
| Linux   | 任何主流发行版。`bash` + `pgrep` 即可。 |
| 权限    | 全平台**均不需要管理员 / sudo**。 |

## 常见问答

**Q：会不会误杀我的其他 Python 程序？**
不会。全平台脚本只杀满足以下之一的进程：

* 可执行文件路径里含 `\hermes\` / `Hermes.app` / `/hermes/`
* 进程名是 `Hermes.exe` / `Hermes`
* Python 进程**且**命令行里包含 `hermes_cli` / `tui_gateway` / `slash_worker` / `hermes.gateway`

macOS/Linux 版本额外会跳过自身 PID 和父 shell PID，不会误杀跑脚本的终端。

**Q：会不会影响我的浏览器代理？**
清完之后浏览器会走**直连**。如果你需要浏览器继续走代理，重新打开你的 VPN / 代理软件即可，它们启动时会把设置刷回。

**Q：macOS 上 `networksetup` 会不会关掉我正在用的 VPN？**
不会。`networksetup` 改的是**系统偏好设置 → 网络 → 高级 → 代理**（HTTP / HTTPS / SOCKS / PAC 那几个勾选），而不是 VPN 连接本身。真正的 VPN 客户端（比如闪连、Clash for Mac）自己会管这些开关，你重新开启它们时会把值刷回。

**Q：能否给别的用户用？**
可以。全平台脚本都只碰当前登录用户的配置，天然是"每用户"作用域。

**Q：为什么不直接改 Hermes 代码去忽略系统代理？**
那是长期方案（Hermes 内部把 `trust_env=False` 塞进 httpx client），本仓库只是应急工具，不需要修改 Hermes 本体。

## License

MIT
