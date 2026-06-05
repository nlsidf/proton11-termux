install_gecko() {
    # 检查是否已安装
    if [ -d "$WINEPREFIX_DIR/drive_d/windows/system32/gecko" ] && ls "$WINEPREFIX_DIR/drive_d/windows/system32/gecko/"* &>/dev/null 2>/dev/null; then
        local gfiles=$(find "$WINEPREFIX_DIR/drive_d/windows/system32/gecko" -type f 2>/dev/null | wc -l)
        if [ "$gfiles" -gt 2 ]; then
            log "Wine Gecko 已安装，跳过"
            return 0
        fi
    fi

    local installed=false

    if [ -f "$GECKO_MSI_X64" ]; then
        log "步骤 4/5: 安装 Wine Gecko 2.47.4 x86_64 (约 1-2 分钟)..."
        $BOX64 $WINE_BIN msiexec /i "Z:\\data\\data\\com.termux\\files\\home\\proton11\\wine-gecko-2.47.4-x86_64.msi" /quiet 2>/dev/null &
        for i in $(seq 1 120); do
            ! kill -0 $! 2>/dev/null && break
            sleep 1
        done
        pkill -9 -f wineserver 2>/dev/null || true
        sleep 1
        installed=true
    fi

    if [ -f "$GECKO_MSI_X86" ]; then
        log "步骤 4/5: 安装 Wine Gecko 2.47.4 x86 (约 1-2 分钟)..."
        $BOX64 $WINE_BIN msiexec /i "Z:\\data\\data\\com.termux\\files\\home\\proton11\\wine-gecko-2.47.4-x86.msi" /quiet 2>/dev/null &
        for i in $(seq 1 120); do
            ! kill -0 $! 2>/dev/null && break
            sleep 1
        done
        pkill -9 -f wineserver 2>/dev/null || true
        sleep 1
        installed=true
    fi

    if ! $installed; then
        warn "Wine Gecko 安装包不存在: $GECKO_MSI_X86 / $GECKO_MSI_X64，跳过"
        return 0
    fi

    log "Wine Gecko 安装完成"
}
