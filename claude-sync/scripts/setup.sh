#!/usr/bin/env bash
# setup.sh — ~/.claude のメモリ類をこのリポジトリへリンクする (Linux / macOS)
#
# 管理者権限不要。再実行可能(冪等)。新しいプロジェクトを作ったら再実行する。
#
# 環境変数:
#   CLAUDE_HOME  … 既定 $HOME/.claude
#   WORK_ROOT    … 作業ディレクトリ規約のルート。既定 $HOME/work
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$REPO_DIR/claude"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
WORK_ROOT="${WORK_ROOT:-$HOME/work}"
TS="$(date +%Y%m%d-%H%M%S)"

log() { printf '%s\n' "$*"; }

# Claude Code のプロジェクトスラッグ: 絶対パスの英数字以外を '-' に置換
slugify() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

mkdir -p "$CLAUDE_HOME/projects" "$SRC_DIR/projects"

# ---------------------------------------------------------------------------
# 1. ~/.claude/CLAUDE.md → repo/claude/CLAUDE.md (symlink)
# ---------------------------------------------------------------------------
repo_md="$SRC_DIR/CLAUDE.md"
home_md="$CLAUDE_HOME/CLAUDE.md"

if [ -L "$home_md" ]; then
  log "CLAUDE.md: リンク済み -> $(readlink "$home_md")"
else
  if [ -f "$home_md" ]; then
    if [ ! -s "$repo_md" ] || grep -q 'claude-sync: template' "$repo_md"; then
      log "CLAUDE.md: ローカルの内容をリポジトリに取り込みます"
      cp "$home_md" "$repo_md"
    else
      log "CLAUDE.md: リポジトリ版と競合。ローカルを CLAUDE.md.bak-$TS に退避しました(必要なら手動マージ)"
      cp "$home_md" "$CLAUDE_HOME/CLAUDE.md.bak-$TS"
    fi
    rm "$home_md"
  fi
  ln -s "$repo_md" "$home_md"
  log "CLAUDE.md: linked $home_md -> $repo_md"
fi

# ---------------------------------------------------------------------------
# 2. auto memory: ~/.claude/projects/<slug>/memory → repo/claude/projects/<正規名>/memory
# ---------------------------------------------------------------------------
link_memory() { # $1=ローカルのプロジェクトdir  $2=リポジトリ側の正規名
  local proj_dir="$1" name="$2"
  local local_mem="$proj_dir/memory"
  local repo_mem="$SRC_DIR/projects/$name/memory"

  [ -L "$local_mem" ] && return 0  # リンク済み

  mkdir -p "$repo_mem" "$proj_dir"
  if [ -d "$local_mem" ]; then
    log "memory[$name]: 既存のローカル memory を取り込み(上書きなし)、memory.bak-$TS に退避"
    cp -Rn "$local_mem/." "$repo_mem/" 2>/dev/null || true
    mv "$local_mem" "$proj_dir/memory.bak-$TS"
  fi
  ln -s "$repo_mem" "$local_mem"
  log "memory[$name]: linked $local_mem -> $repo_mem"
}

declare -A KNOWN_SLUGS=()

# 2a. WORK_ROOT 配下の実プロジェクト(正規名で共有 — OS をまたいで同一メモリ)
if [ -d "$WORK_ROOT" ]; then
  for p in "$WORK_ROOT"/*/; do
    [ -d "$p" ] || continue
    name="$(basename "$p")"
    slug="$(slugify "${WORK_ROOT%/}/$name")"
    KNOWN_SLUGS[$slug]=1
    link_memory "$CLAUDE_HOME/projects/$slug" "$name"
  done
fi

# 2b. リポジトリ側にあってローカルにまだ無いプロジェクト(他マシンで作られたもの)
for r in "$SRC_DIR/projects"/*/; do
  [ -d "$r" ] || continue
  name="$(basename "$r")"
  # スラッグ名ディレクトリ(規約外プロジェクト、2c 由来)は正規名ではない。
  # 同一パスを持つマシン(= 同名の projects/<slug> が存在する)でのみリンクする。
  if [[ "$name" =~ ^(-|[A-Za-z]--) ]]; then
    if [ -d "$CLAUDE_HOME/projects/$name" ] && [ -z "${KNOWN_SLUGS[$name]:-}" ]; then
      KNOWN_SLUGS[$name]=1
      link_memory "$CLAUDE_HOME/projects/$name" "$name"
    fi
    continue
  fi
  slug="$(slugify "${WORK_ROOT%/}/$name")"
  [ -n "${KNOWN_SLUGS[$slug]:-}" ] && continue
  KNOWN_SLUGS[$slug]=1
  link_memory "$CLAUDE_HOME/projects/$slug" "$name"
done

# 2c. WORK_ROOT 規約外の既存プロジェクト: スラッグ名そのままで同期
#     (同一パスのマシン同士でのみ共有される。規約内への移行を推奨)
for d in "$CLAUDE_HOME/projects"/*/; do
  [ -d "$d" ] || continue
  slug="$(basename "$d")"
  [ -n "${KNOWN_SLUGS[$slug]:-}" ] && continue
  [ -L "$d/memory" ] && continue
  [ -d "$d/memory" ] || continue   # memory が実在するものだけ対象
  log "注意: $slug は WORK_ROOT 規約外です(スラッグ名のまま同期します)"
  link_memory "$d" "$slug"
done

log "完了。新しいプロジェクトを作ったら本スクリプトを再実行してください。"
