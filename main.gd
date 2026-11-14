extends Node2D
# SCUTUL DE NEON - tema "Bounce Back"
# Controale: mouse (sau sagetile stanga/dreapta) = rotesti scutul, R = restart

const PLAYER_R := 18.0
const SHIELD_R := 60.0
const ENEMY_RING := 300.0
const MAX_ARC := 100.0   # grade, scutul complet
const MIN_ARC := 30.0    # sub asta = game over

var center := Vector2(640, 360)
var shield_angle := 0.0
var shield_arc := deg_to_rad(MAX_ARC)

var enemies: Array = []   # {angle, dist, base_dist, shoot_t, stun}
var bullets: Array = []   # {pos, vel, reflected}
var score := 0
var game_over := false
var spawn_t := 1.0
var time_alive := 0.0

var shock_active := false
var shock_r := 0.0
var flash := 0.0


func _ready() -> void:
	randomize()
	center = get_viewport_rect().size / 2.0


func restart() -> void:
	enemies.clear()
	bullets.clear()
	score = 0
	game_over = false
	spawn_t = 1.0
	time_alive = 0.0
	shield_arc = deg_to_rad(MAX_ARC)
	shock_active = false
	flash = 0.0


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and game_over:
		restart()
	if not game_over:
		update_game(delta)
	queue_redraw()


func update_game(delta: float) -> void:
	time_alive += delta
	var difficulty: float = 1.0 + time_alive / 40.0

	# --- scutul: urmareste mouse-ul / tastele ---
	var target: float = (get_global_mouse_position() - center).angle()
	shield_angle = lerp_angle(shield_angle, target, 1.0 - exp(-18.0 * delta))
	if Input.is_key_pressed(KEY_LEFT):
		shield_angle -= 5.0 * delta
	if Input.is_key_pressed(KEY_RIGHT):
		shield_angle += 5.0 * delta

	# --- spawn inamici ---
	spawn_t -= delta
	var max_enemies: int = mini(3 + int(time_alive / 20.0), 8)
	if spawn_t <= 0.0 and enemies.size() < max_enemies:
		spawn_t = 2.0
		enemies.append({
			"angle": randf() * TAU,
			"dist": ENEMY_RING + 100.0,
			"base_dist": ENEMY_RING,
			"shoot_t": randf_range(0.5, 2.0),
			"stun": 0.0
		})

	# --- inamici: se misca, trag ---
	for e in enemies:
		e["angle"] += 0.15 * delta
		e["dist"] = move_toward(e["dist"], e["base_dist"], 60.0 * delta)
		if e["stun"] > 0.0:
			e["stun"] -= delta
			continue
		e["shoot_t"] -= delta
		if e["shoot_t"] <= 0.0:
			e["shoot_t"] = randf_range(1.2, 2.5) / difficulty
			var pos: Vector2 = center + Vector2.from_angle(e["angle"]) * e["dist"]
			var dir: Vector2 = (center - pos).normalized()
			bullets.append({"pos": pos, "vel": dir * 170.0 * difficulty, "reflected": false})

	# --- proiectile ---
	var alive_bullets: Array = []
	for b in bullets:
		b["pos"] += b["vel"] * delta
		var keep := true
		var d: Vector2 = b["pos"] - center

		if b["reflected"]:
			# laserul distruge inamicii prin care trece
			for i in range(enemies.size() - 1, -1, -1):
				var epos: Vector2 = center + Vector2.from_angle(enemies[i]["angle"]) * enemies[i]["dist"]
				if b["pos"].distance_to(epos) < 18.0:
					enemies.remove_at(i)
					score += 10
			if d.length() > 800.0:
				keep = false
		else:
			var dist: float = d.length()
			var n: Vector2 = d / maxf(dist, 0.001)
			# PARRY
			if dist <= SHIELD_R + 6.0 and dist >= SHIELD_R - 14.0 and b["vel"].dot(n) < 0.0:
				var diff: float = abs(angle_difference(shield_angle, n.angle()))
				if diff <= shield_arc / 2.0:
					b["reflected"] = true
					b["vel"] = b["vel"].bounce(n) * 2.0   # BOUNCE BACK: viteza x2
					b["pos"] = center + n * (SHIELD_R + 8.0)
					score += 1
			# LOVIT
			if not b["reflected"] and dist < PLAYER_R + 4.0:
				keep = false
				player_hit()
			if dist > 900.0:
				keep = false
		if keep:
			alive_bullets.append(b)
	bullets = alive_bullets

	# --- unda de soc ---
	if shock_active:
		shock_r += 700.0 * delta
		bullets = bullets.filter(func(bb): return bb["reflected"] or (bb["pos"] - center).length() > shock_r)
		if shock_r > 700.0:
			shock_active = false
	flash = maxf(flash - delta * 2.0, 0.0)


func player_hit() -> void:
	shield_arc -= deg_to_rad(18.0)
	flash = 1.0
	shock_active = true
	shock_r = PLAYER_R
	for e in enemies:         # unda de soc ii impinge inapoi
		e["dist"] += 140.0
		e["stun"] = 1.5
	if shield_arc < deg_to_rad(MIN_ARC):
		game_over = true


func _draw() -> void:
	# fundal rosu scurt cand esti lovit
	if flash > 0.0:
		draw_rect(get_viewport_rect(), Color(1, 0.1, 0.1, flash * 0.25))

	# unda de soc
	if shock_active:
		draw_arc(center, shock_r, 0, TAU, 96, Color(1, 0.5, 0.2, 0.7), 4.0)

	# jucator
	draw_circle(center, PLAYER_R + 6.0, Color(0.1, 0.9, 1.0, 0.15))
	draw_circle(center, PLAYER_R, Color(0.2, 1.0, 1.0))

	# scut (cu "glow")
	var a0: float = shield_angle - shield_arc / 2.0
	var a1: float = shield_angle + shield_arc / 2.0
	draw_arc(center, SHIELD_R, a0, a1, 32, Color(0.0, 1.0, 1.0, 0.25), 16.0)
	draw_arc(center, SHIELD_R, a0, a1, 32, Color(0.6, 1.0, 1.0), 5.0)

	# inamici (romburi magenta)
	for e in enemies:
		var p: Vector2 = center + Vector2.from_angle(e["angle"]) * e["dist"]
		var col := Color(1.0, 0.2, 0.8)
		if e["stun"] > 0.0:
			col = Color(0.5, 0.5, 0.5)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -16), p + Vector2(14, 0),
			p + Vector2(0, 16), p + Vector2(-14, 0)]), col)

	# proiectile
	for b in bullets:
		if b["reflected"]:
			var tail: Vector2 = b["pos"] - b["vel"].normalized() * 60.0
			draw_line(tail, b["pos"], Color(1, 1, 0.4, 0.4), 12.0)
			draw_line(tail, b["pos"], Color(1, 1, 1), 5.0)
		else:
			draw_circle(b["pos"], 7.0, Color(1.0, 0.5, 0.2))

	# interfata
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(20, 36), "Scor: %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var lives: int = int((rad_to_deg(shield_arc) - MIN_ARC) / 18.0) + 1
	draw_string(font, Vector2(20, 70), "Scut: " + "■ ".repeat(maxi(lives, 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.5, 1, 1))

	if game_over:
		var sz: Vector2 = get_viewport_rect().size
		draw_string(font, Vector2(0, sz.y / 2 - 20), "GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 64, Color(1, 0.3, 0.3))
		draw_string(font, Vector2(0, sz.y / 2 + 30), "Scor final: %d  -  apasa R pentru restart" % score, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 28, Color.WHITE)
