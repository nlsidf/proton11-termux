#!/data/data/com.termux/files/usr/bin/bash
PROJ="$HOME/proton11"
NAME="seira"
unset LD_PRELOAD

"$PROJ/start-audio.sh" > /dev/null 2>&1 &
export PULSE_SERVER=tcp:127.0.0.1:4713
export FAKE_MACHINE_ID="85536ceb47e8aa768973fe1c6a227604"
export LD_PRELOAD="$HOME/fake_machineid.so"

mkdir -p "$PROJ/.cache/dynacache"

tmux kill-session -t $NAME 2>/dev/null; sleep 1
tmux new-session -c ~/basement/loveai/seira -d -s $NAME \
  "exec env DISPLAY=:1 WINEPREFIX=$PROJ/p11prefix WINEESYNC=1 WINEDEBUG=-all VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/lvp_icd.aarch64.json BOX64_MMAP32=1 BOX64_DYNAREC_SAFEFLAGS=2 BOX64_DYNAREC_BIGBLOCK=3 BOX64_DYNAREC_CALLRET=1 BOX64_DYNAREC_FORWARD=1024 BOX64_DYNAREC_ALIGNED_ATOMICS=1 BOX64_DYNAREC_STRONGMEM=2 BOX64_DYNAREC_WEAKBARRIER=1 BOX64_DYNAREC_FASTNAN=1 BOX64_DYNAREC_FASTROUND=1 BOX64_DYNACACHE=1 BOX64_DYNACACHE_FOLDER=$PROJ/.cache/dynacache BOX64_DYNACACHE_LIMIT=4403 BOX64_DYNACACHE_COMPRESS=1 BOX64_DYNACACHE_MIN=225 BOX64_RCFILE=$PROJ/xaw64_box64/etc/box64.box64rc WINEDLLOVERRIDES=winepulse.drv=b\\;winealsa.drv= PULSE_SERVER=tcp:127.0.0.1:4713 BOX64_LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$PROJ/xaw64_box64/lib:$PROJ/xaw64_wine/proton-11/lib/wine/x86_64-unix:$PROJ/xaw64_wine/x86_64-windows:$PROJ/proton-11/lib $PROJ/box64/build/box64 $PROJ/xaw64_wine/proton-11/bin/wine seira_chs1.0.exe --disable-gpu"

echo ">>> $NAME 已启动，正在显示输出..."
echo ">>> 断开: Ctrl+B, D (游戏继续在后台运行)"
sleep 1
tmux attach -t $NAME
