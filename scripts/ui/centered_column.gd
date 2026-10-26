@tool
class_name CenteredColumn
extends Container
## Conteneur qui centre ses enfants horizontalement avec une largeur maximale.
## Sur téléphone il occupe toute la largeur ; sur PC il évite les lignes trop longues.

@export var max_width := 560.0:
	set(value):
		max_width = value
		queue_sort()
@export var side_margin := 16.0:
	set(value):
		side_margin = value
		queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var width := minf(size.x - side_margin * 2.0, max_width)
		var x := (size.x - width) * 0.5
		for child in get_children():
			if child is Control and child.visible:
				fit_child_in_rect(child, Rect2(x, 0, width, size.y))


func _get_minimum_size() -> Vector2:
	var min_size := Vector2.ZERO
	for child in get_children():
		if child is Control and child.visible:
			var m: Vector2 = child.get_combined_minimum_size()
			min_size.x = maxf(min_size.x, m.x)
			min_size.y = maxf(min_size.y, m.y)
	return min_size
