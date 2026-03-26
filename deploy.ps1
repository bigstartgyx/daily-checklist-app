# 一键部署到服务器（Windows PowerShell）
# 使用：.\deploy.ps1
# 需已配置 SSH 免密登录

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$configPath = Join-Path $scriptDir "deploy.config"
if (-not (Test-Path $configPath)) {
    Write-Host "错误：请先复制 deploy.config.example 为 deploy.config 并填写服务器信息"
    Write-Host "  Copy-Item deploy.config.example deploy.config"
    exit 1
}

$config = Get-Content $configPath | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') { [PSCustomObject]@{ Key = $matches[1].Trim(); Value = $matches[2].Trim() } }
} | Where-Object { $_ }
$vars = @{}
foreach ($line in $config) { $vars[$line.Key] = $line.Value }

$user = $vars["REMOTE_USER"]
$remoteHost = $vars["REMOTE_HOST"]
$path = $vars["REMOTE_PATH"]
$remote = "${user}@${remoteHost}"

Write-Host ">>> 部署到 $path"

# 排除项
$exclude = @("node_modules", ".git", "deploy.config", "*.log")
$excludeArgs = ($exclude | ForEach-Object { "--exclude=$_" }) -join " "

# scp 不支持排除，用 tar + ssh 或 robocopy
# 简单方案：先打包再 scp
$tempDir = Join-Path $env:TEMP "daily-checklist-deplop"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

# 复制项目文件（排除 node_modules、.git）
New-Item -ItemType Directory -Path (Join-Path $tempDir "server") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempDir "css") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $tempDir "js") -Force | Out-Null
Copy-Item (Join-Path $scriptDir "index.html") $tempDir -Force
Copy-Item (Join-Path $scriptDir "css\*") (Join-Path $tempDir "css") -Recurse -Force
Copy-Item (Join-Path $scriptDir "js\*") (Join-Path $tempDir "js") -Recurse -Force
Copy-Item (Join-Path $scriptDir "update.sh") $tempDir -Force
Get-ChildItem (Join-Path $scriptDir "server") -Exclude node_modules | Copy-Item -Destination (Join-Path $tempDir "server") -Recurse -Force

Write-Host ">>> 上传文件..."
scp -r "$tempDir\index.html" "$tempDir\css" "$tempDir\js" "$tempDir\server" "$tempDir\update.sh" "${remote}:${path}/"
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ">>> 安装依赖并重启服务..."
ssh $remote "cd $path/server && npm install --production && (./node_modules/.bin/pm2 restart daily-checklist-api 2>/dev/null || ./node_modules/.bin/pm2 start index.js --name daily-checklist-api)"

Write-Host ">>> 部署完成"
