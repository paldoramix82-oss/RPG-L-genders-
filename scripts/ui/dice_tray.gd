class_name DiceTray
extends Control
## Plateau de dés animé : les dés roulent pendant que l'hôte tire le résultat,
## puis s'arrêtent sur les vraies valeurs (le hasard reste calculé par l'hôte).
## Toucher l'écran ferme le plateau.

const ROLL_TIME := 0.9
const SHOW_TIME := 3.5

var _dice: Array = []  # [{sides, value, pos, vel, angle, spin, final}]
var _expr := ""
var _label := ""
var _result := {}
var _time := 0.0
var _waiting := false
var _font: Font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = get_theme_font("font", "CodeLabel")
	_rng.randomize()


## Lance l'animation pour une formule (« 2d6+3 ») en attendant le résultat de l'hôte.
func start(expr: String, label: String = "") -> void:
	_expr = expr
	_label = label
	_result = {}
	_waiting = true
	_time = 0.0
	_dice.clear()
	for spec in _parse(expr):
		for i in mini(spec.count, 6 - _dice.size()):
			_dice.append({
				"sides": spec.sides, "value": _rng.randi_range(1, spec.sides), "final": -1,
				"pos": Vector2(_rng.randf_range(0.1, 0.3), _rng.randf_range(0.3, 0.7)),
				"vel": Vector2(_rng.randf_range(0.9, 1.4), _rng.randf_range(-0.5, 0.5)),
				"angle": _rng.randf() * TAU, "spin": _rng.randf_range(-14, 14),
			})
	if _dice.is_empty():
		_dice.append({"sides": 20, "value": 1, "final": -1, "pos": Vector2(0.2, 0.5), "vel": Vector2(1.2, 0), "angle": 0.0, "spin": 10.0})
	visible = true
	queue_redraw()


## roll : {expr, detail, total, difficulty?, success?} venant du message de l'hôte.
func finish(roll: Dictionary, label: String = "") -> void:
	if not visible:
		start(String(roll.get("expr", "d20")), label)
	_result = roll
	if label != "":
		_label = label
	# Les valeurs affichées sur les dés : celles du détail « [4, 2] + 3 ».
	var values: Array = []
	var detail := String(roll.get("detail", ""))
	var re := RegEx.create_from_string("\\d+")
	var inside := detail.split("]")
	for chunk in inside:
		var open := chunk.find("[")
		if open >= 0:
			for m in re.search_all(chunk.substr(open)):
				values.append(int(m.get_string()))
	for i in _dice.size():
		_dice[i].final = values[i] if i < values.size() else -1
	_waiting = false
	_time = minf(_time, ROLL_TIME)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed and not _waiting:
		visible = false
		accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var rolling := _waiting or _time < ROLL_TIME
	for d in _dice:
		if rolling:
			d.pos += d.vel * delta * 0.5
			if d.pos.x > 0.85 or d.pos.x < 0.15:
				d.vel.x = -d.vel.x * 0.8
			if d.pos.y > 0.75 or d.pos.y < 0.3:
				d.vel.y = -d.vel.y * 0.8
			d.pos = d.pos.clamp(Vector2(0.15, 0.3), Vector2(0.85, 0.75))
			d.angle += d.spin * delta
			d.vel *= 0.985
			if fmod(_time, 0.07) < delta:
				d.value = _rng.randi_range(1, d.sides)
		elif d.final > 0:
			d.value = d.final
			d.angle = lerp_angle(d.angle, 0.0, minf(1.0, delta * 12))
	if _waiting and _time > 6.0:
		_waiting = false  # pas de réponse : on laisse fermer
	if not _waiting and _time > ROLL_TIME + SHOW_TIME:
		visible = false
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.035, 0.05, 0.72))
	var tray := Rect2(size * Vector2(0.08, 0.22), size * Vector2(0.84, 0.6))
	draw_rect(tray.grow(6), Color("2a2118"))
	draw_rect(tray, Color("1f3a2e"))
	draw_rect(tray, Palette.GOLD_DIM, false, 2.0)
	var title := _label if _label != "" else "Jet de dés"
	_center_text(Vector2(size.x * 0.5, tray.position.y - 18), title + "  ·  " + _expr, 18, Palette.GOLD)
	var die_size := clampf(minf(size.x, size.y) * 0.2, 56.0, 120.0)
	for d in _dice:
		var p: Vector2 = tray.position + d.pos * tray.size
		_draw_die(p, die_size, d.sides, d.value, d.angle)
	if not _result.is_empty() and _time >= ROLL_TIME:
		var y := tray.end.y - die_size * 0.2
		_center_text(Vector2(size.x * 0.5, y - 40), str(_result.get("total", "")), 52, Palette.TEXT)
		var line := String(_result.get("detail", ""))
		if _result.has("difficulty"):
			var ok: bool = _result.get("success", false)
			_center_text(Vector2(size.x * 0.5, y + 4), ("RÉUSSITE" if ok else "ÉCHEC") + "  (difficulté %d)" % int(_result.difficulty), 22, Palette.OK if ok else Palette.DANGER)
		else:
			_center_text(Vector2(size.x * 0.5, y + 4), line, 18, Palette.MUTED)
	elif _waiting:
		_center_text(Vector2(size.x * 0.5, tray.end.y + 30), "Les dés roulent…", 16, Palette.MUTED)
	if not _waiting:
		_center_text(Vector2(size.x * 0.5, tray.end.y + 30), "Touchez pour fermer", 14, Palette.FAINT)


func _draw_die(center: Vector2, s: float, sides: int, value: int, angle: float) -> void:
	var pts := PackedVector2Array()
	var corners := 6 if sides >= 12 else (3 if sides == 4 else (4 if sides == 6 else 5))
	if sides == 20:
		corners = 6
	for i in corners:
		var a := angle + TAU * i / corners - PI / 2 + (PI / corners if corners % 2 == 0 else 0.0)
		pts.append(center + Vector2(cos(a), sin(a)) * s * 0.55)
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(5, 7))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.4))
	var body := Color("ece6da") if sides != 20 else Color("c9a96e")
	if sides == 100:
		body = Color("a07cc9")
	draw_colored_polygon(pts, body)
	# Facettes : reflets vers le centre
	for i in corners:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % corners]
		var shade := 0.08 * (i % 3)
		draw_colored_polygon(PackedVector2Array([a, b, center]), Color(0, 0, 0, shade))
	pts.append(pts[0])
	draw_polyline(pts, body.darkened(0.45), 2.0, true)
	_center_text(center + Vector2(0, s * 0.16), str(value), int(s * 0.42), Color("1b1a1f"))


func _center_text(baseline_center: Vector2, text: String, font_size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, baseline_center - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


static func _parse(expr: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("(\\d*)d(\\d+|%)")
	for m in re.search_all(expr.to_lower()):
		var count := int(m.get_string(1)) if m.get_string(1) != "" else 1
		var sides := 100 if m.get_string(2) == "%" else int(m.get_string(2))
		out.append({"count": clampi(count, 1, 6), "sides": clampi(sides, 2, 1000)})
	return out
