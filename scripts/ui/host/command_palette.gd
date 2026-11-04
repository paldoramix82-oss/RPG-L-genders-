class_name CommandPalette
extends VBoxContainer
## Recherche rapide du MJ (Ctrl + K) : tapez quelques lettres et allez
## directement à une action, un monstre, un objet, un PNJ, une carte, une
## quête ou un réglage, sans fouiller les onglets.
## Entrée : {"title", "kind" (catégorie affichée), "icon", "run": Callable}.

signal done

var entries: Array = []
var _search: LineEdit
var _list: VBoxContainer
var _first: Callable


func _init(list: Array) -> void:
	entries = list
	custom_minimum_size = Vector2(520, 420)
	add_theme_constant_override("separation", 8)
	_search = UIKit.line_edit("", "Que voulez-vous faire ? (ex. : loup, boutique, générer, auberge, Ivo…)")
	_search.text_changed.connect(func(_t): _fill())
	_search.text_submitted.connect(func(_t):
		if _first.is_valid():
			_run(_first))
	add_child(_search)
	var scroll := TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 360
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_fill()
	_search.call_deferred("grab_focus")


## Score de correspondance : début de mot > contenu ; tous les mots tapés doivent apparaître.
static func score(title: String, query: String) -> int:
	var t := title.to_lower()
	var total := 0
	for w in query.to_lower().split(" ", false):
		var i := t.find(w)
		if i < 0:
			return -1
		total += 3 if i == 0 or t[i - 1] in [" ", "'", "(", "-", ":"] else 1
	return total


func _fill() -> void:
	UIKit.clear(_list)
	_first = Callable()
	var q := _search.text.strip_edges()
	var shown: Array = []
	for e in entries:
		var label := "%s %s" % [e.title, e.get("kind", "")]
		var sc := 1 if q == "" else score(label, q)
		if sc >= 0:
			shown.append([sc, e])
	shown.sort_custom(func(a, b): return a[0] > b[0])
	for pair in shown.slice(0, 40):
		var e: Dictionary = pair[1]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   ·   %s" % [e.title, e.get("kind", "")]
		b.custom_minimum_size.y = 40
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_run.bind(e.run))
		_list.add_child(b)
		if not _first.is_valid():
			_first = e.run
	if shown.is_empty():
		_list.add_child(UIKit.label("Aucun résultat.", "MutedLabel", true))


func _run(f: Callable) -> void:
	done.emit()
	f.call()
