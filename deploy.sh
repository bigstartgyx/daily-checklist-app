#!/bin/bash
# 一键部署到服务器：rsync 同步代码 + 自动 npm install + pm2 重启
# 使用：./deploy.sh  或  bash deploy.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="$SCRIPT_DIR/deploy.config"
if [ ! -f "$CONFIG" ]; then
  echo "错误：请先复制 deploy.config.example 为 deploy.config 并填写服务器信息"
  echo "  cp deploy.config.example deploy.config"
  exit 1
fi

source "$CONFIG"
REMOTE="${REMOTE_USER}@${REMOTE_HOST}"

echo ">>> 部署到 $REMOTE_PATH"
echo ">>> 同步文件..."
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'deploy.config' \
  --exclude '*.log' \
  ./ "$REMOTE:$REMOTE_PATH/"

echo ">>> 安装依赖并重启服务..."
ssh "$REMOTE" "cd $REMOTE_PATH/server && npm install --production && (./node_modules/.bin/pm2 restart daily-checklist-api 2>/dev/null || ./node_modules/.bin/pm2 start index.js --name daily-checklist-api)"

echo ">>> 部署完成"
