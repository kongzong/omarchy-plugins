#!/usr/bin/env bash
# 合成卡西欧电子表风格提示音。可调参数(环境变量):
#   WAVE=sine|square  波形(sine=柔和的"滴",square=硬朗的"哔")
#   FREQ=Hz           频率     DUR=秒  时长     VOL=0-1  音量
# 用法:./make-chime.sh [输出路径]
set -euo pipefail

WAVE="${WAVE:-square}"
FREQ="${FREQ:-2000}"
DUR="${DUR:-0.08}"
VOL="${VOL:-0.3}"
OUT="${1:-$(cd "$(dirname "$0")/.." && pwd)/hourly-chime/chime.wav}"

mkdir -p "$(dirname "$OUT")"

# 波形:sine=正弦"滴";square=方波"哔"(ffmpeg eval 无 sign(),用 gte(sin,0)*2-1)
if [ "$WAVE" = "square" ]; then
  OSC="(gte(sin(2*PI*${FREQ}*t)\,0)*2-1)"
else
  OSC="sin(2*PI*${FREQ}*t)"
fi

# 5ms 线性起音 + 30ms 线性收尾,消除截断的咔嗒声
ffmpeg -y -hide_banner -loglevel error -f lavfi -i \
  "aevalsrc=${VOL}*${OSC}*min(1\,t/0.005)*min(1\,(${DUR}-t)/0.03):s=44100:d=${DUR}" \
  -c:a pcm_s16le "$OUT"

echo "chime written: $OUT (${WAVE} ${FREQ}Hz ${DUR}s)"
