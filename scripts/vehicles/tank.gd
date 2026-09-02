class_name Tank
extends RigidBody3D
## Main battle tank. Each road wheel is an independent spring/damper contact
## against the terrain field with its own longitudinal and lateral friction, so
## the hull pitches over crests, rolls in turns and the tracks actually drive it
## rather than the body being slid around.

signal died(who)
signal dismount_requested()

const WHEELS_PER_SIDE := 7
const TRACK_HALF := 1.72          # half track width, wheel centreline
const WHEEL_R := 0.42
const TEL_WHEEL_R := 0.72         # a lorry tyre, not a road wheel
const REST := 0.55                # suspension travel at rest
const MAX_SPEED := 18.0           # governed, about 65 km/h
const POWER := 1_100_000.0        # 1500 hp at the sprockets
const DRIVE_MAX := 240000.0       # traction limit, roughly 0.4 g on 62 tonnes
const BRAKE := 420000.0
const ROLL_RESIST := 0.035

const KINDS := {
	"m1a2": {"faction": "usa", "name": "M1A2 Abrams", "class": "mbt", "hull": Color(0.31, 0.33, 0.27),
			 "mass": 62000.0, "hp": 300.0, "power": 1_100_000.0, "top": 18.0, "gun": 520.0,
			 "muzzle": 1580.0, "reload": 6.5, "blast": 11.0},
	"t90": {"faction": "russia", "name": "T-90M Proryv", "class": "mbt", "hull": Color(0.26, 0.30, 0.22),
			"mass": 46000.0, "hp": 250.0, "power": 840_000.0, "top": 16.5, "gun": 560.0,
			"muzzle": 1660.0, "reload": 7.5, "blast": 11.5},
	"type99": {"faction": "china", "name": "ZTZ-99A", "class": "mbt", "hull": Color(0.29, 0.31, 0.26),
			   "mass": 58000.0, "hp": 260.0, "power": 1_000_000.0, "top": 17.5, "gun": 540.0,
			   "muzzle": 1600.0, "reload": 7.0, "blast": 11.0},
	"m109": {"faction": "usa", "name": "M109A7 Paladin", "class": "spg", "hull": Color(0.30, 0.32, 0.26),
			 "mass": 28000.0, "hp": 190.0, "power": 520_000.0, "top": 13.5, "gun": 900.0,
			 "muzzle": 560.0, "reload": 9.0, "blast": 26.0},
	"msta": {"faction": "russia", "name": "2S19 Msta-S", "class": "spg", "hull": Color(0.25, 0.29, 0.21),
			 "mass": 42000.0, "hp": 185.0, "power": 626_000.0, "top": 13.0, "gun": 940.0,
			 "muzzle": 590.0, "reload": 10.0, "blast": 27.0},
	# `muzzle` is the launch speed the ballistic solution is worked out from, and
	# for a rocket it has to stand in for the whole boost -- a rocket is not a
	# shell that leaves at its top speed and coasts. At 420 m/s the arc closes
	# at v^2/g, which is eighteen kilometres, so an M270 could not reach twenty:
	# these are set from the reach the launcher is supposed to have.
	"m270": {"faction": "usa", "name": "M270 MLRS", "class": "mlrs", "hull": Color(0.28, 0.31, 0.25),
			 "mass": 25000.0, "hp": 160.0, "power": 480_000.0, "top": 15.0, "gun": 420.0,
			 "muzzle": 630.0, "reload": 26.0, "blast": 19.0, "salvo": 12, "ripple": 0.55},
	"bm30": {"faction": "russia", "name": "BM-30 Smerch", "class": "mlrs", "hull": Color(0.24, 0.28, 0.20),
			 "mass": 43700.0, "hp": 150.0, "power": 440_000.0, "top": 14.0, "gun": 470.0,
			 "muzzle": 780.0, "reload": 30.0, "blast": 21.0, "salvo": 12, "ripple": 0.6},
	# Transporter erector launchers. These do not shoot: they raise a canister
	# and send a missile, and the missile does the rest. Everything that makes
	# them worth having is in the round, so the vehicle is a chassis and a
	# reload time.
	"tel_kalibr": {"faction": "russia", "name": "Kalibr TEL", "class": "tel", "hull": Color(0.26, 0.29, 0.24),
			 "hp": 130.0, "power": 400_000.0, "top": 16.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 34.0, "blast": 10.0,
			 "missile": "kalibr", "rounds": 4},
	"tel_zircon": {"faction": "russia", "name": "Zircon TEL", "class": "tel", "hull": Color(0.24, 0.26, 0.28),
			 "hp": 130.0, "power": 400_000.0, "top": 16.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 40.0, "blast": 10.0,
			 "missile": "zircon", "rounds": 2},
	"tel_fattah": {"faction": "iran", "name": "Fattah TEL", "class": "tel", "hull": Color(0.34, 0.36, 0.28),
			 "hp": 130.0, "power": 380_000.0, "top": 15.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 46.0, "blast": 10.0,
			 "missile": "fattah", "rounds": 2},
	"tel_khorram": {"faction": "iran", "name": "Khorramshahr TEL", "class": "tel",
			 "hull": Color(0.30, 0.32, 0.26),
			 "hp": 150.0, "power": 470_000.0, "top": 13.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 95.0, "blast": 10.0,
			 "missile": "khorram", "rounds": 1},
	"tel_oreshnik": {"faction": "russia", "name": "Oreshnik TEL", "class": "tel",
			 "hull": Color(0.28, 0.28, 0.26),
			 "hp": 150.0, "power": 460_000.0, "top": 13.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 90.0, "blast": 10.0,
			 "missile": "oreshnik", "rounds": 1},
	# ------------------------------------------------- more of what exists
	# Filling the holes in the order of battle. Britain and France had no
	# artillery of any kind, China had no gun or rocket artillery, and Iran had
	# no tank — so three of the six factions could not put a fire mission on the
	# map at all.
	"challenger2": {"faction": "uk", "name": "Challenger 2", "class": "mbt",
			 "hull": Color(0.30, 0.32, 0.27),
			 "mass": 64000.0, "hp": 290.0, "power": 890_000.0, "top": 16.0, "gun": 540.0,
			 "muzzle": 1600.0, "reload": 7.0, "blast": 11.0},
	"leclerc": {"faction": "france", "name": "AMX-56 Leclerc", "class": "mbt",
			 "hull": Color(0.32, 0.34, 0.28),
			 "mass": 56000.0, "hp": 255.0, "power": 1_100_000.0, "top": 19.0, "gun": 530.0,
			 "muzzle": 1620.0, "reload": 5.5, "blast": 11.0},
	"karrar": {"faction": "iran", "name": "Karrar", "class": "mbt",
			 "hull": Color(0.34, 0.34, 0.26),
			 "mass": 51000.0, "hp": 220.0, "power": 810_000.0, "top": 17.0, "gun": 500.0,
			 "muzzle": 1580.0, "reload": 8.0, "blast": 10.5},
	"as90": {"faction": "uk", "name": "AS-90 Braveheart", "class": "spg",
			 "hull": Color(0.29, 0.31, 0.26),
			 "mass": 45000.0, "hp": 185.0, "power": 490_000.0, "top": 14.0, "gun": 890.0,
			 "muzzle": 570.0, "reload": 9.5, "blast": 26.0},
	# The obvious French gun is the CAESAR, and the CAESAR is a lorry with a
	# howitzer on the back — 79 km/h on road wheels. Built on the tracked hull
	# this class actually models it could only make 9.4 m/s of its own 22, so it
	# is the AUF1 instead, which is tracked and belongs on this chassis.
	"auf1": {"faction": "france", "name": "AUF1 155", "class": "spg",
			 "hull": Color(0.33, 0.34, 0.27),
			 "mass": 42000.0, "hp": 180.0, "power": 500_000.0, "top": 13.5, "gun": 880.0,
			 "muzzle": 600.0, "reload": 8.5, "blast": 26.0},
	"plz05": {"faction": "china", "name": "PLZ-05", "class": "spg",
			 "hull": Color(0.28, 0.30, 0.25),
			 "mass": 35000.0, "hp": 190.0, "power": 520_000.0, "top": 14.0, "gun": 900.0,
			 "muzzle": 580.0, "reload": 9.0, "blast": 26.5},
	"phl03": {"faction": "china", "name": "PHL-03", "class": "mlrs",
			 "hull": Color(0.26, 0.29, 0.24),
			 "mass": 43000.0, "hp": 155.0, "power": 460_000.0, "top": 14.5, "gun": 460.0,
			 "muzzle": 760.0, "reload": 28.0, "blast": 20.0, "salvo": 12, "ripple": 0.58},
	"df21": {"faction": "china", "name": "DF-21D TEL", "class": "tel",
			 "hull": Color(0.27, 0.29, 0.25),
			 "hp": 145.0, "power": 450_000.0, "top": 14.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 85.0, "blast": 10.0,
			 "missile": "zircon", "rounds": 1},
	# ------------------------------------------------ anti-satellite
	# A direct-ascent launcher. It shoots at nothing in the atmosphere: the only
	# thing it can engage is in orbit, and the round is most of a space launch
	# vehicle. One tube, one round, and a very long reload.
	"asat_usa": {"faction": "usa", "name": "GMD-A ASAT launcher", "class": "asat",
			 "hull": Color(0.30, 0.32, 0.28),
			 "hp": 140.0, "power": 430_000.0, "top": 13.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 150.0, "blast": 10.0,
			 "missile": "asat", "rounds": 1, "reach": 700000.0},
	"asat_ru": {"faction": "russia", "name": "Nudol ASAT launcher", "class": "asat",
			 "hull": Color(0.25, 0.28, 0.23),
			 "hp": 140.0, "power": 430_000.0, "top": 13.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 150.0, "blast": 10.0,
			 "missile": "asat", "rounds": 1, "reach": 700000.0},
	"asat_cn": {"faction": "china", "name": "SC-19 ASAT launcher", "class": "asat",
			 "hull": Color(0.27, 0.30, 0.25),
			 "hp": 140.0, "power": 430_000.0, "top": 13.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 150.0, "blast": 10.0,
			 "missile": "asat", "rounds": 1, "reach": 700000.0},
	# ------------------------------------------------------ air defence
	# There have always been surface-to-air batteries shooting at you and no way
	# to be the one doing the shooting. A battery is a lorry with a radar and
	# four rounds on it: it does not lay a gun, it acquires an aircraft and
	# sends a missile, and everything that makes it dangerous is in the round.
	"patriot": {"faction": "usa", "name": "MIM-104 Patriot", "class": "sam",
			 "hull": Color(0.31, 0.33, 0.28),
			 "radar": 78000.0, "hp": 130.0, "power": 400_000.0, "top": 15.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 6.0, "blast": 10.0,
			 "missile": "sam_med", "rounds": 4, "reach": 65000.0},
	"s400": {"faction": "russia", "name": "S-400 Triumf", "class": "sam",
			 "hull": Color(0.26, 0.29, 0.23),
			 "radar": 84000.0, "hp": 135.0, "power": 420_000.0, "top": 15.5, "gun": 400.0,
			 "muzzle": 400.0, "reload": 6.0, "blast": 10.0,
			 "missile": "sam_med", "rounds": 4, "reach": 70000.0},
	"hq9": {"faction": "china", "name": "HQ-9B", "class": "sam",
			 "hull": Color(0.28, 0.30, 0.26),
			 "radar": 74000.0, "hp": 130.0, "power": 410_000.0, "top": 15.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 6.5, "blast": 10.0,
			 "missile": "sam_med", "rounds": 4, "reach": 62000.0},
	"bavar": {"faction": "iran", "name": "Bavar-373", "class": "sam",
			 "hull": Color(0.34, 0.35, 0.27),
			 "radar": 62000.0, "hp": 120.0, "power": 380_000.0, "top": 14.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 8.0, "blast": 10.0,
			 "missile": "sam_med", "rounds": 3, "reach": 52000.0},
	"skysabre": {"faction": "uk", "name": "Sky Sabre", "class": "sam",
			 "hull": Color(0.30, 0.32, 0.27),
			 "radar": 54000.0, "hp": 115.0, "power": 380_000.0, "top": 16.0, "gun": 400.0,
			 "muzzle": 400.0, "reload": 5.5, "blast": 10.0,
			 "missile": "sam_med", "rounds": 4, "reach": 45000.0},
	"sampt": {"faction": "france", "name": "SAMP/T Mamba", "class": "sam",
			 "hull": Color(0.32, 0.33, 0.28),
			 "radar": 70000.0, "hp": 125.0, "power": 390_000.0, "top": 15.5, "gun": 400.0,
			 "muzzle": 400.0, "reload": 6.0, "blast": 10.0,
			 "missile": "sam_med", "rounds": 4, "reach": 58000.0},
	# ------------------------------------------------ infantry fighting vehicles
	# The gap between a 4x4 and sixty-two tonnes of tank. An autocannon rather
	# than a main gun: it fires fast, it will not trouble frontal armour, and it
	# ruins anything softer.
	"bradley": {"faction": "usa", "name": "M2A3 Bradley", "class": "ifv",
			 "hull": Color(0.31, 0.33, 0.27),
			 "hp": 160.0, "power": 447_000.0, "top": 18.0, "gun": 95.0,
			 "muzzle": 1100.0, "reload": 0.42, "blast": 4.5},
	"bmp3": {"faction": "russia", "name": "BMP-3", "class": "ifv",
			 "hull": Color(0.26, 0.30, 0.22),
			 "hp": 145.0, "power": 373_000.0, "top": 19.0, "gun": 105.0,
			 "muzzle": 1050.0, "reload": 0.46, "blast": 5.0},
	"zbd04": {"faction": "china", "name": "ZBD-04A", "class": "ifv",
			 "hull": Color(0.28, 0.31, 0.25),
			 "hp": 150.0, "power": 440_000.0, "top": 18.5, "gun": 100.0,
			 "muzzle": 1070.0, "reload": 0.45, "blast": 4.8},
	"warrior": {"faction": "uk", "name": "Warrior FV510", "class": "ifv",
			 "hull": Color(0.30, 0.32, 0.27),
			 "hp": 155.0, "power": 410_000.0, "top": 17.5, "gun": 90.0,
			 "muzzle": 1080.0, "reload": 0.44, "blast": 4.4},
	"vbci": {"faction": "france", "name": "VBCI", "class": "ifv",
			 "hull": Color(0.32, 0.34, 0.28),
			 "hp": 140.0, "power": 405_000.0, "top": 20.0, "gun": 88.0,
			 "muzzle": 1090.0, "reload": 0.44, "blast": 4.3},
	"boragh": {"faction": "iran", "name": "Boragh", "class": "ifv",
			 "hull": Color(0.34, 0.35, 0.26),
			 "hp": 120.0, "power": 330_000.0, "top": 17.0, "gun": 78.0,
			 "muzzle": 1000.0, "reload": 0.50, "blast": 4.0},
	# ------------------------------------------- self propelled anti-aircraft
	# Short range air defence with a gun rather than a round. Nothing else on
	# the field can touch a helicopter at two kilometres.
	"avenger": {"faction": "usa", "name": "M-SHORAD Stryker", "class": "spaag",
			 "hull": Color(0.31, 0.33, 0.28),
			 "radar": 16000.0, "sam_rounds": 8, "sam_reach": 9000.0, "sam_missile": "manpads", "hp": 120.0, "power": 260_000.0, "top": 26.0, "gun": 70.0,
			 "muzzle": 1100.0, "reload": 0.10, "blast": 3.0, "reach": 4000.0},
	"shilka": {"faction": "russia", "name": "ZSU-23-4 Shilka", "class": "spaag",
			 "hull": Color(0.26, 0.29, 0.23),
			 "radar": 11000.0, "sam_rounds": 4, "sam_reach": 5500.0, "sam_missile": "manpads", "hp": 110.0, "power": 205_000.0, "top": 14.0, "gun": 55.0,
			 "muzzle": 970.0, "reload": 0.06, "blast": 2.4, "reach": 2600.0},
	"gepard": {"faction": "france", "name": "Gepard 1A2", "class": "spaag",
			 "hull": Color(0.32, 0.33, 0.28),
			 "radar": 18000.0, "sam_rounds": 6, "sam_reach": 8000.0, "sam_missile": "manpads", "hp": 135.0, "power": 610_000.0, "top": 18.0, "gun": 90.0,
			 "muzzle": 1200.0, "reload": 0.11, "blast": 3.4, "reach": 5500.0},
	"pgz09": {"faction": "china", "name": "PGZ-09", "class": "spaag",
			 "hull": Color(0.28, 0.30, 0.25),
			 "radar": 17000.0, "sam_rounds": 6, "sam_reach": 8000.0, "sam_missile": "manpads", "hp": 130.0, "power": 520_000.0, "top": 16.0, "gun": 85.0,
			 "muzzle": 1150.0, "reload": 0.11, "blast": 3.2, "reach": 5000.0},
	# ------------------------------------------------------- light 4x4s
	# Protected patrol vehicles. Not armour: a chassis, a crew cab, four coil
	# sprung wheels that steer, and whatever is bolted to the roof. They are
	# here to move about quickly and to get somewhere a tank cannot, and they
	# lose any argument with something that has a gun on it.
	"humvee": {"faction": "usa", "name": "M1151 HMMWV", "class": "lav",
			 "hull": Color(0.33, 0.35, 0.29),
			 "hp": 70.0, "power": 142_000.0, "top": 31.0, "gun": 34.0, "reach": 1800.0,
			 "muzzle": 890.0, "reload": 0.0, "blast": 0.0,
			 "mass": 5400.0,
			 "mg_rate": 0.11, "mg_damage": 34.0,
			 "chassis": {"len": 4.90, "wide": 2.20, "tall": 1.42, "wb": 3.30,
					 "track": 0.92, "r": 0.47, "mount": "ring"}},
	"jackal": {"faction": "uk", "name": "Jackal 2 MWMIK", "class": "lav",
			 "hull": Color(0.42, 0.38, 0.27),
			 "hp": 62.0, "power": 138_000.0, "top": 36.0, "gun": 32.0, "reach": 1800.0,
			 "muzzle": 890.0, "reload": 0.0, "blast": 0.0,
			 "mass": 7100.0,
			 "mg_rate": 0.10, "mg_damage": 32.0,
			 "chassis": {"len": 5.40, "wide": 2.10, "tall": 1.28, "wb": 3.05,
					 "track": 0.90, "r": 0.52, "mount": "open"}},
	"vbl": {"faction": "france", "name": "Panhard VBL", "class": "lav",
			 "hull": Color(0.29, 0.32, 0.28),
			 "hp": 78.0, "power": 71_000.0, "top": 26.0, "gun": 28.0, "reach": 1600.0,
			 "muzzle": 860.0, "reload": 0.0, "blast": 0.0,
			 "mass": 4000.0,
			 "mg_rate": 0.12, "mg_damage": 28.0,
			 "chassis": {"len": 3.95, "wide": 2.02, "tall": 1.58, "wb": 2.50,
					 "track": 0.84, "r": 0.45, "mount": "ring"}},
	"tigr": {"faction": "russia", "name": "GAZ-2330 Tigr", "class": "lav",
			 "hull": Color(0.27, 0.30, 0.23),
			 "hp": 76.0, "power": 153_000.0, "top": 35.0, "gun": 34.0, "reach": 1800.0,
			 "muzzle": 890.0, "reload": 0.0, "blast": 0.0,
			 "mass": 7800.0,
			 "mg_rate": 0.11, "mg_damage": 34.0,
			 "chassis": {"len": 5.70, "wide": 2.30, "tall": 1.55, "wb": 3.30,
					 "track": 0.96, "r": 0.50, "mount": "ring"}},
	"mengshi": {"faction": "china", "name": "CSK-131 Mengshi", "class": "lav",
			 "hull": Color(0.28, 0.31, 0.26),
			 "hp": 74.0, "power": 160_000.0, "top": 37.0, "gun": 32.0, "reach": 1800.0,
			 "muzzle": 890.0, "reload": 0.0, "blast": 0.0,
			 "mass": 7500.0,
			 "mg_rate": 0.11, "mg_damage": 32.0,
			 "chassis": {"len": 5.05, "wide": 2.12, "tall": 1.60, "wb": 3.20,
					 "track": 0.92, "r": 0.48, "mount": "ring"}},
	"safir": {"faction": "iran", "name": "Safir 4x4", "class": "lav",
			 "hull": Color(0.38, 0.37, 0.26),
			 "hp": 48.0, "power": 78_000.0, "top": 30.0, "gun": 24.0, "reach": 1500.0,
			 "muzzle": 840.0, "reload": 0.0, "blast": 0.0,
			 "mass": 2400.0,
			 "mg_rate": 0.13, "mg_damage": 24.0,
			 "chassis": {"len": 3.80, "wide": 1.74, "tall": 1.24, "wb": 2.40,
					 "track": 0.78, "r": 0.42, "mount": "open"}},
}

