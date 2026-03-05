# TODO

Last updated: 2026-03-04

## Open

- [ ] KIMI 长短周期显示异常排查后续修复
  - 现象：当前看板有时不再同时显示“长周期 + 短周期”。
  - 已定位：`KIMIService` 解析实现未变；更可能是返回值阶段性变化（主/次周期数据趋同）触发了 `MainView` 周期去重逻辑。
  - 需要做：在不引入错误重复展示的前提下，调整 KIMI 周期展示策略（避免被“同值去重”误吞）。
  - 参考位置：
    - `/Users/salmonc/Code/Projects/MacTools/MacUsageTracker/Sources/App/Views/MainView.swift`
    - `/Users/salmonc/Code/Projects/MacTools/MacUsageTracker/Sources/Shared/Services/MiniMaxService.swift`

