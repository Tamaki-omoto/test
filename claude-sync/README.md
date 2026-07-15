# claude-sync — Claude メモリのマシン間同期 (Phase 1)

`~/.claude/CLAUDE.md`(ユーザーグローバルメモリ)と auto memory フォルダを
git 経由で複数マシン(Windows GPU ファーム + Linux/Raspberry Pi)間で同期する。

- 同期方式: **リポジトリが実体、`~/.claude` 側はリンク**(Windows はジャンクション、Linux は symlink。管理者権限不要)
- 競合対策: **pull-rebase 運用**の薄い sync スクリプト(`sync-claude pull` / `push`)
- secrets: **deny-by-default の .gitignore**(許可したものしか同期されない)
- フック等による自動同期は Phase 2

> このディレクトリは自己完結しており、専用のプライベート dotfiles リポジトリへ
> `git subtree split -P claude-sync` などでそのまま切り出せる。

---

## 1. 棚卸し: ~/.claude の同期対象 / 除外

各マシンで `ls -la ~/.claude`(Windows: `dir %USERPROFILE%\.claude`)を実行して突き合わせること。

| パス | 同期 | 理由 |
|---|---|---|
| `CLAUDE.md` | ✅ 同期 | ユーザーグローバルメモリ。同期の主目的 |
| `projects/<slug>/memory/` | ✅ 同期 | auto memory(`MEMORY.md` + トピックファイル)。プロジェクト単位の学習内容 |
| `projects/<slug>/*.jsonl` | ❌ 除外 | セッション履歴。巨大・機密混入リスク・マシン固有 |
| `settings.json` / `settings.local.json` | ❌ 除外 | `env` に API キーが入りうる。マシン固有設定(GPU 環境差など)も混ざる |
| `.credentials.json` | ❌ **絶対除外** | OAuth トークン。漏れたらアカウント乗っ取りと同義 |
| `todos/` `shell-snapshots/` `statsig/` `cache` 系 | ❌ 除外 | 一時ファイル・キャッシュ |
| `plugins/` | ❌ 除外 | インストール実体。各マシンで入れ直す方が安全 |
| `skills/` `commands/` `agents/` | ⏸ Phase 2 候補 | 自作スキル/コマンドは同期価値が高い。`.gitignore` の許可リストに追加すれば対応可能 |
| `keybindings.json` | ⏸ Phase 2 候補 | 好みの共有。secrets リスクなし |

`.gitignore` は「`claude/` 以下は全部無視 → 許可リストで開ける」構造なので、
**Claude Code のアップデートで新しいファイルが増えても勝手に同期されることはない**。
さらに `settings.json` / `.credentials.json` / `*.key` 等は二重ガードで明示拒否している。

---

## 2. リポジトリ構成

```
claude-sync/
├── README.md
├── .gitignore          # deny-by-default 設計(§1 参照)
├── .gitattributes      # Win/Linux 混在での改行コード事故防止
├── claude/
│   ├── CLAUDE.md       # 実体。~/.claude/CLAUDE.md はここへのリンク
│   └── projects/
│       └── <正規プロジェクト名>/
│           └── memory/ # 実体。~/.claude/projects/<slug>/memory はここへのリンク
└── scripts/
    ├── setup.sh        # Linux/macOS: symlink セットアップ(再実行可)
    ├── setup.ps1       # Windows: junction/mklink セットアップ(再実行可・管理者権限不要)
    ├── sync-claude.sh  # pull|push (Linux/macOS)
    └── sync-claude.ps1 # pull|push (Windows)
```

### スラッグと正規名の分離(重要)

Claude Code はプロジェクトを **cwd の絶対パスの英数字以外を `-` に置換したスラッグ**で
インデックスする(例: `/home/pi/work/foo` → `-home-pi-work-foo`、`C:\work\foo` → `C--work-foo`)。
スラッグは OS・ユーザー名によって変わるため、そのままではマシン間で共有できない。

そこでリポジトリ側は **プロジェクトフォルダ名(正規名)** で持ち、
セットアップスクリプトが各マシンの `WORK_ROOT` からスラッグを計算してリンクを張る:

```
Windows:  %USERPROFILE%\.claude\projects\C--work-foo\memory      ─┐
                                                                   ├→ repo/claude/projects/foo/memory
Linux:    ~/.claude/projects/-home-pi-work-foo/memory            ─┘
```

