#!/usr/bin/env zsh
# Mac OS 专属 - 检查Supervisor Incident数据库事件脚本
# 禁用zsh历史替换，避免解析错误
set +o histexpand
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
export TERM=xterm-256color

# ====================== 核心配置 ======================
# 项目根目录
PROJECT_ROOT="/Users/andrew.xie/Documents/AX/x-hub-system"
# 数据库路径
DB_PATH="/Users/andrew.xie/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_grpc/hub.sqlite3"
# 时间窗口（秒）- 最近10分钟
TIME_WINDOW=600

# ====================== 前置检查 ======================
# 切换到项目根目录
cd "${PROJECT_ROOT}" || {
  echo "❌ 项目目录不存在：${PROJECT_ROOT}"
  exit 1
}

# 检查数据库文件是否存在
if [[ ! -f "${DB_PATH}" ]]; then
  echo "❌ 数据库文件不存在：${DB_PATH}"
  exit 1
fi

echo "🔍 开始检查Supervisor Incident数据库事件..."
echo "========================================"
echo "📅 时间窗口：最近 ${TIME_WINDOW} 秒（$((${TIME_WINDOW}/60)) 分钟）"
echo "🗄️  数据库路径：${DB_PATH}"
echo "========================================"

# ====================== 执行Python数据库检查 ======================
python3 - "${DB_PATH}" "${TIME_WINDOW}" <<\PY
import sqlite3
import sys
import time
import json
import traceback

def check_supervisor_incidents(db_path, time_window):
    """检查数据库中的supervisor incident事件"""
    # 定义需要检查的incident code
    target_codes = ["grant_pending", "awaiting_instruction", "runtime_error"]
    # 计算时间戳（毫秒）
    from_ms = int((time.time() - int(time_window)) * 1000)
    
    try:
        # 连接数据库
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        
        # 输出时间窗口信息
        print("⏰ 时间范围：from_ms =", from_ms, f"(≈ {time.ctime(from_ms/1000)})")
        print("========================================")
        
        # 统计各类型事件数量（最近10分钟）
        print("📊 最近10分钟事件统计：")
        stats = {}
        for code in target_codes:
            event_type = f"supervisor.incident.{code}.handled"
            # 查询事件数量
            count = cur.execute(
                "SELECT COUNT(*) FROM audit_events WHERE event_type=? AND created_at_ms>=?",
                (event_type, from_ms)
            ).fetchone()[0]
            count_int = int(count)
            stats[code] = count_int
            # 格式化输出（带颜色提示）
            if count_int == 0:
                print(f"  ⚠️ {code}: {count_int}")
            else:
                print(f"  ✅ {code}: {count_int}")
        
        # 输出最新8条事件
        print("========================================")
        print("📜 最新8条Supervisor Incident事件：")
        latest_events = cur.execute("""
            SELECT event_type, created_at_ms, error_code 
            FROM audit_events 
            WHERE event_type LIKE 'supervisor.incident.%%' 
            ORDER BY created_at_ms DESC 
            LIMIT 8
        """).fetchall()
        
        if not latest_events:
            print("  ❌ 未找到任何supervisor.incident事件")
        else:
            for idx, row in enumerate(latest_events, 1):
                event_type, created_at_ms, error_code = row
                # 格式化时间戳
                event_time = time.ctime(created_at_ms/1000) if created_at_ms else "未知时间"
                error_code = error_code or "无"
                print(f"  {idx}. 事件类型：{event_type} | 时间：{event_time} | 错误码：{error_code}")
                
    except Exception as e:
        print(f"❌ 数据库查询失败：{str(e)}")
        traceback.print_exc()
        return 1
    finally:
        # 确保数据库连接关闭
        if 'con' in locals():
            con.close()
    
    return 0

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("❌ 缺少参数：db_path time_window")
        sys.exit(1)
    exit_code = check_supervisor_incidents(sys.argv[1], sys.argv[2])
    sys.exit(exit_code)
PY

# ====================== 检查执行结果 ======================
if [[ $? -ne 0 ]]; then
  echo "========================================"
  echo "❌ Supervisor Incident数据库检查失败"
  exit 1
fi

echo "========================================"
echo "🎉 Supervisor Incident数据库检查完成！"

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY
