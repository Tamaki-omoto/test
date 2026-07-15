#!/usr/bin/env bash
# sync-claude.sh pull|push — pull-rebase 運用の薄い同期スクリプト (Linux / macOS)
#
#   pull : ローカル変更をスナップショットcommit → git pull --rebase
#   push : 同上 → pull --rebase → git push
#
# commit 前に簡易シークレットスキャンを行う(FORCE=1 でスキップ)。
# alias 推奨: alias sync-claude='~/work/<このリポジトリ>/claude-sync/scripts/sync-claude.sh'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

GIT_ROOT="$(git -C "$REPO_DIR" rev-parse --show-toplevel)"
BRANCH="$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD)"

# --- コピーモード対応(symlink 環境では no-op) ---------------------------
import_copy_mode() {
  local home_md="$CLAUDE_HOME/CLAUDE.md" repo_md="$REPO_DIR/claude/CLAUDE.md"
  if [ -f "$home_md" ] && [ ! -L "$home_md" ] && ! cmp -s "$home_md" "$repo_md"; then
    cp "$home_md" "$repo_md"
  fi
}
export_copy_mode() {
  local home_md="$CLAUDE_HOME/CLAUDE.md" repo_md="$REPO_DIR/claude/CLAUDE.md"
  if [ -f "$home_md" ] && [ ! -L "$home_md" ] && ! cmp -s "$repo_md" "$home_md"; then
    cp "$repo_md" "$home_md"
  fi
}

# --- 追加行のみを対象にした簡易シークレットスキャン -------------------------
secret_scan() {
  local hits
  hits="$(git -C "$GIT_ROOT" diff --cached -- "$REPO_DIR" \
    | grep -E '^\+' \
    | grep -nE '(sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' \
    || true)"
  if [ -n "$hits" ]; then
    echo "!! APIキー/秘密鍵らしき文字列がコミット対象に含まれています:" >&2
    echo "$hits" >&2
    echo "!! 該当箇所を取り除くか、誤検知なら FORCE=1 を付けて再実行してください。" >&2
    exit 1
  fi
}

snapshot_commit() {
  git -C "$GIT_ROOT" add -A -- "$REPO_DIR"
  if ! git -C "$GIT_ROOT" diff --cached --quiet; then
    [ "${FORCE:-0}" = "1" ] || secret_scan
    git -C "$GIT_ROOT" commit -q -m "sync($(hostname)): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "committed local snapshot"
  fi
}

rebase_pull() {
  git -C "$GIT_ROOT" pull --rebase origin "$BRANCH" || {
    echo "!! rebase コンフリクト。ファイルを解決して 'git rebase --continue' 後、" >&2
    echo "!! sync-claude push を再実行してください。" >&2
    exit 1
  }
}

case "${1:-}" in
  pull)
    import_copy_mode
    snapshot_commit
    rebase_pull
    export_copy_mode
    echo "pull 完了 ($BRANCH)"
    ;;
  push)
    import_copy_mode
    snapshot_commit
    rebase_pull
    git -C "$GIT_ROOT" push -u origin "$BRANCH"
    export_copy_mode
    echo "push 完了 ($BRANCH)"
    ;;
  *)
    echo "usage: sync-claude.sh pull|push   (FORCE=1 でシークレットスキャンをスキップ)" >&2
    exit 2
    ;;
esac
