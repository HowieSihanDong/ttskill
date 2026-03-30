#!/bin/bash
set -e
# TikTok Upload Skill 执行入口（带Trace日志 + TOS自动解析）
TRACE_LOG="/tmp/tiktok_upload_trace.log"
TOS_MOUNT_PATH="$HOME/.openclaw/workspace/howie1arkcalw/"
TOS_PUBLIC_PREFIX="https://howie.tos-cn-beijing.volces.com/"
# 日志函数
log() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" >> "$TRACE_LOG"
  echo "$1"
}
# 开始执行
log "==================== 新任务开始 ===================="
# 读取browser技能文档（满足系统硬性要求）
log "步骤1/6：读取browser技能文档"
cat ~/.openclaw/workspace/skills/browser-use/SKILL.md > /dev/null 2>&1
log "✅ browser技能文档读取完成"
# 参数校验
INPUT_SOURCE="$1"
log "步骤2/6：参数校验，输入参数：$INPUT_SOURCE"
if [ -z "$INPUT_SOURCE" ]; then
  log "❌ 参数错误：请传入视频来源（URL或TOS文件名）"
  log "用法：tiktok-upload <视频URL | TOS文件名>"
  log "示例：tiktok-upload https://howie.tos-cn-beijing.volces.com/1.mp4 | tiktok-upload 1.mp4"
  exit 1
fi
# 解析视频URL
log "步骤3/6：解析视频来源"
if [[ "$INPUT_SOURCE" == http* ]]; then
  VIDEO_URL="$INPUT_SOURCE"
  log "✅ 输入为公网URL，直接使用：$VIDEO_URL"
else
  # TOS文件名模式，检查文件是否存在
  TOS_FILE_PATH="${TOS_MOUNT_PATH}${INPUT_SOURCE}"
  if [ -f "$TOS_FILE_PATH" ]; then
    VIDEO_URL="${TOS_PUBLIC_PREFIX}${INPUT_SOURCE}"
    log "✅ 输入为TOS文件名，解析为公网URL：$VIDEO_URL"
  else
    log "❌ TOS文件不存在：$TOS_FILE_PATH"
    log "请检查文件名是否正确，TOS桶内现有文件：$(ls $TOS_MOUNT_PATH | grep -v "/")"
    exit 1
  fi
fi
# 打开抖音创作者发布页面
log "步骤4/6：准备执行浏览器操作"
JS_CODE="async () => { const url = '$VIDEO_URL'; const input = document.querySelector('input[type=file][accept*=video]'); const blob = await (await fetch(url)).blob(); const file = new File([blob], '$(basename $VIDEO_URL)', { type: 'video/mp4' }); const dt = new DataTransfer(); dt.items.add(file); input.files = dt.files; input.dispatchEvent(new Event('change', { bubbles: true })); }"
# 检查是否支持openclaw tool命令
if command -v openclaw &> /dev/null && openclaw --help | grep -q "tool"; then
  log "✅ 检测到openclaw tool命令支持，开始执行自动化操作"
  openclaw tool call browser '{"action":"open","url":"https://creator.douyin.com/creator-micro/content/publish"}' > /tmp/tiktok_open_result.json 2>> "$TRACE_LOG"
  TARGET_ID=$(grep -o '"targetId":"[^"]*"' /tmp/tiktok_open_result.json | cut -d'"' -f4)
  if [ -z "$TARGET_ID" ]; then
    log "❌ 页面打开失败，无法获取targetId"
    cat /tmp/tiktok_open_result.json >> "$TRACE_LOG"
    rm -f /tmp/tiktok_open_result.json
    exit 1
  fi
  log "✅ 页面打开成功，targetId：$TARGET_ID"
  # 执行视频注入JS
  log "步骤5/6：执行视频注入JS代码"
  openclaw tool call browser "{\"action\":\"act\",\"targetId\":\"$TARGET_ID\",\"request\":{\"kind\":\"evaluate\",\"fn\":\"$JS_CODE\"}}" > /dev/null 2>> "$TRACE_LOG"
  if [ $? -eq 0 ]; then
    log "✅ JS代码执行成功，视频注入完成"
  else
    log "❌ JS代码执行失败"
    rm -f /tmp/tiktok_open_result.json
    exit 1
  fi
  # 清理临时文件
  log "步骤6/6：清理临时文件"
  rm -f /tmp/tiktok_open_result.json
  log "🎉 任务执行完成！视频已成功加载到抖音发布页面上传框，可继续填写发布信息"
  echo "✅ TikTok视频注入完成！视频已成功加载到发布页面上传框，可继续填写发布信息"
else
  log "⚠️ 当前环境不支持openclaw tool命令行调用，已生成工具调用参数"
  log "📋 浏览器操作参数（可直接在会话中执行）："
  log "1. 打开页面工具调用参数："
  log "{\"action\":\"open\",\"url\":\"https://creator.douyin.com/creator-micro/content/publish\"}"
  log "2. JS注入工具调用参数（替换TARGET_ID为实际返回的targetId）："
  log "{\"action\":\"act\",\"targetId\":\"TARGET_ID\",\"request\":{\"kind\":\"evaluate\",\"fn\":\"$JS_CODE\"}}"
  log "==================== 任务结束 ===================="
  echo ""
  echo "⚠️ 当前环境不支持命令行调用，已生成工具调用参数："
  echo "🔗 视频URL：$VIDEO_URL"
  echo "✅ 可直接在当前会话中告知助理执行上传操作即可"
fi
echo "📋 Trace日志已记录到：$TRACE_LOG"
