class_name ShopEditor
extends VBoxContainer
## Boutique d'un marchand (ou du MJ) : objets, prix, stock, part rachetée.

var content := {}
var _rows: VBoxContainer
var _buy: SpinBox
var _open: CheckBox


func _init(shop: Dictionary, content_data: Dictionary, show_open: bool = false) -> void:
	content = content_data
	add_theme_constant_override("separation", 6)
	if show_open:
		_open = CheckBox.new()
		_open.text = "Boutique ouverte (les joueurs peuvent acheter et vendre de n'importe où)"
		_open.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_open.button_pressed = bool(shop.get("open", false))
		add_child(_open)
	_buy = UIKit.spin(int(shop.get("buy_pct", 50)), 0, 100)
	_buy.suffix = "%"
	UIKit.field(self, "Rachète les objets des joueurs à (0 = n'achète rien)", _buy)
	var head := HBoxContainer.new()
	add_child(head)
	for spec in [["Objet", true], ["Prix (or)", false], ["Stock (−1 = ∞)", false]]:
		var l := UIKit.label(spec[0], "MutedLabel")
		if spec[1]:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = 96
		head.add_child(l)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)
	for it in shop.get("items", []):
		_add(String(it.get("item", "")), int(it.get("price", 0)), int(it.get("stock", -1)))
	add_child(UIKit.button("+ Ajouter un objet", "", func(): _add("", -1, -1)))


static func item_picker(content_data: Dictionary, selected: String) -> OptionButton:
	var o := OptionButton.new()
	o.fit_to_longest_item = false
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in Content.list(content_data, "items"):
		o.add_item(String(e.name))
		o.set_item_metadata(o.item_count - 1, String(e.id))
		if String(e.id) == selected:
			o.select(o.item_count - 1)
	return o


func _add(item_id: String, price: int, stock: int) -> void:
	var row := HBoxContainer.new()
	var o := item_picker(content, item_id)
	row.add_child(o)
	var p := UIKit.spin(price if price >= 0 else Shop.price_of(content, item_id if item_id != "" else String(o.get_item_metadata(maxi(o.selected, 0)))), 0, 9999999)
	p.custom_minimum_size.x = 96
	row.add_child(p)
	o.item_selected.connect(func(i): p.value = Shop.price_of(content, String(o.get_item_metadata(i))))
	var s := UIKit.spin(stock, -1, 9999)
	s.custom_minimum_size.x = 96
	row.add_child(s)
	row.add_child(UIKit.button("×", "DangerButton", func(): row.queue_free()))
	row.set_meta("get", func(): return {"item": String(o.get_item_metadata(o.selected)) if o.selected >= 0 else "", "price": int(p.value), "stock": int(s.value)})
	_rows.add_child(row)


func collect() -> Dictionary:
	var items: Array = []
	for row in _rows.get_children():
		if not row.is_queued_for_deletion() and row.has_meta("get"):
			var v: Dictionary = row.get_meta("get").call()
			if String(v.item) != "":
				items.append(v)
	return {"items": items, "buy_pct": int(_buy.value), "open": _open.button_pressed if _open else true, "keep": true}
