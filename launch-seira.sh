#!/data/data/com.termux/files/usr/bin/bash
PROJ="$HOME/proton11"
unset LD_PRELOAD

# 后台启动音频，不阻塞
"$PROJ/start-audio.sh" > /dev/null 2>&1 &
export PULSE_SERVER=tcp:127.0.0.1:4713

# 杀掉残留 wineserver，确保 ESYNC 状态一致
"$PROJ/box64/build/box64" "$PROJ/xaw64_wine/proton-11/bin/wine" wineserver -k 2>/dev/null
sleep 1

# 确保共享缓存目录存在
mkdir -p "$PROJ/.cache/dynacache"

# 用 tmux 启动独立会话 (从游戏目录)
tmux kill-session -t seira 2>/dev/null; sleep 1
tmux new-session -c ~/basement/loveai/seira -d -s seira \
  "exec env DISPLAY=:1 WINEPREFIX=$PROJ/p11prefix WINEESYNC=1 WINEDEBUG=-all VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/lvp_icd.aarch64.json BOX64_MMAP32=1 BOX64_DYNAREC_SAFEFLAGS=2 BOX64_DYNAREC_BIGBLOCK=3 BOX64_DYNAREC_CALLRET=1 BOX64_DYNAREC_FORWARD=1024 BOX64_DYNAREC_ALIGNED_ATOMICS=1 BOX64_DYNAREC_STRONGMEM=2 BOX64_DYNAREC_WEAKBARRIER=1 BOX64_DYNAREC_FASTNAN=1 BOX64_DYNAREC_FASTROUND=1 BOX64_DYNACACHE=1 BOX64_DYNACACHE_FOLDER=$PROJ/.cache/dynacache BOX64_DYNACACHE_LIMIT=4403 BOX64_DYNACACHE_COMPRESS=1 BOX64_DYNACACHE_MIN=225 BOX64_RCFILE=$PROJ/xaw64_box64/etc/box64.box64rc WINEDLLOVERRIDES=winepulse.drv=b\\;winealsa.drv= PULSE_SERVER=tcp:127.0.0.1:4713 BOX64_LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$PROJ/xaw64_box64/lib:$PROJ/xaw64_wine/proton-11/lib/wine/x86_64-unix:$PROJ/xaw64_wine/x86_64-windows:$PROJ/proton-11/lib $PROJ/box64/build/box64 $PROJ/xaw64_wine/proton-11/bin/wine seira_chs1.0.exe --disable-gpu"

echo "seira 已启动 (tmux 会话: seira, 共享 DynaCache)"
echo "查看输出: tmux attach -t seira"
echo "断开: Ctrl+B, D"
