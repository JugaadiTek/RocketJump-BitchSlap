extends Node
## MatchState (autoload)
##
## Tiny bit of shared match bookkeeping: registered spawn points, frag
## counts, and a couple of signals the UI can hook into. Deliberately simple
## - this is a starter kit, not a full game mode framework.

signal player_fragged(victim_id: int, killer_id: int, weapon_name: String)
signal score_changed(player_id: int, new_score: int)

var spawn_points: Array[Node3D] = []
var scores: Dictionary = {} # player_id -> int
var registered_players: Dictionary = {} # player_id -> display_name

## get_all_scores() used to rebuild and sort_custom() this list from scratch
## on every call - and Player._physics_process() calls it unconditionally
## every physics tick for the local human's own HUD, whether or not any score
## actually changed since the last tick (measured: ~65-130us/call depending
## on player count, i.e. several ms/s of steady background cost for no
## reason most ticks). Cached here and only rebuilt when something that
## actually affects the result changes.
var _scores_cache: Array[Dictionary] = []
var _scores_dirty: bool = true

## Testing option set on the main menu: everyone starts holding the complete
## arsenal, planet buster included, instead of earning the buster from a pickup.
## Lives here because it has to survive the scene change into the Arena.
var start_with_all_weapons: bool = false

## Aim assist, set from the main menu. Session-only (no disk persistence) -
## strength is 0..1, applied by Weapon._apply_aim_assist() to the local
## human's own shots only (bots already aim precisely).
var aim_assist_enabled: bool = true
var aim_assist_strength: float = 0.5

func register_spawn_point(point: Node3D) -> void:
	if not spawn_points.has(point):
		spawn_points.append(point)

func unregister_spawn_point(point: Node3D) -> void:
	spawn_points.erase(point)

func get_random_spawn_point() -> Node3D:
	if spawn_points.is_empty():
		return null
	return spawn_points[randi() % spawn_points.size()]

## Called once by Arena.gd right after spawning each Player/Bot, so the
## scoreboard can list everyone (even at 0 kills) rather than only players
## who have already scored.
func register_player(player_id: int, display_name: String) -> void:
	registered_players[player_id] = display_name
	_scores_dirty = true

func unregister_player(player_id: int) -> void:
	registered_players.erase(player_id)
	_scores_dirty = true

func report_frag(victim_id: int, killer_id: int, weapon_name: String) -> void:
	if killer_id != -1 and killer_id != victim_id:
		scores[killer_id] = scores.get(killer_id, 0) + 1
		_scores_dirty = true
		score_changed.emit(killer_id, scores[killer_id])
	player_fragged.emit(victim_id, killer_id, weapon_name)

## Score awarded outside the normal one-point-per-frag flow (bounty payouts,
## Planet Killer's 2x-kill bonus) - same score/_scores_dirty bookkeeping as
## report_frag(), just without the frag itself (BountyManager reacts to
## player_fragged for its own logic, it doesn't need another one emitted here).
func add_bonus_score(player_id: int, amount: int) -> void:
	if amount == 0:
		return
	scores[player_id] = scores.get(player_id, 0) + amount
	_scores_dirty = true
	score_changed.emit(player_id, scores[player_id])

func get_score(player_id: int) -> int:
	return scores.get(player_id, 0)

## Sorted highest-first list of {player_id, name, score} for the scoreboard.
## Rebuilt only when registration or a score actually changed (see
## _scores_dirty) instead of on every call.
func get_all_scores() -> Array[Dictionary]:
	if not _scores_dirty:
		return _scores_cache
	_scores_cache = []
	for pid in registered_players:
		_scores_cache.append({
			"player_id": pid,
			"name": registered_players[pid],
			"score": get_score(pid),
		})
	_scores_cache.sort_custom(func(a, b): return a["score"] > b["score"])
	_scores_dirty = false
	return _scores_cache

func reset_scores() -> void:
	scores.clear()
	_scores_dirty = true
