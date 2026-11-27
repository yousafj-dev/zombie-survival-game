class_name Wallet
extends RefCounted

## The coin wallet. Coins are earned from zombie kills and mission
## bonuses (game_manager.gd) and spent on weapon upgrades in the lobby
## (main_menu.gd). The balance lives in user://settings.cfg under
## wallet/coins — the same file as settings/progress, and every write
## loads the file first so other sections are preserved.
## spend_coins() is check-and-deduct in one load/save, so a purchase can
## never take the balance negative or charge twice for one tap.

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "wallet"
const KEY := "coins"

static func get_coins() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return maxi(0, int(cfg.get_value(SECTION, KEY, 0)))
	return 0

static func add_coins(amount: int) -> int:
	if amount <= 0:
		return get_coins()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var balance := maxi(0, int(cfg.get_value(SECTION, KEY, 0))) + amount
	cfg.set_value(SECTION, KEY, balance)
	cfg.save(SETTINGS_PATH)
	return balance

static func spend_coins(amount: int) -> bool:
	if amount <= 0:
		return true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var balance := maxi(0, int(cfg.get_value(SECTION, KEY, 0)))
	if balance < amount:
		return false
	cfg.set_value(SECTION, KEY, balance - amount)
	cfg.save(SETTINGS_PATH)
	return true
