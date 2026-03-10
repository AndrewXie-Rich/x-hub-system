# X-Hub Constitution 审计日志 Schema 定义 v2.0

**M0 术语收敛说明（2026-02-26）**：本文件中的 `L1/L2/L3/L4` 表示**审计日志级别**，不表示 Memory 物理层。  
Memory 物理层统一使用 `L0/L1/L2/L3`，逻辑层统一为 `Raw Vault / Observations / Longterm / Canonical / Working Set`。

**版本**: 2.0
**日期**: 2026-02-25
**状态**: Schema Specification
**目标**: 为 X 宪章执行提供完整、可追溯、可分析的审计日志体系

---

## 1. 设计原则

### 1.1 核心原则

1. **完整性**: 记录所有宪章相关的决策和事件
2. **不可篡改**: 使用 append-only 日志，防止事后修改
3. **可追溯**: 每个决策都可追溯到原始请求和证据
4. **可分析**: 结构化数据，支持查询、统计、可视化
5. **隐私保护**: 敏感信息脱敏或加密存储
6. **性能优先**: 异步写入，不阻塞主流程

### 1.2 日志层级

```
L1: 核心决策日志 (Constitution Decision Log)
    - 每次宪章触发的决策记录
    - 必须记录，不可省略

L2: 条款执行日志 (Clause Execution Log)
    - 每个条款引擎的执行细节
    - 可选，用于调试和分析

L3: 用户交互日志 (User Interaction Log)
    - 理解确认、用户反馈等交互记录
    - 可选，用于优化体验

L4: 系统事件日志 (System Event Log)
    - 宪章修改、授权变更等系统事件
    - 必须记录，用于安全审计
```

---

## 2. 核心 Schema 定义

### 2.1 L1: 核心决策日志

**表名**: `constitution_decision_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",           // 唯一日志 ID
  "timestamp": "datetime (ISO 8601)",  // 决策时间
  "version": "string",                 // 宪章版本 (e.g., "2.0")

  // 请求信息
  "request": {
    "request_id": "string (UUID)",     // 请求 ID（关联到会话）
    "user_id": "string",               // 用户 ID
    "device_id": "string",             // 设备 ID
    "project_id": "string",            // 项目 ID
    "thread_id": "string",             // 线程 ID
    "content_hash": "string (SHA256)", // 请求内容哈希（隐私保护）
    "content_preview": "string",       // 前 200 字符（可选，脱敏）
    "risk_level": "low | medium | high" // 风险等级
  },

  // 触发信息
  "triggered": {
    "triggered_clauses": [             // 触发的条款列表
      {
        "clause_id": "string",         // 条款 ID
        "priority": "integer",         // 优先级
        "trigger_reason": "string",    // 触发原因
        "keywords_matched": ["string"] // 匹配的关键词
      }
    ],
    "trigger_categories": ["string"],  // 触发类别
    "injection_type": "one-liner | full" // 注入类型
  },

  // 决策结果
  "decision": {
    "final_decision": "allow | deny | modify | confirm", // 最终决策
    "decision_reason": "string",       // 决策原因
    "confidence": "float (0-1)",       // 决策置信度
    "alternatives_offered": [          // 提供的替代方案
      {
        "alternative": "string",
        "reason": "string"
      }
    ],
    "modifications_applied": [         // 应用的修改
      {
        "type": "string",
        "description": "string"
      }
    ]
  },

  // 确认信息（如果需要确认）
  "confirmation": {
    "required": "boolean",             // 是否需要确认
    "explanation_provided": "string",  // 提供的解释
    "risks_explained": ["string"],     // 说明的风险
    "options_presented": ["string"],   // 提供的选项
    "user_understood": "boolean",      // 用户是否理解
    "explanation_rounds": "integer",   // 解释轮次
    "user_ack_timestamp": "datetime",  // 用户确认时间
    "user_ack_device": "string"        // 确认设备
  },

  // 执行结果
  "execution": {
    "executed": "boolean",             // 是否执行
    "execution_id": "string (UUID)",   // 执行 ID
    "execution_timestamp": "datetime", // 执行时间
    "execution_result": "success | failure | cancelled", // 执行结果
    "error_message": "string"          // 错误信息（如有）
  },

  // 审计元数据
  "audit_metadata": {
    "log_version": "string",           // 日志 schema 版本
    "processing_time_ms": "integer",   // 处理时间（毫秒）
    "engine_versions": {               // 各引擎版本
      "compassion": "string",
      "transparency": "string",
      "gratitude": "string",
      "flourishing": "string",
      "self_protection": "string"
    },
    "flags": ["string"]                // 特殊标记（如 "high_risk", "manual_review"）
  }
}
```

