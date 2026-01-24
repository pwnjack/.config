#!/bin/bash
gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | tr -d ' ')
gpu_mem_used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
gpu_mem_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)

printf '{"text": "󱤓 %s%%  ", "tooltip": "GPU %s%% [%s°C]\\n\\n%s\\nVRAM: %sMB / %sMB"}' "$gpu_usage" "$gpu_usage" "$gpu_temp" "$gpu_name" "$gpu_mem_used" "$gpu_mem_total"
