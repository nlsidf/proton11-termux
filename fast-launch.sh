#!/data/data/com.termux/files/usr/bin/bash
unset LD_PRELOAD

PROJ="$HOME/proton11"

# ===== 显示 =====
export DISPLAY=:1
export WINEPREFIX=$PROJ/p11prefix
export WINEDEBUG=-all
export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/lvp_icd.aarch64.json

# ===== Box64 性能 =====
export BOX64_MMAP32=1
export BOX64_DYNAREC_SAFEFLAGS=2
export BOX64_DYNAREC_BIGBLOCK=3
export BOX64_DYNAREC_CALLRET=1
export BOX64_DYNAREC_FORWARD=1024
export BOX64_DYNAREC_ALIGNED_ATOMICS=1
export BOX64_DYNAREC_STRONGMEM=2
export BOX64_DYNAREC_WEAKBARRIER=1
export BOX64_DYNAREC_FASTNAN=1
export BOX64_DYNAREC_FASTROUND=1
export BOX64_RCFILE=$PROJ/xaw64_box64/etc/box64.box64rc
export BOX64_DYNACACHE=1
export BOX64_DYNACACHE_FOLDER=$PROJ/.cache/dynacache

# ===== 库搜索路径 =====
export BOX64_LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:$PROJ/xaw64_box64/lib:$PROJ/xaw64_wine/proton-11/lib/wine/x86_64-unix:$PROJ/xaw64_wine/proton-11/lib/wine/i386-windows:$PROJ/xaw64_wine/x86_64-windows:$PROJ/proton-11/lib
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:${LD_LIBRARY_PATH:-}

# ===== 音频 (PulseAudio AAudio - TCP 连接避免死锁) =====
export PULSE_SERVER=tcp:127.0.0.1:4713
# 强制使用 winepulse，禁用 winealsa
export WINEDLLOVERRIDES="winepulse.drv=b;winealsa.drv="

# 游戏参数
GAME_DIR="$HOME/basement/loveai/Amairo Chocolate_wm"
GAME_EXE="ac_chinese.exe"

cd "$GAME_DIR"
exec $PROJ/box64/build/box64 $PROJ/xaw64_wine/proton-11/bin/wine "$GAME_EXE"