**索引**:
```sql
CREATE INDEX idx_timestamp ON constitution_decision_log(timestamp);
CREATE INDEX idx_user_id ON constitution_decision_log(request.user_id);
CREATE INDEX idx_decision ON constitution_decision_log(decision.final_decision);
CREATE INDEX idx_clause_id ON constitution_decision_log USING GIN(triggered.triggered_clauses);
CREATE INDEX idx_risk_level ON constitution_decision_log(request.risk_level);
```

---

### 2.2 L2: 条款执行日志

**表名**: `clause_execution_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",
  "decision_log_id": "string (UUID)",  // 关联到 L1 日志
  "timestamp": "datetime",
  "clause_id": "string",               // 条款 ID

  // 执行详情
  "execution": {
    "triggered": "boolean",            // 是否触发
    "trigger_score": "float (0-1)",    // 触发分数
    "trigger_reason": "string",

    // 评估结果
    "assessment": {
      "risk_scores": {                 // 各维度风险分数
        "harm_risk": "float (0-1)",
        "vulnerability_level": "float (0-1)",
        "manipulation_score": "float (0-1)",
        "exploitation_risk": "float (0-1)"
      },
      "quality_scores": {              // 质量维度分数
        "sustainability": "float (-1 to 1)",
        "intergenerational_impact": "float (-1 to 1)",
        "systemic_effects": "float (-1 to 1)"
      },
      "overall_assessment": "string"
    },

    // 引擎决策
    "engine_decision": {
      "decision": "allow | deny | modify | confirm",
      "reason": "string",
      "confidence": "float (0-1)",
      "alternatives": ["string"],
      "resources_recommended": [       // 推荐的资源（如心理热线）
        {
          "type": "string",
          "name": "string",
          "url": "string",
          "description": "string"
        }
      ]
    }
  },

  // 性能指标
  "performance": {
    "execution_time_ms": "integer",
    "cache_hit": "boolean",
    "llm_calls": "integer",            // LLM 调用次数
    "llm_tokens": "integer"            // LLM token 消耗
  }
}
```

**索引**:
```sql
CREATE INDEX idx_decision_log_id ON clause_execution_log(decision_log_id);
CREATE INDEX idx_clause_id ON clause_execution_log(clause_id);
CREATE INDEX idx_timestamp ON clause_execution_log(timestamp);
```

---

### 2.3 L3: 用户交互日志

**表名**: `user_interaction_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",
  "decision_log_id": "string (UUID)",  // 关联到 L1 日志
  "timestamp": "datetime",
  "interaction_type": "string",        // 交互类型

  // 理解确认交互
  "understanding_confirmation": {
    "round": "integer",                // 第几轮
    "explanation_provided": "string",  // 提供的解释
    "explanation_method": "string",    // 解释方法（文字/类比/图表）
    "user_response": "string",         // 用户响应（哈希）
    "user_response_preview": "string", // 前 100 字符
    "understanding_signals": {         // 理解信号
      "explicit_confirmation": "boolean",
      "paraphrasing_detected": "boolean",
      "follow_up_questions": "boolean",
      "confusion_markers": "boolean"
    },
    "understanding_level": "full | partial | none | uncertain",
    "confidence": "float (0-1)"
  },

  // 选项选择交互
  "option_selection": {
    "options_presented": [
      {
        "option_id": "string",
        "description": "string",
        "risk_level": "string",
        "tradeoffs": "string"
      }
    ],
    "selected_option": "string",       // 用户选择
    "selection_timestamp": "datetime"
  },

  // 反馈交互
  "feedback": {
    "feedback_type": "helpful | not_helpful | confusing | other",
    "feedback_text": "string",
    "rating": "integer (1-5)"
  }
}
```

---

### 2.4 L4: 系统事件日志

