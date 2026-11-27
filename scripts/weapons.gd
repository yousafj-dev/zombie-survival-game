class_name Weapons
extends RefCounted

## Static weapon data for Phase 1.
## damage      = hit points removed per pellet that connects
## fire_rate   = shots per second
## magazine    = rounds per magazine
## reload_time = seconds to reload
## range       = max shooting distance in metres
## pellets     = pellets per shot (shotgun > 1)
## auto        = true if holding fire keeps shooting
## reserve     = starting spare rounds

const ORDER: Array[String] = ["pistol", "rifle", "shotgun"]

const DATA := {
	"pistol": {
		"name": "Pistol",
		"damage": 12,
		"fire_rate": 3.0,
		"magazine": 12,
		"reload_time": 1.1,
		"range": 40.0,
		"pellets": 1,
		"auto": false,
		"reserve": 60,
	},
	"rifle": {
		"name": "Rifle",
		"damage": 10,
		"fire_rate": 8.0,
		"magazine": 30,
		"reload_time": 1.6,
		"range": 55.0,
		"pellets": 1,
		"auto": true,
		"reserve": 120,
	},
	"shotgun": {
		"name": "Shotgun",
		"damage": 9,
		"fire_rate": 1.1,
		"magazine": 6,
		"reload_time": 2.2,
		"range": 22.0,
		"pellets": 6,
		"auto": false,
		"reserve": 24,
	},
}

static func get_weapon(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistol"])

# --- upgrades --------------------------------------------------------------
## Bought in the lobby with coins (see main_menu.gd / wallet.gd).
## Two stats per gun — damage and fire rate — five levels each.
## Levels persist in user://settings.cfg under upgrades/<id>_<stat>.
## Prices: going from level L to L+1 costs 100 * (L+1) coins.

const MAX_UPGRADE_LEVEL: int = 5
const UPGRADES_PATH := "user://settings.cfg"

static func upgrade_price(current_level: int) -> int:
	return 100 * (current_level + 1)

static func get_upgrade_level(id: String, stat: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(UPGRADES_PATH) == OK:
		return clampi(int(cfg.get_value("upgrades", id + "_" + stat, 0)), 0, MAX_UPGRADE_LEVEL)
	return 0

static func set_upgrade_level(id: String, stat: String, level: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(UPGRADES_PATH)
	cfg.set_value("upgrades", id + "_" + stat, clampi(level, 0, MAX_UPGRADE_LEVEL))
	cfg.save(UPGRADES_PATH)

## Base data with the bought upgrades applied (+20% damage and +10%
## fire rate per level). Combat code uses this, never get_weapon().
static func get_upgraded(id: String) -> Dictionary:
	var d: Dictionary = get_weapon(id).duplicate()
	var damage_level := get_upgrade_level(id, "damage")
	var rate_level := get_upgrade_level(id, "fire_rate")
	d["damage"] = int(round(float(d["damage"]) * pow(1.2, float(damage_level))))
	d["fire_rate"] = float(d["fire_rate"]) * pow(1.1, float(rate_level))
	d["damage_level"] = damage_level
	d["fire_rate_level"] = rate_level
	return d