var kind := "m1a2"
var team := 0
var health := 260.0
var alive := true
var occupied := false

# driver inputs
var in_throttle := 0.0            # -1 reverse .. +1 forward
var in_steer := 0.0               # -1 left .. +1 right
var in_brake := false
var turret_yaw := 0.0             # desired, world relative
var turret_pitch := 0.0

var speed := 0.0
var _turret: Node3D
var _wrecked := false
var _burn := 0.0
var _fire: GPUParticles3D
var _wreck_smoke: GPUParticles3D
var _mantlet: Node3D
var _muzzle: Node3D
## Something left the vehicle. The weapon camera rides whatever comes out of
## this; only aircraft and ships had it, so a launcher's round had nothing to
## follow and the view stayed on the lorry.
signal store_released(node)

var _road_wheels: Array = []
# ---------------------------------------------------------------- running gear
# Set from the vehicle's class in setup(). These were constants tuned for a
# tracked hull, which is why a launcher on lorry tyres arrived on the ground and
# bounced: it was sprung for sixty-two tonnes and damped at a fifth of critical.
var _travel := REST               # suspension travel, metres
var _damp := 0.75                 # damping ratio of the whole hull on its springs
var _skid := true                 # tracks steer by braking one side
## Lateral bite. NOT how hard a track holds — how hard it resists being dragged
## sideways, which is the thing a skid-steered vehicle has to overcome to turn
## at all. A tracked vehicle yaws by shearing both contact patches across the
## ground, and the classic condition for it is that the thrust difference
## between the tracks beats mu*W*L/(4*B).
##
## For an M1A2 -- 62 tonnes, 4.6 m of track on the ground, 3.44 m gauge -- that
## is 488 kN at the 2.4 this used to be, against the 240 kN the drivetrain can
## actually produce. The vehicle was over-constrained by a factor of two: it
## could not turn, and no amount of stick was ever going to make it. Measured,
## a tank at road speed swept five to nine degrees in five seconds of full lock.
##
## Real track-on-ground lateral resistance is 0.5 to 0.7. At 0.85 the same tank
## needs 173 kN, which it has, and it will still sit on a forty degree side
## slope without sliding.
var _mu_lat := 0.85
var _mu_roll := 1.5
var _yaw_damp := 2.4              # resistance to the hull spinning up on its own
var _max_steer := 0.0             # steered road wheels, radians
var _steer := 0.0                 # where they are now
var _drive_max := DRIVE_MAX
var _brake_max := BRAKE
var _wheel_r := WHEEL_R           # the radius the visual spin is worked out from
## Where a launcher's canisters sit, so a round leaves from inside one.
var _tube_lanes: Array = []
var _tube_len := 3.0
var _tube_rise := 0.9      # {node, side, index, rest_y, spin}
var _wheel_spin := 0.0
var rounds_left := 1              # rounds on the rails, refilled on resupply
## A gun vehicle's missiles, counted separately: `rounds_left` belongs to the
## cannon and is refilled every time the breech clears, which is exactly what a
## magazine must not do.
var sam_left := 0
var bounds := AABB()              # local model extents, for hull_distance()
var sel_weapon := 0               # 0 main gun, 1 coax
var laying := false               # laid on? false once the piece is on target
var _gun_cd := 0.0
var cam: Camera3D
var gunner := false
var aim_yaw := 0.0
var aim_pitch := 0.0
var _cam_yaw := 0.0
var last_solution := {}
var _aim_cache := Vector3.ZERO
var _aim_cache_key := Vector3.ZERO
var _aim_cache_map := Vector3.INF
var _aim_cache_t := 0
## A point picked off the map overrides the barrel line.
var map_target := Vector3.INF
## Indirect pieces are laid by bearing and range. Trying to place a crosshair on
## distant ground with a barrel that only depresses a few degrees is hopeless:
## a tenth of a degree is a kilometre of range.
var arty_range := 4000.0
var _coax_cd := 0.0

func setup(t := 0, k := "m1a2") -> void:
	team = t
	kind = k if KINDS.has(k) else "m1a2"
	var kd: Dictionary = KINDS[kind]
	health = float(kd["hp"])
	# a launcher carries canisters, not a salvo of rockets
	rounds_left = int(kd.get("rounds", kd.get("salvo", 1)))
	sam_left = int(kd.get("sam_rounds", 0))
	# A launcher is a lorry with a canister on it, not a main battle tank. At a
	# tank's 62 tonnes the suspension had to be wound up to hold it, and every
	# bump then threw it.
	match vclass():
		"tel":
			mass = 34000.0
			inertia = Vector3(90000.0, 110000.0, 34000.0)
			# Long travel on soft coils, but damped like a lorry rather than
			# left to oscillate: this is the vehicle that arrived on the ground
			# and pogoed for five seconds.
			_travel = 0.34
			_damp = 0.95
			_skid = false
			_mu_lat = 1.15
			_mu_roll = 1.05
			_yaw_damp = 0.45
			_max_steer = deg_to_rad(32.0)
			_drive_max = 130000.0
			_brake_max = 220000.0
			_wheel_r = TEL_WHEEL_R
		"asat":
			mass = 42000.0
			inertia = Vector3(120000.0, 145000.0, 42000.0)
			_travel = 0.34
			_damp = 0.95
			_skid = false
			_mu_lat = 1.15
			_mu_roll = 1.05
			_yaw_damp = 0.45
			_max_steer = deg_to_rad(30.0)
			_drive_max = 120000.0
			_brake_max = 220000.0
			_wheel_r = TEL_WHEEL_R
		"sam":
			# A battery is the same lorry a launcher is, carrying rounds
			# instead of a canister.
			mass = 30000.0
			inertia = Vector3(80000.0, 96000.0, 30000.0)
			_travel = 0.34
			_damp = 0.95
			_skid = false
			_mu_lat = 1.15
			_mu_roll = 1.05
			_yaw_damp = 0.45
			_max_steer = deg_to_rad(32.0)
			_drive_max = 120000.0
			_brake_max = 200000.0
			_wheel_r = TEL_WHEEL_R
		"ifv", "spaag":
			# Tracked, but half a tank: it accelerates and turns far better and
			# it will not survive being shot at by one.
			mass = 30000.0
			inertia = Vector3(58000.0, 68000.0, 29000.0)
			_travel = 0.46
			_damp = 0.80
			_mu_lat = 0.85
			_yaw_damp = 1.6
			_drive_max = 150000.0
			_brake_max = 260000.0
		"lav":
			var ch: Dictionary = KINDS[kind].get("chassis", {})
			mass = float(KINDS[kind].get("mass", 5400.0))
			inertia = Vector3(mass * 0.55, mass * 0.62, mass * 0.24)
			_travel = 0.30
			_damp = 0.80
			_skid = false
			_mu_lat = 1.30
			_mu_roll = 1.25
			_yaw_damp = 0.25
			_max_steer = deg_to_rad(34.0)
			_drive_max = mass * 6.4
			_brake_max = mass * 9.0
			_wheel_r = float(ch.get("r", 0.47))
		_:
			# Tracked: a main battle tank, a howitzer or a rocket launcher — and
			# they are not all the same size. Every one of them was 62 tonnes,
			# which is an Abrams; an M109 is 28 and an M270 is 25. Carrying an
			# MBT's weight on half an MBT's power is why the artillery could not
			# skid-steer even once the lateral resistance was right: the thrust
			# difference needed scales with the weight, and they did not have
			# it. Inertia follows the mass rather than staying fixed too.
			mass = float(KINDS[kind].get("mass", 62000.0))
			var f: float = mass / 62000.0
			inertia = Vector3(120000.0, 140000.0, 60000.0) * f
			_mu_lat = 0.85
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# A launcher is nearly twice the length of a tank and sits higher on its
	# wheels; giving it a tank's box had it resting on a hull that was not
	# where its body is.
	match vclass():
		"tel":
			box.size = Vector3(3.2, 2.6, 13.4)
		"asat":
			box.size = Vector3(3.4, 2.8, 15.2)
		"sam":
			box.size = Vector3(3.1, 2.5, 11.4)
		"ifv", "spaag":
			box.size = Vector3(3.3, 1.9, 6.6)
		"lav":
			var cb: Dictionary = KINDS[kind].get("chassis", {})
			box.size = Vector3(float(cb.get("wide", 2.2)), float(cb.get("tall", 1.4)),
				float(cb.get("len", 4.9)))
		_:
			box.size = Vector3(3.7, 2.0, 7.9)
	shape.shape = box
	add_child(shape)
	_build()
	_cache_bounds()
	add_to_group("hittable")
	add_to_group("vehicles")
	# An air defence vehicle carries its own search set — the battery has the
	# panel modelled on the back of it — so it contributes to what its side can
	# see, the same way an early warning aircraft does.
	if float(KINDS[kind].get("radar", 0.0)) > 0.0:
		add_to_group("air_radar")
	add_to_group("boardable")
	cam = Camera3D.new()
	cam.far = 45000.0
	cam.near = 0.15
	cam.fov = 70.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)

