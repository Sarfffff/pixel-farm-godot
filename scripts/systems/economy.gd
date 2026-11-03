class_name Economy
extends Node
## 金币：唯一的数值来源，HUD 与商店都只读它、通过它改。
##
## 加入 economy 组，任何节点都能 get_first_node_in_group(&"economy") 拿到。

signal changed(coins: int)
## 收入时单独发一次，供 HUD 飘 "+N"。
signal coins_gained(amount: int)

const STARTING_COINS: int = 500

var coins: int = STARTING_COINS
## 今天进账的总额（睡觉后清零），日报用。
var today_income: int = 0


func _ready() -> void:
	add_to_group(&"economy")
	_connect_time.call_deferred()


## 每天开始清零今日收入；时间系统还没就绪时安静跳过。
func _connect_time() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_signal(&"day_started"):
		time.day_started.connect(func(_day: int) -> void: today_income = 0)


func can_afford(cost: int) -> bool:
	return cost >= 0 and cost <= coins


## 扣钱；钱不够时不做任何改动并返回 false。
func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	coins -= cost
	changed.emit(coins)
	return true


## 进账；负数或零直接忽略，避免调用方写错把金币扣掉。
func earn(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	today_income += amount
	coins_gained.emit(amount)
	changed.emit(coins)
