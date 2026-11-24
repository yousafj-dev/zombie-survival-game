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
