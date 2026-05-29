#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# PulseAudio 启动脚本 - Android AAudio 硬件输出
# 为 Wine/Proton 游戏提供音频支持
# ============================================================
# 用法: ./start-audio.sh        # 后台启动音频
#        ./start-audio.sh stop  # 停止音频
#        ./start-audio.sh status # 查看状态
# ============================================================

PA_SOCKET="$HOME/.config/pulse/pulseaudio.sock"
PA_CONFIG="$HOME/.config/pulse/default.pa"

log() { echo "[Audio] $1"; }

stop_pa() {
    # 停止 runsv 服务（如果启用）
    sv stop pulseaudio 2>/dev/null
    # 杀掉所有 pulseaudio 进程
    pkill -x pulseaudio 2>/dev/null
    sleep 1
    # 确保杀干净
    if pgrep -x pulseaudio > /dev/null 2>&1; then
        pkill -9 -x pulseaudio 2>/dev/null
        sleep 1
    fi
    rm -f "$PA_SOCKET" 2>/dev/null
}

start_pa() {
    # 如果已经在运行，先检查是否正常
    if pgrep -x pulseaudio > /dev/null 2>&1; then
        if [ -S "$PA_SOCKET" ] && pactl info > /dev/null 2>&1; then
            log "PulseAudio 已在运行"
            return 0
        fi
        log "PulseAudio 状态异常，重启..."
        stop_pa
    fi

    log "启动 PulseAudio (AAudio 硬件输出)..."

    # 使用 -n 标志不加载默认配置，只用 default.pa
    PULSEAUDIO_NOAUTOSPAWN=1 \
    pulseaudio -n -F "$PA_CONFIG" \
        --daemonize=no \
        --exit-idle-time=-1 \
        > "$HOME/.pulseaudio.log" 2>&1 &

    # 等待启动
    for i in $(seq 1 10); do
        sleep 1
        if [ -S "$PA_SOCKET" ] && pactl info > /dev/null 2>&1; then
            log "PulseAudio 启动成功"
            log "  Socket: $PA_SOCKET"
            SINK=$(pactl list sinks short 2>/dev/null | head -1 | awk '{print $2}')
            RATE=$(pactl list sinks short 2>/dev/null | head -1 | awk '{print $5}')
            log "  Sink: $SINK ($RATE)"
            return 0
        fi
    done

    log "错误: PulseAudio 启动失败"
    log "  日志: $HOME/.pulseaudio.log"
    tail -5 "$HOME/.pulseaudio.log" 2>/dev/null
    return 1
}

show_status() {
    if ! pgrep -x pulseaudio > /dev/null 2>&1; then
        log "PulseAudio 未运行"
        return 1
    fi
    if ! pactl info > /dev/null 2>&1; then
        log "PulseAudio 运行中但无法连接"
        return 1
    fi
    pactl info 2>/dev/null | grep -E "Server Name|Server Version|Default Sink|Default Source"
    echo ""
    pactl list sinks short 2>/dev/null
}

case "${1:-}" in
    stop|kill)
        stop_pa
        log "PulseAudio 已停止"
        ;;
    status)
        show_status
        ;;
    restart)
        stop_pa
        start_pa
        ;;
    *)
        start_pa
        ;;
esac