# --------------------------------------------------------------------------
func _build() -> void:
	var body := MeshKit.panelled(KINDS[kind]["hull"], 0.92, 0.10, 1.1)
	var dark := MeshKit.mat(Color(0.11, 0.11, 0.12), 0.85, 0.2)

	var st := MeshKit.begin()
	if vclass() == "tel" or vclass() == "asat":
		_build_tel_chassis(st, body, dark)
		return
	if vclass() == "lav":
		_build_light_chassis(st, body, dark)
		return
	if vclass() == "sam":
		_build_battery(st, body, dark)
		return
	# lower hull, glacis and side skirts. An infantry vehicle and a gun tank
	# share the running gear but not the size of it: `k` is how much of a main
	# battle tank this one is.
	var k: float = 0.86 if vclass() == "ifv" or vclass() == "spaag" else 1.0
	MeshKit.box(st, Vector3(3.5 * k, 0.85, 7.3 * k), Vector3(0, 0.10, 0))
	var glacis := PackedVector2Array([
		Vector2(-1.75 * k, -3.65 * k), Vector2(1.75 * k, -3.65 * k),
		Vector2(1.75 * k, -1.30 * k), Vector2(-1.75 * k, -1.30 * k)])
	MeshKit.prism(st, glacis, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		PackedFloat32Array([0.06, 0.06, 0.40, 0.40]), Vector3(0, 0.72, 0))
	MeshKit.box(st, Vector3(3.42 * k, 0.62, 4.9 * k), Vector3(0, 0.86, 0.9 * k))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.16, 0.72, 7.0 * k), Vector3(sx * 1.79 * k, 0.62, 0.1))
		MeshKit.box(st, Vector3(0.55, 0.30, 1.5), Vector3(sx * 1.5 * k, 1.30, 2.9 * k))
	MeshKit.box(st, Vector3(1.2, 0.45, 1.1), Vector3(0, 1.28, 3.2 * k))   # engine deck
	if vclass() == "spg":
		MeshKit.box(st, Vector3(2.6, 0.35, 1.2), Vector3(0, 0.30, 4.1))   # recoil spade
	add_child(MeshKit.mi(MeshKit.finish(st, body), "Hull"))

	# tracks: belt shell plus separate road wheels that follow the suspension
	var tst := MeshKit.begin()
	for sx in [-1.0, 1.0]:
		var belt := PackedVector2Array([
			Vector2(-3.9 * k, 0.06), Vector2(-3.35 * k, 0.95), Vector2(3.35 * k, 0.95),
			Vector2(3.9 * k, 0.06), Vector2(3.35 * k, -0.30), Vector2(-3.35 * k, -0.30)])
		MeshKit.prism(tst, belt, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
			PackedFloat32Array([0.30, 0.30, 0.30, 0.30, 0.30, 0.30]),
			Vector3(sx * TRACK_HALF * k, 0.02, 0))
	add_child(MeshKit.mi(MeshKit.finish(tst, dark), "Tracks"))

	for sx in [-1.0, 1.0]:
		for i in WHEELS_PER_SIDE:
			var z := lerpf(-2.95 * k, 2.95 * k, float(i) / float(WHEELS_PER_SIDE - 1))
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = WHEEL_R * k
			cyl.bottom_radius = WHEEL_R * k
			cyl.height = 0.34
			cyl.radial_segments = 10
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.17, 0.18, 0.17), 0.9, 0.1)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * TRACK_HALF * k, -0.18, z)
			add_child(w)
			_road_wheels.append({"node": w, "side": sx, "lat": sx * TRACK_HALF * k,
				"z": z, "rest_y": -0.18, "r": WHEEL_R, "comp": 0.0})

	# turret and gun
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 1.20, 0.55)
	add_child(_turret)
	var tu := MeshKit.begin()
	match vclass():
		"ifv":
			# a small two-man turret with an autocannon and a missile box
			MeshKit.box(tu, Vector3(1.35, 0.62, 1.65), Vector3(0, 0.32, 0))
			MeshKit.box(tu, Vector3(0.42, 0.36, 0.70), Vector3(0.86, 0.46, 0.15))
			MeshKit.box(tu, Vector3(0.30, 0.24, 0.34), Vector3(-0.72, 0.72, -0.20))
		"spaag":
			# a wide radar-topped mount: two barrels and a dish
			MeshKit.box(tu, Vector3(2.30, 0.72, 1.85), Vector3(0, 0.36, 0))
			MeshKit.cone(tu, 0.46, 0.46, -0.10, 0.10, Vector3(0, 0.92, 0.55), 12)
			MeshKit.box(tu, Vector3(0.10, 0.62, 0.62), Vector3(0, 1.24, 0.55))
		"mlrs":
			# armoured cab up front, rotating launcher cradle behind it
			MeshKit.box(tu, Vector3(2.9, 1.05, 2.3), Vector3(0, 0.50, -1.4))
			MeshKit.box(tu, Vector3(2.5, 0.35, 0.9), Vector3(0, 1.05, -0.3))
		"spg":
			var plan_spg := PackedVector2Array([Vector2(-1.45, -1.60), Vector2(-1.60, 0.30),
				Vector2(-1.35, 2.20), Vector2(1.35, 2.20), Vector2(1.60, 0.30), Vector2(1.45, -1.60)])
			MeshKit.prism(tu, plan_spg, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
				PackedFloat32Array([0.52, 0.58, 0.58, 0.58, 0.58, 0.52]), Vector3(0, 0.52, 0))
			MeshKit.box(tu, Vector3(2.4, 0.55, 0.7), Vector3(0, 0.60, 2.35))   # ammo bustle
			MeshKit.box(tu, Vector3(0.55, 0.35, 0.55), Vector3(-0.85, 1.15, 0.4))
		_:
			var plan := PackedVector2Array([Vector2(-1.30, -1.85), Vector2(-1.55, -0.20),
				Vector2(-1.25, 1.75), Vector2(1.25, 1.75), Vector2(1.55, -0.20), Vector2(1.30, -1.85)])
			MeshKit.prism(tu, plan, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
				PackedFloat32Array([0.34, 0.40, 0.40, 0.40, 0.40, 0.34]), Vector3(0, 0.34, 0))
			MeshKit.box(tu, Vector3(0.75, 0.30, 0.85), Vector3(-0.55, 0.80, 0.55))
			MeshKit.box(tu, Vector3(0.42, 0.22, 0.60), Vector3(0.72, 0.78, 0.30))
			MeshKit.box(tu, Vector3(1.9, 0.42, 0.28), Vector3(0, 0.42, 1.80))
	_turret.add_child(MeshKit.mi(MeshKit.finish(tu, body), "TurretShell"))

	_mantlet = Node3D.new()
	_mantlet.name = "Mantlet"
	if vclass() == "mlrs":
		_mantlet.position = Vector3(0, 1.25, 1.0)
	else:
		_mantlet.position = Vector3(0, 0.36, -1.55)
	_turret.add_child(_mantlet)
	var gst := MeshKit.begin()
	match vclass():
		"mlrs":
			# two pods of six tubes on an elevating cradle
			for px in [-0.62, 0.62]:
				for row in 2:
					for col in 3:
						var cy := 0.30 + float(row) * 0.44
						var cx: float = float(px) + (float(col) - 1.0) * 0.42
						MeshKit.cone(gst, 0.19, 0.19, -1.9, 1.9, Vector3(cx, cy, 0), 8)
			MeshKit.box(gst, Vector3(2.9, 0.22, 0.5), Vector3(0, 0.05, 1.2))
		"spg":
			MeshKit.box(gst, Vector3(1.15, 0.72, 0.62), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.19, 0.155, -7.4, 0.0, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.30, 0.30, -2.4, -1.2, Vector3.ZERO, 10)   # fume extractor
			MeshKit.cone(gst, 0.27, 0.27, -7.7, -7.2, Vector3.ZERO, 10)   # muzzle brake
		"ifv":
			MeshKit.box(gst, Vector3(0.42, 0.34, 0.44), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.055, 0.048, -2.35, 0.0, Vector3.ZERO, 8)
		"spaag":
			# twin barrels side by side, which is what one of these looks like
			MeshKit.box(gst, Vector3(0.85, 0.38, 0.50), Vector3(0, 0, 0.1))
			for bx in [-0.30, 0.30]:
				MeshKit.cone(gst, 0.052, 0.045, -2.75, 0.0, Vector3(bx, 0, 0), 8)
		_:
			MeshKit.box(gst, Vector3(1.05, 0.62, 0.55), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.135, 0.115, -5.6, 0.0, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.20, 0.20, -4.3, -3.3, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.19, 0.19, -5.75, -5.35, Vector3.ZERO, 10)
	_mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	_muzzle = Node3D.new()
	match vclass():
		"spg":
			_muzzle.position = Vector3(0, 0, -8.0)
		"mlrs":
			_muzzle.position = Vector3(0, 0.55, -2.1)
		"ifv":
			_muzzle.position = Vector3(0, 0, -2.45)
		"spaag":
			_muzzle.position = Vector3(0, 0, -2.85)
		_:
			_muzzle.position = Vector3(0, 0, -5.9)
	_mantlet.add_child(_muzzle)

# --------------------------------------------------------------------------
## Garrison crew: find something hostile, traverse onto it and shoot. Direct
## fire vehicles lead the target; the artillery pieces arc onto it.
func _ai_think(delta: float) -> void:
	_ai_scan -= delta
	if _ai_scan <= 0.0:
		_ai_scan = 1.2
		_ai_target = null
		var best := 1e9
		var reach: float = 22000.0 if is_indirect() \
			else float(KINDS[kind].get("reach", 2600.0))
		if is_air_defence():
			reach = float(KINDS[kind].get("reach", 30000.0))
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == self:
				continue
			if ("team" in n) and n.team == team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			# an artillery piece does not shoot at aircraft
			if is_indirect() and (n is Aircraft):
				continue
			# ...and a battery shoots at nothing else. Everything about it —
			# the rails, the radar, the round — is for what is overhead.
			if is_air_defence() and not (n is Aircraft):
				continue
			var d: float = global_position.distance_to(n.global_position)
			var agl: float = n.global_position.y - Sim.height_at(n.global_position.x,
				n.global_position.z)
			# A tank cannot reach an aeroplane at altitude; air defence exists
			# precisely to, so the ceiling does not apply to it.
			if n is Aircraft and agl > 900.0 and not is_air_defence():
				continue
			if d < reach and d < best:
				best = d
				_ai_target = n
	if _ai_target == null or not is_instance_valid(_ai_target):
		return
	var tp: Vector3 = _ai_target.global_position
	if "linear_velocity" in _ai_target:
		var tof: float = global_position.distance_to(tp) / 1500.0
		tp += (_ai_target.linear_velocity as Vector3) * tof
	if is_indirect():
		aim_yaw = atan2(tp.x - global_position.x, -(tp.z - global_position.z))
		map_target = Vector3(tp.x, Sim.height_at(tp.x, tp.z), tp.z)
	else:
		aim_at(tp)
		aim_yaw = turret_yaw
		aim_pitch = turret_pitch
	var lay: float = absf(wrapf(-turret_yaw - (rotation.y + _turret.rotation.y), -PI, PI))
	# A battery sends its round once the rails are up and pointed at the right
	# quarter of the sky; the round does the rest. A gun has to be laid.
	if vclass() == "sam":
		if lay < 0.25 and _erect > 0.9 and _gun_cd <= 0.0:
			fire_main(get_tree().current_scene)
		return
	if lay < 0.05 and _gun_cd <= 0.0:
		fire_main(get_tree().current_scene)
	if not is_indirect() and lay < 0.08 \
			and global_position.distance_to(_ai_target.global_position) < 1400.0:
		fire_coax(get_tree().current_scene)

