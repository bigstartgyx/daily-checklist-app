#!/usr/bin/env bash

# 一键部署到服务器（macOS / Linux）
# 使用：./deploy-mac.sh
# 需已配置 SSH 免密登录

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

config_path="$script_dir/deploy.config"
local_env_path="$script_dir/deploy.local.env"
if [[ ! -f "$config_path" ]]; then
  echo "错误：请先创建 deploy.config 并填写服务器信息"
  echo "  可参考现有 deploy.config 或自己新增 REMOTE_USER / REMOTE_HOST / REMOTE_PATH"
  exit 1
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

REMOTE_USER=""
REMOTE_HOST=""
REMOTE_PATH=""

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" != *"="* ]] && continue

  key="$(trim "${line%%=*}")"
  value="$(trim "${line#*=}")"

  case "$key" in
    REMOTE_USER) REMOTE_USER="$value" ;;
    REMOTE_HOST) REMOTE_HOST="$value" ;;
    REMOTE_PATH) REMOTE_PATH="$value" ;;
  esac
done < "$config_path"

if [[ -f "$local_env_path" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"
    export "$key=$value"
  done < "$local_env_path"
fi

if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" || -z "$REMOTE_PATH" ]]; then
  echo "错误：deploy.config 必须包含 REMOTE_USER、REMOTE_HOST、REMOTE_PATH"
  exit 1
fi

remote="${REMOTE_USER}@${REMOTE_HOST}"

echo ">>> 部署到 $REMOTE_PATH"
echo ">>> 创建远端目录..."
ssh "$remote" "mkdir -p '$REMOTE_PATH'"

echo ">>> 上传文件..."
COPYFILE_DISABLE=1 tar -czf - \
  --exclude=".git" \
  --exclude="node_modules" \
  --exclude="deploy.config" \
  --exclude="*.log" \
  index.html \
  css \
  js \
  server \
  update.sh | ssh "$remote" "cd '$REMOTE_PATH' && tar -xzf -"

echo ">>> 安装依赖并重启服务..."
ssh "$remote" "cd '$REMOTE_PATH/server' && npm install --production && env AI_ACCESS_TOKENS='${AI_ACCESS_TOKENS}' DEEPSEEK_API_KEY='${DEEPSEEK_API_KEY}' DEEPSEEK_API_BASE='${DEEPSEEK_API_BASE:-https://api.deepseek.com}' DEEPSEEK_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}' ALIYUN_AK_ID='${ALIYUN_AK_ID}' ALIYUN_AK_SECRET='${ALIYUN_AK_SECRET}' ALIYUN_ASR_APPKEY='${ALIYUN_ASR_APPKEY}' ALIYUN_ASR_GATEWAY='${ALIYUN_ASR_GATEWAY:-https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr}' ALIYUN_ASR_TOKEN_ENDPOINT='${ALIYUN_ASR_TOKEN_ENDPOINT:-http://nls-meta.cn-shanghai.aliyuncs.com}' ALIYUN_ASR_SAMPLE_RATE='${ALIYUN_ASR_SAMPLE_RATE:-16000}' ./node_modules/.bin/pm2 restart daily-checklist-api --update-env 2>/dev/null || env AI_ACCESS_TOKENS='${AI_ACCESS_TOKENS}' DEEPSEEK_API_KEY='${DEEPSEEK_API_KEY}' DEEPSEEK_API_BASE='${DEEPSEEK_API_BASE:-https://api.deepseek.com}' DEEPSEEK_MODEL='${DEEPSEEK_MODEL:-deepseek-chat}' ALIYUN_AK_ID='${ALIYUN_AK_ID}' ALIYUN_AK_SECRET='${ALIYUN_AK_SECRET}' ALIYUN_ASR_APPKEY='${ALIYUN_ASR_APPKEY}' ALIYUN_ASR_GATEWAY='${ALIYUN_ASR_GATEWAY:-https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr}' ALIYUN_ASR_TOKEN_ENDPOINT='${ALIYUN_ASR_TOKEN_ENDPOINT:-http://nls-meta.cn-shanghai.aliyuncs.com}' ALIYUN_ASR_SAMPLE_RATE='${ALIYUN_ASR_SAMPLE_RATE:-16000}' ./node_modules/.bin/pm2 start index.js --name daily-checklist-api"

echo ">>> 部署完成"