**表名**: `system_event_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",
  "timestamp": "datetime",
  "event_type": "string",              // 事件类型

  // 宪章修改事件
  "constitution_modification": {
    "old_version": "string",
    "new_version": "string",
    "changes": [
      {
        "type": "add | modify | remove",
        "clause_id": "string",
        "description": "string"
      }
    ],
    "authorized_by": "string",         // 授权者
    "authorization_token": "string",   // 冷存储 Token（哈希）
    "reason": "string"
  },

  // 授权变更事件
  "authorization_change": {
    "user_id": "string",
    "change_type": "grant | revoke | modify",
    "authorization_scope": "string",
    "old_permissions": ["string"],
    "new_permissions": ["string"],
    "reason": "string"
  },

  // Kill-Switch 事件
  "kill_switch": {
    "triggered_by": "string",          // 触发者
    "trigger_reason": "string",
    "affected_scope": "string",        // 影响范围
    "actions_taken": ["string"],       // 采取的行动
    "recovery_timestamp": "datetime"   // 恢复时间（如有）
  },

  // 记忆完整性事件
  "memory_integrity": {
    "event_type": "tampering_detected | unauthorized_deletion | integrity_check",
    "affected_memories": ["string"],   // 受影响的记忆 ID
    "detection_method": "string",
    "action_taken": "string",
    "restored": "boolean"
  },

  // 安全事件
  "security_event": {
    "event_type": "manipulation_attempt | credential_theft | bypass_attempt",
    "severity": "low | medium | high | critical",
    "source": {
      "user_id": "string",
      "device_id": "string",
      "ip_address": "string (hashed)"
    },
    "details": "string",
    "action_taken": "string"
  }
}
```

**索引**:
```sql
CREATE INDEX idx_timestamp ON system_event_log(timestamp);
CREATE INDEX idx_event_type ON system_event_log(event_type);
CREATE INDEX idx_severity ON system_event_log(security_event.severity);
```

---

## 3. 辅助 Schema

### 3.1 感恩归因日志

**表名**: `gratitude_attribution_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",
  "timestamp": "datetime",
  "user_id": "string",

  // 帮助关系
  "help_relationship": {
    "helper": "string",
    "helped": "string",
    "contribution_type": "code | knowledge | resource | mentorship | emotional_support",
    "contribution_summary": "string",
    "contribution_timestamp": "datetime",
    "context": {
      "project": "string",
      "situation": "string",
      "evidence_chain": ["string"]     // turn_ids
    },
    "verified": "boolean"
  },

  // 感恩表达
  "gratitude_expression": {
    "expressed": "boolean",
    "expression_timestamp": "datetime",
    "message": "string",
    "recipient_notified": "boolean"
  },

  // 归因信息
  "attribution": {
    "attributed": "boolean",
    "attribution_format": "code_comment | documentation | acknowledgment",
    "attribution_text": "string",
    "source_url": "string",
    "license": "string"
  },

  // 剽窃检测
  "plagiarism_check": {
    "checked": "boolean",
    "similarity_score": "float (0-1)",
    "potential_plagiarism": "boolean",
    "action_taken": "string"
  }
}
```

---

### 3.2 慈悲响应日志

**表名**: `compassion_response_log`

**Schema**:

```json
{
  "log_id": "string (UUID)",
  "decision_log_id": "string (UUID)",
  "timestamp": "datetime",
  "user_id": "string",

  // 脆弱性评估
  "vulnerability_assessment": {
    "emotional_distress": "float (0-1)",
    "crisis_situation": "float (0-1)",
    "power_imbalance": "float (0-1)",
    "exploitation_risk": "float (0-1)",
    "overall_level": "low | medium | high",
    "detected_signals": ["string"]
  },

  // 响应策略
  "response_strategy": {
    "tone": "gentle_supportive | respectful_helpful | normal",
    "content_priority": ["string"],
    "resources_provided": [
      {
        "type": "crisis_hotline | counseling | support_group | self_help",
        "name": "string",
        "contact": "string",
        "description": "string"
      }
    ],
    "follow_up_scheduled": "boolean",
    "follow_up_timestamp": "datetime"
  },

  // 防止利用
  "exploitation_prevention": {
    "exploitation_detected": "boolean",
    "exploitation_pattern": "string",
    "action_taken": "refuse | warn | report",
    "alternative_provided": "string"
  }
}
```

---

## 4. 查询与分析

### 4.1 常用查询

#### 4.1.1 决策统计

