extends Node
## MatchState (autoload)
##
## Tiny bit of shared match bookkeeping: registered spawn points, frag
## counts, and a couple of signals the UI can hook into. Deliberately simple
## - this is a starter kit, not a full game mode framework.

signal player_fragged(victim_id: int, killer_id: int, weapon_name: String)
signal score_changed(player_id: int, new_score: int)

var spawn_points: Array[Node3D] = []
var scores: Dictionary = {} # peer_id -> int

func register_spawn_point(point: Node3D) -> void:
	if not spawn_points.has(point):
		spawn_points.append(point)

func unregister_spawn_point(point: Node3D) -> void:
	spawn_points.erase(point)

func get_random_spawn_point() -> Node3D:
	if spawn_points.is_empty():
		return null
	return spawn_points[randi() % spawn_points.size()]

func report_frag(victim_id: int, killer_id: int, weapon_name: String) -> void:
	if killer_id != -1 and killer_id != victim_id:
		scores[killer_id] = scores.get(killer_id, 0) + 1
		score_changed.emit(killer_id, scores[killer_id])
	player_fragged.emit(victim_id, killer_id, weapon_name)

func get_score(player_id: int) -> int:
	return scores.get(player_id, 0)

func reset_scores() -> void:
	scores.clear()
