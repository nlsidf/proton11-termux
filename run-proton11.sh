#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Proton 11 + DXVK + lavapipe 快速启动脚本 (优化版)
# 适用于 Android Termux + TigerVNC 环境
# ============================================================

set -e

# ==================== 配置区 ====================

# 项目根目录
PROJ="$HOME/proton11"

GAMEDIR="$HOME/basement/loveai/sky-rail-and-white-travel"
GAMEEXE="game.exe"
WINE_BIN="$PROJ/xaw64_wine/proton-11/bin/wine"
BOX64="$PROJ/box64/build/box64"
WINEPREFIX_DIR="$PROJ/p11prefix"
DXVK_DIR="$PROJ/dxvk-2.5.3/x64"
MONO_MSI="$PROJ/wine-mono-11.1.0-x86.msi"
VK_ICD="/data/data/com.termux/files/usr/share/vulkan/icd.d/lvp_icd.aarch64.json"

# 缓存目录
CACHE_DIR="$PROJ/.cache"
DYNACACHE_DIR="$CACHE_DIR/dynacache"
SHADER_CACHE_DIR="$CACHE_DIR/shaders"

# ==================== 辅助函数 ====================

kill_wine() {
    pkill -9 -f wineserver 2>/dev/null || true
    pkill -9 -f ".exe" 2>/dev/null || true
    sleep 1
}

log() { echo "[Proton11] $1"; }

# ==================== 首次初始化 ====================

first_time_setup() {
    [ -f "$WINEPREFIX_DIR/drive_d/windows/system32/kernel32.dll" ] && return 0

    log "首次运行: 初始化 wineprefix..."
    setup_env

    $BOX64 $WINE_BIN wineboot --init 2>/dev/null &
    WPID=$!
    for i in $(seq 1 60); do
        if [ -d "$WINEPREFIX_DIR/drive_d" ] && [ ! -e "$WINEPREFIX_DIR/drive_c" ]; then
            ln -s drive_d "$WINEPREFIX_DIR/drive_c"
            break
        fi
        sleep 1
    done
    for i in $(seq 1 180); do
        ! kill -0 $WPID 2>/dev/null && break
        sleep 1
    done
    kill_wine

    rm -f "$WINEPREFIX_DIR/dosdevices/z:"
    ln -s / "$WINEPREFIX_DIR/dosdevices/z:"

    cp "$DXVK_DIR/d3d11.dll" "$WINEPREFIX_DIR/drive_d/windows/system32/"
    cp "$DXVK_DIR/dxgi.dll" "$WINEPREFIX_DIR/drive_d/windows/system32/"

    cat >> "$WINEPREFIX_DIR/user.reg" << 'EOF'

[Software\\Wine\\DllOverrides]
"d3d11"="native,builtin"
"dxgi"="native,builtin"
EOF

    if [ -f "$MONO_MSI" ]; then
        log "安装 Wine Mono..."
        $BOX64 $WINE_BIN msiexec /i "Z:\\data\\data\\com.termux\\files\\home\\proton11\\wine-mono-11.1.0-x86.msi" /quiet 2>/dev/null &
        for i in $(seq 1 120); do
            ! kill -0 $! 2>/dev/null && break
            sleep 1
        done
        kill_wine
    fi

    log "首次初始化完成"
}

# ==================== 环境变量 ====================

setup_env() {
    unset LD_PRELOAD

    # 显示和 Wine 基础
    export DISPLAY=:1
    export WINEPREFIX=$WINEPREFIX_DIR
    export WINEESYNC=1
    export WINEDEBUG=-all
    export VK_ICD_FILENAMES=$VK_ICD

    # Box64 DynaCache - 缓存翻译代码到磁盘，后续启动跳过重编译
    mkdir -p "$DYNACACHE_DIR"
    export BOX64_DYNACACHE=1
    export BOX64_DYNACACHE_FOLDER="$DYNACACHE_DIR"
    export BOX64_DYNACACHE_LIMIT=0            # 不限制缓存大小，用空间换时间
    export BOX64_DYNACACHE_COMPRESS=1          # 最快压缩，节省空间同时开销极小
    export BOX64_DYNACACHE_MIN=100             # 降低最小缓存阈值，更多代码被缓存

    # Box64 DynaRec 性能优化 (Wine 推荐配置)
    export BOX64_DYNAREC_BIGBLOCK=3          # Wine 程序用 3（最大化代码块）
    export BOX64_DYNAREC_STRONGMEM=2         # Wine 需要 x86 内存序，SIMD 屏障
    export BOX64_DYNAREC_WEAKBARRIER=1       # 减少屏障开销
    export BOX64_DYNAREC_SAFEFLAGS=2
    export BOX64_DYNAREC_CALLRET=1           # 优化 CALL/RET 跳转
    export BOX64_DYNAREC_FORWARD=1024        # 更大的前向间隙
    export BOX64_DYNAREC_FASTNAN=1           # 快速 NaN 处理
    export BOX64_DYNAREC_FASTROUND=1         # 快速舍入
    export BOX64_DYNAREC_ALIGNED_ATOMICS=1
    export BOX64_MMAP32=1
    export BOX64_RCFILE=$PROJ/xaw64_box64/etc/box64.box64rc

    # 库搜索路径
    export BOX64_LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$PROJ/xaw64_box64/lib:$PROJ/xaw64_wine/proton-11/lib/wine/x86_64-unix:$PROJ/xaw64_wine/proton-11/lib/wine/i386-windows:$PROJ/xaw64_wine/x86_64-windows:$PROJ/proton-11/lib
    export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:${LD_LIBRARY_PATH:-}

    # 音频 (PulseAudio AAudio - TCP 连接避免死锁)
    export PULSE_SERVER=tcp:127.0.0.1:4713
    export WINEDLLOVERRIDES="winepulse.drv=b;winealsa.drv="

    # Shader 缓存 - 避免每次重编译着色器
    mkdir -p "$SHADER_CACHE_DIR/dxvk" "$SHADER_CACHE_DIR/mesa"
    export DXVK_STATE_CACHE_PATH="$SHADER_CACHE_DIR/dxvk/state-cache"
    export MESA_SHADER_CACHE_DIR="$SHADER_CACHE_DIR/mesa"
    export MESA_SHADER_CACHE_MAX_SIZE=512M
}

# ==================== 主流程 ====================

main() {
    local exe_path="${1:-$GAMEDIR/$GAMEEXE}"
    [ ! -f "$exe_path" ] && { echo "错误: 找不到 $exe_path"; exit 1; }

    first_time_setup
    setup_env

    log "启动游戏 (DynaCache: $DYNACACHE_DIR)"
    cd "$(dirname "$exe_path")"
    exec $BOX64 $WINE_BIN "$(basename "$exe_path")"
}

main "$@"
