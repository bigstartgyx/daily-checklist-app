#!/bin/bash
# 服务器端更新脚本：拉取最新代码并重启服务
# 放置于项目根目录，执行：./update.sh 或 bash update.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ">>> 拉取最新代码..."
git pull

echo ">>> 安装依赖..."
cd server && npm install --production

echo ">>> 重启 PM2..."
./node_modules/.bin/pm2 restart daily-checklist-api 2>/dev/null || ./node_modules/.bin/pm2 start index.js --name daily-checklist-api

echo ">>> 更新完成"
