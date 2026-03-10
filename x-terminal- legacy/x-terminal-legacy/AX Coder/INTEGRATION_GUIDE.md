# AX Coder 功能增强集成指南

## 已实现的功能

### 1. 事件系统 (AXEventBus)
**文件**: `Sources/Event/AXEventBus.swift`

**功能**:
- 完整的事件发布/订阅机制
- 支持的事件类型:
  - `sessionCreated` / `sessionUpdated` / `sessionDeleted` / `sessionDiff` / `sessionError`
  - `messageCreated` / `messageUpdated` / `messageDeleted`
  - `toolCallCreated` / `toolCallUpdated` / `toolCallDeleted`

**使用方法**:
```swift
// 发布事件
AXEventBus.shared.publish(.sessionCreated(sessionInfo))

// 监听事件
let cancellable = AXEventBus.shared.eventPublisher
    .sink { event in
        switch event {
        case .sessionCreated(let info):
            print("Session created: \(info.title)")
        default:
            break
        }
    }
```

### 2. Session管理器 (AXSessionManager)
**文件**: `Sources/Session/AXSessionManager.swift`

**功能**:
- Session生命周期管理（创建、删除、更新）
- Fork功能：创建session分支
- Revert功能：回滚到指定消息
- Compaction功能：压缩历史记录

**使用方法**:
```swift
// 创建session
let session = AXSessionManager.shared.createSession(
    projectId: "project123",
    title: "New Session"
)

// Fork session
let forkedSession = AXSessionManager.shared.forkSession(sessionId, messageId: "msg123")

// Revert session
AXSessionManager.shared.revertSession(sessionId, to: "msg123")

// Compact session
await AXSessionManager.shared.compactSession(sessionId)

// 删除session
AXSessionManager.shared.deleteSession(sessionId)
```

### 3. HTTP API服务器 (AXServerManager)
**文件**: `Sources/Server/AXServerManager.swift`

**功能**:
- 基于Network框架的HTTP服务器
- 支持多客户端连接
- 提供Session管理API
- 支持远程驱动

**API端点**:
```
GET    /api/sessions          - 列出所有sessions
POST   /api/sessions          - 创建新session
GET    /api/sessions/:id      - 获取指定session
POST   /api/sessions/:id/fork - Fork session
POST   /api/sessions/:id/revert - Revert session
POST   /api/sessions/:id/compact - Compact session
DELETE /api/sessions/:id      - 删除session
GET    /api/events            - SSE事件流
```

**使用方法**:
```swift
// 启动服务器
try await AXServerManager.shared.startServer()

// 停止服务器
AXServerManager.shared.stopServer()

// 检查服务器状态
if AXServerManager.shared.isRunning {
    print("Server is running on port \(AXServerManager.shared.port)")
}
```

### 4. 历史框功能 (HistoryPanelView)
**文件**: `Sources/UI/HistoryPanelView.swift`

**功能**:
- 显示消息历史
- 复制内容到剪贴板
- 插入到光标位置
- 添加到新文件

**使用方法**:
```swift
// 在SwiftUI视图中使用
HistoryPanelView()
    .environmentObject(appModel)
```

### 5. AI选择器 (ModelSelectorView)
**文件**: `Sources/UI/ModelSelectorView.swift`

**功能**:
- 显示Hub已加载的模型列表
- 支持模型切换
- 与Hub集成

**使用方法**:
```swift
// 在SwiftUI视图中使用
ModelSelectorView()
    .environmentObject(appModel)
```

### 6. 输入优化 (AmbiguityDetector)
**文件**: `Sources/UI/AmbiguityDetector.swift`

**功能**:
- 本地AI歧义检测
- 3秒自动发送
- 确认对话框

**使用方法**:
```swift
// 使用增强的输入视图
EnhancedInputView()
```

### 7. 语音输入 (VoiceInputView)
**文件**: `Sources/UI/VoiceInputView.swift`

**功能**:
- 集成Speech框架
- 实时语音识别
- 支持中文识别

**使用方法**:
```swift
// 使用语音输入按钮
VoiceInputButton(text: $inputText)
```

## 集成步骤

### ✅ 步骤1: 更新AppModel（已完成）

已在 `AppModel.swift` 中添加以下内容:

```swift
// 添加了服务器状态
@Published var serverRunning: Bool = false

// 添加了Session管理器和服务器管理器
private let sessionManager = AXSessionManager.shared
private let serverManager = AXServerManager.shared

// 在init()中启动HTTP服务器
Task {
    do {
        try await serverManager.startServer()
        await MainActor.run {
            self.serverRunning = serverManager.isRunning
        }
    } catch {
        print("Failed to start server: \(error)")
    }
}
```