## An unmanned ASAT battery. It watches the sky, stands its tube up when
## something hostile is overhead, and sends its one round.
func _asat_think(delta: float) -> void:
	_ai_scan -= delta
	if _ai_scan > 0.0:
		return
	_ai_scan = 2.0
	if rounds_left <= 0 or _gun_cd > 0.0:
		return
	var sat := _nearest_satellite()
	if not is_instance_valid(sat):
		return
	var lay: float = absf(wrapf(-turret_yaw - (rotation.y + _turret.rotation.y),
		-PI, PI))
	if _erect > 0.97 and lay < 0.06:
		fire_main(get_tree().current_scene)

func mount(on: bool) -> void:
	occupied = on
	if on:
		cam.current = true
		aim_yaw = -(rotation.y + _turret.rotation.y)
		_cam_yaw = rotation.y
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func display_name() -> String:
	return String(KINDS[kind]["name"])

func _unhandled_input(e: InputEvent) -> void:
	if not occupied or not alive:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		aim_mouse((e as InputEventMouseMotion).relative)

## Lay the piece with the mouse. Split out of the input handler so the guard
## below can be exercised without a captured pointer.
func aim_mouse(rel: Vector2) -> void:
	# With the commander's sight up the mouse slews the sight, not the turret.
	# Left unguarded, looking around the sight walked the fall of shot out and
	# threw away the fire mission the sight had just handed over.
	if sight_active:
		return
	# Plus. `aim_yaw` is a bearing -- the laid direction is sin(yaw) east of
	# north -- so it grows to the right, while the mouse also reads positive to
	# the right. Subtracting one from the other swung the turret the opposite
	# way to the hand moving it.
	aim_yaw += rel.x * 0.0026
	if is_indirect():
		# pushing away walks the fall of shot out, pulling back brings it in
		arty_range = clampf(arty_range - rel.y * 18.0, 300.0, 32000.0)
		map_target = Vector3.INF
	else:
		var el_max := deg_to_rad(20.0)
		match vclass():
			"lav":
				el_max = deg_to_rad(58.0)
			"spaag":
				el_max = deg_to_rad(85.0)
			"ifv":
				el_max = deg_to_rad(55.0)
			"sam":
				el_max = deg_to_rad(80.0)
		aim_pitch = clampf(aim_pitch - rel.y * 0.0022, deg_to_rad(-9.0), el_max)

