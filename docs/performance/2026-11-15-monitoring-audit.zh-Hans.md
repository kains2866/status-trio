# 监控与调度优化审查（2026-11-15）

审查基线：`d4c12de2`。本轮为源码只读审查，没有运行性能基准或修改监控策略；以下是代码可确认的重复工作，不是测得的 CPU 降幅。暂停应用修复属于行为修复，单独验证。

## 优先级

1. **每轮音频发现共用设备快照。** `Audio/CoreAudioApplicationProcessDiscovery.swift` 的 `refresh → readProcess → readDevices → routeFingerprint` 会为每个进程读取设备 alive、UID、名称、采样率、流及格式。多个应用和浏览器 helper 共用一个扬声器时，同轮重复。优先使用按 device ID/方向索引的单轮局部快照，结束立即丢弃；失败保持 incomplete route，不能沿用上轮数据。用假 HAL 统计读取次数，再比较相同进程/路由事件的 worker 耗时。
2. **每轮只枚举一次运行应用身份。** `Audio/ApplicationAudioAppIdentity.swift` 的 `resolve(pid:)` 每次扫描 `NSWorkspace.shared.runningApplications`；controller 对每个 PID 分别调用。可在每轮提供不可变 owner evidence 并复用该轮 bundle、owner 证据；保留 PID 启动时间验证，不使用长寿命身份缓存。衡量每轮 Workspace 枚举次数及 MainActor reconcile 耗时。
3. **合并打开面板的电源采样需求。** `Presentation/Panel/StatusPanelViewModel.swift` 先提交 `.panel` 再提交 `.powerInfoBar`；`Monitoring/PowerSamplingService.swift` 每个新增 demand 刷新，第二次在 in-flight 时标记补读，可能形成一次 system-only 后立刻一次 auxiliary 的读取。可一次性提交完整需求，但不能丢失新增 rails 的即时采样。先用 fake reader 验证读取次数/rails，再实测首次完整信息延迟。
4. **相同 mixer rows 不重复发布。** controller 仍需执行身份存活、退出及清理判断，但当生成的业务行与旧值相等时可跳过 `@Published rows` 赋值，减少无变化的 SwiftUI 更新。不能仅因 snapshots 相同就跳过整个 reconcile；Workspace 退出事件仍需清理离开 HAL 的应用。用发布次数和 body 更新次数验证。
5. **先测再考虑：HAL 会话创建/拆除离开 MainActor。** 当前首次调整、helper 变化及设备切换时，tap/aggregate 创建和拆除同步执行。若测得主线程停顿，再设计串行所有权、代际取消、pending gain 和失败句柄恢复；不能简单使用 detached Task。该项风险高，不作为首选，也不能声称会降低 idle CPU。

## 已有优化与建议边界

已存在：后台降频与显示器睡眠暂停、共享 power demand 与 icon-only cadence、按需能耗采样、受限 `pmset` 子进程读取、异步/按需 VPN、snapshot/popup 相等判断和独立 icon scene。

不建议继续统一降频、引入全局调度器或长寿命身份缓存。最先值得实施的是第 1 项，随后可做第 2 和第 4 项；没有测量依据时不承诺具体 CPU、内存或耗电收益。真实测量须记录硬件、进程来源、测试场景、区间及基线，遵守项目 performance rule。
