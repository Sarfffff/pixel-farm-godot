extends RefCounted
## 从注入模型生成只读显示数据；View不读取金币、库存、时钟或活动系统。

var clock: Node
var economy: Economy
var inventory: Inventory
var tomorrow: Callable


func snapshot() -> Dictionary:
	var day: int = clock.day
	var night: bool = clock.is_evening()
	var time: String = clock.clock_text()
	var headline: String = "今日收获 %d 件 · 今日收入 %d 金币\n金币余额 %d" % [inventory.today_collected, economy.today_income, economy.coins]
	var tail: String = "现在 %s，睡一觉到 20:00；晚上再睡才算过完这一天。" % time
	if night: tail = String(tomorrow.call()) if tomorrow.is_valid() else "明天是第 %d 天，作物会按浇水情况生长一阶。" % (day + 1)
	return {
		"title": "第 %d 天结束" % day if night else "第 %d 天 · %s 还没到晚上" % [day, time],
		"button": "睡觉 · 进入第 %d 天" % (day + 1) if night else "小睡到 20:00",
		"lines": headline + "\n\n" + tail,
	}