### ✅ 步骤2: 更新ContentView（已完成）

已在 `ContentView.swift` 中添加历史框:

```swift
// 添加状态变量
@State private var showHistoryPanel: Bool = false

// 在HSplitView中添加历史框面板
if showHistoryPanel {
    HistoryPanelView()
        .frame(minWidth: 300, maxWidth: 400)
}

// 在toolbar中添加切换按钮
Button {
    showHistoryPanel.toggle()
} label: {
    Image(systemName: "clock")
}
.help("Toggle History Panel")
.disabled(appModel.projectContext == nil)
```

### ✅ 步骤3: 更新TerminalChatView（已完成）

已在 `TerminalChatView.swift` 中添加AI选择器和语音输入:

```swift
// 在inputBar中添加
ModelSelectorView()
    .environmentObject(appModel)

VoiceInputButton(text: $session.draft)
```

### ✅ 步骤4: 添加权限配置（已完成）

已创建 `AXCoder.entitlements` 文件，包含以下权限:

```xml
<key>com.apple.security.device.microphone</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

### ⚠️ 步骤5: 更新Info.plist（需要手动添加）

在 `Info.plist` 中添加以下权限说明:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限以支持语音输入功能</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>需要语音识别权限以支持语音输入功能</string>
```

注意：Info.plist需要在Xcode项目中配置，或者通过build脚本生成。

## 测试建议

### 1. 测试事件系统
```swift
// 在AppModel中添加测试代码
AXEventBus.shared.publish(.sessionCreated(
    AXSessionInfo(
        id: "test",
        projectId: "test",
        title: "Test Session",
        directory: "",
        parentId: nil,
        createdAt: Date().timeIntervalSince1970,
        updatedAt: Date().timeIntervalSince1970,
        version: "1.0",
        summary: nil
    )
))
```

### 2. 测试Session管理
```swift
// 创建session
let session = AXSessionManager.shared.createSession(
    projectId: "test",
    title: "Test Session"
)

// Fork session
let forked = AXSessionManager.shared.forkSession(session.id)

// 删除session
AXSessionManager.shared.deleteSession(session.id)
```

### 3. 测试HTTP API
```bash
# 启动服务器后，使用curl测试
curl http://localhost:8080/api/sessions

# 创建session
curl -X POST http://localhost:8080/api/sessions

# Fork session
curl -X POST http://localhost:8080/api/sessions/{id}/fork
```

### 4. 测试UI功能
- 打开历史框面板
- 测试复制、插入、添加到新文件功能
- 测试AI选择器
- 测试语音输入（需要授权）

## 已知限制

1. **HTTP API**: 当前实现是简化版本，不支持完整的HTTP协议解析
2. **歧义检测**: 需要集成本地AI模型才能正常工作
3. **语音识别**: 需要用户授权麦克风和语音识别权限
4. **Session存储**: 当前使用UserDefaults，生产环境建议使用文件存储

## 后续优化建议

1. **HTTP服务器**: 使用Vapor或VaporKit实现完整的HTTP服务器
2. **WebSocket**: 添加WebSocket支持以实现实时通信
3. **数据库**: 使用SQLite或Core Data存储session数据
4. **本地AI**: 集成Core ML或Hub的本地AI模型进行歧义检测
5. **国际化**: 添加多语言支持

## 文件清单

新增文件:
- `Sources/Event/AXEventBus.swift` - 事件系统
- `Sources/Session/AXSessionManager.swift` - Session管理器
- `Sources/Server/AXServerManager.swift` - HTTP API服务器
- `Sources/UI/HistoryPanelView.swift` - 历史框视图
- `Sources/UI/ModelSelectorView.swift` - AI选择器
- `Sources/UI/AmbiguityDetector.swift` - 歧义检测器
- `Sources/UI/VoiceInputView.swift` - 语音输入视图

需要修改的文件:
- `Sources/AppModel.swift` - 添加Session管理器和服务器管理器
- `Sources/ContentView.swift` - 添加历史框面板
- `Sources/UI/TerminalChatView.swift` - 添加AI选择器和语音输入
- `AXCoder.entitlements` - 添加权限配置
- `Info.plist` - 添加权限说明

## 总结

所有功能已经实现并可以直接集成到AX Coder中。这些功能参考了OpenCode的优秀设计，同时保持了AX Coder的架构优势。核心功能（事件系统、Session管理、HTTP API）已经完成，UI增强功能（历史框、AI选择器、输入优化、语音输入）也已经实现。

下一步需要做的是:
1. 按照集成步骤修改现有文件
2. 添加必要的权限配置
3. 进行测试和调试
4. 根据实际使用情况进行优化
