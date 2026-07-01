# nvwa-hermes-fix

修复 **Hermes Agent** 在 Windows 下常见的
`API call failed after 3 retries: Connection error` 错误的一键工具。

---

## 现象

在 Hermes 桌面版里发消息，模型返回：

```
API call failed after 3 retries: Connection error
```

后端日志能看到 httpx 在往 `127.0.0.1:<某端口>`（比如 `19828`）连接，
但那个端口根本没有服务在监听。

## 根因

Windows 上的 **WinInet 系统代理注册表**里被 VPN / 代理软件
（闪连 VPN、Clash、v2rayN、Shadowsocks 等）留下了"幽灵值"：

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings
  ProxyEnable  = 1
  ProxyServer  = 127.0.0.1:19828
  AutoConfigURL= http://127.0.0.1:xxxx/xxx.pac
```

代理软件已经关了，但注册表里的值没被恢复。
Python `httpx` 客户端启动时会读一次这些值并**缓存**到 HTTP client 对象里，
之后所有 Ark / Anthropic / OpenAI API 请求都被路由到那个死端口 → 连不上 → 重试 3 次报错。

即便你手动把注册表清了，**已经在跑的 Hermes 进程** 也已经把旧值缓存了，必须**重启后端**才能读到干净的值。

## 这个脚本做什么（4 步）

1. **打印**当前 WinInet 代理状态（`ProxyServer` / `ProxyEnable` / `AutoConfigURL`），便于事后核对。
2. **清空** `ProxyServer` / `AutoConfigURL`，把 `ProxyEnable` 设成 `0` —— 彻底铲除幽灵代理。
3. **停掉 Hermes 后端**：`Hermes.exe`（Electron 壳）、`gateway` / `tui_gateway` / `slash_worker` 等 Python 进程 —— 因为它们启动时已经把旧代理值缓存进 httpx client。
4. **广播** `WinInet INTERNET_OPTION_SETTINGS_CHANGED` / `REFRESH`，让还活着的 WinInet 消费者立刻感知变化。

**范围：** 仅当前用户（`HKCU`），**不需要管理员权限**，**不影响真正在用的代理软件**——
如果你之后重新打开闪连 VPN / Clash 等，它们会自动把注册表值改回去，
本脚本只清"死"的、被丢下的值。

## 使用方法

**下载脚本**：直接下载仓库里的 [`Fix-Hermes-Proxy.bat`](./Fix-Hermes-Proxy.bat)，
放到桌面（或任意你顺手的位置）。

**触发方式**：再次遇到 `API call failed after 3 retries: Connection error` 时，
**双击** `Fix-Hermes-Proxy.bat` 运行即可。

**恢复 Hermes**：脚本跑完后，双击**桌面 / 开始菜单**的 Hermes 图标重新打开就行，
新进程会读到干净的注册表。脚本末尾也会打印出 `Hermes.exe` 常见路径供你手动定位：

* 安装版：`%LOCALAPPDATA%\Programs\hermes\Hermes.exe`
* 开发版：`%LOCALAPPDATA%\hermes\hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe`

**下次再出现**同样错误：直接双击这个 bat，不用重复排查。

## 兼容性

| 项目 | 说明 |
|---|---|
| 系统 | Windows 10 1607+ / Windows 11（含 24H2） |
| 权限 | 当前用户，无需 UAC 管理员 |
| 依赖 | 系统自带 PowerShell 5.1+、`reg`、`taskkill`（无 `wmic` 依赖，因为 Win11 24H2 已经移除 wmic） |
| 影响面 | 仅 `HKCU` 注册表；仅 `Hermes.exe` + Hermes 相关 Python 进程 |

## 常见问答

**Q：会不会误杀我的其他 Python 程序？**
不会。脚本只杀满足以下之一的进程：

* 可执行文件路径里含 `\hermes\`
* 进程名是 `Hermes.exe`
* 进程名是 `python.exe` / `pythonw.exe` **且** 命令行里包含 `hermes_cli` / `tui_gateway` / `slash_worker` / `hermes.gateway`

**Q：会不会影响我的浏览器代理？**
清完之后浏览器会走**直连**（`ProxyEnable=0`）。
如果你需要浏览器继续走代理，重新打开你的 VPN / 代理软件即可，它们启动时会把注册表值刷回。

**Q：能否给别的用户用？**
可以。把 `Fix-Hermes-Proxy.bat` 拷到别的 Windows 用户桌面双击即可。
它只碰当前登录用户的 `HKCU`，天然是"每用户"作用域。

**Q：为什么不直接改 Hermes 代码去忽略系统代理？**
那是长期方案（Hermes 内部把 `trust_env=False` 塞进 httpx client），
本仓库只是应急工具，不需要修改 Hermes 本体。

## License

MIT
