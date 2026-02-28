# Project Structure (整理后)

## 目标

- 按职责拆分 `Sources/App` 与 `Sources/Shared` 下的文件，降低“同级堆叠”带来的查找成本。
- 保持 XcodeGen 配置兼容，不修改业务逻辑代码。

## 当前目录建议

```text
Sources/
├── App/
│   ├── MacUsageTrackerApp.swift
│   ├── ViewModels/
│   │   └── AppViewModel.swift
│   ├── Views/
│   │   ├── MainView.swift
│   │   └── SettingsView.swift
│   └── Resources/
├── Shared/
│   ├── Models/
│   │   └── SharedModels.swift
│   ├── Services/
│   │   └── MiniMaxService.swift
│   └── Security/
│       └── KeychainManager.swift
└── Widget/
    ├── UsageWidget.swift
    ├── Info.plist
    └── UsageWidget.entitlements
```

## 目录职责

- `Sources/App/ViewModels`: App 侧状态管理与业务编排（MVVM 的 VM 层）。
- `Sources/App/Views`: SwiftUI 视图。
- `Sources/Shared/Models`: App 与 Widget 共享的数据模型、存储结构。
- `Sources/Shared/Services`: 各 API Provider 的请求实现与服务工厂。
- `Sources/Shared/Security`: Keychain 等安全相关能力。

## 后续建议（可选）

- 将 `MiniMaxService.swift` 按 Provider 拆分为多个文件（如 `MiniMaxService.swift`、`GLMService.swift`、`TavilyService.swift`）。
- 在 `Sources/Shared/Services` 中单独抽出 `UsageService` 协议文件，减少单文件职责。
- 增加 `Scripts/` 目录承载构建/打包脚本，避免命令散落在 README。
