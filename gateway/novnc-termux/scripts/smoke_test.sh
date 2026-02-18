#!/data/data/com.termux/files/usr/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib_config.sh"

FAIL_COUNT=0

pass() { echo -e "  ${GREEN}[OK]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

echo -e "${BLUE}=======================================${NC}"
echo -e "${BLUE} SwissWorkspaceGateway — Smoke Test${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""

# ─── 0. Check bind safety ───────────────────────────────────────
log_info "Checking websockify bind configuration..."
if [ "${WEBSOCKIFY_BIND:-__UNSET__}" = "__UNSET__" ]; then
    fail "WEBSOCKIFY_BIND unresolved (Tailscale not detected, .env not set)"
elif [ "$WEBSOCKIFY_BIND" = "0.0.0.0" ]; then
    echo -e "  ${YELLOW}[WARN]${NC} WEBSOCKIFY_BIND=0.0.0.0 — websockify listens on ALL interfaces"
    echo -e "  ${YELLOW}[WARN]${NC} Recommend binding to Tailscale IP for Tailscale-only access"
else
    pass "WEBSOCKIFY_BIND=$WEBSOCKIFY_BIND (not 0.0.0.0)"
fi

# ─── 1. Run healthcheck ─────────────────────────────────────────
log_info "Running healthcheck..."
if bash "$SCRIPT_DIR/healthcheck.sh" all > /dev/null 2>&1; then
    pass "Healthcheck passed"
else
    fail "Healthcheck failed (run 'bash scripts/healthcheck.sh all' for details)"
fi

# ─── 2. Verify VNC localhost-only binding (Debian-side nc) ──────
echo ""
log_info "Verifying VNC localhost binding..."

while IFS= read -r ws_id; do
    config=$(get_ws_config "$ws_id")
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    if proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z 127.0.0.1 "$vnc_port" 2>/dev/null; then
        pass "VNC :$vnc_port reachable on 127.0.0.1 (localhost)"
    else
        fail "VNC :$vnc_port not listening on 127.0.0.1"
    fi
done < <(get_all_ws_ids)

# ─── 3. Verify VNC NOT on 0.0.0.0 (Debian-side nc) ─────────────
echo ""
log_info "Verifying VNC NOT exposed on 0.0.0.0..."

while IFS= read -r ws_id; do
    config=$(get_ws_config "$ws_id")
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    if proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        nc -z 0.0.0.0 $vnc_port 2>/dev/null && \
        ! nc -z 127.0.0.1 $vnc_port 2>/dev/null
    " 2>/dev/null; then
        fail "VNC :$vnc_port exposed on 0.0.0.0 (MUST be localhost)"
    else
        pass "VNC :$vnc_port not exposed on 0.0.0.0"
    fi
done < <(get_all_ws_ids)

# ─── 4. Verify noVNC HTTP endpoints ─────────────────────────────
echo ""
log_info "Verifying noVNC HTTP endpoints..."

novnc_check_host="${WEBSOCKIFY_BIND:-127.0.0.1}"
if [ "$novnc_check_host" = "__UNSET__" ] || [ "$novnc_check_host" = "0.0.0.0" ]; then
    novnc_check_host="127.0.0.1"
fi

while IFS= read -r ws_id; do
    config=$(get_ws_config "$ws_id")
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    check_url="http://${novnc_check_host}:${novnc_port}/vnc.html"
    fallback_url="http://127.0.0.1:${novnc_port}/vnc.html"

    http_code=""
    http_code=$(proot-distro login "$PROOT_DISTRO" --shared-tmp -- bash -c "
        if command -v curl &>/dev/null; then
            code=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 '$check_url' 2>/dev/null)
            if [ \"\$code\" != '200' ] && [ \"\$code\" != '302' ]; then
                code=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 '$fallback_url' 2>/dev/null)
            fi
            echo \"\$code\"
        elif command -v wget &>/dev/null; then
            wget -q --spider -S '$check_url' 2>&1 | grep 'HTTP/' | tail -1 | awk '{print \$2}'
        else
            echo 'nocurl'
        fi
    " 2>/dev/null || echo "error")

    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        pass "noVNC port $novnc_port: HTTP $http_code"
    elif [ "$http_code" = "nocurl" ]; then
        fail "noVNC port $novnc_port: curl/wget not available inside Debian"
    elif [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
        fail "noVNC port $novnc_port: HTTP $http_code (expected 200 or 302)"
    else
        fail "noVNC port $novnc_port: no HTTP response (websockify not running?)"
    fi
done < <(get_all_ws_ids)

# ─── 5. Verify websockify remotely accessible (Debian-side nc) ──
echo ""
log_info "Verifying websockify is remotely accessible..."

while IFS= read -r ws_id; do
    config=$(get_ws_config "$ws_id")
    read -r display vnc_port novnc_port geometry depth base_dir bind_host <<< "$config"

    if proot-distro login "$PROOT_DISTRO" --shared-tmp -- nc -z "$novnc_check_host" "$novnc_port" 2>/dev/null; then
        pass "websockify :$novnc_port reachable on $novnc_check_host"
    else
        fail "websockify :$novnc_port not reachable on $novnc_check_host"
    fi
done < <(get_all_ws_ids)

# ─── Summary ────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}=======================================${NC}"
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN} All smoke tests passed${NC}"
else
    echo -e "${RED} $FAIL_COUNT smoke test(s) failed${NC}"
fi
echo -e "${BLUE}=======================================${NC}"

exit $FAIL_COUNT
