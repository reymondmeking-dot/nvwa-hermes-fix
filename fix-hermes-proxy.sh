#!/usr/bin/env bash
# fix-hermes-proxy.sh — macOS / Linux 版本
#
# 修复 Hermes Agent "API call failed after 3 retries: Connection error"。
# 与 Windows 版 Fix-Hermes-Proxy.bat 一致的 4 步：
#   1. 打印当前代理状态（env + macOS 系统代理）
#   2. 清空脚本子进程的 HTTP_PROXY/HTTPS_PROXY/ALL_PROXY，并给出父 shell 提示
#      macOS: 顺便关闭所有网络服务的 Web/Secure/SOCKS Proxy
#   3. 停掉 Hermes 后端进程
#   4. 提示如何重启
#
# 用法：
#   下载后先检查内容：chmod +x fix-hermes-proxy.sh && ./fix-hermes-proxy.sh
#
# 选项：
#   --dry-run    只打印会做什么，不真执行
#   --no-kill    不杀 Hermes 进程（只清代理）
#
# 无需 sudo。networksetup 改代理开关在 macOS 上是当前用户可写的。

set -uo pipefail

DRY=0
KILL=1
VERSION=1.1.1
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --no-kill) KILL=0 ;;
        --version) printf '%s\n' "$VERSION"; exit 0 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

say()   { printf '%s\n' "$*"; }
step()  { printf '\n\033[1;36m[%s]\033[0m %s\n' "$1" "$2"; }
run() {
    if [ "$DRY" = 1 ]; then
        printf '  (dry)'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}
proxy_value_status() {
    local name="$1"
    if [ "${!name+x}" != x ]; then
        printf '[unset]'
    elif [ -z "${!name}" ]; then
        printf '[empty]'
    else
        printf '[configured; value redacted]'
    fi
}

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
    printf '  env %-12s = %s\n' "$v" "$(proxy_value_status "$v")"
done

if [ "$OS_KIND" = mac ]; then
    say "  --- macOS system proxy (scutil --proxy):"
    proxy_state="$(scutil --proxy 2>/dev/null || true)"
    for key in HTTPEnable HTTPSEnable SOCKSEnable ProxyAutoConfigEnable; do
        value="$(printf '%s\n' "$proxy_state" | awk -v key="$key" '$1 == key && $2 == ":" { print $3; exit }')"
        if [ -n "$value" ]; then
            printf '    %-28s = %s\n' "$key" "$value"
        else
            printf '    %-28s = [unset]\n' "$key"
        fi
    done
    for key in HTTPProxy HTTPSProxy SOCKSProxy ProxyAutoConfigURLString ExceptionsList; do
        if printf '%s\n' "$proxy_state" | grep -Eq "^[[:space:]]*${key}[[:space:]]*:"; then
            printf '    %-28s = [configured; value redacted]\n' "$key"
        else
            printf '    %-28s = [unset]\n' "$key"
        fi
    done
fi

# --- 2) Clear proxy ---------------------------------------------------------
step "2/4" "Clearing proxy env vars inside this repair process"
for v in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
    if [ "$DRY" = 1 ]; then
        say "  (dry) unset $v"
    else
        unset "$v"
    fi
done
say "  done. A child script cannot modify its parent shell environment."
say "  To clear the current terminal too, run this fixed command after the script:"
say "    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy"
say "  For persistence, remove or comment out"
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
                run networksetup "$proto" "$svc" off
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
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            [ "$pid" = "$$" ] && continue           # never nuke ourselves
            [ "$pid" = "$PPID" ] && continue        # nor the shell that launched us
            name=$(ps -o comm= -p "$pid" 2>/dev/null || echo "?")
            say "  killing pid $pid ($name)"
            run kill -TERM "$pid" 2>/dev/null || true
        done <<< "$pids"
        # give TERM a moment, then hard-kill stragglers
        [ "$DRY" = 0 ] && sleep 1
        for pid in $pids; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            [ "$pid" = "$$" ] && continue
            [ "$pid" = "$PPID" ] && continue
            if kill -0 "$pid" 2>/dev/null; then
                run kill -KILL "$pid" 2>/dev/null || true
            fi
        done
        say "  done."
    fi
fi

# --- 4) Restart hint --------------------------------------------------------
step "4/4" "Restart Hermes"
say "  macOS : open -a Hermes    # or launch from Applications / Spotlight"
say "  Linux : run your Hermes desktop launcher, or the hermes CLI you use"
say ""
say "  If you launch Hermes from this terminal, clear its parent-shell proxy"
say "  variables with the command shown in step 2 before restarting."
say "============================================================"
