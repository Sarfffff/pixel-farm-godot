class_name AnimalProfile
extends Resource
## 动物行为配置。计时器和目标点由各自状态机持有，不写进共享资源。

@export var species_id: StringName = &"animal"
@export_range(0.0, 128.0, 0.5) var move_speed: float = 16.0
@export_range(0.0, 256.0, 1.0) var home_radius: float = 40.0
@export_range(0.1, 1.0, 0.05) var vertical_range_scale: float = 0.6
@export_range(0.1, 8.0, 0.1) var arrival_distance: float = 3.0
@export_range(0.1, 30.0, 0.1) var idle_min: float = 0.8
@export_range(0.1, 30.0, 0.1) var idle_max: float = 2.4
## 觅食目前只是停留行为，不扣饲料、不产生物品。
@export_range(0.0, 1.0, 0.05) var graze_chance: float = 0.35
@export_range(0.1, 30.0, 0.1) var graze_min: float = 1.2
@export_range(0.1, 30.0, 0.1) var graze_max: float = 2.5
@export_range(0.1, 5.0, 0.05) var obstacle_wait: float = 0.4
@export var sleeps_at_night: bool = true
@export_range(0, 1439, 1) var sleep_minutes: int = 22 * 60
@export_range(0, 1439, 1) var wake_minutes: int = 6 * 60


func is_sleep_time(game_minutes: int) -> bool:
	if not sleeps_at_night or sleep_minutes == wake_minutes:
		return false
	# 游戏的凌晨采用 24:00–26:00，先折回一天内的分钟数。
	var minute: int = posmod(game_minutes, 24 * 60)
	if sleep_minutes > wake_minutes:
		return minute >= sleep_minutes or minute < wake_minutes
	return minute >= sleep_minutes and minute < wake_minutes
