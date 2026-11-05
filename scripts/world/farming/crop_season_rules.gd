extends RefCounted
## 纯作物季节规则：不依赖场景、界面或文件。


static func season_at(day: int) -> StringName:
	return TimeSystem.SEASONS[((maxi(1, day) - 1) / TimeSystem.DAYS_PER_SEASON) % 4]


static func should_wither(data: CropData, season: StringName, protected: bool = false) -> bool:
	return data != null and not protected and not data.grows_in(season)


static func information(data: CropData, day: int) -> Dictionary:
	var grow_nights: int = 0
	for stage: int in data.last_stage(): grow_nights += data.days_at_stage(stage)
	var safe_nights: int = -1
	for offset: int in range(1, 113):
		if not data.grows_in(season_at(day + offset)):
			safe_nights = offset - 1
			break
	var in_season: bool = data.grows_in(season_at(day))
	return {"in_season": in_season, "grow_nights": grow_nights, "regrow_nights": data.regrow_days,
		"days_left": 28 - ((maxi(1, day) - 1) % 28), "safe_nights": safe_nights,
		"fits_first_harvest": in_season and (safe_nights < 0 or grow_nights <= safe_nights)}
