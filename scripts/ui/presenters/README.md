# 界面Presenter

Presenter接收组合根注入的模型与View，把查询结果整理为显示快照，将输入意图转交应用服务。容量、收费、生产、换天与保存规则不在这里重写。

| 文件 | 职责与所有权 |
| --- | --- |
| `day_summary_presenter.gd` | 构建睡前标题、按钮和统计；RefCounted由GameSession显式持有 |
| `farm_activities_presenter.gd` | 木箱/钓鱼显示数据、输入转交与提示；Node由GameSession挂入Systems，离树解除全部绑定 |

View只接收 `render(snapshot)` 和发布意图信号。应用服务放对应业务目录；物理、动画和过场适配继续使用Godot节点。统一规则见 `docs/06-架构与开发规范.md` 第3节，隔离替身验证入口为 `tools/check/check_layer_boundaries.gd`。
