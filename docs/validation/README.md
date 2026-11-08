# 验证证据索引

报告记录“某个固定快照跑过什么”，不是当前版本永久有效的合格证。每次交付在[开发记录](../history/开发记录.md)说明范围，并在[总纲](../04-后续开发总纲.md)维护状态；执行方式只在[工具索引](../../tools/README.md)维护。

## 现有报告

| 报告 | 适用内容 |
| --- | --- |
| [2026-11-08-b2-chapter-integration.json](2026-11-08-b2-chapter-integration.json) | 第一章正式接线、NPC六任务链、K日志、邮件/过场/独立输入租约、可用工作台；43套全量、原生159项、实际PCK70项及失败修复记录 |
| [2026-11-08-b2-events.json](2026-11-08-b2-events.json) | B2-04条件事件/独立过场，83项专项、84项窗口、43套全量/PCK；不代表正式章节接线或人工试玩完成 |
| [2026-11-08-b2-mailbox.json](2026-11-08-b2-mailbox.json) | B2-05邮件状态/整批附件、防重入、保存失败、模态与View替换、真实窗口和PCK |
| [2026-11-06-b2-quests.json](2026-11-06-b2-quests.json) | 章节任务模型/事务、39套全量（含包内运行）、重入与写档失败；不含玩家可见界面 |
| [2026-11-06-docs-cleanup.json](2026-11-06-docs-cleanup.json) | 本次文档整理、归档来源、链接和目录检查；不是玩法复测 |
| [b1-05-development-controls.json](b1-05-development-controls.json) | 开发输入默认关闭、显式启用和发行隔离；本次整理期间新增的并行验证记录 |
| [2026-11-05-layered-mvp.json](2026-11-05-layered-mvp.json) | 分层/MVP首批改造、36套全量与窗口检查、界面替身和异步生命周期 |
| [2026-11-05-resource-safety.json](2026-11-05-resource-safety.json) | 满包命中、动画中存档、免费恢复和连续多日资源供给 |
| [2026-11-05-terrain-v2.json](2026-11-05-terrain-v2.json) | 地表、桥面、坡地与植物占地修正 |
| [2026-11-05-bridge-fences.json](2026-11-05-bridge-fences.json) | 桥梁/围栏相关范围，以报告字段为准 |
| [2026-11-05-animal-motion.json](2026-11-05-animal-motion.json) | 鸡四步循环、镜像与备用动物动画适配 |
| [2026-11-05-path-atlas-fix.json](2026-11-05-path-atlas-fix.json) | 主农场道路图集依赖修复 |
| [2026-11-05-regions.json](2026-11-05-regions.json) | 正式区域、采集掉落、再生与保存 |
| [2026-11-05-layout.json](2026-11-05-layout.json) | 代码/素材目录迁移与引用核对 |
| [latest-assurance.json](latest-assurance.json) | 早期强化编译、退出清理与PCK完整性报告；名称不保证它是时间上最新的一份 |
| [2026-11-04-solid.json](2026-11-04-solid.json) | 首轮SOLID迁移、隔离与扩展契约 |

## 如何判断结果

- 检查命令、引擎、快照、套件、退出码、断言、关键末尾执行、SCRIPT ERROR/引擎错误和泄漏。末尾PASS不能覆盖前面的错误。
- 无窗口逻辑、原生渲染、脚本触发的实际流程、真实键鼠、新玩家观察和发行环境是不同证据，不互相替代。
- 临时绝对路径只是运行时日志位置，可能已清理；仓库内摘要和必要来源仍保留。`docs/screenshots/`默认不入库，需要时通过报告所列工具重建。
- 复测后新增有日期的报告，保留失败及修复适用范围，不将旧结果改成新版本成绩。本次清理保留所有既有JSON原样。