func _drive_input(delta: float) -> void:
	in_throttle = Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up")
	in_steer = Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	in_brake = Sim.held(&"brakes")
	turret_yaw = aim_yaw
	if vclass() == "sam":
		# The rails do not aim, they lean: the crew picks the quarter and the
		# round finds the aeroplane. Elevation is a launch angle.
		turret_pitch = deg_to_rad(62.0)
	elif is_indirect():
		# lay the barrel at the live firing solution so what you see is what the
		# gun will actually do
		var aim := ground_aim()
		var sol := fire_solution(aim, float(KINDS[kind]["muzzle"])) if aim != Vector3.INF else {}
		turret_pitch = float(sol["elev"]) if not sol.is_empty() else deg_to_rad(40.0)
		if map_target != Vector3.INF:
			turret_yaw = atan2(map_target.x - global_position.x,
				-(map_target.z - global_position.z))
			# and the readout follows the piece. aim_yaw is what the HUD prints
			# as BEARING and what the wheel steers; leaving it on the mouse
			# heading while the tubes swung to the map target is why the
			# displayed bearing disagreed with where the launcher was facing.
			aim_yaw = turret_yaw
	else:
		turret_pitch = aim_pitch
	if Sim.tapped(&"camera"):
		gunner = not gunner
	# Weapon select works the way it does in the air: cycle, or pick directly.
	# The trigger is then just a trigger, whichever weapon is up.
	if Sim.tapped(&"cycle_weapon"):
		cycle_weapon()
	for wi in weapons().size():
		if Sim.tapped(StringName("weapon_%d" % (wi + 1))):
			set_weapon(wi)
	# ALT/META + right click is the sensor page chord. The trigger is also on
	# right click, so without this the act of opening the sensors fired the gun.
	var chord := Sim.held(&"freelook") or Sim.ui_modal
	var held := Sim.held(&"fire") and not chord
	var tapped := Sim.tapped(&"fire") and not chord
	var w_now := current_weapon()
	if w_now == "coax" or w_now == "mg":
		if held:
			fire_coax(get_tree().current_scene)
	elif w_now == "aa" or w_now == "cannon":
		# An automatic cannon fires for as long as the trigger is down. These
		# were falling through to the main gun rule below and firing one round
		# per press: a Shilka that puts out sixteen hundred rounds a minute gave
		# you a single shell and stopped.
		if held:
			fire_main(get_tree().current_scene)
	else:
		# a launcher walks its pod out while the trigger is held; everything
		# else is one round per press. Designating on the map lays the piece and
		# nothing more -- the round goes when the crew is told.
		if tapped or (is_ripple() and held):
			fire_main(get_tree().current_scene)
	# V still works as a dedicated coax key whatever is selected
	if Sim.held(&"gun") and current_weapon() != "coax" and vclass() != "lav":
		fire_coax(get_tree().current_scene)
	if Sim.tapped(&"interact"):
		dismount_requested.emit()
	# camera — unless the weapon camera has the screen, in which case putting
	# the view back on the vehicle every physics frame is what stopped a round
	# out of the tubes from ever being followed. Same fault the ships had.
	if not cam.current:
		return
	if gunner:
		var sight: Vector3 = _mantlet.global_transform * Vector3(0.55, 0.55, -0.4)
		cam.global_position = sight
		cam.global_transform.basis = _mantlet.global_transform.basis
		cam.fov = lerpf(cam.fov, 24.0, clampf(delta * 6.0, 0, 1))
	else:
		_cam_yaw = lerp_angle(_cam_yaw, aim_yaw, clampf(delta * 3.0, 0, 1))
		# Sit the camera BEHIND the bearing the turret is laid on. Built with a
		# positive sine the rig ended up looking along the mirror image of it:
		# tubes on 010, camera on 349. The gun then appeared to swing the
		# opposite way to the cursor.
		var back := Vector3(-sin(_cam_yaw), 0, cos(_cam_yaw))
		var want := global_position + Vector3(0, 4.2, 0) + back * 11.0
		want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 2.2)
		cam.global_position = cam.global_position.lerp(want, clampf(delta * 8.0, 0, 1)) \
			if cam.global_position.length() > 0.1 else want
		cam.look_at(global_position + Vector3(0, 1.8, 0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 70.0, clampf(delta * 6.0, 0, 1))

var scripted := false          # test harness drives the sticks directly
var ai := false                # garrison crews traverse and shoot on their own
var _ai_target: Node3D = null
var _ai_scan := 0.0

func _physics_process(delta: float) -> void:
	if _wrecked:
		# It burns hard for half a minute, then sits there smoking. Leaving the
		# flames on for the rest of the match makes a battlefield look like a
		# stage set; leaving the smoke on is what a burnt-out hull actually does.
		_burn += delta
		if is_instance_valid(_fire) and _burn > 34.0:
			_fire.emitting = false
		if is_instance_valid(_wreck_smoke) and _burn > 30.0:
			_wreck_smoke.amount_ratio = clampf(1.0 - (_burn - 30.0) / 90.0, 0.25, 1.0)
	if ai and alive and not occupied:
		if vclass() == "asat":
			_asat_think(delta)
		else:
			_ai_think(delta)
	if occupied and alive and not scripted:
		_drive_input(delta)
	elif occupied and alive:
		turret_yaw = aim_yaw
		turret_pitch = aim_pitch
	_gun_cd = maxf(_gun_cd - delta, 0.0)
	_coax_cd = maxf(_coax_cd - delta, 0.0)
	# A gun reloads from the bustle for as long as the crew is alive, so its
	# "rounds on the rails" go back to one the moment the breech is clear. A
	# launcher does not: it carries the canisters it was loaded with, and when
	# they have gone it has to go back for more. Without this exception an
	# Oreshnik with one round on the vehicle had an unlimited supply of them.
	if _gun_cd <= 0.0 and int(KINDS[kind].get("salvo", 1)) <= 1 \
			and vclass() != "tel" and vclass() != "sam" and vclass() != "asat":
		rounds_left = 1
	if not alive:
		return
	# turret slew, rate limited like a real drive
	# A node rotated about +Y by theta points its -Z axis at bearing -theta, so
	# the yaw command has to be negated to drive the barrel to a world bearing.
	# Without this the turret laid on the mirror image of the target: the fall
	# of shot was right because the solution supplies its own vector, but the
	# tubes visibly pointed twenty degrees the other way.
	if vclass() == "tel" or vclass() == "sam" or vclass() == "asat":
		# A launcher does not lay. The round is guided and turns onto the
		# bearing itself once it is off the rail, so the vehicle has nothing to
		# aim -- it raises the canister to near vertical, fires, and puts it
		# back down. Slewing the erector round to a compass bearing like a gun
		# turret was both wrong and the reason it looked like a tank.
		# A cruise launcher's canister points wherever the lorry is parked; a
		# battery's rails sit on a ring and follow the contact, which is what
		# makes it read as tracking you.
		if vclass() == "sam" or vclass() == "asat":
			# An ASAT lays on its target the way a battery does. Fired straight
			# up at something that is a hundred kilometres away and forty of
			# them off to one side, the round spends its whole burn turning and
			# arrives nowhere near: it has to leave the tube already pointed at
			# where the satellite is going to be.
			if vclass() == "asat":
				var sat := _nearest_satellite()
				if is_instance_valid(sat):
					turret_yaw = _asat_bearing(sat)
			var yerr := wrapf(-turret_yaw - (rotation.y + _turret.rotation.y), -PI, PI)
			_turret.rotation.y += clampf(yerr, -1.1 * delta, 1.1 * delta)
		else:
			_turret.rotation.y = 0.0
		var want_up: float = 1.0 if _erect_wanted() else 0.0
		_erect = move_toward(_erect, want_up,
			delta * (SAM_ERECT_RATE if vclass() == "sam" else ERECT_RATE))
		# A battery launches at a steep angle, not vertically: the round has to
		# lean at the contact to have somewhere to go.
		var top_angle: float = ERECT_ANGLE
		if vclass() == "sam":
			top_angle = deg_to_rad(62.0)
		elif vclass() == "asat":
			top_angle = _asat_elevation()
		_mantlet.rotation.x = _erect * top_angle
	else:
		var yaw_err := wrapf(-turret_yaw - (rotation.y + _turret.rotation.y), -PI, PI)
		_turret.rotation.y += clampf(yaw_err, -0.9 * delta, 0.9 * delta)
		var max_el: float = deg_to_rad(70.0) if vclass() != "mbt" else deg_to_rad(20.0)
		if vclass() == "lav":
			max_el = deg_to_rad(58.0)     # a ring mount will point at aircraft
		elif vclass() == "spaag":
			max_el = deg_to_rad(85.0)     # very nearly straight up
		elif vclass() == "ifv":
			max_el = deg_to_rad(55.0)     # an autocannon can reach a helicopter
		elif vclass() == "sam":
			max_el = deg_to_rad(80.0)     # a launch rail, not a sight
		_mantlet.rotation.x = lerp_angle(_mantlet.rotation.x,
			clampf(turret_pitch, deg_to_rad(-9.0), max_el), clampf(delta * 2.2, 0, 1))
	# The steered axle follows the wheel, not the stick: a road wheel takes about
	# a third of a second to come off lock.
	if _max_steer > 0.0:
		_steer = move_toward(_steer, -clampf(in_steer, -1.0, 1.0) * _max_steer,
			_max_steer * 3.0 * delta)
	_wheel_spin += speed / maxf(_wheel_r, 0.05) * delta
	for w in _road_wheels:
		var n: Node3D = w["node"]
		n.position.y = lerpf(n.position.y, float(w["rest_y"]) + float(w["comp"]),
			clampf(delta * 14.0, 0, 1))
		var turn := Basis()
		if bool(w.get("steer", false)) and absf(_steer) > 0.0001:
			turn = Basis(Vector3(0, 1, 0), _steer)
		n.transform.basis = turn * Basis(Vector3(1, 0, 0), _wheel_spin) \
			* Basis(Vector3(0, 0, 1), PI * 0.5)

## Hull half-width, for the obstacle test. A launcher on six axles is longer
## than a tank but no wider, and this only has to keep it out of a wall.
const HULL_R := 1.9

## Which side a vehicle belongs to. Team 0 is the NATO bloc and team 1 is
## everyone else, so a garrison can be equipped out of the right shed instead of
## every sector on the map fielding the same two tanks.
static func team_of(k: String) -> int:
	var f := String(KINDS.get(k, {}).get("faction", "usa"))
	var bloc := String(JetSpec.FACTIONS.get(f, {}).get("bloc", "nato"))
	return 0 if bloc == "nato" else 1

## Every vehicle of one class that a side fields, in declaration order.
static func kinds_of(cls: String, side := -1) -> PackedStringArray:
	var out := PackedStringArray()
	for k in KINDS:
		if String(KINDS[k].get("class", "mbt")) != cls:
			continue
		if side >= 0 and team_of(String(k)) != side:
			continue
		out.append(String(k))
	return out

## One of them, chosen from a seed so that a networked garrison comes out the
## same on both ends rather than each machine rolling its own.
static func pick_kind(cls: String, side: int, seed_v := 0) -> String:
	var list := kinds_of(cls, side)
	if list.is_empty():
		list = kinds_of(cls)
	if list.is_empty():
		return "m1a2"
	return list[absi(seed_v) % list.size()]

## Where a vehicle goes when it is put on the ground: standing on its own
## suspension, and lying along the slope rather than level with the horizon.
## Everything used to be dropped a flat 1.1 m onto a level basis, so on any
## ground that was not flat one side of the running gear was buried and the
## other was in the air -- and the hull spent the next few seconds sorting
## that out in front of you.
static func ground_pose(at: Vector3, yaw: float, lift: float) -> Transform3D:
	var up := Sim.normal_at(at.x, at.z)
	if up.dot(Vector3.UP) < 0.2:
		up = Vector3.UP
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	fwd = (fwd - up * fwd.dot(up))
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	var frame := Basis(right, up, -fwd)
	return Transform3D(frame,
		Vector3(at.x, Sim.height_at(at.x, at.z) + lift, at.z))

func hull_radius() -> float:
	return 1.15 if vclass() == "lav" else HULL_R

## How far the body origin sits above the ground with the vehicle stood on its
## own suspension. Every spawn used a flat 1.1 m, which for a launcher -- whose
## wheel centres are a tyre radius above its origin -- meant dropping it a metre
## onto its springs the instant it appeared. That drop is where the bouncing
## came from; put it down where it belongs and there is nothing to bounce.
func rest_height() -> float:
	if _road_wheels.is_empty():
		return 1.1
	var lift := 0.0
	for w in _road_wheels:
		lift = maxf(lift, float(w["r"]) - float(w["rest_y"]))
	# Static deflection: the N springs together hold mass*g at 2*k*x, and
	# k = mass*g*2.6/travel, so the hull settles travel/5.2 into its travel.
	return lift - _travel / 5.2

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# A knocked out tank keeps its suspension. Skipping the whole physics step
	# because the crew is dead leaves nothing holding the hull up and the hulk
	# sinks through the terrain for ever: there is no world collision mesh, the
	# ground only exists because these wheels look it up.
	if not alive:
		in_throttle = 0.0      # nothing is driving a wreck; let it roll to a stop
		in_steer = 0.0
		in_brake = true
	var xf := state.transform
	var fwd := -xf.basis.z
	speed = state.linear_velocity.dot(fwd)

	# Buildings. There is no world collision mesh -- the ground exists only
	# because the wheels look it up -- so a wall has to be pushed out of the
	# same way. Shove the hull clear along the shortest axis out of the
	# footprint and kill the part of the velocity that was driving into it,
	# which stops a tank climbing a tower block one frame at a time.
	var struck := Obstacles.hit(xf.origin, hull_radius())
	if struck >= 0:
		var out := xf.origin - Obstacles.centre_of(struck)
		out.y = 0.0
		if out.length_squared() < 0.01:
			out = fwd * -1.0
		out = out.normalized()
		state.transform.origin += out * 0.35
		var into: float = state.linear_velocity.dot(out)
		if into < 0.0:
			state.linear_velocity -= out * into

	var contacts := 0
	var k: float = mass * 9.81 * 2.6 / _travel
	# Damped as a hull on springs, not per imaginary wheel. The old figure was
	# 1.05*sqrt(k*m/N), which works out at about a fifth of critical on fourteen
	# wheels: the vehicle met the ground and then oscillated for several
	# seconds. The whole hull sees 2k and 2c (each of the N wheels carries 2/N
	# of the load), so the ratio that matters is c / sqrt(2*k*m) -- solve that
	# for c and the launcher settles onto its springs instead of pogoing off
	# them.
	var c: float = _damp * sqrt(2.0 * k * mass)
	# Shared out over the wheels this vehicle has, not over the seven-a-side
	# running gear of a tank. A launcher on six axles a side was having its
	# weight held up by fourteen imaginary wheels, four of which were not there.
	var per: float = 2.0 / maxf(float(_road_wheels.size()), 1.0)
	for w in _road_wheels:
		var lat: float = float(w.get("lat", float(w["side"]) * TRACK_HALF))
		var lp := Vector3(lat, float(w["rest_y"]), float(w["z"]))
		var wp: Vector3 = xf * lp
		var ground := Sim.height_at(wp.x, wp.z)
		# and its own radius: a lorry tyre is not a road wheel, and testing a
		# 0.72 m wheel as though it were 0.42 m buried a third of every tyre in
		# the ground and dropped the chassis with it.
		var wr: float = float(w.get("r", WHEEL_R))
		var comp: float = (ground + wr) - wp.y
		w["comp"] = clampf(comp, -_travel, _travel * 0.6)
		if comp <= 0.0:
			continue
		contacts += 1
		comp = minf(comp, _travel)
		var n := Sim.normal_at(wp.x, wp.z)
		var arm := wp - xf.origin
		var pv := state.linear_velocity + state.angular_velocity.cross(arm)
		var fn: float = maxf(k * comp - c * pv.dot(n), 0.0) * per
		fn = minf(fn, mass * 9.81 * 1.6)
		var f := n * fn
		var roll_dir := (fwd - n * fwd.dot(n)).normalized()
		# A wheeled vehicle points its front axle where it is going; only tracks
		# steer by dragging one side. Turning a lorry with a skid-steer command
		# is what made the launchers slew about like armour.
		if not _skid and bool(w.get("steer", false)) and absf(_steer) > 0.0001:
			roll_dir = roll_dir.rotated(n, _steer)
		var lat_dir := n.cross(roll_dir).normalized()
		var grip: float = Sim.surface_grip(wp.x, wp.z)
		var mu_lat: float = _mu_lat * grip
		f += lat_dir * clampf(-pv.dot(lat_dir) * mass * 1.6, -mu_lat * fn, mu_lat * fn)
		var side_cmd: float = in_throttle
		if _skid:
			side_cmd += in_steer * float(w["side"]) * 0.85
		side_cmd = clampf(side_cmd, -1.0, 1.0)
		var v_roll := pv.dot(roll_dir)
		# power limited tractive effort: strong off the mark, tailing off with
		# road speed the way a real drivetrain does
		var want: float = side_cmd * float(KINDS[kind]["top"]) * (0.65 if grip < 0.9 else 1.0)
		var avail: float = minf(_drive_max, float(KINDS[kind]["power"]) / maxf(absf(v_roll), 3.0)) * per
		var raw: float = (want - v_roll) * mass * 0.30
		# Braking is not limited by engine power. A skid steer turns by holding
		# the inside track back, and holding it back is a brake — it does not
		# ask the engine for anything. Clamping that side to the power-limited
		# tractive effort is why the heavy, under-powered pieces could not turn
		# at road speed however much lateral slip they were allowed: a 2S19 had
		# 55 kN of authority against the 117 kN the turn needed, and half of
		# what it needed was braking it was not being allowed to use.
		var cap: float = avail
		if raw * v_roll < 0.0:
			cap = maxf(avail, _brake_max * per)
		var drive: float = clampf(raw, -cap, cap)
		drive -= signf(v_roll) * ROLL_RESIST * fn
		if in_brake:
			drive = clampf(-v_roll * mass * 2.0, -_brake_max * per * 0.5, _brake_max * per * 0.5)
		var mu_roll: float = _mu_roll * grip
		drive = clampf(drive, -mu_roll * fn, mu_roll * fn)
		f += roll_dir * drive
		state.apply_force(f, arm)

	if contacts == 0:
		return
	# resist the hull trying to spin up on its own. A wheeled vehicle gets very
	# little of this: what turns it is the front axle, and damping the yaw as
	# hard as a tank's simply cancelled the steering.
	state.apply_torque(-Vector3(0, state.angular_velocity.y, 0) * mass * _yaw_damp)

# --------------------------------------------------------------------------
## A surface-to-air battery: the launcher lorry with four rounds canted up on
## the back and a search radar behind the cab. It does not lay a gun — it
## acquires an aircraft and sends a round — so the "turret" carries the rail
## pack and the elevation is a launch angle, not an aiming one.
func _build_battery(st: SurfaceTool, body: Material, dark: Material) -> void:
	# chassis and cab, the same lorry a launcher rides on
	MeshKit.box(st, Vector3(3.0, 0.42, 9.6), Vector3(0, 0.95, 0.4))
	MeshKit.box(st, Vector3(2.7, 0.34, 8.6), Vector3(0, 1.28, 0.4))
	MeshKit.box(st, Vector3(2.80, 1.55, 2.9), Vector3(0, 1.62, -3.9))
	MeshKit.box(st, Vector3(2.50, 0.62, 0.12), Vector3(0, 2.15, -5.30))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.70, 0.72, 3.4))
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.70, 0.72, -1.8))
	# the search radar: a flat panel on a mast behind the cab, which is the one
	# thing that tells you what this lorry is from a distance
	MeshKit.box(st, Vector3(0.34, 1.30, 0.34), Vector3(0, 2.20, -2.20))
	MeshKit.box(st, Vector3(2.30, 1.70, 0.16), Vector3(0, 3.45, -2.10))
	add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))
	var axles := [-4.3, -3.1, 0.6, 1.9, 3.2]
	for sx2 in [-1.0, 1.0]:
		for i in axles.size():
			var z: float = float(axles[i])
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = TEL_WHEEL_R
			cyl.bottom_radius = TEL_WHEEL_R
			cyl.height = 0.46
			cyl.radial_segments = 12
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.09, 0.09, 0.10), 0.95, 0.0)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx2 * 1.40, TEL_WHEEL_R, z)
			add_child(w)
			_road_wheels.append({"node": w, "side": sx2, "lat": sx2 * 1.40, "z": z,
				"rest_y": TEL_WHEEL_R, "r": TEL_WHEEL_R, "comp": 0.0,
				"steer": i < 2})
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 1.55, 1.6)
	add_child(_turret)
	var tu := MeshKit.begin()
	MeshKit.box(tu, Vector3(2.2, 0.32, 2.4), Vector3(0, 0.08, 0))
	_turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Deck"))
	_mantlet = Node3D.new()
	_mantlet.name = "Mantlet"
	_mantlet.position = Vector3(0, 0.36, 2.2)
	_turret.add_child(_mantlet)
	# four rounds in their tubes, in a two by two pack
	var gst := MeshKit.begin()
	var tube := 2.9
	MeshKit.box(gst, Vector3(1.90, 0.24, tube * 1.9), Vector3(0, 0.06, -tube * 0.85))
	_tube_lanes = []
	for cx in [-0.52, 0.52]:
		for cy in [0.44, 1.06]:
			MeshKit.cone(gst, 0.26, 0.26, -tube * 1.85, 0.05,
				Vector3(cx, cy, 0), 10)
			MeshKit.cone(gst, 0.29, 0.29, -tube * 1.9, -tube * 1.78,
				Vector3(cx, cy, 0), 10)
			_tube_lanes.append(cx)
	_tube_len = tube
	_tube_rise = 0.75
	_mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.75, -tube * 1.9)
	_mantlet.add_child(_muzzle)

