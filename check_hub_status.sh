#!/usr/bin/env zsh
# Mac OS 专属 - 检查RELFlowHub状态脚本
# 禁用zsh历史替换，避免解析错误
set +o histexpand
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
export TERM=xterm-256color

# ====================== 核心配置 ======================
# Hub状态文件路径
HUB_STATUS_FILE="$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_status.json"

# ====================== 前置检查 ======================
# 检查状态文件是否存在
if [[ ! -f "${HUB_STATUS_FILE}" ]]; then
  echo "❌ Hub状态文件不存在：${HUB_STATUS_FILE}"
  echo "⚠️ 可能Hub未运行或状态文件未生成"
  exit 1
fi

echo "🔍 开始检查Hub状态..."
echo "========================================"

# ====================== 执行Python状态检查 ======================
python3 - <<\PY
import json
import os
import time
import traceback

def check_hub_status():
    """检查Hub状态并输出格式化结果"""
    # 定义状态文件路径
    status_file = os.path.expanduser("~/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_status.json")
    
    try:
        # 读取并解析状态文件
        with open(status_file, 'r', encoding='utf8') as f:
            st = json.load(f)
        
        # 计算Hub运行时长（秒）
        updated_at = float(st.get("updatedAt", 0) or 0)
        age_sec = round(time.time() - updated_at, 3)
        
        # 组装状态数据
        status_data = {
            "pid": st.get("pid"),
            "age_sec": age_sec,
            "ipcPath": st.get("ipcPath"),
            "updatedAt": updated_at,
            "status_file": status_file
        }
        
        # 格式化输出（JSON格式，易读）
        print(json.dumps(status_data, indent=2, ensure_ascii=False))
        
        # 额外的健康检查提示
        if age_sec > 30:
            print("\n⚠️ 警告：Hub状态超过30秒未更新，可能已挂死")
        elif st.get("pid") is None:
            print("\n⚠️ 警告：Hub PID未配置，可能未正常运行")
        else:
            print("\n✅ Hub状态正常")
            
    except json.JSONDecodeError:
        print(f"❌ 状态文件JSON格式错误：{status_file}")
        traceback.print_exc()
        return 1
    except Exception as e:
        print(f"❌ 检查Hub状态失败：{str(e)}")
        traceback.print_exc()
        return 1
    
    return 0

if __name__ == "__main__":
    exit_code = check_hub_status()
    exit(exit_code)
PY

# ====================== 检查执行结果 ======================
if [[ $? -ne 0 ]]; then
  echo "========================================"
  echo "❌ Hub状态检查失败"
  exit 1
fi

echo "========================================"
echo "🎉 Hub状态检查完成！"

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY
