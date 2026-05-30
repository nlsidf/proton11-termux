#!/data/data/com.termux/files/usr/bin/bash
PROJ="$HOME/proton11"
NAME="naga"

tmux kill-session -t $NAME 2>/dev/null; sleep 1
tmux new-session -c ~/basement/loveai/starfalling -d -s $NAME \
  "exec $PROJ/proton11-run ~/basement/loveai/starfalling/Nagaruboshi.exe"

echo ">>> $NAME 已启动，正在显示输出..."
echo ">>> 断开: Ctrl+B, D (游戏继续在后台运行)"
sleep 1
tmux attach -t $NAME