# --------------------------------------------------------------------------
## A light 4x4: ladder chassis, crew cab, load bed and four independently
## sprung wheels, the front pair of which steer. Nothing about a tank's hull
## fits one of these -- there are no tracks to build, the body is a metre and
## a half tall rather than three, and what is on the roof is a ring mount with
## a machine gun on it, not a turret.
func _build_light_chassis(st: SurfaceTool, body: Material, dark: Material) -> void:
	var ch: Dictionary = KINDS[kind].get("chassis", {})
	var ln: float = float(ch.get("len", 4.9))
	var wd: float = float(ch.get("wide", 2.2))
	var ht: float = float(ch.get("tall", 1.42))
	var wb: float = float(ch.get("wb", 3.30))
	var tk: float = float(ch.get("track", wd * 0.42))
	var wr: float = float(ch.get("r", 0.47))
	var open_top: bool = String(ch.get("mount", "ring")) == "open"
	# The body origin sits at the axle line, so the wheels hang either side of
	# it and rest_height() has something square to work from.
	var deck: float = wr + 0.22                      # top of the chassis rails
	var sill: float = deck + 0.16

	# ladder chassis
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.16, 0.20, ln * 0.94), Vector3(sx * tk * 0.55, deck - 0.12, 0))
	MeshKit.box(st, Vector3(tk * 1.1, 0.14, 0.5), Vector3(0, deck - 0.12, -wb * 0.5))
	MeshKit.box(st, Vector3(tk * 1.1, 0.14, 0.5), Vector3(0, deck - 0.12, wb * 0.5))
	# hull tub, with the nose and tail cut back so it does not overhang the tyres
	MeshKit.box(st, Vector3(wd, 0.44, ln * 0.90), Vector3(0, sill, 0))
	# bonnet: a flat deck over the engine, sloped up to the windscreen
	var nose_z: float = -ln * 0.30
	MeshKit.box(st, Vector3(wd * 0.92, 0.30, ln * 0.30), Vector3(0, sill + 0.34, nose_z))
	var scuttle := PackedVector2Array([
		Vector2(-wd * 0.46, nose_z + ln * 0.15), Vector2(wd * 0.46, nose_z + ln * 0.15),
		Vector2(wd * 0.46, nose_z + ln * 0.30), Vector2(-wd * 0.46, nose_z + ln * 0.30)])
	MeshKit.prism(st, scuttle, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		PackedFloat32Array([0.06, 0.06, 0.34, 0.34]), Vector3(0, sill + 0.49, 0))
	# radiator grille and a brush guard, which is the front of one of these
	MeshKit.box(st, Vector3(wd * 0.80, 0.42, 0.14), Vector3(0, sill + 0.30, nose_z - ln * 0.16))
	MeshKit.box(st, Vector3(wd * 0.86, 0.12, 0.12), Vector3(0, sill + 0.52, nose_z - ln * 0.20))
	MeshKit.box(st, Vector3(wd * 0.86, 0.12, 0.12), Vector3(0, sill + 0.08, nose_z - ln * 0.20))
	# crew compartment: sides and a rear bulkhead, roofed unless it is open
	var cab_z: float = -ln * 0.02
	var cab_l: float = ln * 0.40
	var cab_h: float = ht * 0.66
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.12, cab_h, cab_l), Vector3(sx * wd * 0.44, sill + 0.22 + cab_h * 0.5, cab_z))
	MeshKit.box(st, Vector3(wd * 0.88, cab_h, 0.12), Vector3(0, sill + 0.22 + cab_h * 0.5, cab_z + cab_l * 0.5))
	if not open_top:
		MeshKit.box(st, Vector3(wd * 0.90, 0.10, cab_l), Vector3(0, sill + 0.22 + cab_h, cab_z))
		# A pillars, so the windscreen reads as glass in a frame
		for sx in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0.10, cab_h, 0.10),
				Vector3(sx * wd * 0.42, sill + 0.22 + cab_h * 0.5, cab_z - cab_l * 0.5))
	# load bed behind the cab
	var bed_z: float = ln * 0.30
	MeshKit.box(st, Vector3(wd * 0.94, 0.34, ln * 0.30), Vector3(0, sill + 0.28, bed_z))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.10, 0.30, ln * 0.30), Vector3(sx * wd * 0.46, sill + 0.52, bed_z))
	# spare wheel on the tail, jerry cans on the flank
	MeshKit.box(st, Vector3(0.30, 0.34, 0.22), Vector3(wd * 0.30, sill + 0.62, bed_z + ln * 0.10))
	# arches over each wheel, or the tyres cut straight through the body side
	for sx in [-1.0, 1.0]:
		for zz in [-wb * 0.5, wb * 0.5]:
			MeshKit.box(st, Vector3(0.10, 0.44, wr * 2.5),
				Vector3(sx * (tk + 0.22), deck + 0.10, zz))
			MeshKit.box(st, Vector3(tk * 0.6, 0.10, wr * 2.5),
				Vector3(sx * (tk * 0.7 + 0.22), deck + 0.30, zz))
	add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))

	# glass: windscreen and door windows, dark so they read as glazing
	if not open_top:
		var gst := MeshKit.begin()
		var wind := PackedVector2Array([
			Vector2(-wd * 0.40, nose_z + ln * 0.16), Vector2(wd * 0.40, nose_z + ln * 0.16),
			Vector2(wd * 0.40, nose_z + ln * 0.29), Vector2(-wd * 0.40, nose_z + ln * 0.29)])
		MeshKit.prism(gst, wind, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
			PackedFloat32Array([0.05, 0.05, 0.30, 0.30]), Vector3(0, sill + 0.52, 0))
		for sx in [-1.0, 1.0]:
			MeshKit.box(gst, Vector3(0.05, cab_h * 0.52, cab_l * 0.58),
				Vector3(sx * wd * 0.45, sill + 0.28 + cab_h * 0.66, cab_z - cab_l * 0.10))
		add_child(MeshKit.mi(MeshKit.finish(gst,
			MeshKit.mat(Color(0.07, 0.09, 0.10), 0.18, 0.5)), "Glass"))

	# four wheels on coils, the front pair steered
	var tyre := MeshKit.mat(Color(0.08, 0.08, 0.09), 0.95, 0.0)
	for sx in [-1.0, 1.0]:
		for zz in [-wb * 0.5, wb * 0.5]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = wr
			cyl.bottom_radius = wr
			cyl.height = wr * 0.62
			cyl.radial_segments = 14
			w.mesh = cyl
			w.material_override = tyre
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * tk, wr, zz)
			add_child(w)
			_road_wheels.append({"node": w, "side": sx, "lat": sx * tk, "z": zz,
				"rest_y": wr, "r": wr, "comp": 0.0, "steer": zz < 0.0})

	# the ring mount stands in for the turret, so laying and elevating work
	# exactly as they do on everything else
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, sill + 0.22 + (cab_h if not open_top else cab_h * 0.55),
		cab_z + (0.0 if not open_top else -cab_l * 0.10))
	add_child(_turret)
	var tu := MeshKit.begin()
	MeshKit.cone(tu, 0.46, 0.46, -0.09, 0.09, Vector3(0, 0.10, 0), 12)
	MeshKit.box(tu, Vector3(0.62, 0.22, 0.14), Vector3(0, 0.28, 0.34))   # gun shield mount
	MeshKit.box(tu, Vector3(0.72, 0.34, 0.06), Vector3(0, 0.44, -0.22))  # shield plate
	_turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Ring"))

	_mantlet = Node3D.new()
	_mantlet.name = "Mantlet"
	_mantlet.position = Vector3(0, 0.34, 0.06)
	_turret.add_child(_mantlet)
	var gst2 := MeshKit.begin()
	MeshKit.box(gst2, Vector3(0.16, 0.20, 0.62), Vector3(0, 0, 0.16))    # receiver
	MeshKit.cone(gst2, 0.045, 0.038, -0.92, -0.10, Vector3.ZERO, 8)      # barrel
	MeshKit.box(gst2, Vector3(0.10, 0.10, 0.22), Vector3(0, 0.13, 0.10)) # ammo box
	MeshKit.box(gst2, Vector3(0.06, 0.14, 0.06), Vector3(0, -0.14, -0.30))
	_mantlet.add_child(MeshKit.mi(MeshKit.finish(gst2,
		MeshKit.mat(Color(0.10, 0.10, 0.11), 0.85, 0.25)), "Gun"))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -0.95)
	_mantlet.add_child(_muzzle)

# --------------------------------------------------------------------------
## A launcher is a lorry, not a tank. It was being given the tracked hull, the
## glacis, the side skirts and the road wheels of an armoured vehicle, so a
## TEL came out looking exactly like everything else on the field with a
## canister balanced on top of it.
func _build_tel_chassis(st: SurfaceTool, body: Material, dark: Material) -> void:
	# a long flat load bed on a chassis
	MeshKit.box(st, Vector3(3.1, 0.42, 11.6), Vector3(0, 0.95, 0.6))
	MeshKit.box(st, Vector3(2.7, 0.34, 10.4), Vector3(0, 1.28, 0.6))
	# the cab, forward and separate, with glass in it
	MeshKit.box(st, Vector3(2.85, 1.55, 3.0), Vector3(0, 1.62, -4.6))
	MeshKit.box(st, Vector3(2.55, 0.62, 0.12), Vector3(0, 2.15, -6.05))
	# outriggers, which is what holds it down when it launches
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.75, 0.72, 3.9))
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.75, 0.72, -2.2))
	add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))
	# eight wheels a side on a proper wheelbase, not a track run
	var axles := [-5.1, -3.9, -0.6, 0.7, 2.0, 3.3]
	for sx2 in [-1.0, 1.0]:
		for i in axles.size():
			var z: float = float(axles[i])
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.72
			cyl.bottom_radius = 0.72
			cyl.height = 0.46
			cyl.radial_segments = 12
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.09, 0.09, 0.10), 0.95, 0.0)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx2 * 1.42, TEL_WHEEL_R, z)
			add_child(w)
			# the front bogie steers, as it does on the real lorry
			_road_wheels.append({"node": w, "side": sx2, "lat": sx2 * 1.42, "z": z,
				"rest_y": TEL_WHEEL_R, "r": TEL_WHEEL_R, "comp": 0.0,
				"steer": i < 2})
	# the erector and its canisters live on the turret node, as with everything
	# else, so laying and elevating work unchanged
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 1.55, 1.1)
	add_child(_turret)
	var tu := MeshKit.begin()
	MeshKit.box(tu, Vector3(2.2, 0.36, 2.0), Vector3(0, 0.10, 0))
	add_child_turret_mesh(tu, dark)

func add_child_turret_mesh(tu: SurfaceTool, dark: Material) -> void:
	_turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Deck"))
	_mantlet = Node3D.new()
	_mantlet.name = "Mantlet"
	# At the back of the load bed, where a launcher's erector is actually
	# hinged.
	_mantlet.position = Vector3(0, 0.45, 4.0)
	_turret.add_child(_mantlet)
	var gst := MeshKit.begin()
	# One canister or two, and how big, follows the round it carries. Every
	# launcher was given the same twin tubes, so an Oreshnik — fourteen and a
	# half metres of it — rode in the same pair of pipes as a Kalibr.
	var mid: Dictionary = WeaponSpec.get_spec(
		String(KINDS[kind].get("missile", "kalibr")))
	var bore: float = maxf(float(mid.get("dia", 0.5)) * 0.62, 0.30)
	var tube: float = maxf(float(mid.get("length", 6.0)) * 0.5, 2.4)
	var twin: bool = float(mid.get("dia", 0.5)) < 0.7
	# The whole load sits *forward* of the hinge rather than straddling it. Built
	# centred on the pivot, raising the canister swung its back half down
	# through the chassis at the same rate as its nose went up -- the missiles
	# rotated through the vehicle they were sitting on.
	var back: float = -tube * 0.94
	MeshKit.box(gst, Vector3(bore * 4.2, 0.30, tube * 1.9), Vector3(0, 0.10, 0.4 + back))
	var lanes: Array = [-bore * 1.15, bore * 1.15] if twin else [0.0]
	for cx in lanes:
		MeshKit.cone(gst, bore, bore, -tube + back, tube * 0.94 + back,
			Vector3(cx, bore + 0.3, 0), 12)
		MeshKit.cone(gst, bore * 1.11, bore * 1.11, -tube - 0.1 + back,
			-tube + 0.2 + back, Vector3(cx, bore + 0.3, 0), 12)
	MeshKit.box(gst, Vector3(bore * 4.6, 0.5, 0.5),
		Vector3(0, 0.30, tube * 0.82 + back))
	_tube_lanes = lanes
	_tube_len = tube
	_tube_rise = bore + 0.3
	_mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, _tube_rise, -_tube_len - tube * 0.94)
	_mantlet.add_child(_muzzle)

## How far this vehicle's search radar reaches, for the side's picture.
func radar_range() -> float:
	return float(KINDS[kind].get("radar", 0.0))

func vclass() -> String:
	return String(KINDS[kind].get("class", "mbt"))

## A multiple launcher ripples its pod; a howitzer loads one round at a time.
## What this vehicle can shoot with, in selection order.
func weapons() -> PackedStringArray:
	# A patrol vehicle has one weapon and it is the thing on the roof.
	if vclass() == "lav":
		return PackedStringArray(["mg"])
	if vclass() == "asat":
		return PackedStringArray(["asat"])
	if vclass() == "sam":
		return PackedStringArray(["sam"])
	if vclass() == "spaag":
		# Gun AND missile, the way a Pantsir or an M-SHORAD actually is: the
		# cannon for what is close and the rounds for what is not.
		return PackedStringArray(["aa", "sam"])
	if vclass() == "ifv":
		return PackedStringArray(["cannon", "coax"])
	var w := PackedStringArray(["main"])
	if vclass() == "mbt":
		w.append("coax")
	return w

func current_weapon() -> String:
	var w := weapons()
	return w[clampi(sel_weapon, 0, w.size() - 1)]

func weapon_label() -> String:
	match current_weapon():
		"mg":
			return "HEAVY MG"
		"asat":
			return "ASAT  %d IN THE TUBE" % rounds_left
		"sam":
			# A battery's rounds are its magazine; a gun vehicle's missiles are
			# counted apart from its cannon.
			if vclass() == "spaag":
				return "SHORT RANGE SAM  %d LEFT" % sam_left
			return "SAM  %d ON THE RAILS" % rounds_left
		"aa":
			return "AA CANNON"
		"cannon":
			return "AUTOCANNON"
		"coax":
			return "COAXIAL"
		_:
			return "MAIN GUN"

func set_weapon(i: int) -> void:
	var w := weapons()
	if i < 0 or i >= w.size() or i == sel_weapon:
		return
	sel_weapon = i
	Sim.report(weapon_label(), Sim.Ev.INFO)

func cycle_weapon() -> void:
	set_weapon((sel_weapon + 1) % weapons().size())

func is_ripple() -> bool:
	return int(KINDS[kind].get("salvo", 1)) > 1

## Pieces that are laid by bearing and range rather than pointed at what they
## are shooting. A light vehicle's machine gun is neither of those: it is aimed
## down the barrel, and treating it as artillery gave a Humvee a fire mission
## page and a forty degree quadrant elevation.
func is_indirect() -> bool:
	var c := vclass()
	return c == "spg" or c == "mlrs" or c == "tel"

## Vehicles whose whole job is shooting at aircraft. They elevate much higher
## than a tank, they lead a fast crossing target, and their AI looks up rather
## than along.
func is_air_defence() -> bool:
	var c := vclass()
	return c == "sam" or c == "spaag"

## March the barrel line onto the ground: where the crosshair is pointing. The
## march samples the height field a hundred times, so the answer is cached for a
## few frames rather than recomputed for the HUD and the gun separately.
func ground_aim() -> Vector3:
	# The march down the height field is expensive, so the answer is cached for
	# a few frames -- but the cache has to know what it was computed FROM.
	# Keyed on time alone, designating a target on the map and pressing fire in
	# the same breath laid the tubes on the new bearing and sent the rounds to
	# the old one, kilometres away.
	var key := Vector3(aim_yaw, arty_range, aim_pitch)
	var now := Time.get_ticks_msec()
	if now - _aim_cache_t < 100 and _aim_cache != Vector3.ZERO \
			and key.is_equal_approx(_aim_cache_key) \
			and map_target.is_equal_approx(_aim_cache_map):
		return _aim_cache
	_aim_cache_t = now
	_aim_cache_key = key
	_aim_cache_map = map_target
	_aim_cache = _ground_aim_now()
	return _aim_cache

