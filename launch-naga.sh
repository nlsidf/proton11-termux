#!/data/data/com.termux/files/usr/bin/bash
export FAKE_MACHINE_ID="85536ceb47e8aa768973fe1c6a227604"
export LD_PRELOAD="$HOME/fake_machineid.so"
PROJ="$HOME/proton11"
NAME="naga"

tmux kill-session -t $NAME 2>/dev/null; sleep 1
tmux new-session -c ~/basement/loveai/starfalling -d -s $NAME \
  "exec $PROJ/proton11-run ~/basement/loveai/starfalling/Nagaruboshi.exe"

echo ">>> $NAME 已启动，正在显示输出..."
echo ">>> 断开: Ctrl+B, D (游戏继续在后台运行)"
sleep 1
tmux attach -t $NAME
