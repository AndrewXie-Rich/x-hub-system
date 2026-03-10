#!/usr/bin/env zsh
# Mac OS 专属 - Supervisor Incident DB探针脚本
# 禁用zsh历史替换，避免解析错误
set +o histexpand
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
export TERM=xterm-256color

# ====================== 核心配置 ======================
# 项目根目录
PROJECT_ROOT="/Users/andrew.xie/Documents/AX/x-hub-system"
# RELFlowHub基础路径
BASE="/Users/andrew.xie/Library/Containers/com.rel.flowhub/Data/RELFlowHub"
IPC_DIR="${BASE}/ipc_events"
DB_PATH="${BASE}/hub_grpc/hub.sqlite3"

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

# 创建IPC目录（确保存在）
mkdir -p "${IPC_DIR}"
echo "✅ 前置检查完成，开始执行DB探针..."
echo "========================================"

# ====================== 生成探针参数 ======================
# 生成唯一REQ_ID（小写）
REQ_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
AUDIT_REF="audit-db-probe-${REQ_ID}"

# 生成当前时间戳（毫秒）
NOW_MS="$(python3 - <<\PY
import time
print(int(time.time() * 1000))
PY
)"

# 定义探针文件路径
PROBE_FILE="${IPC_DIR}/xterminal_incident_audit_${NOW_MS}_${REQ_ID}.json"
echo "🔧 生成探针文件：${PROBE_FILE}"

# ====================== 生成JSON探针文件 ======================
cat > "${PROBE_FILE}" <<\EOF
{
  "type": "supervisor_incident_audit",
  "req_id": "$REQ_ID",
  "supervisor_incident": {
    "incident_id": "incident-db-probe-$REQ_ID",
    "lane_id": "lane-probe",
    "task_id": "task-db-probe",
    "project_id": "",
    "incident_code": "db_probe",
    "event_type": "supervisor.incident.db_probe.handled",
    "deny_code": "db_probe",
    "proposed_action": "pause_lane",
    "severity": "high",
    "category": "runtime",
    "detected_at_ms": $NOW_MS,
    "handled_at_ms": $NOW_MS,
    "takeover_latency_ms": 0,
    "audit_ref": "$AUDIT_REF",
    "detail": "manual_db_probe",
    "status": "handled",
    "source": "db_probe_script"
  }
}
EOF

# 替换文件中的变量（解决heredoc中变量不解析的问题）
sed -i '' "s/\$REQ_ID/${REQ_ID}/g" "${PROBE_FILE}"
sed -i '' "s/\$NOW_MS/${NOW_MS}/g" "${PROBE_FILE}"
sed -i '' "s/\$AUDIT_REF/${AUDIT_REF}/g" "${PROBE_FILE}"

echo "✅ 探针文件生成完成：${PROBE_FILE}"
echo "⏳ 等待1.5秒，让Hub消费IPC文件..."
sleep 1.5

# ====================== 检查数据库是否写入数据 ======================
echo "🔍 检查数据库中探针数据是否写入..."
python3 - "${DB_PATH}" "${AUDIT_REF}" <<\PY
import sqlite3
import sys
import json

def check_probe_data(db_path, audit_ref):
    """检查数据库中是否存在探针数据"""
    try:
        # 连接数据库
        con = sqlite3.connect(db_path)
        cur = con.cursor()
        
        # 查询探针相关数据
        cur.execute("""
            SELECT COUNT(*), MAX(created_at_ms)
            FROM audit_events
            WHERE event_type='supervisor.incident.db_probe.handled'
              AND ext_json LIKE ?
        """, (f'%\"audit_ref\":\"{audit_ref}\"%',))
        
        cnt, ts = cur.fetchone()
        result = {
            "probe_rows": int(cnt or 0),
            "latest_created_at_ms": ts
        }
        
        # 输出结果
        print(json.dumps(result, indent=2))
        
        # 检查行数是否大于0
        if int(cnt or 0) <= 0:
            print("❌ 数据库中未找到探针数据")
            sys.exit(2)
            
    except Exception as e:
        print(f"❌ 数据库查询失败：{str(e)}")
        sys.exit(1)
    finally:
        if 'con' in locals():
            con.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("❌ 缺少参数：db_path audit_ref")
        sys.exit(1)
    check_probe_data(sys.argv[1], sys.argv[2])
PY

# 检查Python脚本执行结果
if [[ $? -ne 0 ]]; then
  echo "❌ DB探针检查失败"
  exit 1
fi

# ====================== 检查IPC文件是否被消费 ======================
echo "========================================"
if [[ -f "${PROBE_FILE}" ]]; then
  echo "⚠️ 探针文件仍存在（Hub可能未消费ipc_events）：${PROBE_FILE}"
else
  echo "✅ 探针文件已被Hub消费"
fi

# ====================== 收尾 ======================
echo "========================================"
echo "🎉 DB探针执行成功！"

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY
