#!/bin/bash

# 🚀 multi-agent communication demo 環境構築 (boss, worker1, worker2)

set -e  # エラー時に停止

# 色付きログ関数
log_info() {
    echo -e "\033[1;32m[info]\033[0m $1"
}

log_success() {
    echo -e "\033[1;34m[success]\033[0m $1"
}

echo "🤖 multi-agent communication demo 環境構築 (3エージェント)"
echo "========================================================"
echo ""

# step 1: 既存セッションクリーンアップ
log_info "🧹 既存セッションクリーンアップ開始..."

tmux kill-session -t multiagent 2>/dev/null && log_info "multiagentセッション削除完了" || log_info "multiagentセッションは存在しませんでした"

# 完了ファイルクリア
mkdir -p ./tmp
rm -f ./tmp/worker*_done.txt 2>/dev/null && log_info "既存の完了ファイルをクリア" || log_info "完了ファイルは存在しませんでした"

log_success "✅ クリーンアップ完了"
echo ""

# step 2: multiagentセッション作成（3ペイン：boss, worker1, worker2）
log_info "📺 multiagentセッション作成開始 (3ペイン)..."

# 最初のペイン(boss)作成
tmux new-session -d -s multiagent -n "agents"

# 3ペインレイアウト作成 (main-vertical: 左にboss, 右にworker1,2)
tmux split-window -h -t "multiagent:0"      # 水平分割（左右）
tmux select-pane -t "multiagent:0.1"
tmux split-window -v                      # 右側を垂直分割

# ペインタイトル設定
log_info "ペインタイトル設定中..."
pane_titles=("boss" "worker1" "worker2")

for i in {0..2}; do
    tmux select-pane -t "multiagent:0.$i"
    tmux select-pane -t "multiagent:0.$i" -T "${pane_titles[$i]}" # -Tオプションでタイトル設定

    # 作業ディレクトリ設定
    tmux send-keys -t "multiagent:0.$i" "cd $(pwd)" c-m

    # カラープロンプト設定
    if [ $i -eq 0 ]; then
        # boss: 赤色
        tmux send-keys -t "multiagent:0.$i" "export PS1='(\[\033[1;31m\]${pane_titles[$i]}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ '" c-m
    else
        # workers: 青色
        tmux send-keys -t "multiagent:0.$i" "export PS1='(\[\033[1;34m\]${pane_titles[$i]}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ '" c-m
    fi

    # ウェルカムメッセージ
    tmux send-keys -t "multiagent:0.$i" "echo '=== ${pane_titles[$i]} エージェント ==='" c-m
done

log_success "✅ multiagentセッション作成完了"
echo ""

# step 3: 環境確認・表示
log_info "🔍 環境確認中..."

echo ""
echo "📊 セットアップ結果:"
echo "==================="

# tmuxセッション確認
echo "📺 tmux sessions:"
tmux list-sessions
echo ""

# ペイン構成表示
echo "📋 ペイン構成:"
echo "  multiagentセッション（3ペイン）:"
echo "    pane 0: boss       (チームリーダー)"
echo "    pane 1: worker1    (実行担当者a)"
echo "    pane 2: worker2    (実行担当者b)"
echo ""

log_success "🎉 demo環境セットアップ完了！"
echo ""
echo "📋 次のステップ:"
echo "  1. 🔗 セッションアタッチ:"
echo "     # マルチエージェント確認"
echo "     tmux attach-session -t multiagent"
echo ""
echo "  2. 🤖 claude code起動:"
echo "     # 各エージェントのペインで claude と入力して起動"
echo "     for i in {0..2}; do tmux send-keys -t multiagent:0.\$i 'claude' c-m; done"
echo ""
echo "  3. 📜 指示書確認:"
echo "     boss: instructions/boss.md"
echo "     worker1,2: instructions/worker.md"
echo "     システム構造: claude.md"
echo ""
echo "  あなたは boss です。"
echo "  ./todo.md に書かれたタスクを実行してください。"
