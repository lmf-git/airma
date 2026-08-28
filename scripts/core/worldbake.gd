class_name WorldBake
## The parts of world generation that are the same every run, kept on disk.
##
## Nothing in here is a decision -- it is all the *result* of running the same
## deterministic field over the same coordinates. The road distance field, the
## ground mask, the relief map and the scatter come out identical every launch
## and cost the best part of ten seconds to arrive at, so they are computed
## once and read back after that.
##
## The hard part of a cache like this is knowing when it is wrong. A version
## number that has to be remembered gets forgotten, and then the game ships
## with terrain that does not match its own code. This keys on a hash of the
## scripts that do the generating instead: change how a road is routed or where
## the noise is sampled and the bake is discarded on the next run without
## anyone having to notice. In an exported build the sources are not readable
## and the binary cannot change under itself, so VERSION carries it alone.

const VERSION := 1
const PATH := "user://world_bake.dat"
## Every script whose output ends up in the bake. Missing one means stale
## terrain that looks right and is not, so err towards listing too many.
const SOURCES := [
	"res://scripts/core/sim.gd",
	"res://scripts/world/terrain.gd",
	"res://scripts/world/scenery.gd",
	"res://scripts/ui/map_view.gd",
]

static var _data: Dictionary = {}
static var _dirty := false
static var _loaded := false
static var enabled := true
static var stats := {}

static func signature() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("v%d" % VERSION).to_utf8_buffer())
	for f in SOURCES:
		var fa := FileAccess.open(f, FileAccess.READ)
		if fa == null:
			continue
		ctx.update(fa.get_buffer(fa.get_length()))
		fa.close()
	return ctx.finish().hex_encode()

## Read the bake if there is one and it belongs to this build. Safe to call
## more than once.
static func begin() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {}
	_dirty = false
	stats = {"hit": 0, "miss": 0}
	if not enabled:
		stats["state"] = "disabled"
		return
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open_compressed(PATH, FileAccess.READ,
		FileAccess.COMPRESSION_ZSTD)
	if f == null:
		stats["state"] = "no bake on disk"
		return
	var sig := f.get_pascal_string()
	if sig != signature():
		f.close()
		stats["state"] = "bake is for different code, discarded"
		return
	var got: Variant = f.get_var(true)
	f.close()
	if got is Dictionary:
		_data = got
		stats["state"] = "loaded"
		stats["load_ms"] = Time.get_ticks_msec() - t0
		stats["keys"] = _data.size()
	else:
		stats["state"] = "bake unreadable, discarded"

## What was baked for this key, or null. Callers compute and `put` on a miss.
static func get_baked(key: String) -> Variant:
	if not enabled or not _data.has(key):
		stats["miss"] = int(stats.get("miss", 0)) + 1
		return null
	stats["hit"] = int(stats.get("hit", 0)) + 1
	return _data[key]

static func put(key: String, value: Variant) -> void:
	if not enabled:
		return
	_data[key] = value
	_dirty = true

## For a table that only ever grows -- the terrain's node errors, which pick up
## new entries as you fly somewhere the tree has not had to think about. Writing
## four megabytes back on every launch to record that nothing changed is not
## worth the ninety milliseconds, so the count decides.
static func put_grown(key: String, value: Dictionary) -> void:
	if not enabled:
		return
	var had: Variant = _data.get(key)
	_data[key] = value
	if not (had is Dictionary) or (had as Dictionary).size() != value.size():
		_dirty = true

## Write the bake out, if anything in it is new. Called once the world is up,
## so a first run pays the generation cost and no run after it does.
static func finish() -> void:
	if not enabled or not _dirty:
		return
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open_compressed(PATH, FileAccess.WRITE,
		FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[bake] could not write %s: %s" % [PATH,
			error_string(FileAccess.get_open_error())])
		return
	f.store_pascal_string(signature())
	f.store_var(_data, true)
	f.close()
	_dirty = false
	stats["saved_ms"] = Time.get_ticks_msec() - t0
	stats["saved_bytes"] = _file_size()

static func _file_size() -> int:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n

## Throw the bake away. For the harnesses, and for anyone who wants to watch
## the world being made from nothing.
static func clear() -> void:
	_data = {}
	_dirty = false
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
