class_name Biomes
extends RefCounted
## What grows where: the blend of snow, rock, forest, grass, steppe, sand and
## marsh at a point, from its height, slope, latitude and climate, and the colour
## and name that comes to.
##
## Split out of `sim.gd`; reached as `Sim.biomes`.


# ---------------------------------------------------------------- biomes
## Blended biome weights at a spot. Everything that dresses the ground - terrain
## colour, scatter species, density - reads from here so they always agree.
## Written without allocations: this runs a few hundred thousand times during
## terrain generation and a Dictionary per vertex was costing seconds.
const B_SNOW := 0
const B_ROCK := 1
const B_FOREST := 2
const B_GRASS := 3
const B_STEPPE := 4
const B_SAND := 5
const B_MARSH := 6
const NAMES := ["snow", "rock", "forest", "grass", "steppe", "sand", "marsh"]
const COLOURS := [
	Color(0.93, 0.95, 0.98),   # snow
	Color(0.31, 0.28, 0.26),   # rock
	Color(0.13, 0.24, 0.12),   # forest
	Color(0.22, 0.33, 0.15),   # grass
	Color(0.44, 0.41, 0.23),   # steppe
	Color(0.60, 0.55, 0.38),   # sand
	Color(0.19, 0.28, 0.20),   # marsh
]
var _bw := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])

