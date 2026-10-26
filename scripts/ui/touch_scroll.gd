class_name TouchScroll
extends ScrollContainer
## Zone défilante utilisable au doigt partout : on peut faire glisser la liste même
## en posant le doigt sur un bouton, un champ ou une carte (ce que le
## ScrollContainer de base ne permet pas). Inertie au lâcher.
## Sur PC, la molette et la barre de défilement fonctionnent normalement.

const START_DISTANCE := 12.0
const FRICTION := 4.0

var _index := -1
var _start := Vector2.ZERO
var _tracking := false
var _scrolling := false
var _velocity := 0.0
var _last_time := 0


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Le glisser natif est remplacé par celui de ce script (sinon il serait bloqué
	# par les boutons et les champs).
	scroll_deadzone = 100000


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _index == -1 and get_global_rect().has_point(st.position) and _is_on_top(st.position):
				_index = st.index
				_start = st.position
				_tracking = true
				_scrolling = false
				_velocity = 0.0
		elif st.index == _index:
			_index = -1
			_tracking = false
			# Pas besoin de bloquer ce relâcher : NOTIFICATION_SCROLL_BEGIN a déjà
			# annulé l'appui du bouton touché (comportement de BaseButton).
			_scrolling = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _tracking or sd.index != _index:
			return
		if not _scrolling and absf(sd.position.y - _start.y) > START_DISTANCE:
			_scrolling = true
			# Annule l'appui en cours sur un bouton de la liste.
			propagate_notification(NOTIFICATION_SCROLL_BEGIN)
		if _scrolling:
			var dy := sd.relative.y
			scroll_vertical = int(scroll_vertical - dy)
			var now := Time.get_ticks_msec()
			var dt := maxf(1.0, float(now - _last_time)) / 1000.0
			_last_time = now
			_velocity = lerpf(_velocity, -dy / dt, 0.5)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _scrolling or absf(_velocity) < 5.0:
		return
	scroll_vertical = int(scroll_vertical + _velocity * delta)
	_velocity = lerpf(_velocity, 0.0, minf(1.0, FRICTION * delta))
	var bar := get_v_scroll_bar()
	if scroll_vertical <= 0 or scroll_vertical >= int(bar.max_value - bar.page):
		_velocity = 0.0


## Ignore les touchers quand un calque (plateau de dés, panneau superposé…)
## recouvre l'écran, sauf si cette liste fait partie du calque lui-même.
## Ces calques s'inscrivent dans le groupe « touch_block ».
func _is_on_top(_pos: Vector2) -> bool:
	var blocked := false
	for node in get_tree().get_nodes_in_group("touch_block"):
		if node is CanvasItem and node.is_visible_in_tree():
			if node.is_ancestor_of(self):
				blocked = false
				# Le calque le plus récent (dernier ajouté) prime.
				continue
			blocked = true
	return not blocked
