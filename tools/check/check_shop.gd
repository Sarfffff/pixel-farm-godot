extends SceneTree
## 商店与金币回归：初始金币、买卖结算、金币不足、背包满、面板联动、HUD 同步。
## --headless --path . --script res://tools/check/check_shop.gd

const MAIN_SCENE := "res://scenes/main.tscn"

var _main: Node2D
var _economy: Economy
var _inventory: Inventory
var _shop: Control
var _hud: Control
var _player: CharacterBody2D
var _toolbar: Control
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[shop] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	# 关掉自动读档：测试固定从干净的开局状态出发，不受真实存档影响
	_main.get_node("Systems/Save").autoload_enabled = false
	await process_frame
	await process_frame
	_economy = _main.get_node("Systems/Economy") as Economy
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	_shop = _main.get_node("UI/ShopPanel") as Control
	_hud = _main.get_node("UI/HUD") as Control
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	_toolbar = _main.get_node("UI/Toolbar") as Control

	_check(_economy != null, "economy node exists")
	_check(_economy.coins == Economy.STARTING_COINS, "starting coins")
	_check(_main.get_node_or_null("Farm/World/ShopDoor") != null, "shop door placed in world")
	_check(not _economy.spend(Economy.STARTING_COINS + 1), "cannot spend more than held")
	_check(_economy.coins == Economy.STARTING_COINS, "failed spend leaves coins unchanged")

	# 打开商店：锁输入、收起工具栏
	_shop.set_open(true)
	_check(_shop.visible, "shop opens")
	_check(_player.input_locked, "player locked while shopping")
	_check(not _toolbar.visible, "toolbar hidden while shopping")
	_check(not _shop._rows.is_empty(), "shop rows built")

	var seed_index: int = _find_row(&"carrot_seeds", true)
	var wood_index_before: int = _find_row(&"wood", false)
	_check(seed_index >= 0, "carrot seeds listed for sale")
	_check(wood_index_before < 0, "empty inventory shows no wood for sale")

	# 买种子：扣钱、进背包
	var coins_before: int = _economy.coins
	var seeds_before: int = _inventory.count_of(&"carrot_seeds")
	_shop._trade(seed_index, false)
	_check(_economy.coins == coins_before - 8, "buying seeds costs 8")
	_check(_inventory.count_of(&"carrot_seeds") == seeds_before + 1, "bought seed lands in bag")

	# 卖木材：加钱、出背包
	_inventory.add_item(&"wood", 5)
	_shop._rebuild()
	var wood_index: int = _find_row(&"wood", false)
	_check(wood_index >= 0, "wood listed for sale once owned")
	coins_before = _economy.coins
	_shop._trade(wood_index, false)
	_check(_economy.coins == coins_before + 8, "selling one wood earns 8")
	_check(_inventory.count_of(&"wood") == 4, "sold wood leaves the bag")

	# Shift 整批：一次卖光剩下的木材
	_shop._trade(wood_index, true)
	_check(_inventory.count_of(&"wood") == 0, "shift-click sells the whole stack")
	_check(_economy.coins == coins_before + 8 + 4 * 8, "batch sale pays per unit")

	# 连续 10 次买 1 卖 1：金币只按差价变化，不出现漂移
	_inventory.add_item(&"wood", 10)
	_shop._rebuild()
	seed_index = _find_row(&"carrot_seeds", true)
	wood_index = _find_row(&"wood", false)
	var start_coins: int = _economy.coins
	for round_index in 10:
		# 每笔交易都会重建列表，索引要重新查，否则会点到别的行
		_shop._trade(_find_row(&"carrot_seeds", true), false)
		_shop._trade(_find_row(&"wood", false), false)
	_check(_economy.coins == start_coins, "ten buy/sell rounds keep coins consistent")
	_check(_inventory.count_of(&"wood") == 0, "ten rounds consumed the wood")

	# 金币不足时：不扣钱、不给货、给出提示
	while _economy.coins > 4:
		_economy.spend(mini(_economy.coins - 4, 8))
	_shop._rebuild()
	seed_index = _find_row(&"carrot_seeds", true)
	var seeds_low: int = _inventory.count_of(&"carrot_seeds")
	var coins_low: int = _economy.coins
	_shop._trade(seed_index, false)
	_check(_economy.coins == coins_low, "insufficient coins leave money untouched")
	_check(_inventory.count_of(&"carrot_seeds") == seeds_low, "insufficient coins give no item")
	_check(String(_shop._message.text).contains("金币不足"), "insufficient coins show a hint")

	# HUD 跟随金币
	_economy.earn(25)
	await process_frame
	var amount_label := _hud.get_node("%Amount") as Label
	_check(amount_label.text == str(_economy.coins), "hud shows current coins")

	# 关闭商店：输入与工具栏恢复
	_shop.set_open(false)
	_check(not _shop.visible, "shop closes")
	_check(not _player.input_locked, "input restored after shopping")
	_check(_toolbar.visible, "toolbar restored after shopping")

	# 与背包互斥：商店开着时打开背包，商店自动收起
	_shop.set_open(true)
	var bag := _main.get_node("UI/InventoryPanel") as Control
	bag.call(&"set_open", true)
	_check(not _shop.visible, "opening the bag closes the shop")
	bag.call(&"set_open", false)

	print("[shop] %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_main.queue_free()
	await process_frame
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


## 在商店行里找某个物品；buy=true 找买入列，false 找卖出列。找不到返回 -1。
func _find_row(id: StringName, buy: bool) -> int:
	for index in _shop._rows.size():
		var row: Dictionary = _shop._rows[index]
		if row[&"id"] == id and bool(row[&"buy"]) == buy:
			return index
	return -1
