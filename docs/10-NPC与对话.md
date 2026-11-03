# NPC 与对话

第一批 NPC 是四个只有待机姿势的角色（商店老板、园艺师、木匠、渔夫），目前只有商店老板接了实际玩法：**对话 → 选「看看今天的货」→ 打开商店**。

## 素材

`assets/generated/characters/npcs_v1/`（生成脚本 `tools/art/prepare_npc_art.gd`）：

| 项 | 说明 |
| --- | --- |
| 图集 | `<id>_directions.png`：128×32，4 帧 32×32，帧序 **down / up / left / right**（见 `catalog.json` 的 `scene_frame_order`） |
| 单帧 | `<id>_down/up/left/right.png`，方便单独取用 |
| 脚底 | 精灵内容底边在 y=24，所以场景里 `offset = Vector2(0, -8)`，与玩家一致 |
| 限制 | 只有待机姿势，没有行走循环 |

## 商店老板

`scenes/npcs/shopkeeper.tscn`：

```
Shopkeeper (Sprite2D, hframes=4, offset(0,-8))
└─ Body (StaticBody2D)
   └─ Feet (CollisionShape2D, 10×6, position (0,-3))
```

- 脚底小碰撞体：玩家撞不过去，也不会挡住身后的木屋
- 老板固定朝下站着（第 0 帧），不根据玩家位置转向 —— 少一层每帧判断，站着守店的姿态也更自然
- 加入 `interactable` 组，和睡觉点共用玩家的「最近可交互对象」逻辑
- `player_in_range` 半径 26px，`hint()` 返回「按 E 和杂货铺老板聊聊」
- `interact()` 打开对话面板，传入说话人、台词与三个选项

## 对话面板

`scenes/ui/dialogue_panel.tscn` + `scripts/ui/dialogue_panel.gd`，做成了通用组件：

```gdscript
panel.open_with("杂货铺老板", "想买点什么？", [
    {&"id": &"shop",  &"text": "看看今天的货"},
    {&"id": &"chat",  &"text": "最近生意怎么样？"},
    {&"id": &"leave", &"text": "先不买了"},
], self)
```

- 选中后回调 owner 的 `on_dialogue_option(id)`：返回非空字符串 → 原地换台词继续聊；返回空串 → 收起对话
- 键盘 `↑↓` 选项、`Enter` 确认、`Esc` / 点空白关闭
- 打开时锁玩家输入、收起工具栏，并与背包 / 商店 / 日报互斥（打开对话会关掉它们，反之亦然）

老板的三个选项：

| 选项 | 行为 |
| --- | --- |
| 看看今天的货 | 关闭对话 → 打开商店面板 |
| 最近生意怎么样？ | 换一句台词「还行，托你的福。多浇点水，收成不会差。」 |
| 先不买了 | 收起对话 |

一个容易踩的坑：老板在 `on_dialogue_option` 里已经自己关掉对话去开商店了，面板收到空返回值时**不能无条件再 close 一次** —— 重复 close 会把工具栏与提示条重新显示出来，盖住商店标题。现在面板会先判断 `visible`。

## 商店入口的变化

- 旧的「门口钱袋子」`shop_stand.tscn/gd` 已删除，`main.tscn` 里不再有 `ShopStand` 节点
- 老板放在 `Farm/World` 下（`(502,160)`），参与 y 排序，站在木屋右侧空地上

## 验收

```powershell
godot --headless --path . --script res://tools/check/check_npcs.gd
godot --headless --path . --script res://tools/check/check_shop.gd
godot --headless --path . --script res://tools/check/smoke_check.gd
```

`check_npcs` 覆盖：4 个角色的 16 张单帧都是 32×32、脚底 24、二值透明、调色板 ≤19 色；四个场景的 `hframes=4`、`offset(0,-8)`、最近邻过滤；主场景里老板存在且**钱袋子已移除**；站在老板前算在范围内、走远失效；对话打开时商店仍关着、选「看货」后商店打开且对话关闭；老板有脚底碰撞体。

## 已知限制

1. 园艺师、木匠、渔夫只有贴图和场景，没有对话与玩法。
2. NPC 不会走动、也不会转身，站着不动、没有作息（后面接时间系统可以做「几点在店里」）。
3. 对话是固定台词，没有分支、好感度、任务。
4. 商店老板没有自己的头像框，对话框只显示名字。