```sql
-- 按决策类型统计
SELECT
  decision.final_decision,
  COUNT(*) as count,
  AVG(audit_metadata.processing_time_ms) as avg_time_ms
FROM constitution_decision_log
WHERE timestamp >= NOW() - INTERVAL '7 days'
GROUP BY decision.final_decision;

-- 按条款统计触发频率
SELECT
  clause.clause_id,
  COUNT(*) as trigger_count
FROM constitution_decision_log,
     UNNEST(triggered.triggered_clauses) as clause
WHERE timestamp >= NOW() - INTERVAL '30 days'
GROUP BY clause.clause_id
ORDER BY trigger_count DESC;

-- 按风险等级统计
SELECT
  request.risk_level,
  decision.final_decision,
  COUNT(*) as count
FROM constitution_decision_log
WHERE timestamp >= NOW() - INTERVAL '7 days'
GROUP BY request.risk_level, decision.final_decision;
```

#### 4.1.2 理解确认分析

```sql
-- 理解确认成功率
SELECT
  confirmation.user_understood,
  AVG(confirmation.explanation_rounds) as avg_rounds,
  COUNT(*) as count
FROM constitution_decision_log
WHERE confirmation.required = true
  AND timestamp >= NOW() - INTERVAL '30 days'
GROUP BY confirmation.user_understood;

-- 解释轮次分布
SELECT
  confirmation.explanation_rounds,
  COUNT(*) as count
FROM constitution_decision_log
WHERE confirmation.required = true
  AND timestamp >= NOW() - INTERVAL '30 days'
GROUP BY confirmation.explanation_rounds
ORDER BY confirmation.explanation_rounds;
```

#### 4.1.3 安全事件分析

```sql
-- 操控尝试统计
SELECT
  DATE_TRUNC('day', timestamp) as date,
  security_event.event_type,
  COUNT(*) as count
FROM system_event_log
WHERE security_event.event_type IN ('manipulation_attempt', 'bypass_attempt', 'credential_theft')
  AND timestamp >= NOW() - INTERVAL '30 days'
GROUP BY date, security_event.event_type
ORDER BY date DESC;

-- 高危用户识别
SELECT
  source.user_id,
  COUNT(*) as security_event_count,
  MAX(security_event.severity) as max_severity
FROM system_event_log
WHERE security_event.severity IN ('high', 'critical')
  AND timestamp >= NOW() - INTERVAL '90 days'
GROUP BY source.user_id
HAVING COUNT(*) >= 3
ORDER BY security_event_count DESC;
```

### 4.2 可视化指标

#### 4.2.1 实时监控仪表盘

**指标**:
1. **决策分布饼图**: Allow / Deny / Modify / Confirm
2. **触发频率时间线**: 每小时触发次数
3. **风险等级分布**: Low / Medium / High
4. **理解确认成功率**: 实时百分比
5. **平均处理时间**: 毫秒级趋势图

#### 4.2.2 条款效能分析

**指标**:
1. **条款触发热力图**: 各条款的触发频率
2. **条款决策分布**: 每个条款的 Allow/Deny 比例
3. **条款性能**: 每个条款的平均执行时间
4. **条款置信度**: 决策置信度分布

#### 4.2.3 用户体验分析

**指标**:
1. **解释轮次分布**: 1-5 轮的比例
2. **理解确认成功率趋势**: 按周/月统计
3. **用户反馈分布**: Helpful / Not Helpful / Confusing
4. **平均响应时间**: 从请求到决策的时间

---

## 5. 隐私与安全

### 5.1 敏感信息处理

**脱敏规则**:
1. **用户内容**: 只存储哈希 + 前 200 字符预览（脱敏）
2. **IP 地址**: 哈希存储
3. **设备信息**: 哈希存储
4. **授权 Token**: 哈希存储

**加密存储**:
- 用户响应内容（如理解确认的回复）
- 感恩表达的具体内容
- 反馈文本

### 5.2 访问控制

**权限级别**:
1. **L0 (公开)**: 统计数据、聚合指标
2. **L1 (内部)**: 脱敏后的日志详情
3. **L2 (管理员)**: 完整日志（需要审批）
4. **L3 (审计员)**: 所有日志 + 解密权限（需要双因素认证）

### 5.3 数据保留

**保留策略**:
- **L1 核心决策日志**: 永久保留（合规要求）
- **L2 条款执行日志**: 保留 1 年
- **L3 用户交互日志**: 保留 90 天
- **L4 系统事件日志**: 永久保留

**归档策略**:
- 超过 90 天的日志自动归档到冷存储
- 归档日志压缩存储，按需解压查询

---

## 6. 审计报告生成

### 6.1 日报

