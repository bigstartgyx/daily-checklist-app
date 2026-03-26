#!/bin/bash
# 一键部署到服务器：rsync 同步代码 + 自动 npm install + pm2 重启
# 使用：./deploy.sh  或  bash deploy.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="$SCRIPT_DIR/deploy.config"
LOCAL_ENV="$SCRIPT_DIR/deploy.local.env"
if [ ! -f "$CONFIG" ]; then
  echo "错误：请先复制 deploy.config.example 为 deploy.config 并填写服务器信息"
  echo "  cp deploy.config.example deploy.config"
  exit 1
fi

source "$CONFIG"
if [ -f "$LOCAL_ENV" ]; then
  source "$LOCAL_ENV"
fi
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
ssh "$REMOTE" "cd $REMOTE_PATH/server && npm install --production && env AI_ACCESS_TOKENS='${AI_ACCESS_TOKENS}' DEEPSEEK_API_KEY='${DEEPSEEK_API_KEY}' DEEPSEEK_API_BASE='${DEEPSEEK_API_BASE:-https://api.deepseek.com}' DEEPSEEK_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}' ALIYUN_AK_ID='${ALIYUN_AK_ID}' ALIYUN_AK_SECRET='${ALIYUN_AK_SECRET}' ALIYUN_ASR_APPKEY='${ALIYUN_ASR_APPKEY}' ALIYUN_ASR_GATEWAY='${ALIYUN_ASR_GATEWAY:-https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr}' ALIYUN_ASR_TOKEN_ENDPOINT='${ALIYUN_ASR_TOKEN_ENDPOINT:-http://nls-meta.cn-shanghai.aliyuncs.com}' ALIYUN_ASR_SAMPLE_RATE='${ALIYUN_ASR_SAMPLE_RATE:-16000}' ./node_modules/.bin/pm2 restart daily-checklist-api --update-env 2>/dev/null || env AI_ACCESS_TOKENS='${AI_ACCESS_TOKENS}' DEEPSEEK_API_KEY='${DEEPSEEK_API_KEY}' DEEPSEEK_API_BASE='${DEEPSEEK_API_BASE:-https://api.deepseek.com}' DEEPSEEK_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}' ALIYUN_AK_ID='${ALIYUN_AK_ID}' ALIYUN_AK_SECRET='${ALIYUN_AK_SECRET}' ALIYUN_ASR_APPKEY='${ALIYUN_ASR_APPKEY}' ALIYUN_ASR_GATEWAY='${ALIYUN_ASR_GATEWAY:-https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr}' ALIYUN_ASR_TOKEN_ENDPOINT='${ALIYUN_ASR_TOKEN_ENDPOINT:-http://nls-meta.cn-shanghai.aliyuncs.com}' ALIYUN_ASR_SAMPLE_RATE='${ALIYUN_ASR_SAMPLE_RATE:-16000}' ./node_modules/.bin/pm2 start index.js --name daily-checklist-api"

echo ">>> 部署完成"
