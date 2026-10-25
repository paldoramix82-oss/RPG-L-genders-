#!/usr/bin/env bash
# Test d'intégration réseau : 1 serveur (MJ) + 4 clients, chacun dans son propre
# processus Godot, qui communiquent réellement en UDP (ENet) sur 127.0.0.1.
#
# Usage : GODOT=/chemin/vers/godot tests/run_net_test.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-17777}"
LOGDIR="${LOGDIR:-$(mktemp -d)}"

run() {
	"$GODOT" --headless --path . res://tests/net_test.tscn -- --role="$1" --port="$PORT" --profile="test_$1" \
		>"$LOGDIR/$1.log" 2>&1
	echo $? >"$LOGDIR/$1.code"
}

run server &
sleep 1.5
for role in alice bob wrongcode mallory; do
	run "$role" &
done
wait

# Scénario 2 : Zoe disparaît sans prévenir (kill -9), puis le MJ termine la partie.
run server2 &
sleep 1.5
run yann &
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=zoe --port="$PORT" --profile=test_zoe >"$LOGDIR/zoe.log" 2>&1 &
ZOE=$!
sleep 4
kill -9 $ZOE 2>/dev/null
wait

# Scénario 3 : fiches, carte, pions, dés, actions et secrets.
run server3 &
sleep 1.5
for role in dana eli; do
	run "$role" &
done
wait

status=0
for role in server alice bob wrongcode mallory server2 yann server3 dana eli; do
	grep -E "^\[$role\]|SCRIPT ERROR|ERROR:" "$LOGDIR/$role.log" | sed "s/^/  /"
	if [ "$(cat "$LOGDIR/$role.code")" != "0" ]; then
		status=1
	fi
done
echo
if [ $status -eq 0 ]; then echo "RÉSULTAT : tous les tests réseau passent."; else echo "RÉSULTAT : échec (journaux : $LOGDIR)"; fi
exit $status