func _ground_aim_now() -> Vector3:
	if map_target != Vector3.INF:
		return map_target
	var origin: Vector3 = _turret.global_position
	if is_indirect():
		# bearing and range: the wheel or the stick sets how far out to drop them
		var flat := Vector3(sin(aim_yaw), 0.0, -cos(aim_yaw)).normalized()
		var p := origin + flat * arty_range
		return Vector3(p.x, Sim.height_at(p.x, p.z), p.z)
	var dir := Vector3(sin(aim_yaw), tan(clampf(-aim_pitch, -1.2, -0.02)), -cos(aim_yaw)).normalized()
	var t := 15.0
	while t < 26000.0:
		var q := origin + dir * t
		if q.y <= Sim.height_at(q.x, q.z):
			return Vector3(q.x, Sim.height_at(q.x, q.z), q.z)
		t += maxf(t * 0.05, 12.0)
	return Vector3.INF

## Firing solution onto a ground point. Real artillery does not use the lofted
## root of the ballistic equation - that gives near vertical mortar arcs - it
## picks a propelling charge so the piece sits at a sensible quadrant elevation.
## So: hold about 40 degrees and solve for the velocity, and only flatten out at
## full charge when the target is beyond that.
const ARTY_QE := 40.0

func fire_solution(target: Vector3, v_max: float) -> Dictionary:
	var origin: Vector3 = _muzzle.global_position
	var d := Vector2(target.x - origin.x, target.z - origin.z).length()
	var dy := target.y - origin.y
	var g := 9.81
	if d < 60.0:
		return {}
	var el := deg_to_rad(ARTY_QE)
	var denom := 2.0 * (d * tan(el) - dy)
	if denom > 0.0:
		var need := d / cos(el) * sqrt(g / denom)
		if need <= v_max:
			return {"elev": el, "speed": need,
				"tof": d / (need * cos(el)), "range": d, "charge": need / v_max}
	# beyond the 40 degree arc: full charge on the low angle solution
	var root := v_max * v_max * v_max * v_max - g * (g * d * d + 2.0 * dy * v_max * v_max)
	if root < 0.0:
		return {}
	var low := atan((v_max * v_max - sqrt(root)) / (g * d))
	return {"elev": low, "speed": v_max, "tof": d / (v_max * cos(low)),
		"range": d, "charge": 1.0}

func aim_at(point: Vector3) -> void:
	var to := point - _turret.global_position
	turret_yaw = atan2(to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	turret_pitch = atan2(to.y, maxf(flat, 0.1))

func fire_main(world: Node) -> bool:
	var kd: Dictionary = KINDS[kind]
	if vclass() == "lav":
		# There is no breech to reload: pulling the trigger runs the roof gun.
		return fire_coax(world)
	if _gun_cd > 0.0 or not alive:
		return false
	# An autocannon and an anti-aircraft gun are the same thing as far as this
	# is concerned: a fast shell, a small burst, and a fuse that goes off near
	# whatever it passes. Neither is a main gun and neither is artillery.
	if vclass() == "ifv" or vclass() == "spaag":
		_gun_cd = float(kd["reload"])
		var adir := -_muzzle.global_transform.basis.z
		var spread: float = 0.004 if vclass() == "ifv" else 0.006
		adir = (adir + Vector3(randf_range(-spread, spread),
			randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
		Effects.tracer(world, _muzzle.global_position - adir * 1.5,
			adir * float(kd["muzzle"]) + linear_velocity, self,
			float(kd["gun"]), team, float(kd.get("blast", 3.0)) * 0.4)
		Effects.muzzle_flash(world, _muzzle.global_position - adir * 1.2, adir, 1.1)
		# "rifle", not "gun": the gun clip is a looping buzzsaw meant to be
		# started and stopped, and firing it as a one-shot sixteen times a
		# second stacks up loops that never end. A shell leaving an autocannon
		# is a discrete crack, which is what this clip is.
		Sfx.play_at(world, "rifle", _muzzle.global_position, -5.0,
			randf_range(0.92, 1.08), 1800.0)
		return true
	if vclass() == "spaag" and current_weapon() == "sam":
		return _fire_shorad(world, kd)
	if vclass() == "sam":
		return _fire_sam(world, kd)
	if vclass() == "asat":
		return _fire_asat(world, kd)
	if vclass() == "tel":
		if rounds_left <= 0:
			return false
		return _fire_tel(world, kd)
	if is_indirect():
		# Wait until the launcher is actually laid. The solution is worked out
		# the instant you designate, but the traverse takes 0.9 rad/s and the
		# elevation longer, so firing straight away sent rockets off the correct
		# bearing while the tubes were still pointing somewhere else entirely.
		# tight, because at six kilometres a degree of quadrant elevation is
		# nearly forty metres of range and the tubes are now the launch axis
		var off := lay_error()
		if off > 0.006:
			laying = true
			return false
		laying = false
		if rounds_left <= 0:
			if int(kd.get("salvo", 1)) <= 1:
				# a gun, not a rack: the loader is already working and pulling
				# the trigger again must not send him back to the start
				return false
			# pod empty: the crew reloads the whole rack before anything else
			_gun_cd = float(kd["reload"])
			rounds_left = int(kd.get("salvo", 1))
			return false
		var pod: int = int(kd.get("salvo", 1))
		_gun_cd = float(kd.get("ripple", 0.55)) if pod > 1 else float(kd["reload"])
		_fire_indirect(world, kd)
		return true
	_gun_cd = float(kd["reload"])
	_lob(world, -_muzzle.global_transform.basis.z * float(kd["muzzle"]),
		float(kd["gun"]), float(kd["blast"]), 3.4)
	apply_central_impulse(_muzzle.global_transform.basis.z * 34000.0)
	return true

## How far the piece still is from the bearing and elevation it needs, in
## radians: the worst of the two axes. Zero means it is laid and may fire.
## How far up the canister goes, 0 stowed to 1 vertical, and how fast. Four
## seconds to erect is about what a real one takes.
const ERECT_ANGLE := deg_to_rad(86.0)
const ERECT_RATE := 0.25
## A battery raises its rails in a few seconds — it is answering an aeroplane,
## not preparing a strategic launch.
const SAM_ERECT_RATE := 0.55
var _erect := 0.0
## A unit locked from the map, rather than a patch of ground. A hypersonic given
## a coordinate arrives where the target *was*; given the target it arrives
## where it is.
var map_lock: Node = null
## Extra aiming points for a round that carries more than one warhead.
##
## A MIRV bus is independently targetable -- that is what the letters stand for
## -- and until now every warhead it carried was thrown at one footprint round a
## single mark. Shift and right click on the map adds a point to this list, and
## the bus hands one to each warhead as it opens. Empty means the old behaviour:
## spread the load over the footprint at the primary mark.
var mirv_marks: Array = []

## Is there anything worth standing the canister up for? It goes back down when
## there is not, because a launcher sitting on the road with its tube in the air
## is a launcher that has already been seen.
func _erect_wanted() -> bool:
	if rounds_left <= 0 or not alive:
		return false
	if vclass() == "asat":
		return is_instance_valid(_nearest_satellite())
	if map_target != Vector3.INF:
		return true
	if is_instance_valid(_ai_target):
		return true
	return occupied

## Sending a round at something in orbit. The only target this vehicle has is a
## satellite: everything in the atmosphere is somebody else's problem, and the
## round is far too large and far too slow to turn to be any use against it.
func _fire_asat(world: Node, kd: Dictionary) -> bool:
	if rounds_left <= 0:
		return false
	var tgt: Node3D = _nearest_satellite()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in orbit to shoot at" % display_name(), Sim.Ev.BAD)
		return false
	if _erect < 0.97:
		Sim.report("%s: erecting — %d%%" % [display_name(), int(_erect * 100.0)],
			Sim.Ev.INFO)
		return false
	_gun_cd = float(kd["reload"])
	rounds_left -= 1
	var from: Vector3 = _muzzle.global_position
	var dir := -_muzzle.global_transform.basis.z
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("missile", "asat")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 30.0, self, tgt)
	world.add_child(m)
	store_released.emit(m)
	Sim.report("%s: ASAT away at %s" % [display_name(),
		tgt.call("display_name") if tgt.has_method("display_name") else "orbital contact"],
		Sim.Ev.BAD)
	return true

## Where the round has to be pointed. The satellite is doing eleven hundred
## metres a second and the round takes the better part of a minute to get up
## there, so the tube is laid on where it WILL be, not where it is.
func _asat_lead(sat: Node3D) -> Vector3:
	var aim: Vector3 = sat.global_position
	var tv := Vector3.ZERO
	if sat.has_method("get_velocity"):
		tv = sat.call("get_velocity")
	# average speed over the climb, which is most of the burn plus the coast
	var tof: float = global_position.distance_to(aim) / 2200.0
	return aim + tv * clampf(tof, 0.0, 120.0)

func _asat_bearing(sat: Node3D) -> float:
	var to: Vector3 = _asat_lead(sat) - global_position
	return atan2(to.x, -to.z)

## Launch elevation, from the geometry rather than from a constant. Steep, but
## not vertical unless the thing is actually overhead.
func _asat_elevation() -> float:
	var sat := _nearest_satellite()
	if not is_instance_valid(sat):
		return ERECT_ANGLE
	var to: Vector3 = _asat_lead(sat) - global_position
	var flat: float = Vector2(to.x, to.z).length()
	return clampf(atan2(to.y, maxf(flat, 1.0)), deg_to_rad(35.0), deg_to_rad(88.0))

## The hostile satellite that is easiest to reach: the one nearest overhead.
func _nearest_satellite() -> Node3D:
	# Whatever was picked on the map wins: that is the whole point of being able
	# to pick one. Only if nothing is assigned does the crew choose for itself.
	var told: Node = Sim.sat_target
	if is_instance_valid(told) and (told is Node3D) \
			and (not ("team" in told) or int(told.team) != team) \
			and (not told.has_method("is_alive") or told.is_alive()):
		return told as Node3D
	var best: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if ("team" in n) and n.team == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

## A battery sending a round. Unlike a launcher it has something to aim at —
## an aeroplane — and unlike a gun it does not have to be laid on it: the round
## leaves the rail on the launch elevation and turns onto the target itself.
func _fire_sam(world: Node, kd: Dictionary) -> bool:
	if rounds_left <= 0:
		return false
	var tgt: Node3D = _ai_target
	if not is_instance_valid(tgt):
		tgt = _nearest_air()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in the air to shoot at" % display_name(), Sim.Ev.BAD)
		return false
	var reach: float = float(kd.get("reach", 60000.0))
	var rng: float = global_position.distance_to(tgt.global_position)
	if rng > reach:
		Sim.report("%s: contact is %.0f km out, the round reaches %.0f" % [
			display_name(), rng * 0.001, reach * 0.001], Sim.Ev.BAD)
		return false
	_gun_cd = float(kd["reload"])
	rounds_left -= 1
	var from: Vector3 = _muzzle.global_position
	var dir := -_muzzle.global_transform.basis.z
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("missile", "sam_med")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 40.0, self, tgt)
	world.add_child(m)
	store_released.emit(m)
	Sim.report("%s: round away — %d on the rails" % [display_name(), rounds_left],
		Sim.Ev.GOOD)
	return true

## A gun vehicle's missile. Short ranged and infrared — it is the round you use
## on what the cannon cannot reach, not a substitute for a battery.
func _fire_shorad(world: Node, kd: Dictionary) -> bool:
	if sam_left <= 0:
		Sim.report("%s: no missiles left" % display_name(), Sim.Ev.BAD)
		return false
	var tgt: Node3D = _ai_target if is_instance_valid(_ai_target) else _nearest_air()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in the air to shoot at" % display_name(), Sim.Ev.BAD)
		return false
	var reach: float = float(kd.get("sam_reach", 8000.0))
	var rng: float = global_position.distance_to(tgt.global_position)
	if rng > reach:
		Sim.report("%s: contact is %.1f km out, the round reaches %.1f" % [
			display_name(), rng * 0.001, reach * 0.001], Sim.Ev.BAD)
		return false
	sam_left -= 1
	_gun_cd = 1.6
	var from: Vector3 = _muzzle.global_position
	var dir := (tgt.global_position - from).normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("sam_missile", "manpads")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 40.0, self, tgt)
	world.add_child(m)
	store_released.emit(m)
	Sim.report("%s: missile away — %d left" % [display_name(), sam_left], Sim.Ev.GOOD)
	return true

## The nearest hostile aircraft this battery can see.
func _nearest_air() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not (n is Aircraft):
			continue
		if ("team" in n) and n.team == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

