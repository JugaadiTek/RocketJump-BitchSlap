extends Node
## BountyManager (autoload)
##
## Bounty state is peer-locally-derived, computed identically on every peer
## from the same events MatchState already relies on (player_fragged,
## score_changed, registered_players) - no bounty-specific networking of its
## own, the same trust model MatchState itself uses (see its own doc comment).
##
## A player's bounty is the sum of every active BountyEntry on them (source ->
## value): "top_N" (Top Players, recomputed continuously), "planet_killer",
## "war_criminal". The number shown on a nametag/panel adds +1 on top of that
## sum for the regular kill point a kill is worth anyway (MatchState.
## report_frag already grants that +1 on every frag) - see get_display_value().
## BountyManager only ever pays out the STACK on top of it (add_bonus_score).

signal bounties_changed

## Rank -> bounty value tables, indexed 0 = 1st place. Non-increasing, per
## design spec. Picked by player_count via _table_for_count().
const TOP_TABLE_2_4: Array[int] = [1]
const TOP_TABLE_5_8: Array[int] = [2, 1]
const TOP_TABLE_9_16: Array[int] = [2, 1, 1]
const TOP_TABLE_17_23: Array[int] = [2, 2, 1, 1]
const TOP_TABLE_24_31: Array[int] = [2, 2, 1, 1, 1]
const TOP_TABLE_32_PLUS: Array[int] = [3, 2, 2, 1, 1]

const TOP_PLAYER_GRACE_SECONDS: float = 120.0

var _match_start_ms: int = 0
var _bounties: Dictionary = {}          # player_id -> {source: String -> value: int}
var _war_criminal_gunship_kills: Dictionary = {}  # player_id -> int

func _ready() -> void:
	MatchState.player_fragged.connect(_on_player_fragged)

## Called by Arena._ready() - BountyManager is an autoload and survives the
## MainMenu -> Arena scene change, so its own _ready() only ever runs once
## per app launch, not once per match. This is the actual "match started".
func start_match() -> void:
	_match_start_ms = Time.get_ticks_msec()
	_bounties.clear()
	_war_criminal_gunship_kills.clear()
	bounties_changed.emit()

func _process(_delta: float) -> void:
	_recompute_top_bounties()

## ---- Top Players ---------------------------------------------------------

func _table_for_count(count: int) -> Array:
	if count < 2:
		return []
	if count <= 4:
		return TOP_TABLE_2_4
	if count <= 8:
		return TOP_TABLE_5_8
	if count <= 16:
		return TOP_TABLE_9_16
	if count <= 23:
		return TOP_TABLE_17_23
	if count <= 31:
		return TOP_TABLE_24_31
	return TOP_TABLE_32_PLUS

## Rebuilds every "top_N" entry from the current scoreboard each frame -
## cheap (scoreboard is already cached/sorted by MatchState) and means rank
## changes show up immediately without any bookkeeping of who held what rank
## last frame.
func _recompute_top_bounties() -> void:
	var changed: bool = false
	for pid in _bounties.keys():
		if _bounties[pid].has("top"):
			_bounties[pid].erase("top")
			if _bounties[pid].is_empty():
				_bounties.erase(pid)
			changed = true

	var elapsed_sec: float = (Time.get_ticks_msec() - _match_start_ms) / 1000.0
	if elapsed_sec >= TOP_PLAYER_GRACE_SECONDS:
		var scores: Array[Dictionary] = MatchState.get_all_scores()
		var table: Array = _table_for_count(scores.size())
		var rank: int = 0
		var i: int = 0
		while i < scores.size() and rank < table.size():
			var tie_count: int = 1
			while i + tie_count < scores.size() and scores[i + tie_count]["score"] == scores[i]["score"]:
				tie_count += 1
			# Ties always take the LOWER of the ranks they span - table values
			# are non-increasing, so that's whichever occupied slot's value is
			# smallest (0/none if the tie runs past the table's last rank).
			var lowest_value: int = table[rank] if rank < table.size() else 0
			for r in range(rank + 1, rank + tie_count):
				var v: int = table[r] if r < table.size() else 0
				lowest_value = mini(lowest_value, v)
			if lowest_value > 0:
				for j in range(i, i + tie_count):
					_set_entry(scores[j]["player_id"], "top", lowest_value)
					changed = true
			rank += tie_count
			i += tie_count

	if changed:
		bounties_changed.emit()

## ---- Planet Killer --------------------------------------------------------