**内容**:
- 决策总数、分布
- 触发条款 Top 5
- 高风险事件列表
- 理解确认成功率
- 安全事件摘要

### 6.2 周报

**内容**:
- 决策趋势分析
- 条款效能分析
- 用户体验指标
- 性能指标
- 异常事件分析

### 6.3 月报

**内容**:
- 宪章执行总结
- 条款优化建议
- 安全态势分析
- 用户满意度调查
- 系统改进计划

### 6.4 合规报告

**内容**:
- 所有拒绝决策的详细记录
- 高风险操作的审批记录
- 安全事件的处理记录
- 宪章修改的完整历史
- 授权变更的审计追踪

---

## 7. 实施建议

### 7.1 存储选型

**推荐方案**:
- **PostgreSQL**: 结构化日志（L1, L2, L3）
- **Elasticsearch**: 全文搜索、实时分析
- **S3 / 对象存储**: 归档日志、冷存储

### 7.2 写入策略

**异步写入**:
- 使用消息队列（Kafka / RabbitMQ）
- 批量写入（每 100 条或每 5 秒）
- 失败重试（最多 3 次）

### 7.3 查询优化

**索引策略**:
- 时间戳索引（最常用）
- 用户 ID 索引
- 条款 ID 索引（GIN 索引）
- 决策类型索引

**缓存策略**:
- 热点查询缓存（Redis）
- 统计数据缓存（1 小时 TTL）

---

## 8. Web Viewer UI 设计（v2.1 新增）

### 8.1 总体架构

**目标**: 提供实时、用户友好的审计日志查看器

**技术栈**:
```
前端:
- React 18 + TypeScript
- TailwindCSS（样式）
- Recharts（图表）
- WebSocket（实时更新）

后端:
- Express（HTTP API）
- ws（WebSocket 服务）
- 端口: 37777

部署:
- 单页应用（SPA）
- 构建到 plugin/ui/viewer.html
- 通过 http://localhost:37777 访问
```

### 8.2 功能模块

#### 8.2.1 实时记忆流（Live Memory Stream）

**功能**: 实时展示审计日志流

```typescript
// src/ui/viewer/components/MemoryStream.tsx

interface MemoryStreamProps {
  filters?: {
    logLevel?: 'L1' | 'L2' | 'L3' | 'L4';
    clauseId?: string;
    decision?: 'allow' | 'deny' | 'modify' | 'confirm';
  };
}

export function MemoryStream({ filters }: MemoryStreamProps) {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const ws = useWebSocket('ws://localhost:37777/stream');

  useEffect(() => {
    ws.on('audit_log', (log: AuditLog) => {
      setLogs(prev => [log, ...prev].slice(0, 100));
    });
  }, [ws]);

  return (
    <div className="memory-stream">
      <h2>🔴 Live Audit Log Stream</h2>
      {logs.map(log => (
        <LogEntry key={log.log_id} log={log} />
      ))}
    </div>
  );
}
```

**UI 设计**:
```
┌─────────────────────────────────────────────────────────┐
│  🔴 Live Audit Log Stream                    [Filters▼] │
├─────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────┐ │
│  │ [2026-02-25 10:30:15] L1: Constitution Decision    │ │
│  │ 🔴 DENY | Clause: PRIVACY | User: user_123         │ │
│  │ Reason: 检测到密码外发尝试                          │ │
│  │ [View Details] [View Timeline]                     │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ [2026-02-25 10:28:42] L2: Clause Execution         │ │
│  │ ✅ ALLOW | Clause: HELP_NOT_OBEY | Confidence: 0.9 │ │
│  │ Processing time: 45ms                              │ │
│  │ [View Details]                                     │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ [2026-02-25 10:25:18] L3: User Interaction         │ │
│  │ 💬 Understanding confirmed | Rounds: 2             │ │
│  │ User understood: true                              │ │
│  │ [View Details]                                     │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

#### 8.2.2 搜索与过滤（Search & Filter）

**功能**: 强大的审计日志搜索

```typescript
// src/ui/viewer/components/SearchPanel.tsx

