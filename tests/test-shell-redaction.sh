#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_redacted() {
    local output="$1"
    shift
    local secret
    for secret in "$@"; do
        if grep -Fq "$secret" <<< "$output"; then
            printf 'proxy diagnostic leaked fixture secret: %s\n' "$secret" >&2
            return 1
        fi
    done
}

linux_output="$({
    HTTP_PROXY='http://proxy-user:super-secret@proxy.invalid:8080' \
    NO_PROXY='internal-secret.invalid' \
    bash "$ROOT/fix-hermes-proxy.sh" --dry-run --no-kill
} 2>&1)"
assert_redacted "$linux_output" proxy-user super-secret internal-secret.invalid
grep -Fq '[configured; value redacted]' <<< "$linux_output"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/uname" <<'EOF'
#!/usr/bin/env sh
printf 'Darwin\n'
EOF
cat > "$fixture/scutil" <<'EOF'
#!/usr/bin/env sh
cat <<'OUT'
<dictionary> {
  HTTPEnable : 1
  HTTPProxy : proxy-host-secret.invalid
  HTTPPort : 8080
  ProxyAutoConfigEnable : 1
  ProxyAutoConfigURLString : https://pac-user:pac-password@pac.invalid/config?token=pac-token
  ExceptionsList : <array> {
    0 : internal-bypass-secret.invalid
  }
}
OUT
EOF
cat > "$fixture/networksetup" <<'EOF'
#!/usr/bin/env sh
if [ "${1-}" = '-listallnetworkservices' ]; then
    printf 'An asterisk denotes a disabled service.\nWi-Fi\n'
fi
EOF
chmod +x "$fixture/uname" "$fixture/scutil" "$fixture/networksetup"

mac_output="$(PATH="$fixture:$PATH" bash "$ROOT/fix-hermes-proxy.sh" --dry-run --no-kill 2>&1)"
assert_redacted "$mac_output" proxy-host-secret pac-user pac-password pac-token internal-bypass-secret
grep -Fq 'ProxyAutoConfigURLString' <<< "$mac_output"
grep -Fq '[configured; value redacted]' <<< "$mac_output"