## `shooter_id` blew up a planet with `kill_count` (>=1) kills in the blast -
## called from OrbitalBody.shatter(). Bounty is kills+1, floored at 2.
func report_planet_kill(shooter_id: int, kill_count: int) -> void:
	var value: int = maxi(kill_count + 1, 2)
	_set_entry(shooter_id, "planet_killer", value)
	bounties_changed.emit()

func is_planet_killer(player_id: int) -> bool:
	return _bounties.has(player_id) and _bounties[player_id].has("planet_killer")

## ---- War Criminal ----------------------------------------------------------

## Called (from Gunship) the moment a player's requested artillery burst is
## accepted - applies the bounty the first time, at minimum value, same as
## every subsequent call while it's still just "1 point per 2 kills, min 1".
func report_gunship_strike(player_id: int) -> void:
	if not _war_criminal_gunship_kills.has(player_id):
		_war_criminal_gunship_kills[player_id] = 0
	_recompute_war_criminal(player_id)

func is_war_criminal(player_id: int) -> bool:
	return _bounties.has(player_id) and _bounties[player_id].has("war_criminal")

func _recompute_war_criminal(player_id: int) -> void:
	var kills: int = _war_criminal_gunship_kills.get(player_id, 0)
	var value: int = maxi(kills / 2, 1)
	_set_entry(player_id, "war_criminal", value)
	bounties_changed.emit()

## ---- Kill/frag reactions ---------------------------------------------------

func _on_player_fragged(victim_id: int, killer_id: int, weapon_name: String) -> void:
	if killer_id != -1 and killer_id != victim_id:
		# Planet Killer: kills scored while the bounty is active are worth 2x
		# (report_frag already granted the base +1) and self-escalate the
		# bounty by 1 per kill.
		if is_planet_killer(killer_id):
			MatchState.add_bonus_score(killer_id, 1)
			var cur: int = _bounties[killer_id].get("planet_killer", 2)
			_set_entry(killer_id, "planet_killer", cur + 1)
			bounties_changed.emit()
		# War Criminal: only gunship-attributed kills count toward the ratio.
		if weapon_name == "Artillery Gunship":
			_war_criminal_gunship_kills[killer_id] = _war_criminal_gunship_kills.get(killer_id, 0) + 1
			_recompute_war_criminal(killer_id)

	# Any bounty on the victim pays out to their killer and is cleared - the
	# stacking rule ("sum of all their bounties + 1 for the regular kill
	# point") means the killer's payout here is the SUM only; report_frag
	# already granted the +1 for the kill itself.
	if _bounties.has(victim_id):
		var payout: int = get_total_bounty(victim_id)
		_bounties.erase(victim_id)
		_war_criminal_gunship_kills.erase(victim_id)
		if payout > 0 and killer_id != -1 and killer_id != victim_id:
			MatchState.add_bonus_score(killer_id, payout)
		bounties_changed.emit()

## ---- Queries ---------------------------------------------------------------

func _set_entry(player_id: int, source: String, value: int) -> void:
	if not _bounties.has(player_id):
		_bounties[player_id] = {}
	_bounties[player_id][source] = value

func get_total_bounty(player_id: int) -> int:
	if not _bounties.has(player_id):
		return 0
	var total: int = 0
	for v in _bounties[player_id].values():
		total += v
	return total

## What actually gets shown on a nametag/panel row - the stack plus the
## baseline kill point, per the spec's stacking rule. 0 (no display) for a
## player with no active bounty.
func get_display_value(player_id: int) -> int:
	var total: int = get_total_bounty(player_id)
	return total + 1 if total > 0 else 0

func has_bounty(player_id: int) -> bool:
	return _bounties.has(player_id) and not _bounties[player_id].is_empty()

## Suffix appended to a bountied player's nametag, per the special bounty
## types' own spec ("\nPlanet Killer" / "\nWar Criminal"). Empty if neither.
func get_nametag_suffix(player_id: int) -> String:
	var suffix: String = ""
	if is_planet_killer(player_id):
		suffix += "\nPlanet Killer"
	if is_war_criminal(player_id):
		suffix += "\nWar Criminal"
	return suffix

## Descending-by-value list for the left-side HUD panel:
## [{player_id, name, value}], highest bounty first.
func get_sorted_bounties() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for pid in _bounties.keys():
		var value: int = get_display_value(pid)
		if value <= 0:
			continue
		list.append({
			"player_id": pid,
			"name": MatchState.registered_players.get(pid, "?"),
			"value": value,
		})
	list.sort_custom(func(a, b): return a["value"] > b["value"])
	return list
