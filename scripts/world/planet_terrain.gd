class_name PlanetTerrain
extends RefCounted
## The planet's terrain, as the game above asks about it.
##
## The generator lives in `sphere.rs` and this is a way of asking it. It was
## once a second implementation of the same rule written in GDScript, which is
## how a planet ends up disagreeing with its own map: when the sheet moved into
## the extension for speed the two diverged immediately -- one scaled its
## frequencies with the planet's radius and the other did not, and the same seed
## drew a world with nineteen per cent land in one and half a world of islands
## in the other.
##
## There is no theatre and no authored square. One terrain, the whole planet,
## with the roads, aerodromes and town platforms carved into it wherever they
## are laid out -- which is the only part of the old flat world that was ever
## worth keeping, because it was never terrain in the first place.
##
## Sea level is the planet's radius. Everything here is metres above that.

var radius: float

func _init(_p_seed: int, p_radius: float) -> void:
	radius = p_radius

## Height above sea level for a direction from the planet's centre, with the
## roads and aerodromes carved in.
func elevation(d: Vector3) -> float:
	return Sim.native.planet_height(d)

## A batch of them, which is what anything sampling the whole planet wants.
func elevations(dirs: PackedVector3Array) -> PackedFloat32Array:
	return Sim.native.planet_heights(dirs)
