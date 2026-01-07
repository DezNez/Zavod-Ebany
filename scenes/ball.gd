class_name Ball
extends RigidBody2D

@export var size_level: int = 0
var merged := false
var merge_cooldown := false
var can_trigger_game_over := false

const RADII := [14, 18, 22, 26, 32, 38, 46, 56, 68, 90]
const COLORS := [
	
	Color("#81C784"),
	Color("#FFF176"),
	Color("#FFB74D"),
	Color("#BA68C8"),
	Color("#f06292ff"),
	Color("#4DD0E1"),
	Color("#FFD54F"),
	Color("#7986CB"),
	Color("#E57373"),
	Color("#ff7300ff")
]

func _ready():
	update_size()
	add_to_group("balls")
	contact_monitor = true
	max_contacts_reported = 2
	mass = RADII[size_level] * 1.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	physics_material_override.friction = 0.7
	continuous_cd = RigidBody2D.CCD_MODE_DISABLED

	# твин спавна
	scale = Vector2.ONE * 0.5
	var tw = create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var jitter := Vector2(
		randf_range(-0.5, 0.5),
		0
	)
	apply_impulse(jitter * 8.0)


	# таймер чтобы шарик не триггерил game over сразу
	var t := Timer.new()
	t.wait_time = 0.4
	t.one_shot = true
	t.autostart = true
	add_child(t)
	t.timeout.connect(func():
		can_trigger_game_over = true
		t.queue_free()
	)

func update_size():
	queue_redraw()
	call_deferred("_update_collision")

func _update_collision():
	var r = RADII[size_level]
	var shape := CircleShape2D.new()
	shape.radius = r
	$CollisionShape2D.shape = shape

func _draw():
	var r = RADII[size_level]
	var col = COLORS[size_level]
	var width = 4
	# основной круг (чистый цвет, без прозрачности)
	draw_circle(Vector2.ZERO, r, col)

	# обводка (чуть толще, контрастная)
	draw_circle(Vector2.ZERO, RADII[size_level] - 2, col.darkened(0.4), width)

func _on_body_entered(body):
	if merged:
		return
	if body is Ball:
		try_merge(body)

func try_merge(other: Ball):
	if merge_cooldown:
		return
	if size_level >= RADII.size() - 1:
		return
	if other.merged:
		return
	if other.size_level != size_level:
		return

	merge_cooldown = true
	other.merge_cooldown = true
	merged = true
	other.merged = true

	_start_delayed_merge(other)


func _start_delayed_merge(other: Ball) -> void:
	await get_tree().create_timer(0.02).timeout  # ← вот реальная задержка

	if not is_instance_valid(other):
		return
	if not is_inside_tree():
		return
	
	await get_tree().process_frame
	_merge_with(other)


func _apply_merge_impulse(center: Vector2):
	for b in get_tree().get_nodes_in_group("balls"):
		if b == self:
			continue

		var dist = b.global_position.distance_to(center)
		if dist > 120:
			continue

		var dir = (b.global_position - center).normalized()
		var strength = lerp(80.0, 20.0, dist / 120.0)
		b.apply_impulse(dir * strength)

func _merge_with(other: Ball):
	if not is_instance_valid(other):
		return

	if size_level + 1 >= RADII.size():
		return

	var pos = (global_position + other.global_position) / 2
	var next_level := size_level + 1
	if next_level < COLORS.size():
		_spawn_merge_particles(pos, COLORS[next_level])

	_apply_merge_impulse(pos)

	var new_ball = preload("res://scenes/ball.tscn").instantiate()
	new_ball.size_level = size_level + 1
	new_ball.global_position = pos
	get_tree().current_scene.add_child(new_ball)
	get_tree().current_scene.add_score(size_level)

	# твины мерджа
	var tw = create_tween()
	tw.tween_property(new_ball, "scale", Vector2.ONE * 1.2, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(new_ball, "scale", Vector2.ONE, 0.01).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	queue_free()
	other.queue_free()

func _make_circle_texture(size: int = 16) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in range(size):
		for x in range(size):
			if center.distance_to(Vector2(x + 0.5, y + 0.5)) <= radius:
				img.set_pixel(x, y, Color(1, 1, 1))
	return ImageTexture.create_from_image(img)

# func _spawn_merge_particles(pos: Vector2, color: Color):
# 	var p := CPUParticles2D.new()
# 	p.texture = _make_circle_texture(16)
# 	p.color = color
# 	p.global_position = pos
# 	p.z_index = 0
# 	p.amount = 128
# 	p.lifetime = 0.5
# 	p.one_shot = true
# 	p.explosiveness = 1.0
# 	p.emitting = false
# 	p.direction = Vector2(0, -1)
# 	p.spread = 180
# 	p.initial_velocity_min = 60
# 	p.initial_velocity_max = 140
# 	p.gravity = Vector2(0, 200)
# 	p.scale_amount_min = 0.4
# 	p.scale_amount_max = 0.8
# 	get_tree().current_scene.add_child(p)
# 	p.emitting = true
# 	p.finished.connect(func():
# 		p.queue_free()
# 	)

func _spawn_merge_particles(pos: Vector2, color: Color):
	var p := GPUParticles2D.new()

	# ─── материал ───────────────────────────
	var mat := ParticleProcessMaterial.new()
	mat.color = color
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0

	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 140.0
	mat.gravity = Vector3(0, 200, 0)

	mat.scale_min = 0.4
	mat.scale_max = 0.8

	p.process_material = mat

	# ─── визуал ─────────────────────────────
	p.texture = _make_circle_texture(16)
	p.global_position = pos
	p.z_index = 0

	# ─── эмиссия ────────────────────────────
	p.amount = 128
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false

	get_tree().current_scene.add_child(p)
	p.emitting = true

	# ─── автоудаление ───────────────────────
	p.finished.connect(func():
		p.queue_free()
	)
