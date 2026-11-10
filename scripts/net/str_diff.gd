class_name StrDiff
extends RefCounted
## Différences compactes entre deux chaînes de même longueur (cases de carte,
## brouillard) et entre deux dictionnaires (décor). Renvoie null quand la
## différence ne vaut pas la peine (longueurs différentes, trop de changements) :
## on envoie alors tout.

const BLOCK := 64


## [[début, texte], …] ou null.
static func diff(old: String, now: String) -> Variant:
	var n := now.length()
	if old.length() != n or n == 0:
		return null
	if old == now:
		return []
	var out: Array = []
	var budget := n / 3
	var used := 0
	var i := 0
	while i < n:
		var len := mini(BLOCK, n - i)
		if old.substr(i, len) == now.substr(i, len):
			i += len
			continue
		# Bloc différent : on cherche précisément les plages changées.
		var end := i + len
		var j := i
		while j < end:
			if old.unicode_at(j) == now.unicode_at(j):
				j += 1
				continue
			var k := j
			while k < end and old.unicode_at(k) != now.unicode_at(k):
				k += 1
			if not out.is_empty() and int(out[-1][0]) + String(out[-1][1]).length() >= j - 4:
				# Plages voisines : on les fusionne.
				var s0 := int(out[-1][0])
				out[-1][1] = now.substr(s0, k - s0)
			else:
				out.append([j, now.substr(j, k - j)])
			used += k - j + 4
			if used > budget:
				return null
			j = k
		i = end
	return out


static func patch(old: String, p: Array) -> String:
	if p.is_empty():
		return old
	var buf := old
	for seg in p:
		if not seg is Array or seg.size() != 2:
			continue
		var at := int(seg[0])
		var txt := String(seg[1])
		if at < 0 or at + txt.length() > buf.length():
			continue
		buf = buf.substr(0, at) + txt + buf.substr(at + txt.length())
	return buf


## {"set": {clé: valeur}, "del": [clés]} ou null (trop de changements).
static func dict_diff(old: Dictionary, now: Dictionary) -> Variant:
	var set := {}
	var del: Array = []
	for k in now:
		if not old.has(k) or old[k] != now[k]:
			set[k] = now[k]
	for k in old:
		if not now.has(k):
			del.append(k)
	if set.size() + del.size() > maxi(32, now.size() / 2):
		return null
	return {"set": set, "del": del}


static func dict_patch(old: Dictionary, p: Dictionary) -> Dictionary:
	var out := old.duplicate()
	for k in p.get("del", []):
		out.erase(k)
	var s: Variant = p.get("set", {})
	if s is Dictionary:
		for k in s:
			out[k] = s[k]
	return out
