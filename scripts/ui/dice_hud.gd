class_name DiceHud
extends Control
## Bandeau des jets de combat, en haut de la carte : on voit le dé lancé (« il a
## fait 2 »), le bonus, la Défense visée, le résultat, puis les dés de dégâts et
## le calcul jusqu'aux dégâts subis. Les dés roulent un instant puis s'arrêtent
## sur les valeurs tirées par l'hôte. Ne bloque jamais le toucher ; les jets
## s'enchaînent (plus vite s'il y en a beaucoup). Le détail reste dans le récit.

const ROLL_TIME := 0.45
const SHOW_TIME := 2.6

## Cartes en attente : [{actor, target, label, attack: {}, damage: {}, heal: {}}]
var _queue: Array = []
var _card := {}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _font: Font
var _font_big: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_font("font", "StrongLabel")
	_font_big = get_theme_font("font", "CodeLabel")
	_rng.randomize()


## Regroupe les jets d'une action par (acteur, cible) et les met en file.
func push_fx(list: Array) -> void:
	var cards := {}
	var order: Array = []
	for f in list:
		var kind := String(f.get("type", ""))
		if kind not in ["roll", "dmg_roll", "heal_roll"]:
			continue
		var key := "%s>%s" % [f.get("token", ""), f.get("target", "")]
		if not cards.has(key):
			cards[key] = {"actor": String(f.get("actor_name", "")), "target": String(f.get("target_name", "")), "label": String(f.get("label", "")),
				"attack": {}, "damage": {}, "heal": {}}
			order.append(key)
		var c: Dictionary = cards[key]
		if String(f.get("label", "")) != "":
			c.label = String(f.label)
		match kind:
			"roll":
				c.attack = f
			"dmg_roll":
				# Plusieurs effets de dégâts : on cumule.
				if c.damage.is_empty():
					c.damage = f.duplicate(true)
				else:
					(c.damage.faces as Array).append_array(f.get("faces", []))
					c.damage.mod = int(c.damage.mod) + int(f.get("mod", 0))
					c.damage.dealt = int(c.damage.dealt) + int(f.get("dealt", 0))
					c.damage.resist = int(c.damage.resist) + int(f.get("resist", 0))
			"heal_roll":
				c.heal = f
	for key in order:
		_queue.append(cards[key])
	if _card.is_empty():
		_next()


func _next() -> void:
	_card = _queue.pop_front() if not _queue.is_empty() else {}
	_t = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if _card.is_empty():
		return
	# File chargée : on accélère pour ne pas prendre de retard sur le combat.
	_t += delta * (1.0 + 0.6 * _queue.size())
	if _t >= SHOW_TIME + 0.3:
		_next()
	queue_redraw()


func _rows() -> int:
	var n := 0
	for k in ["attack", "damage", "heal"]:
		if not (_card.get(k, {}) as Dictionary).is_empty():
			n += 1
	return n


