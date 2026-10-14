# Run only after authenticating the official GitHub CLI: gh auth login
# The script does not accept or print tokens. It refuses a conflicting existing repo.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspacePath
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Install GitHub CLI from https://cli.github.com/ then run gh auth login.' }
gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Run gh auth login first. Never paste a token into chat or source files.' }
$gitHubLogin = (gh api user --jq .login).Trim()
if ($LASTEXITCODE -ne 0) { throw 'GitHub account lookup failed.' }
$repoName = "$gitHubLogin/campus-lens"
gh api "repos/$repoName" --silent 2>$null
if ($LASTEXITCODE -eq 0) { throw "Repository $repoName already exists; inspect it before pushing." }
git status --short
git add .gitignore App AppTests CampusLens.xcodeproj Sources Tests UITests scripts .github docs Package.swift README.md LICENSE
if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
git -c user.name='CampusLens Contributor' -c user.email="$gitHubLogin@users.noreply.github.com" commit -m 'Implement CampusLens RAW capture, offline solver, calibration and cloud builds'
if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
git branch -M main
gh repo create $repoName --public --source . --remote origin --push --description '校园新闻摄影助手：App 内 Bayer RAW 与两台相机离线起始参数'
if ($LASTEXITCODE -ne 0) { throw 'Repository creation or push failed; inspect before retry.' }
Write-Output "Repository: https://github.com/$repoName"
Write-Output 'Follow both iOS workflows in Actions. No IPA exists until the main archive job passes.'
