#!/bin/sh
# Two networked copies of the game side by side, watching one C-130's hold:
# the host flies it (level, then an orbit), the client's man walks in its
# hold and then stands still. Each window shows the hold from inside, with
# the outside in the corner. Logs and screenshots go to OUT; at the end the
# two machines' view of the passenger is compared second by second.
#
#   tools/holdnet.sh [OUT]          OUT defaults to /tmp/holdnet
#   GODOT=/path/to/Godot tools/holdnet.sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-/tmp/holdnet}"
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/host.log "$OUT"/join.log

"$GODOT" --path . --position 0,40 --resolution 960x600 -- \
	--preset=free:c130 --holdnet=host --holdshots="$OUT" > "$OUT/host.log" 2>&1 &
HOST=$!
# the host has to be listening before the client asks
sleep 12
"$GODOT" --path . --position 970,40 --resolution 960x600 -- \
	--preset=free:c130 --holdnet=join --holdshots="$OUT" > "$OUT/join.log" 2>&1 &
JOIN=$!
wait $JOIN || true
wait $HOST || true

python3 - "$OUT" <<'EOF'
import re, sys
out = sys.argv[1]
pat = re.compile(r'\[holdnet\] (\w+) w=(\d+) t=\s*([\d.]+) (.*?) jet (\S+)\s+(\d+) m/s bank\s*([+-]?\d+) \| passenger (\w+) in hold (\w+) at \((.*?)\)')
def read(name):
    rows = {}
    for line in open(f"{out}/{name}.log", errors="replace"):
        m = pat.search(line)
        if m:
            t = int(m.group(2)) / 1000.0   # wall clock: the two started apart
            xyz = m.group(10)
            pos = None if 'inf' in xyz else tuple(float(v) for v in xyz.split(','))
            rows[t] = dict(phase=m.group(4).strip(), seen=m.group(8) == "seen",
                           inhold=m.group(9) == "true", pos=pos, bank=int(m.group(7)))
    return rows
host, join = read("host"), read("join")
for name in ("host", "join"):
    for line in open(f"{out}/{name}.log", errors="replace"):
        if "done:" in line or "boarded" in line or "SCRIPT ERROR" in line:
            print(f"{name}: {line.strip()}")
print(f"\n{'s':>5} {'host / client':<28} {'client (the man)':<24} {'host (his ghost), then':<24} {'apart':>6}")
# The two log at different moments in each second: the host's track is
# interpolated to the client's timestamps, so walking pace is not counted as
# disagreement.
hk = sorted(t for t in host if host[t]["pos"])
worst = 0.0
t0 = min(join) if join else 0
import bisect
for t in sorted(join):
    j = join[t]
    i = bisect.bisect_left(hk, t)
    if not j["pos"] or i == 0 or i >= len(hk):
        continue
    a, b = hk[i - 1], hk[i]
    if b - a > 1.6:
        continue
    f = (t - a) / (b - a)
    hp = tuple(x + (y - x) * f for x, y in zip(host[a]["pos"], host[b]["pos"]))
    d = sum((x - y) ** 2 for x, y in zip(hp, j["pos"])) ** 0.5
    worst = max(worst, d)
    flag = "" if (host[a]["inhold"] and j["inhold"]) else "  OUT OF THE HOLD"
    hs = "(%.2f, %.2f, %.2f)" % hp
    print(f"{t - t0:5.1f} {host[a]['phase'] + ' / ' + j['phase']:<28} {str(j['pos']):<24} {hs:<24} {d:6.2f}{flag}")
print(f"\nworst disagreement about where he is in the hold: {worst:.2f} m")
print(f"screenshots: {out}/host_*.png, {out}/join_*.png")
EOF
