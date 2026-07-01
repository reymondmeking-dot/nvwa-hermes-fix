#!/usr/bin/env bash
# fix-hermes-proxy.sh — macOS / Linux 版本
#
# 修复 Hermes Agent "API call failed after 3 retries: Connection error"。
# 与 Windows 版 Fix-Hermes-Proxy.bat 一致的 4 步：
#   1. 打印当前代理状态（env + macOS 系统代理）
#   2. 清空 HTTP_PROXY/HTTPS_PROXY/ALL_PROXY（当前 shell + 给出持久化提示）
#      macOS: 顺便关闭所有网络服务的 Web/Secure/SOCKS Proxy
#   3. 停掉 Hermes 后端进程
#   4. 提示如何重启
#
# 用法：
#   curl -sSL https://raw.githubusercontent.com/reymondmeking-dot/nvwa-hermes-fix/main/fix-hermes-proxy.sh | bash
#   或下载后：chmod +x fix-hermes-proxy.sh && ./fix-hermes-proxy.sh
#
# 选项：
#   --dry-run    只打印会做什么，不真执行
#   --no-kill    不杀 Hermes 进程（只清代理）
#
# 无需 sudo。networksetup 改代理开关在 macOS 上是当前用户可写的。

set -u

DRY=0
KILL=1
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --no-kill) KILL=0 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    esac
done

say()   { printf '%s\n' "$*"; }
step()  { printf '\n\033[1;36m[%s]\033[0m %s\n' "$1" "$2"; }
run()   { if [ "$DRY" = 1 ]; then printf '  (dry) %s\n' "$*"; else eval "$@"; fi; }

OS="$(uname -s)"
case "$OS" in
    Darwin) OS_KIND=mac ;;
    Linux)  OS_KIND=linux ;;
    *)      say "unsupported OS: $OS (this script targets macOS/Linux; use Fix-Hermes-Proxy.bat on Windows)"; exit 2 ;;
esac

say "============================================================"
say " Hermes API Connection Error - Fix Tool ($OS_KIND)"
say " ---------------------------------------------------------"
say " Symptom : API call failed after 3 retries: Connection error"
say " Root    : Ghost proxy in env or system settings; httpx caches"
say "           it at startup so all API calls hit a dead port."
say " Scope   : Current user. No sudo needed."
[ "$DRY" = 1 ] && say " Mode    : DRY-RUN (no changes will be made)"
say "============================================================"

# --- 1) Show state ----------------------------------------------------------
step "1/4" "Current proxy state"
for v in HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy; do
    val="${!v-<unset>}"
    printf '  env %-12s = %s\n' "$v" "$val"
done

if [ "$OS_KIND" = mac ]; then
    say "  --- macOS system proxy (scutil --proxy):"
    scutil --proxy | sed 's/^/    /'
fi

# --- 2) Clear proxy ---------------------------------------------------------
step "2/4" "Clearing proxy env vars for THIS shell"
for v in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
    run "unset $v"
done
say "  done (this shell only). For persistence, remove or comment out"
say "  any 'export HTTP_PROXY=...' / 'export HTTPS_PROXY=...' lines in:"
say "    ~/.zshrc  ~/.bashrc  ~/.bash_profile  ~/.profile  ~/.config/fish/config.fish"

if [ "$OS_KIND" = mac ]; then
    step "2b/4" "Disabling macOS system proxies on every network service"
    if ! command -v networksetup >/dev/null 2>&1; then
        say "  networksetup not found — skipping."
    else
        # First line of `listallnetworkservices` is a legend; skip it.
        # Skip disabled services (they start with '*').
        services=$(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | grep -v '^\*')
        while IFS= read -r svc; do
            [ -z "$svc" ] && continue
            for proto in setwebproxystate setsecurewebproxystate setsocksfirewallproxystate setautoproxystate; do
                run "networksetup $proto \"$svc\" off"
            done
        done <<< "$services"
        say "  done."
    fi
fi

# --- 3) Kill Hermes backend -------------------------------------------------
step "3/4" "Stopping Hermes backend processes"
if [ "$KILL" = 0 ]; then
    say "  --no-kill: skipping."
else
    # match: any process whose exe/argv references Hermes app or the backend python modules
    pattern='Hermes\.app|/hermes/|hermes_cli|tui_gateway|slash_worker|hermes\.gateway'
    # pgrep -f matches full command line; -l prints pid + name
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [ -z "$pids" ]; then
        say "  no matching processes found."
    else
        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            [ "$pid" = "$$" ] && continue           # never nuke ourselves
            [ "$pid" = "$PPID" ] && continue        # nor the shell that launched us
            name=$(ps -o comm= -p "$pid" 2>/dev/null || echo "?")
            say "  killing pid $pid ($name)"
            run "kill -TERM $pid 2>/dev/null || true"
        done <<< "$pids"
        # give TERM a moment, then hard-kill stragglers
        [ "$DRY" = 0 ] && sleep 1
        for pid in $pids; do
            [ "$pid" = "$$" ] && continue
            [ "$pid" = "$PPID" ] && continue
            kill -0 "$pid" 2>/dev/null && run "kill -KILL $pid 2>/dev/null || true"
        done
        say "  done."
    fi
fi

# --- 4) Restart hint --------------------------------------------------------
step "4/4" "Restart Hermes"
say "  macOS : open -a Hermes    # or launch from Applications / Spotlight"
say "  Linux : run your Hermes desktop launcher, or the hermes CLI you use"
say ""
say "  New Hermes processes will read a clean environment and hit the"
say "  API directly."
say "============================================================"