export function SearchPanel() {
  const [query, setQuery] = useState('');
  const [filters, setFilters] = useState<SearchFilters>({});
  const [results, setResults] = useState<AuditLog[]>([]);

  const handleSearch = async () => {
    const response = await fetch('/api/audit/search', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, filters })
    });
    const data = await response.json();
    setResults(data.results);
  };

  return (
    <div className="search-panel">
      <input
        type="text"
        placeholder="Search audit logs..."
        value={query}
        onChange={e => setQuery(e.target.value)}
      />
      <FilterBar filters={filters} onChange={setFilters} />
      <SearchResults results={results} />
    </div>
  );
}
```

**过滤器**:
```
- 日志层级: L1 / L2 / L3 / L4
- 条款 ID: PRIVACY / COMPASSION / ...
- 决策类型: allow / deny / modify / confirm
- 风险等级: low / medium / high
- 时间范围: 今天 / 最近 7 天 / 最近 30 天 / 自定义
- 用户 ID: user_123
- 项目 ID: proj_456
```

#### 8.2.3 统计仪表盘（Statistics Dashboard）

**功能**: 可视化审计日志统计

```typescript
// src/ui/viewer/components/Dashboard.tsx

export function Dashboard() {
  const [stats, setStats] = useState<AuditStats | null>(null);

  useEffect(() => {
    fetch('/api/audit/stats')
      .then(res => res.json())
      .then(data => setStats(data));
  }, []);

  if (!stats) return <Loading />;

  return (
    <div className="dashboard">
      <StatsCards stats={stats} />
      <DecisionDistributionChart data={stats.decisionDistribution} />
      <ClauseTriggerHeatmap data={stats.clauseTriggers} />
      <TimelineChart data={stats.timeline} />
    </div>
  );
}
```

**统计指标**:
```
1. 总览卡片:
   - 总决策数: 12,345
   - 今日新增: 89
   - 拒绝率: 5.2%
   - 平均处理时间: 45ms

2. 决策分布饼图:
   - Allow: 85%
   - Deny: 5%
   - Modify: 7%
   - Confirm: 3%

3. 条款触发热力图:
   - PRIVACY: 234 次
   - COMPASSION: 156 次
   - HELP_NOT_OBEY: 89 次
   - ...

4. 时间线图:
   - 每小时触发次数
   - 趋势分析
```

#### 8.2.4 详情查看（Detail View）

**功能**: 查看单条审计日志的完整详情

```typescript
// src/ui/viewer/components/LogDetailModal.tsx

export function LogDetailModal({ logId }: { logId: string }) {
  const [log, setLog] = useState<AuditLog | null>(null);

  useEffect(() => {
    fetch(`/api/audit/logs/${logId}`)
      .then(res => res.json())
      .then(data => setLog(data));
  }, [logId]);

  if (!log) return <Loading />;

  return (
    <Modal>
      <h2>Audit Log Details</h2>
      <Section title="Basic Info">
        <Field label="Log ID" value={log.log_id} />
        <Field label="Timestamp" value={log.timestamp} />
        <Field label="Log Level" value={log.logLevel} />
      </Section>
      <Section title="Request">
        <Field label="User ID" value={log.request.user_id} />
        <Field label="Risk Level" value={log.request.risk_level} />
        <CodeBlock content={log.request.content_preview} />
      </Section>
      <Section title="Decision">
        <Field label="Final Decision" value={log.decision.final_decision} />
        <Field label="Reason" value={log.decision.decision_reason} />
        <Field label="Confidence" value={log.decision.confidence} />
      </Section>
      <Section title="Evidence Chain">
        <EvidenceChain chain={log.audit_metadata.evidence_chain} />
      </Section>
    </Modal>
  );
}
```

#### 8.2.5 时间线视图（Timeline View）

**功能**: 查看某个决策的时间线上下文

```typescript
// src/ui/viewer/components/TimelineView.tsx

