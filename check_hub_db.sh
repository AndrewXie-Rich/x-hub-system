#!/usr/bin/env zsh
# Mac OS 专属 - 检查hub.sqlite3数据库审计事件
# 禁用zsh历史替换，避免解析错误
set +o histexpand
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
export TERM=xterm-256color

# 定义数据库路径列表（和你的路径完全一致）
DB_PATHS=(
  "/Users/andrew.xie/Documents/AX/x-hub-system/data/hub.sqlite3"
  "/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3"
  "/Users/andrew.xie/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_grpc/hub.sqlite3"
)

# 切换到项目根目录（可选，确保路径上下文一致）
cd /Users/andrew.xie/Documents/AX/x-hub-system || {
  echo "❌ 项目目录不存在，退出执行"
  exit 1
}

echo "🔍 开始检查SQLite数据库审计事件..."
echo "========================================"

# 遍历数据库路径
for db in "${DB_PATHS[@]}"; do
  # 跳过不存在的文件
  if [[ ! -f "$db" ]]; then
    echo "⏭️  文件不存在，跳过：$db"
    continue
  fi

  # 执行Python检查脚本（关键：<<\PY隔离，避免zsh解析）
  python3 - "$db" <<\PY
import sqlite3
import sys
import traceback

def check_audit_events(db_path):
    """检查数据库中的audit_events表"""
    try:
        # 连接数据库
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        
        # 查询总事件数
        total = cur.execute("SELECT COUNT(*) FROM audit_events").fetchone()[0]
        
        # 查询supervisor.incident相关事件数（%%转义%，避免shell解析）
        sup = cur.execute(
            "SELECT COUNT(*) FROM audit_events WHERE event_type LIKE 'supervisor.incident.%%'"
        ).fetchone()[0]
        
        # 输出结果
        print(f"✅ {db_path} | total={total} | supervisor_incident={sup}")
        
    except Exception as e:
        # 错误处理
        print(f"❌ {db_path} | 执行失败：{str(e)}")
        traceback.print_exc()
    finally:
        # 确保数据库连接关闭
        if 'con' in locals():
            con.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("❌ 缺少数据库路径参数")
        sys.exit(1)
    check_audit_events(sys.argv[1])
PY
done

echo "========================================"
echo "✅ 数据库检查完成"

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY
