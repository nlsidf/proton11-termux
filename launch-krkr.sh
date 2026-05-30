#!/data/data/com.termux/files/usr/bin/bash
PROJ="$HOME/proton11"
NAME="krkr"

tmux kill-session -t $NAME 2>/dev/null; sleep 1
tmux new-session -c ~/basement/loveai/starfalling -d -s $NAME \
  "exec $PROJ/proton11-run ~/basement/loveai/krkrpc/krkr-incomplete-load.exe"

echo "$NAME 已启动 (tmux 会话: $NAME)"
echo "查看输出: tmux attach -t $NAME"
echo "断开: Ctrl+B, D"
