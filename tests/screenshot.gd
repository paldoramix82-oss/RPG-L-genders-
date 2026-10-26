extends Node
## Captures d'écran automatiques pour vérifier l'interface (développement).
## Exemples (fenêtre réelle requise, pas --headless) :
##   godot --path . res://tests/screenshot.tscn -- --shot=host --out=/tmp/host.png
##   godot --path . res://tests/screenshot.tscn -- --shot=player --force-mobile --out=/tmp/p.png
## Rôles : menu, host, join, player.

const PORT := 17800


func _ready() -> void:
	var driver := Node.new()
	driver.set_script(load("res://tests/screenshot_driver.gd"))
	get_tree().root.add_child.call_deferred(driver)
