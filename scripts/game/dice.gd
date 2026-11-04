class_name Dice
extends RefCounted
## Lancers de dés : « d20 », « 2d6+3 », « 1d20+1d4-1 », « d% ».
## Les lancers officiels sont toujours calculés par le serveur.

const MAX_TERMS := 10
const MAX_DICE := 50
const MAX_SIDES := 1000
const COMMON := [4, 6, 8, 10, 12, 20, 100]


## Renvoie {ok, error, expr, rolls: [{count, sides, sign, values}], modifier, total}.
static func roll(expression: String, rng: RandomNumberGenerator) -> Dictionary:
	var expr := expression.to_lower().replace(" ", "").replace("d%", "d100")
	if expr == "" or expr.length() > 60:
		return {"ok": false, "error": "Formule vide ou trop longue."}
	if expr[0] != "+" and expr[0] != "-":
		expr = "+" + expr
	var regex := RegEx.create_from_string("([+-])(\\d*)(d(\\d+))?")
	var pos := 0
	var rolls: Array = []
	var modifier := 0
	var total := 0
	var normalized := ""
	while pos < expr.length():
		var m := regex.search(expr, pos)
		if m == null or m.get_start() != pos or m.get_string() == m.get_string(1):
			return {"ok": false, "error": "Formule invalide. Exemples : d20, 2d6+3, 1d20-1."}
		pos = m.get_end()
		var sign := 1 if m.get_string(1) == "+" else -1
		if m.get_string(3) != "":
			var count := int(m.get_string(2)) if m.get_string(2) != "" else 1
			var sides := int(m.get_string(4))
			if count < 1 or count > MAX_DICE or sides < 2 or sides > MAX_SIDES:
				return {"ok": false, "error": "Entre 1 et %d dés, de 2 à %d faces." % [MAX_DICE, MAX_SIDES]}
			if rolls.size() >= MAX_TERMS:
				return {"ok": false, "error": "Trop de groupes de dés."}
			var values: Array = []
			for i in count:
				var v := rng.randi_range(1, sides)
				values.append(v)
				total += v * sign
			rolls.append({"count": count, "sides": sides, "sign": sign, "values": values})
			normalized += ("-" if sign < 0 else "+") + "%dd%d" % [count, sides]
		else:
			var n := int(m.get_string(2))
			if n > 10000:
				return {"ok": false, "error": "Modificateur trop grand."}
			modifier += n * sign
			total += n * sign
	if rolls.is_empty():
		return {"ok": false, "error": "Ajoutez au moins un dé (ex. d20)."}
	if modifier != 0:
		normalized += "%+d" % modifier
	return {"ok": true, "expr": normalized.trim_prefix("+"), "rolls": rolls, "modifier": modifier, "total": total}


## « 2d6+3 : [4, 2] +3 = 9 »
static func describe(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r in result.get("rolls", []):
		var values: PackedStringArray = []
		for v in r.values:
			values.append(str(v))
		parts.append(("− " if int(r.sign) < 0 else "") + "[" + ", ".join(values) + "]")
	var text := " ".join(parts)
	var mod := int(result.get("modifier", 0))
	if mod != 0:
		text += " %s %d" % ["+" if mod > 0 else "−", absi(mod)]
	return text
