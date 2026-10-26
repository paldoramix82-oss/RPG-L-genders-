#!/bin/bash
# Compile tous les scripts du projet et affiche les erreurs.
# Usage : GODOT=/chemin/vers/godot tests/check.sh
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . res://tests/check_scripts.tscn 2>&1 | grep -E "SCRIPT ERROR|ÉCHEC|vérifiés|at: GDScript" 
