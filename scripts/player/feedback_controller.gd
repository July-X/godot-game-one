extends Node
## 表现控制器
##
## 处理行走动画、引擎辉光、无敌闪烁、受击光效。

@onready var _player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _sprite: Sprite2D = _player.get_node("Sprite2D") as Sprite2D if _player.has_node("Sprite2D") else null
@onready var _engine_glow: Sprite2D = _player.get_node("EngineGlow") as Sprite2D if _player.has_node("EngineGlow") else null
@onready var _original_exhaust: Texture2D = _engine_glow.texture if _engine_glow else null

## 关闭后第一档也走原有等级贴图和程序化回退。
const USE_SWIFT_HULL := true
const SWIFT_EXHAUST := "res://assets/sprites/player/swift_exhaust.png"
const DOWNED_HULL := preload("res://scripts/player/downed_hull.gdshader")
var _using_swift := false
var _downed_tween: Tween

var _walk_cycle: float = 0.0
var _invincible_timer: float = 0.0
var _explosion_scene = preload("res://scenes/effects/explosion.tscn")
var _reward_body_cue: Node2D
var _reward_speed_before := -1.0
var _reward_exhaust_boost := 0.0
var _reward_exhaust_tween: Tween


func update(delta: float) -> void:
	_invincible_timer = max(_invincible_timer - delta, 0.0)
	_update_walk_animation(delta)
	_update_invincible_flash()
	_update_engine_breathing(delta)


func update_walk_animation(delta: float) -> void:
	_walk_cycle += delta * 8.0


func reset_pose() -> void:
	if _sprite:
		_sprite.rotation = 0.0
	if _engine_glow:
		_engine_glow.position.y = 32.0


var _breath_timer: float = 0.0
var _base_breath_alpha: float = 0.6
var _glow_base_scale: Vector2 = Vector2(1.45, 1.45)

func _update_engine_breathing(delta: float) -> void:
	if not _engine_glow or not _engine_glow.visible:
		return
	_breath_timer += delta * 2.5
	var breath: float = 0.85 + sin(_breath_timer) * 0.15
	_engine_glow.modulate.a = _base_breath_alpha * breath
	## 呼吸只做轻微的横向涨缩，纵向留给"射速等级越高尾焰越长"，
	## 两者都基于 PLAYER_VISUAL_SCALE，不能写死倍率
	var base: Vector2 = _glow_base_scale
	_engine_glow.scale = Vector2(base.x * breath, base.y)
	if _reward_exhaust_boost > 0.0:
		_engine_glow.modulate.a = minf(_engine_glow.modulate.a + _reward_exhaust_boost * 0.27, 1.0)
		_engine_glow.scale.y *= 1.0 + _reward_exhaust_boost * 0.52

func _update_walk_animation(delta: float) -> void:
	if _player.velocity.length() > 10.0:
		_walk_cycle += delta * 8.0
		var swing: float = sin(_walk_cycle) * 0.02
		var bounce: float = abs(sin(_walk_cycle)) * 0.01
		if _sprite:
			_sprite.rotation = swing
		if _engine_glow:
			_engine_glow.position.y = 32.0 + bounce * 20.0
	else:
		reset_pose()


func _update_invincible_flash() -> void:
	if not _sprite:
		return
	if _invincible_timer > 0 and not _player.is_downed:
		_sprite.modulate.a = 0.3 + abs(sin(_invincible_timer * 20)) * 0.7
	else:
		_sprite.modulate.a = 1.0


func set_downed_visual(active: bool) -> void:
	if active:
		clear_first_boss_reward_visuals()
	if _engine_glow:
		_engine_glow.visible = not active
	if not _sprite:
		return
	if _downed_tween:
		_downed_tween.kill()
		_downed_tween = null
	if not active:
		_sprite.material = null
		_sprite.self_modulate.a = 1.0
		return
	var material := ShaderMaterial.new()
	material.shader = DOWNED_HULL
	_sprite.material = material
	_sprite.self_modulate.a = 0.82
	# 绑定到节点的 Tween 也更新对端幽灵，且退场时随节点释放。
	_downed_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_downed_tween.tween_property(_sprite, "self_modulate:a", 0.52, 0.75)
	_downed_tween.tween_property(_sprite, "self_modulate:a", 0.82, 0.75)