## Fills the shared weight buffer and returns it. Do not hold on to the result.
## `cl` overrides the two climate lookups with values from somewhere else --
## the baked texture the ground shader reads. Only the harness passes it, and it
## is what lets the fidelity of that texture be measured against this, the
## arithmetic both sides share, rather than against a second copy of it.
func weights(x: float, z: float, y_in: float, slope: float,
		cl: Vector2 = Vector2(-1.0, -1.0)) -> PackedFloat32Array:
	# Height above the sea under this point, not the world `y`.
	#
	# The two are the same on a flat world and they are not on a planet: the
	# ground falls away from the middle of the chart, so a fixed place has a
	# different `y` depending on where the chart is centred, and its climate
	# moved with it. Measured, 44 of 120 places came back with a different
	# biome after the chart was moved 150 km. Elevation above the local sea is
	# the same number from any chart.
	var y: float = y_in - Sim.sea_shell(x, z) + Sim.WATER_LEVEL
	# Latitude first, weather second. Without a band running with the map there
	# is no reason for the far north to be colder than the middle, so climate
	# was noise alone and the world had no geography to it — the same patchwork
	# everywhere. `z` is north-south, so this is the only term that can make a
	# pole cold and a middle latitude hot.
	var lat: float = Sim.climate_lat(x, z)
	var band: float = 1.0 - lat * 1.25
	# the dry belts sit either side of the hot middle, the way they do on Earth
	var belt: float = clampf(1.0 - absf(lat - 0.32) * 3.0, 0.0, 1.0)
	# The same pair the ground shader reads, and on the planet the same field:
	# sampled on the chart the climate slides out from under a place whenever
	# the chart moves off it.
	var nt: float = cl.x
	var nm: float = cl.y
	if nt < 0.0 or nm < 0.0:
		if Sim.globe:
			# Their own fields, at their own frequencies.
			#
			# Scaling the *coordinates* by forty and handing them to the flat
			# world's noise -- which carries a frequency of 6.2e-6 -- asks for
			# features a hundred and sixty thousand times too large, and gets
			# back very nearly a constant. The extension bakes the texture with
			# a frequency of forty on the unit sphere, so this has to be the
			# same field or the map and the ground disagree about the weather.
			var cd := Sim.chart_to_dir(x, z)
			nt = (Sim.noise_temp3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
			nm = (Sim.noise_moist3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
		else:
			nt = (Sim.noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
			nm = (Sim.noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
	var temp: float = clampf(band * 0.70 + nt * 0.42
		- clampf((y - 300.0) / 2200.0, 0.0, 1.0) * 0.85
		+ Sim.season_warmth(x, z), 0.0, 1.0)
	var moist: float = clampf(nm
		+ clampf(1.0 - absf(y - Sim.WATER_LEVEL) / 900.0, 0.0, 1.0) * 0.25
		- belt * 0.66, 0.0, 1.0)
	var steep: float = clampf((0.90 - slope) / 0.34, 0.0, 1.0)
	# Snow keyed on height alone, so a polar plain at sea level was grass and
	# the only white in the world was on the mountains. Cold is cold.
	_bw[B_SNOW] = clampf((y - 1500.0) / 700.0, 0.0, 1.0) * (1.0 - steep * 0.7) \
		* clampf(1.0 - temp * 1.4, 0.0, 1.0) + clampf((y - 2400.0) / 500.0, 0.0, 1.0) \
		+ clampf((0.18 - temp) / 0.18, 0.0, 1.0) * 1.6
	_bw[B_ROCK] = steep + clampf((y - 1100.0) / 1400.0, 0.0, 1.0) * 0.5
	_bw[B_FOREST] = clampf(moist * 1.5 - 0.35, 0.0, 1.0) * clampf(temp * 1.6, 0.0, 1.0) \
		* clampf(1.0 - (y - 200.0) / 1500.0, 0.0, 1.0)
	# and grass was drawn so broadly that it won nearly everywhere it was not
	# outright excluded, which is why the map read as one green sheet
	_bw[B_GRASS] = clampf(1.0 - absf(moist - 0.55) * 3.2, 0.0, 1.0) * 0.85 \
		* clampf(1.0 - (y - 400.0) / 1600.0, 0.0, 1.0)
	_bw[B_STEPPE] = clampf(0.62 - moist, 0.0, 1.0) * 1.7 * clampf(temp * 1.3, 0.0, 1.0)
	# Desert wanted moisture under 0.30 *and* temperature over 0.55 at once,
	# which almost never happened: there was no desert anywhere in the world,
	# only the thin band of beach sand along the shore.
	_bw[B_SAND] = clampf(1.0 - absf(y - Sim.WATER_LEVEL) / 26.0, 0.0, 1.0) * 1.4 \
		+ clampf(0.40 - moist, 0.0, 1.0) * clampf(temp - 0.30, 0.0, 1.0) * 7.0
	_bw[B_MARSH] = clampf(moist - 0.72, 0.0, 1.0) * 2.2 \
		* clampf(1.0 - absf(y - Sim.WATER_LEVEL) / 140.0, 0.0, 1.0)
	var total := 0.0
	for i in 7:
		if _bw[i] < 0.0:
			_bw[i] = 0.0
		total += _bw[i]
	if total < 0.001:
		_bw[B_GRASS] = 1.0
		total = 1.0
	for i in 7:
		_bw[i] /= total
	return _bw

func colour(x: float, z: float, y: float, slope: float,
		cl: Vector2 = Vector2(-1.0, -1.0)) -> Color:
	var w := weights(x, z, y, slope, cl)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for i in 7:
		var c: Color = COLOURS[i]
		var k: float = w[i]
		r += c.r * k
		g += c.g * k
		b += c.b * k
	var out := Color(r, g, b)
	# Under the sea. The biome field is a function of height, moisture and
	# slope, and knows nothing about the waterline -- so the seabed came out as
	# grassland, and there was meadow under three hundred metres of water. Sand
	# in the shallows, grading to silt and then to bare rock as it drops away.
	if y < Sim.WATER_LEVEL:
		var deep: float = clampf((Sim.WATER_LEVEL - y) / 150.0, 0.0, 1.0)
		var bed := Color(0.46, 0.42, 0.33).lerp(Color(0.17, 0.18, 0.19), deep)
		out = out.lerp(bed, clampf((Sim.WATER_LEVEL - y) / 10.0, 0.0, 1.0))
	return out

## Dominant biome name, used by the scatter to pick a species.
func kind(x: float, z: float, y: float, slope: float) -> String:
	var w := weights(x, z, y, slope)
	var best := 3
	var bv := -1.0
	for i in 7:
		if w[i] > bv:
			bv = w[i]
			best = i
	return NAMES[best]
