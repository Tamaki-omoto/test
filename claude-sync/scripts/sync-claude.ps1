# sync-claude.ps1 pull|push — pull-rebase 運用の薄い同期スクリプト (Windows)
#
#   pull : ローカル変更をスナップショットcommit → git pull --rebase
#   push : 同上 → pull --rebase → git push
#
# commit 前に簡易シークレットスキャンを行う(-Force でスキップ)。
# 例: powershell -File C:\work\<このリポジトリ>\claude-sync\scripts\sync-claude.ps1 push
param(
    [Parameter(Position = 0)][ValidateSet('pull', 'push')][string]$Command,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if (-not $Command) { Write-Host 'usage: sync-claude.ps1 pull|push [-Force]'; exit 2 }

$RepoDir    = Split-Path -Parent $PSScriptRoot
$ClaudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $env:USERPROFILE '.claude' }

$GitRoot = (git -C $RepoDir rev-parse --show-toplevel).Trim()
$Branch  = (git -C $GitRoot rev-parse --abbrev-ref HEAD).Trim()

$homeMd = Join-Path $ClaudeHome 'CLAUDE.md'
$repoMd = Join-Path $RepoDir 'claude\CLAUDE.md'

function Test-CopyMode {
    $item = Get-Item $homeMd -ErrorAction SilentlyContinue
    return ($item -and -not $item.LinkType)
}
function Test-SameContent($a, $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return $false }
    return (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash
}
# コピーモード対応(symlink 環境では no-op)
function Import-CopyMode { if ((Test-CopyMode) -and -not (Test-SameContent $homeMd $repoMd)) { Copy-Item $homeMd $repoMd -Force } }
function Export-CopyMode { if ((Test-CopyMode) -and -not (Test-SameContent $repoMd $homeMd)) { Copy-Item $repoMd $homeMd -Force } }

# 追加行のみを対象にした簡易シークレットスキャン
function Invoke-SecretScan {
    $pattern = '(sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
    $hits = git -C $GitRoot diff --cached -- $RepoDir |
        Where-Object { $_ -match '^\+' } |
        Where-Object { $_ -match $pattern }
    if ($hits) {
        Write-Error ("APIキー/秘密鍵らしき文字列がコミット対象に含まれています:`n" +
                     ($hits -join "`n") +
                     "`n該当箇所を取り除くか、誤検知なら -Force を付けて再実行してください。")
    }
}

function Invoke-SnapshotCommit {
    git -C $GitRoot add -A -- $RepoDir
    git -C $GitRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        if (-not $Force) { Invoke-SecretScan }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        git -C $GitRoot commit -q -m "sync($($env:COMPUTERNAME)): $stamp"
        Write-Host 'committed local snapshot'
    }
}

function Invoke-RebasePull {
    git -C $GitRoot pull --rebase origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Error "rebase コンフリクト。ファイルを解決して 'git rebase --continue' 後、sync-claude push を再実行してください。"
    }
}

Import-CopyMode
Invoke-SnapshotCommit
Invoke-RebasePull

if ($Command -eq 'push') {
    git -C $GitRoot push -u origin $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error 'push 失敗。ネットワーク/認証を確認してください。' }
}

Export-CopyMode
Write-Host "$Command 完了 ($Branch)"