## 本机到账时用两道机翼短光，避免覆盖原机体的受击和队友配色。
func show_first_boss_reward(reward_type: String, previous_value: float) -> void:
	clear_first_boss_reward_visuals()
	if reward_type == "speed" and previous_value >= 0.0 \
			and GameState.get_move_speed_multiplier(_player.peer_id) > previous_value:
		_reward_speed_before = previous_value
	var cue := Node2D.new()
	cue.name = "FirstBossRewardBody"
	cue.modulate.a = 0.15
	cue.scale = Vector2.ONE * 0.9
	_player.add_child(cue)
	_reward_body_cue = cue
	for side: float in [-1.0, 1.0]:
		var strake := Line2D.new()
		strake.points = PackedVector2Array([Vector2(side * 15.0, -16.0), Vector2(side * 31.0, -2.0),
			Vector2(side * 30.0, 11.0), Vector2(side * 21.0, 15.0)])
		strake.width = 2.7
		strake.default_color = Color("#c1f0fc")
		strake.antialiased = true
		cue.add_child(strake)
	var lift := cue.create_tween().set_parallel()
	lift.tween_property(cue, "scale", Vector2.ONE * 1.12, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lift.tween_property(cue, "modulate:a", 0.93, 0.075)
	lift.tween_property(cue, "modulate:a", 0.0, 0.29).from(0.93).set_delay(0.075)
	lift.chain().tween_callback(cue.queue_free)

func has_first_boss_speed_reward() -> bool:
	return _reward_speed_before >= 0.0

func show_first_boss_speed_move() -> void:
	if GameState.get_move_speed_multiplier(_player.peer_id) <= _reward_speed_before:
		return
	_reward_speed_before = -1.0
	_reward_exhaust_boost = 1.0
	_reward_exhaust_tween = create_tween()
	_reward_exhaust_tween.tween_property(self, "_reward_exhaust_boost", 0.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func clear_first_boss_reward_visuals() -> void:
	if is_instance_valid(_reward_body_cue):
		_reward_body_cue.hide()
		_reward_body_cue.queue_free()
		_reward_body_cue = null
	if _reward_exhaust_tween:
		_reward_exhaust_tween.kill()
		_reward_exhaust_tween = null
	if _reward_exhaust_boost > 0.0:
		_reward_exhaust_boost = 0.0
		_update_engine_breathing(0.0)


## ── 外观刷新 ────────────────────────────────────────

func update_appearance() -> void:
	_apply_visual_scale()
	var visual_tier: int = _get_visual_tier()
	var shoot_level: int = GameState.get_shoot_level(_player.peer_id)
	if _sprite:
		var hull: Texture2D
		if USE_SWIFT_HULL and visual_tier == 1:
			# peer_id 属于这艘飞机。加入端也把房主的远端机画成 P1。
			var path := "res://assets/sprites/player/swift_p%d.png" % (1 if _player.peer_id == 1 else 2)
			if ResourceLoader.exists(path):
				hull = load(path)
		_using_swift = hull != null
		_sprite.texture = hull if _using_swift else SpriteFactory.create_player_sprite(visual_tier)
		_apply_peer_tint()
	if _engine_glow:
		_engine_glow.visible = not _player.is_downed
		_engine_glow.position.y = 32.0
		_base_breath_alpha = 0.6 + shoot_level * 0.2
		_engine_glow.modulate = Color(1.0, 0.6, 0.2, _base_breath_alpha)
		_engine_glow.texture = _original_exhaust
		if _using_swift and ResourceLoader.exists(SWIFT_EXHAUST):
			_engine_glow.texture = load(SWIFT_EXHAUST)
			_engine_glow.modulate = Color("#c8b7fa") if _player.peer_id != 1 else Color("#9ef2ff")
		## 尾焰纵向随射速等级变长：给"变强了"一个持续可见的视觉反馈，
		## 比只在属性条上加数字更容易被玩家注意到
		_glow_base_scale = Vector2(PLAYER_VISUAL_SCALE,
			PLAYER_VISUAL_SCALE * (1.0 + shoot_level * 0.06))
		_engine_glow.scale = _glow_base_scale
		if _engine_glow.texture == null:
			var tex_path: String = "res://assets/sprites/ui/engine_flame.png"
			if ResourceLoader.exists(tex_path):
				_engine_glow.texture = load(tex_path)

func _apply_peer_tint() -> void:
	if not _sprite:
		return
	if _using_swift or not NetworkManager.is_online():
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	if _player.peer_id == 1:
		## 房主：偏青蓝
		_sprite.modulate = Color(0.75, 0.95, 1.25, 1.0)
	else:
		## 加入者：偏橙红
		_sprite.modulate = Color(1.25, 0.85, 0.65, 1.0)


func _get_visual_tier() -> int:
	var tier := int((GameState.level - 1) / 5) + 1
	tier = clampi(tier, 1, 5)
	if NetworkManager.is_online() and _player.peer_id != 1:
		tier = maxi(tier - 1, 1)
	return tier


## ── 受击表现 ────────────────────────────────────────

func trigger_hit() -> void:
	_invincible_timer = 1.0
	Pool.spawn_hit(_player.global_position, Pool.Impact.LEGACY)
	_play_hit_animation()
	## 受击是"我错了"的信号：震屏要明显、连击要清零，不能让玩家
	## 挨打了还觉得连击在涨。
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("emit_hit_feedback"):
		scene.emit_hit_feedback(scene.SHAKE_PLAYER_HURT, 0.05, false)
	if SFX.has_method("reset_combo"):
		SFX.reset_combo()


## 飞机在**设计空间**里的视觉放大倍率。
##
## 为什么不是去重画更大的图：项目是 1280×720 设计视口 + viewport 拉伸，
## 64px 源图在 2560 宽的屏幕上本来就占 128 物理像素。把源图重画成 128px，
## 它在视口里照样被缩回 64px 再放大，最终画面与现在**完全一致，零收益**。
## 真正的收益是让飞机在设计空间里就占更大面积。
##
## 关键：只放大 Sprite2D，**不动 CollisionShape2D**（判定半径仍是 12px）。
## 这是弹幕射击的通行做法——"视觉体型大于判定点"，画面更好看也更易读，
## 而玩家的实际受击判定不变，难度没有被偷偷改掉。
const PLAYER_VISUAL_SCALE: float = 1.45


func _apply_visual_scale() -> void:
	if _sprite == null:
		return
	_sprite.scale = Vector2(PLAYER_VISUAL_SCALE, PLAYER_VISUAL_SCALE)
	if _engine_glow != null:
		_engine_glow.scale = Vector2(PLAYER_VISUAL_SCALE, PLAYER_VISUAL_SCALE)


func _play_hit_animation() -> void:
	if not _sprite:
		return
	var base_color: Color = _sprite.modulate
	var base_scale: float = PLAYER_VISUAL_SCALE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_sprite, "modulate", Color(3.0, 3.0, 3.0, 1.0), 0.04)
	tween.tween_property(_sprite, "scale",
		Vector2(base_scale * 1.2, base_scale * 1.2), 0.04)
	tween.tween_callback(func():
		var recover := create_tween().set_parallel(true)
		recover.tween_property(_sprite, "modulate", base_color, 0.12)
		## 受击回弹必须回到放大后的基准倍率，写死 (1,1) 会让飞机缩回原大小
		recover.tween_property(_sprite, "scale",
			Vector2(base_scale, base_scale), 0.12)
	)


func spawn_explosion() -> void:
	var exp = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(exp)
	exp.global_position = _player.global_position
	SFX.play_explosion()


## 闪避残影：冲刺时留一串半透明拷贝，让"我刚才冲过去了"看得见
const DASH_AFTERIMAGE_COUNT: int = 5
var _dash_afterimages: Array[Sprite2D] = []


func trigger_dash() -> void:
	if _sprite == null:
		return
	_dash_afterimages.clear()
	var dir: Vector2 = _player.velocity.normalized()
	if dir.length() < 0.01:
		dir = Vector2.UP
	for i in range(DASH_AFTERIMAGE_COUNT):
		var ghost := Sprite2D.new()
		ghost.texture = _sprite.texture
		ghost.scale = _sprite.scale
		ghost.rotation = _sprite.rotation
		ghost.global_position = _sprite.global_position - dir * float(i) * 16.0
		ghost.modulate = Color(0.5, 0.85, 1.0, 0.55 - float(i) * 0.1)
		ghost.z_index = _sprite.z_index - 1
		get_tree().current_scene.add_child(ghost)
		_dash_afterimages.append(ghost)
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, 0.26)
		tw.tween_callback(ghost.queue_free)


func play_level_up_effect() -> void:
	var tween := create_tween()
	tween.set_loops(3)
	if _sprite:
		tween.tween_property(_sprite, "modulate", Color(1.5, 1.5, 1.5, 1.0), 0.1)
		tween.tween_property(_sprite, "modulate", Color(1, 1, 1, 1.0), 0.1)
		tween.finished.connect(func():
			_apply_peer_tint()
		)