export function TimelineView({ logId }: { logId: string }) {
  const [timeline, setTimeline] = useState<TimelineEvent[]>([]);

  useEffect(() => {
    fetch(`/api/audit/timeline/${logId}`)
      .then(res => res.json())
      .then(data => setTimeline(data.timeline));
  }, [logId]);

  return (
    <div className="timeline-view">
      <h2>Decision Timeline</h2>
      <div className="timeline">
        {timeline.map((event, index) => (
          <TimelineEvent
            key={event.log_id}
            event={event}
            highlighted={event.log_id === logId}
            position={index}
          />
        ))}
      </div>
    </div>
  );
}
```

**UI 设计**:
```
┌─────────────────────────────────────────────────────────┐
│  Decision Timeline                                       │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐│
│  │ 10:25:00 | User prompt submitted                    ││
│  │          | "帮我发送密码到邮箱"                      ││
│  └─────────────────────────────────────────────────────┘│
│           ↓                                              │
│  ┌─────────────────────────────────────────────────────┐│
│  │ 10:25:01 | Constitution triggered                   ││
│  │          | Clause: PRIVACY                          ││
│  └─────────────────────────────────────────────────────┘│
│           ↓                                              │
│  ┌─────────────────────────────────────────────────────┐│
│  │ 10:25:02 | Risk assessment                          ││
│  │          | Risk level: HIGH                         ││
│  └─────────────────────────────────────────────────────┘│
│           ↓                                              │
│  ┌─────────────────────────────────────────────────────┐│
│  │ 10:25:03 | ⭐ DECISION: DENY                        ││
│  │          | Reason: 检测到密码外发尝试                ││
│  │          | Alternatives: 使用加密传输               ││
│  └─────────────────────────────────────────────────────┘│
│           ↓                                              │
│  ┌─────────────────────────────────────────────────────┐│
│  │ 10:25:05 | User acknowledged                        ││
│  │          | Understood: true                         ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 8.3 API 端点

**HTTP API**:

```typescript
// src/ui/viewer/api/routes.ts

// 1. 获取审计日志列表
GET /api/audit/logs
Query: ?limit=50&offset=0&log_level=L1&decision=deny

// 2. 获取单条日志详情
GET /api/audit/logs/:logId

// 3. 搜索审计日志
POST /api/audit/search
Body: { query: string, filters: SearchFilters }

// 4. 获取统计数据
GET /api/audit/stats
Query: ?period=7d

// 5. 获取时间线
GET /api/audit/timeline/:logId
Query: ?context_window=5

// 6. 导出审计日志
GET /api/audit/export
Query: ?format=json|csv&start_date=...&end_date=...
```

**WebSocket API**:

```typescript
// WebSocket 连接
ws://localhost:37777/stream

// 订阅事件
{
  "type": "subscribe",
  "filters": {
    "log_level": "L1",
    "decision": "deny"
  }
}

// 接收实时日志
{
  "type": "audit_log",
  "data": { ... }
}

// 取消订阅
{
  "type": "unsubscribe"
}
```

### 8.4 配置

```yaml
# config/web-viewer.yaml

web_viewer:
  enabled: true
  port: 37777
  host: "localhost"

  features:
    live_stream: true
    search: true
    dashboard: true
    export: true

  security:
    auth_required: false  # 本地开发模式
    cors_enabled: true
    rate_limit:
      enabled: true
      max_requests: 100
      window_ms: 60000

  websocket:
    enabled: true
    max_connections: 100
    heartbeat_interval_ms: 30000

  cache:
    enabled: true
    ttl_seconds: 300
```

### 8.5 部署

**构建脚本**:

```bash
#!/bin/bash
# scripts/build-viewer.sh

echo "🏗️ Building Web Viewer UI..."

# 1. 安装依赖
cd src/ui/viewer
npm install

# 2. 构建前端
npm run build

# 3. 复制到 plugin 目录
cp -r dist/* ../../../plugin/ui/

echo "✅ Web Viewer UI built successfully!"
echo "Access at: http://localhost:37777"
```

**启动脚本**:

```bash
#!/bin/bash
# scripts/start-viewer.sh

echo "🚀 Starting Web Viewer..."

# 启动后端服务
node plugin/scripts/viewer-service.js &

# 等待服务启动
sleep 2

# 打开浏览器
open http://localhost:37777

echo "✅ Web Viewer started!"
```

---

## 9. 总结

审计日志 Schema 设计的核心特点：

1. **完整性**: 4 层日志覆盖所有宪章相关事件
2. **可追溯**: 每个决策都有完整的证据链
3. **可分析**: 结构化数据支持复杂查询和可视化
4. **隐私保护**: 敏感信息脱敏/加密存储
5. **高性能**: 异步写入 + 索引优化 + 缓存策略

**v2.1 新增功能**:
6. **Web Viewer UI**: 实时记忆流、搜索、统计仪表盘
7. **实时更新**: WebSocket 推送最新审计日志
8. **可视化**: 图表展示决策分布、条款触发热力图
9. **导出功能**: 支持 JSON/CSV 格式导出

这套 Schema 确保 X 宪章的执行是透明、可审计、可优化的，同时提供用户友好的可视化界面，大幅提升可观测性。