## Send one. A TEL does not need to be laid the way a gun does — the round is
## guided and will turn onto the bearing itself — so all this has to do is get
## it off the rail cleanly and pointed up.
func _fire_tel(world: Node, kd: Dictionary) -> bool:
	var mark: Vector3 = map_target
	if is_instance_valid(map_lock):
		mark = (map_lock as Node3D).global_position
	if mark == Vector3.INF:
		mark = ground_aim()
	if mark == Vector3.INF and is_instance_valid(_ai_target):
		mark = _ai_target.global_position
	if mark == Vector3.INF:
		Sim.report("%s: no aiming point" % display_name(), Sim.Ev.BAD)
		return false
	# the round's reach, not a shell's
	var spec := WeaponSpec.get_spec(String(kd.get("missile", "kalibr")))
	var rng := global_position.distance_to(mark)
	if rng > float(spec.get("range", 100000.0)):
		Sim.report("%s: mark is %.0f km away, the round reaches %.0f" % [
			display_name(), rng * 0.001,
			float(spec.get("range", 100000.0)) * 0.001], Sim.Ev.BAD)
		return false
	if _erect < 0.97:
		Sim.report("%s: erecting — %d%%" % [display_name(), int(_erect * 100.0)],
			Sim.Ev.INFO)
		return false
	_gun_cd = float(kd["reload"])
	rounds_left -= 1
	var id: String = String(kd.get("missile", "kalibr"))
	# Out of the tube it is actually sitting in, along the tube's own axis.
	# Spawning it in the air on a computed bearing meant the round never
	# appeared to leave the vehicle — it simply existed, already flying.
	var from: Vector3 = global_position + Vector3(0, 3.0, 0)
	# Straight out of the tube, wherever the tube happens to be pointing, and
	# the tube points up. No lean onto the bearing: the round does that itself
	# once it is clear, and a canister launch that comes out already heading
	# for the target is the thing that made these look like guns.
	var dir := Vector3.UP
	if is_instance_valid(_muzzle):
		from = _muzzle.global_position
		dir = -_muzzle.global_transform.basis.z
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	# Guide onto the unit itself when one was locked; onto a bare mark otherwise.
	var aim: Node3D = map_lock as Node3D if is_instance_valid(map_lock) else null
	if aim == null:
		var mk := _TelMark.new()
		mk.team = 1 if team == 0 else 0
		world.add_child(mk)
		mk.global_position = mark
		aim = mk
	m.launch(id, Transform3D(Basis.looking_at(dir, up_ref), from), dir * 22.0,
		self, aim)
	# The primary mark first, then whatever else has been assigned, so a bus
	# given two extra points still puts a warhead on the one you laid to begin
	# with rather than leaving it alone.
	if not mirv_marks.is_empty():
		m.programmed = ([mark] as Array) + mirv_marks
	
	m.team = team
	world.add_child(m)
	store_released.emit(m)
	# Where it is going, not just that it has gone. A canister launch goes
	# straight up and turns over out of sight, so without this there is nothing
	# to tell you whether it is on its way to the mark or simply leaving.
	var brg: float = rad_to_deg(atan2(mark.x - from.x, -(mark.z - from.z)))
	Sim.report("%s: %s away — %.0f km on %03d, %d left" % [display_name(),
		String(WeaponSpec.get_spec(id)["short"]), rng * 0.001,
		int(wrapf(brg, 0.0, 360.0)), rounds_left], Sim.Ev.BAD)
	return true

## A place for the round to guide onto. A patch of ground is not a contact, so
## it is deliberately not lockable and not a radar return.
class _TelMark extends Node3D:
	var team := 1
	func _ready() -> void:
		add_to_group("no_lock")
	func hit_radius() -> float:
		return 6.0
	func is_alive() -> bool:
		return true
	func take_hit(_a: float, _f: Node = null) -> void:
		pass

## How far the piece still is from the bearing and elevation it needs, in
## radians: the worst of the two axes. Zero means it is laid and may fire.
func lay_error() -> float:
	# A launcher has nothing to lay. The round turns onto the bearing itself
	# once it is off the rail, so the erector never slews -- and asking it how
	# far its turret is from the target bearing therefore never returned zero,
	# and the launcher sat there "laying" for ever. What it is actually waiting
	# for is the canister to finish coming up.
	if vclass() == "tel":
		return (1.0 - _erect) * PI
	var aim := ground_aim()
	if aim == Vector3.INF:
		return PI
	var sol := fire_solution(aim, float(KINDS[kind]["muzzle"]))
	if sol.is_empty():
		return PI
	var want_yaw := atan2(aim.x - global_position.x, -(aim.z - global_position.z))
	var yaw_off := absf(wrapf(-want_yaw - (rotation.y + _turret.rotation.y), -PI, PI))
	var max_el: float = deg_to_rad(70.0) if vclass() != "mbt" else deg_to_rad(20.0)
	var want_el: float = clampf(float(sol["elev"]), deg_to_rad(-9.0), max_el)
	return maxf(yaw_off, absf(want_el - _mantlet.rotation.x))

## Howitzers and rocket launchers arc onto wherever the barrel is pointing.
func _fire_indirect(world: Node, kd: Dictionary) -> bool:
	var aim := ground_aim()
	if aim == Vector3.INF:
		return false
	var sol := fire_solution(aim, float(kd["muzzle"]))
	if sol.is_empty():
		return false
	# Straight out of the tubes. The lay check has already established that the
	# barrels are pointing at the solution, so using their actual axis is both
	# the correct direction and the one the player is looking at -- a round that
	# leaves on a computed bearing while the tubes point somewhere else is the
	# thing that looks wrong however good the fall of shot is.
	var origin: Vector3 = _muzzle.global_position
	var el: float = sol["elev"]
	var tube := (-_muzzle.global_transform.basis.z).normalized()
	var flat := Vector2(aim.x - origin.x, aim.z - origin.z)
	var dir := Vector3(flat.x, 0, flat.y).normalized()
	if Sim.debug_weapons:
		# the tubes and the ballistics must agree, or the round leaves in a
		# direction the player can see is wrong however good the impact is
		print("[lay] el sol %.2f tube %.2f | bearing sol %.2f tube %.2f" % [
			rad_to_deg(el), rad_to_deg(asin(clampf(tube.y, -1.0, 1.0))),
			rad_to_deg(atan2(dir.x, -dir.z)), rad_to_deg(atan2(tube.x, -tube.z))])
	var launch := (dir * cos(el) + Vector3.UP * sin(el)) * float(sol["speed"])
	var salvo: int = int(kd.get("salvo", 1))

	last_solution = {"range": sol["range"], "elev": rad_to_deg(el),
		"salvo": rounds_left, "tof": sol["tof"], "charge": sol["charge"]}
	# One round per trigger press. Holding the trigger walks the rest of the pod
	# out at the ripple rate, so a fire mission is yours to place rather than an
	# all or nothing dump of everything on the rails.
	var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4),
		randf_range(-1.0, 1.0)) * (4.0 if salvo > 1 else 0.35)
	# an indirect round climbs away over its own battery, so it needs room
	_lob(world, launch + spread, float(kd["gun"]), float(kd["blast"]),
		2.2 if salvo > 1 else 4.2, aim, 90.0, salvo > 1)
	rounds_left = maxi(rounds_left - 1, 0)
	return true

func _lob(world: Node, vel: Vector3, dmg: float, blast: float, flash: float,
		aim := Vector3.INF, arm := 12.0, as_rocket := false) -> void:
	var shell := Aircraft.Shell.new()
	shell.arm_dist = arm
	shell.rocket = as_rocket
	if aim != Vector3.INF:
		shell.set_meta("aim", aim)
		shell.set_meta("origin", global_position)
	shell.vel = vel + linear_velocity
	shell.damage = dmg
	shell.blast = blast
	shell.shooter = self
	shell.team = team
	world.add_child(shell)
	shell.global_position = _muzzle.global_position
	Effects.muzzle_flash(world, _muzzle.global_position, vel.normalized(), flash)
	Effects.dust(world, _muzzle.global_position, 4.5)
	Sfx.play_at(world, "boom", _muzzle.global_position, -2.0, 0.7, 4000.0)
	# The weapon camera can ride this too. Only launchers announced their rounds,
	# so a rocket battery -- the one thing whose whole point is watching where
	# the salvo lands -- was the one thing you could not follow.
	store_released.emit(shell)

func fire_coax(world: Node) -> bool:
	if _coax_cd > 0.0 or not alive:
		return false
	var kd: Dictionary = KINDS[kind]
	# A .50 on a ring mount is slower and hits harder than a tank's coax.
	_coax_cd = float(kd.get("mg_rate", 0.09))
	var spread: float = 0.006 if vclass() != "lav" else 0.009
	var dir := -_muzzle.global_transform.basis.z
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread),
		randf_range(-spread, spread))).normalized()
	Effects.tracer(world, _muzzle.global_position - dir * 1.5,
		dir * float(kd.get("muzzle", 900.0)) + linear_velocity,
		self, float(kd.get("mg_damage", 26.0)), team)
	Effects.muzzle_flash(world, _muzzle.global_position - dir * 1.2, dir, 0.8)
	Sfx.play_at(world, "rifle", _muzzle.global_position, -8.0, 0.85, 600.0)
	return true

func hit_radius() -> float:
	return 1.8 if vclass() == "lav" else 3.4

func is_alive() -> bool:
	return alive

## See Aircraft.hull_distance: the walk-up scan has to compare like with like.
##
## Measured relative to the hull, not to whatever node each mesh happens to hang
## from. Taking the mesh's own transform alone threw away every offset above it,
## and the turret is a metre and a fifth up: an Abrams reported a roof at 1.50 m,
## which is below its own turret ring. Everything that asks how big this vehicle
## is -- the walk-up scan most of all -- was answered a metre and a half short.
## This cannot use global_transform the way an aircraft does, because setup()
## runs before the vehicle is in the tree.
func _cache_bounds() -> void:
	var box := AABB()
	var first := true
	for c in find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf: Transform3D = mi.transform
		var up: Node = mi.get_parent()
		while up != null and up != self:
			if up is Node3D:
				xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var t: AABB = xf * mi.get_aabb()
		box = t if first else box.merge(t)
		first = false
	bounds = box

func hull_distance(p: Vector3) -> float:
	var lp: Vector3 = global_transform.affine_inverse() * p
	var mn := bounds.position
	var mx := bounds.end
	var q := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y),
		clampf(lp.z, mn.z, mx.z))
	return lp.distance_to(q)

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	# Whoever simulates this vehicle decides whether it just died. A ghost of a
	# remote player's tank, or a garrison the host owns, reports the hit instead
	# of applying it, and learns the outcome from replicated state.
	if Sim.net != null and Sim.net.active and not Sim.net.is_host \
			and (has_meta("net_id") or has_meta("zone_asset")):
		Sim.net.report_ground_damage(self, amount)
		return
	apply_damage(amount)

## The damage itself, with no question of who is allowed to deal it.
func apply_damage(amount: float) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
		Effects.explosion(get_tree().current_scene, global_position + Vector3(0, 1.5, 0), 18.0)
		remove_from_group("boardable")
		_wreck()
		died.emit(self)

## What is left after the ammunition goes up. The turret comes off — that is
## what a hull full of propellant actually does, and it is the one silhouette
## everybody recognises — the paint burns off what is left, and the hull sits
## there on fire for a while before settling down to smoke.
func _wreck() -> void:
	if _wrecked:
		return
	_wrecked = true
	_burn = 0.0
	var parent := get_parent()
	if is_instance_valid(_turret) and parent != null:
		# Off the hull and onto a piece of debris, so it flies, lands and stays
		# where it fell rather than continuing to track the gun.
		var thrown := Effects.Debris.new()
		thrown.name = "%s turret" % name
		thrown.rest_offset = 0.8
		thrown.life = 1e9                # a blown turret is scenery from now on
		var keep := _turret.global_transform
		for c in _turret.get_children():
			if c is MeshInstance3D or c == _mantlet:
				_turret.remove_child(c)
				thrown.add_child(c)
		parent.add_child(thrown)
		thrown.global_transform = keep
		# up, over the side, and spinning
		thrown.vel = Vector3(randf_range(-3.0, 3.0), randf_range(7.0, 12.0),
			randf_range(-3.0, 3.0))
		thrown.spin = Vector3(randf_range(-2.5, 2.5), randf_range(-3.5, 3.5),
			randf_range(-2.5, 2.5))
		_turret.visible = false
	# scorch whatever is left standing
	for n in _all_meshes(self):
		var mi := n as MeshInstance3D
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			var burnt := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			burnt.albedo_color = burnt.albedo_color.darkened(0.72)
			burnt.metallic = 0.0
			burnt.roughness = 0.95
			mi.material_override = burnt
	_fire = Effects.ember_particles(Color(1.0, 0.5, 0.12), 1.6, 26)
	_fire.emitting = true
	_fire.position = Vector3(0, 1.6, 0.4)
	add_child(_fire)
	var smoke := Effects.trail_particles(Color(0.14, 0.14, 0.15), 4.5, 40)
	smoke.emitting = true
	smoke.position = Vector3(0, 2.0, 0.2)
	add_child(smoke)
	_wreck_smoke = smoke
	# a handful of pieces thrown clear
	for i in 5:
		if parent == null:
			break
		var d := Effects.Debris.new()
		var sz := Vector3(randf_range(0.3, 0.9), randf_range(0.2, 0.5),
			randf_range(0.3, 1.0))
		d.rest_offset = sz.y * 0.5
		var db := MeshKit.begin()
		MeshKit.box(db, sz, Vector3.ZERO)
		d.add_child(MeshKit.mi(MeshKit.finish(db,
			MeshKit.mat(Color(0.13, 0.13, 0.14), 0.9, 0.15)), "Chunk"))
		parent.add_child(d)
		d.global_position = global_position + Vector3(0, 1.8, 0)
		d.vel = Vector3(randf_range(-9.0, 9.0), randf_range(5.0, 14.0),
			randf_range(-9.0, 9.0))
		d.spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))

## Every MeshInstance3D under a node, so the whole vehicle can be scorched.
func _all_meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out

## Set by the world while the commander's sight page is up on this vehicle.
var sight_active := false

## Where the commander's sight sits. The sensor mounts here rather than at the
## eighteen metres a ship's masthead assumes.
func sight_height() -> float:
	return 1.95 if vclass() == "lav" else 2.65

func crew_position() -> Vector3:
	if vclass() == "lav":
		return global_transform * Vector3(-0.42, 1.65, -0.30)
	return global_transform * Vector3(-0.55, 2.35, 1.0)