これにより **OS・ユーザー名が違っても同じプロジェクトのメモリを共有できる**。

---

## 3. 作業ディレクトリのパス規約(全マシン共通ルール)

| 環境 | 規約 | 例 |
|---|---|---|
| Windows(GPU ファーム全台) | `C:\work\<project>` | `C:\work\robomaster` |
| Linux / Raspberry Pi | `~/work/<project>` | `/home/pi/work/robomaster` |

ルール:

1. **Claude Code のセッションは必ず規約パス直下のプロジェクトフォルダで開始する**(`cd C:\work\foo` してから `claude`)。
2. **プロジェクトフォルダ名を全マシンで一致させる**(大文字小文字も含めて)。これが共有キーになる。
3. 規約外パスで始めたセッションのメモリはスラッグ名のまま同期され、同一パスのマシン同士でしか共有されない(setup スクリプトが警告を出す)。
4. ドライブ/ルートを変えたいマシンは環境変数 `WORK_ROOT` で上書きできる(例: `WORK_ROOT=D:\work`)。ただしスラッグはパス依存なので、**そのマシン上で今後も同じ WORK_ROOT を使い続けること**。

> 注意: memory の内容自体にマシン固有の絶対パスが書かれることがある。パス規約を
> 揃えておくことで Windows 同士・Linux 同士では記述が一致し、実害を最小化できる。

---

## 4. セットアップ(マシンごとに 1 回)

### 事前

- git がインストール済みで、このリポジトリ(プライベート)に SSH/HTTPS でアクセスできること
- Tailscale 内のプライベート git サーバでも GitHub でも手順は同じ

### Linux / Raspberry Pi

```sh
mkdir -p ~/work && cd ~/work
git clone <このリポジトリのURL> <repo>
cd <repo>
bash claude-sync/scripts/setup.sh
```

### Windows

```powershell
mkdir C:\work; cd C:\work
git clone <このリポジトリのURL> <repo>
cd <repo>
powershell -ExecutionPolicy Bypass -File claude-sync\scripts\setup.ps1
```

セットアップスクリプトの挙動:

- 既存の `~/.claude/CLAUDE.md` の内容は初回にリポジトリへ**取り込まれる**(リポジトリ側に既に実内容がある場合はローカルを `.bak-<日時>` に退避して警告)
- 既存の auto memory は**上書きなしで**リポジトリへ取り込み、元フォルダを `.bak-<日時>` に退避してからリンクを張る
- **新しいプロジェクトを作ったら再実行する**(未リンクのものだけ処理される)
- Windows でファイル symlink が作れない場合(開発者モード無効)は CLAUDE.md のみ**コピーモード**になり、sync スクリプトがコピーで整合させる

---

## 5. 日常運用: sync-claude

```sh
# 作業開始前(他マシンの変更を取り込む)
claude-sync/scripts/sync-claude.sh pull

# 作業後(自分の変更を配る)
claude-sync/scripts/sync-claude.sh push
```

Windows は `sync-claude.ps1 pull` / `push`。alias / PATH 登録を推奨。

挙動:

1. ローカル変更を `sync(<hostname>): <UTC時刻>` としてスナップショット commit
   - commit 前に**簡易シークレットスキャン**(sk-ant- / AKIA / ghp_ / xoxb- / PRIVATE KEY 等)。検出時は中断(誤検知なら `FORCE=1` / `-Force`)
2. `git pull --rebase`(コンフリクト時は指示を出して停止 → 解決後 `git rebase --continue` → 再度 push)
3. push の場合はそのまま `git push`

メモリは Markdown の追記が中心なので rebase コンフリクトは稀。起きた場合も
memory ファイルは「両方残す」方向で解決すれば安全。

---

## 6. Phase 2 以降の候補

- `skills/` `commands/` `agents/` `keybindings.json` の同期(`.gitignore` の許可リスト追加 + setup にリンク 1 行追加)
- SessionStart / Stop フックによる pull/push 自動化
- systemd timer / タスクスケジューラでの定期 `sync-claude push`
- 専用プライベート dotfiles リポジトリへの切り出し(`git subtree split -P claude-sync`)
