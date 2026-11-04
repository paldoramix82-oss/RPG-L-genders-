class_name ChestEditor
extends VBoxContainer
## Contenu d'un coffre choisi par le MJ : nom, objets précis, or, table de butin.

var content := {}
var _name: LineEdit
var _rows: VBoxContainer
var _gold: SpinBox
var _loot: OptionButton


func _init(t: Dictionary, content_data: Dictionary) -> void:
	content = content_data
	add_theme_constant_override("separation", 6)
	_name = UIKit.line_edit(String(t.get("name", "Coffre")), "Nom du coffre")
	UIKit.field(self, "Nom", _name)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	add_child(UIKit.label("Objets dedans", "StrongLabel"))
	add_child(_rows)
	for it in t.get("chest_items", []):
		_add(String(it.get("item", "")), int(it.get("qty", 1)))
	add_child(UIKit.button("+ Ajouter un objet", "", func(): _add("", 1)))
	_gold = UIKit.spin(int(t.get("chest_gold", 0)), 0, 999999)
	_gold.suffix = "or"
	UIKit.field(self, "Pièces d'or", _gold)
	_loot = OptionButton.new()
	_loot.add_item("Aucun tirage")
	_loot.set_item_metadata(0, "")
	for l in Content.list(content, "loot"):
		_loot.add_item("En plus : butin « %s » tiré au hasard" % l.name)
		_loot.set_item_metadata(_loot.item_count - 1, String(l.id))
		if String(l.id) == String(t.get("loot", "")):
			_loot.select(_loot.item_count - 1)
	add_child(_loot)


func _add(item_id: String, qty: int) -> void:
	var row := HBoxContainer.new()
	var o := ShopEditor.item_picker(content, item_id)
	row.add_child(o)
	var q := UIKit.spin(qty, 1, 999)
	q.prefix = "×"
	row.add_child(q)
	row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
	row.set_meta("get", func(): return {"item": String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "", "qty": int(q.value)})
	_rows.add_child(row)


func collect() -> Dictionary:
	var items: Array = []
	for row in _rows.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("get"):
			var v: Dictionary = row.get_meta("get").call()
			if String(v.item) != "":
				items.append(v)
	return {"name": _name.text, "items": items, "gold": int(_gold.value), "loot": String(_loot.get_item_metadata(_loot.selected)) if _loot.selected >= 0 else ""}