func _draw() -> void:
	if _card.is_empty():
		return
	var alpha := clampf(_t / 0.15, 0.0, 1.0) * clampf((SHOW_TIME + 0.3 - _t) / 0.3, 0.0, 1.0)
	var rows := _rows()
	var w := minf(size.x - 16.0, 420.0)
	var h := 30.0 + rows * 46.0 + 6.0
	var top := 56.0 if size.y > 300 else 8.0
	var rect := Rect2(Vector2((size.x - w) * 0.5, top), Vector2(w, h))
	var bg := OrnateStyle.make(Color(Palette.PANEL_ALT, 0.95 * alpha), Color(Palette.BG_DEEP, 0.95 * alpha), Color(Palette.GOLD_DIM, alpha), Color(Palette.GOLD, 0.8 * alpha), 6, 8)
	draw_style_box(bg, rect)
	var x0 := rect.position.x + 12
	var y := rect.position.y + 20
	var head := "%s  →  %s" % [_card.actor, _card.target] if String(_card.target) != "" and _card.target != _card.actor else String(_card.actor)
	if String(_card.label) != "":
		head += "   ·   " + String(_card.label)
	draw_string(_font, Vector2(x0, y), head, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 15, Color(Palette.GOLD, alpha))
	y += 8
	var settled := _t >= ROLL_TIME
	var atk: Dictionary = _card.attack
	if not atk.is_empty():
		var val := int(atk.d20) if settled else _rng.randi_range(1, 20)
		var outcome := String(atk.get("outcome", "hit"))
		var col := Palette.TEXT
		if settled:
			col = {"crit": Palette.ULT, "hit": Palette.HEAL, "miss": Palette.MUTED, "fumble": Palette.DANGER}.get(outcome, Palette.TEXT)
		_d20(Vector2(x0 + 20, y + 20), 19.0, val, col, alpha)
		var tx := x0 + 48
		var line := "%+d  =  %d   contre Défense %d" % [int(atk.bonus), int(atk.bonus) + val, int(atk.vs)] if settled else "…"
		draw_string(_font, Vector2(tx, y + 18), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Palette.TEXT, alpha))
		if settled:
			var tag: String = {"crit": "CRITIQUE !", "hit": "TOUCHÉ", "miss": "RATÉ", "fumble": "ÉCHEC CRITIQUE"}.get(outcome, "")
			draw_string(_font, Vector2(tx, y + 37), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col, alpha))
		y += 46
	for kind in ["damage", "heal"]:
		var r: Dictionary = _card.get(kind, {})
		if r.is_empty():
			continue
		# Les dégâts apparaissent après le jet d'attaque.
		var show := settled or atk.is_empty()
		var faces: Array = r.get("faces", [])
		var x := x0 + 4
		var shown_faces := faces.slice(0, 8)
		var rolling := (not atk.is_empty() and _t < ROLL_TIME * 1.8) or (atk.is_empty() and not settled)
		for f in shown_faces:
			var v := int(f.value) if not rolling else _rng.randi_range(1, int(f.sides))
			_die(Vector2(x + 15, y + 20), 15.0, int(f.sides), v, Palette.HP if kind == "damage" else Palette.HEAL, alpha)
			x += 34
		if faces.size() > shown_faces.size():
			draw_string(_font, Vector2(x, y + 25), "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(Palette.MUTED, alpha))
			x += 14
		if show and not rolling:
			var parts: PackedStringArray = []
			if int(r.get("mod", 0)) != 0:
				parts.append("%+d" % int(r.mod))
			if r.get("power", false):
				parts.append("×1,5")
			if int(r.get("resist", 0)) > 0:
				parts.append("−%d rés." % int(r.resist))
			var txt := " ".join(parts)
			if kind == "damage":
				txt += ("   =   " if txt != "" else "=  ") + "%d dégâts" % int(r.get("dealt", 0))
			else:
				txt += "   PV rendus"
			draw_string(_font, Vector2(x + 6, y + 25), txt, HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - x - 16, 16, Color(Palette.HP.lightened(0.25) if kind == "damage" else Palette.HEAL, alpha))
		y += 46


## Dé à 20 faces vu de dessus : hexagone et triangle intérieur, valeur au centre.
func _d20(c: Vector2, r: float, value: int, col: Color, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2) * r)
	draw_colored_polygon(pts, Color(col.darkened(0.7), alpha))
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(col, alpha), 2.0, true)
	var tri := PackedVector2Array([c + Vector2(0, -r * 0.62), c + Vector2(r * 0.55, r * 0.34), c + Vector2(-r * 0.55, r * 0.34), c + Vector2(0, -r * 0.62)])
	draw_polyline(tri, Color(col, 0.35 * alpha), 1.0, true)
	_center_text(c, str(value), 17 if value < 10 else 15, Color(Palette.TEXT if value not in [1, 20] else col.lightened(0.3), alpha))


## Autres dés : carré (d6), losange (d8, d10), triangle (d4), pentagone (d12…).
func _die(c: Vector2, r: float, sides: int, value: int, col: Color, alpha: float) -> void:
	var n := 4
	var rot := PI / 4
	match sides:
		4:
			n = 3
			rot = -PI / 2
		8, 10:
			n = 4
			rot = 0.0
		6:
			n = 4
			rot = PI / 4
		_:
			n = 5
			rot = -PI / 2
	var pts := PackedVector2Array()
	for i in n:
		pts.append(c + Vector2.from_angle(TAU * i / n + rot) * r * (1.15 if n == 4 and rot != 0.0 else 1.0))
	draw_colored_polygon(pts, Color(col.darkened(0.72), alpha))
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(col, alpha), 1.5, true)
	_center_text(c + Vector2(0, 2 if n == 3 else 0), str(value), 14, Color(Palette.TEXT, alpha))


func _center_text(c: Vector2, t: String, fs: int, col: Color) -> void:
	var ts := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(_font, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
