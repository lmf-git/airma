class_name TestHarness
extends RefCounted
## The command-line test harness: `--xxxtest` flags, screenshots and scripted
## runs. Created by `World` only when it is given command-line arguments it does
## not handle itself, so a normal game never builds any of it.
##
## Each group of tests is a `TestSuite`. This owns them, hands each argument to
## them in turn, and calls their per-frame work from `World._tick_world` at the
## same points it ran from when it was written inline there.
##
## To add a test: pick the suite it belongs to, claim its flag in that suite's
## `parse_arg`, keep its state and code together in a `#region`, and if it needs
## to run every frame give it a `tick_` function and call it from the hook below
## that matches where in the frame it has to run. Return true from a tick to end
## the frame there, as a `return` in `World._tick_world` would.

var world: World
var dev_options: DevOptions
var flight_tests: FlightTests
var weapon_tests: WeaponTests
var ground_tests: GroundTests
var naval_tests: NavalTests
var infantry_tests: InfantryTests
var terrain_tests: TerrainTests
var planet_tests: PlanetTests
var session_tests: SessionTests
var suites: Array[TestSuite] = []

func _init(w: World) -> void:
	world = w
	dev_options = DevOptions.new(w, self)
	flight_tests = FlightTests.new(w, self)
	weapon_tests = WeaponTests.new(w, self)
	ground_tests = GroundTests.new(w, self)
	naval_tests = NavalTests.new(w, self)
	infantry_tests = InfantryTests.new(w, self)
	terrain_tests = TerrainTests.new(w, self)
	planet_tests = PlanetTests.new(w, self)
	session_tests = SessionTests.new(w, self)
	suites = [dev_options, flight_tests, weapon_tests, ground_tests, naval_tests, infantry_tests, terrain_tests, planet_tests, session_tests]


func parse_arg(a: String) -> bool:
	for s in suites:
		if s.parse_arg(a):
			return true
	return false


## Called from `World._tick_world`.
## Early in the frame: after the hangar camera and the preview, before the
## sensor pod and the armour sight are settled.
func tick_before_sensors(delta: float) -> void:
	flight_tests.tick_gunner(delta)


## Called from `World._tick_world`.
## After the frame's input and modal state are worked out, before the
## hangar's session line.
func tick_after_input(_delta: float) -> void:
	session_tests.tick_nettest()


## Called from `World._tick_world`.
## After boarding and the landing watch. True ends the frame.
func tick_after_flight(delta: float) -> bool:
	dev_options.tick_dump(delta)
	dev_options.tick_net_log(delta)
	weapon_tests.tick_wtest(delta)
	planet_tests.tick_fps_log(delta)
	ground_tests.tick_boom()
	flight_tests.tick_cam(delta)
	ground_tests.tick_arty(delta)
	if flight_tests.tick_heli(delta):
		return true
	flight_tests.tick_ctl(delta)
	flight_tests.tick_hover(delta)
	return false


## Called from `World._tick_world`.
## The bulk of the per-frame tests, after the admin camera's follow. True
## ends the frame.
func tick_main(delta: float) -> bool:
	dev_options.tick_nuke_shot()
	dev_options.tick_road_probe()
	weapon_tests.tick_decoy()
	ground_tests.tick_mirv_lock(delta)
	ground_tests.tick_map_lock(delta)
	ground_tests.tick_tel_range()
	terrain_tests.tick_terrain()
	ground_tests.tick_fire_map(delta)
	ground_tests.tick_rocket_view()
	ground_tests.tick_moon()
	ground_tests.tick_launch()
	ground_tests.tick_icbm()
	session_tests.tick_obj(delta)
	ground_tests.tick_track_kill(delta)
	flight_tests.tick_rof(delta)
	ground_tests.tick_field_svc(delta)
	ground_tests.tick_drive()
	session_tests.tick_mode(delta)
	weapon_tests.tick_apkws(delta)
	naval_tests.tick_carrier_conn(delta)
	session_tests.tick_admin(delta)
	if session_tests.tick_restart(delta):
		return true
	naval_tests.tick_shiptest(delta)
	flight_tests.tick_wcam(delta)
	if naval_tests.tick_naval(delta):
		return true
	if naval_tests.tick_bat(delta):
		return true
	planet_tests.tick_sky()
	if naval_tests.tick_subtest():
		return true
	if weapon_tests.tick_cruise(delta):
		return true
	weapon_tests.tick_flirtest()
	if planet_tests.tick_culltest():
		return true
	planet_tests.tick_geomtest()
	if ground_tests.tick_tanksensor(delta):
		return true
	if naval_tests.tick_navsensor(delta):
		return true
	if weapon_tests.tick_salvo(delta):
		return true
	weapon_tests.tick_shake(delta)
	weapon_tests.tick_break(delta)
	weapon_tests.tick_clutter(delta)
	weapon_tests.tick_cm(delta)
	if weapon_tests.tick_mav(delta):
		return true
	if planet_tests.tick_fps(delta):
		return true
	if session_tests.tick_faction():
		return true
	if planet_tests.tick_cloud():
		return true
	if weapon_tests.tick_tracer():
		return true
	if planet_tests.tick_globe_world():
		return true
	if planet_tests.tick_chart():
		return true
	if planet_tests.tick_map():
		return true
	if planet_tests.tick_globe():
		return true
	if await planet_tests.tick_cost():
		return true
	if await planet_tests.tick_map_shot():
		return true
	if await planet_tests.tick_layer():
		return true
	if planet_tests.tick_sun():
		return true
	if planet_tests.tick_air():
		return true
	if await planet_tests.tick_patch():
		return true
	if planet_tests.tick_planet():
		return true
	if terrain_tests.tick_field():
		return true
	if flight_tests.tick_light(delta):
		return true
	if flight_tests.tick_wing(delta):
		return true
	if await ground_tests.tick_susp(delta):
		return true
	if await session_tests.tick_spawn(delta):
		return true
	if await weapon_tests.tick_lag(delta):
		return true
	if await ground_tests.tick_tel(delta):
		return true
	if terrain_tests.tick_seamix():
		return true
	if weapon_tests.tick_locktime(delta):
		return true
	if terrain_tests.tick_float():
		return true
	if naval_tests.tick_boat(delta):
		return true
	if flight_tests.tick_fx():
		return true
	if naval_tests.tick_guard(delta):
		return true
	if session_tests.tick_respawn(delta):
		return true
	if weapon_tests.tick_wave(delta):
		return true
	if naval_tests.tick_conn(delta):
		return true
	if weapon_tests.tick_mp(delta):
		return true
	if flight_tests.tick_hover2(delta):
		return true
	if ground_tests.tick_slope(delta):
		return true
	if ground_tests.tick_svc(delta):
		return true
	if flight_tests.tick_ad(delta):
		return true
	if weapon_tests.tick_asat(delta):
		return true
	if flight_tests.tick_ap(delta):
		return true
	if naval_tests.tick_fleetfire(delta):
		return true
	if weapon_tests.tick_tacnuke(delta):
		return true
	if weapon_tests.tick_nuke(delta):
		return true
	if weapon_tests.tick_reach():
		return true
	if terrain_tests.tick_subview():
		return true
	if weapon_tests.tick_land(delta):
		return true
	if await flight_tests.tick_accel():
		return true
	if flight_tests.tick_ab():
		return true
	if await ground_tests.tick_tel_rig():
		return true
	if naval_tests.tick_river():
		return true
	if await session_tests.tick_warlords():
		return true
	if await terrain_tests.tick_gun():
		return true
	if await session_tests.tick_pause():
		return true
	if await weapon_tests.tick_tfr():
		return true
	if terrain_tests.tick_churn():
		return true
	if await naval_tests.tick_carrier():
		return true
	if terrain_tests.tick_obstacle():
		return true
	if await terrain_tests.tick_lod():
		return true
	if terrain_tests.tick_skirt():
		return true
	if terrain_tests.tick_road():
		return true
	terrain_tests.tick_town()
	if naval_tests.tick_vls(delta):
		return true
	dev_options.tick_auto_diag(delta)
	if weapon_tests.tick_splash(delta):
		return true
	naval_tests.tick_shipnet(delta)
	weapon_tests.tick_mask(delta)
	flight_tests.tick_form(delta)
	session_tests.tick_chat(delta)
	flight_tests.tick_cas(delta)
	if naval_tests.tick_dc(delta):
		return true
	weapon_tests.tick_trig(delta)
	if terrain_tests.tick_biome():
		return true
	terrain_tests.tick_seam()
	weapon_tests.tick_laser(delta)
	flight_tests.tick_hud(delta)
	weapon_tests.tick_fire(delta)
	flight_tests.tick_view(delta)
	if await weapon_tests.tick_lock(delta):
		return true
	flight_tests.tick_flap(delta)
	naval_tests.tick_sea()
	if naval_tests.tick_sub(delta):
		return true
	naval_tests.tick_fleet(delta)
	weapon_tests.tick_pod(delta)
	return false


## Called from `World._tick_world`.
## After the town sets, the street fight's support and the map bounds.
func tick_after_street(delta: float) -> void:
	infantry_tests.tick_cqb(delta)
	infantry_tests.tick_obs()
	infantry_tests.tick_gib()
	infantry_tests.tick_round()
	infantry_tests.tick_prone()
	infantry_tests.tick_yaw()
	infantry_tests.tick_zoom()
	infantry_tests.tick_arms()
	infantry_tests.tick_cqb_fix()
	infantry_tests.tick_streak()
	infantry_tests.tick_ball()
	flight_tests.tick_hf()
	infantry_tests.tick_bounds()
	flight_tests.tick_hgear(delta)
	dev_options.tick_cqb_view()
	infantry_tests.tick_sight()
	infantry_tests.tick_ground_probe()
	infantry_tests.tick_bridge_probe()
	infantry_tests.tick_bridge_drive()
	infantry_tests.tick_range_listen()
	infantry_tests.tick_range_cam()
	infantry_tests.tick_range()
	infantry_tests.tick_aim(delta)
	flight_tests.tick_seat(delta)
	ground_tests.tick_key(delta)
	flight_tests.tick_tvc(delta)
	flight_tests.tick_board(delta)
	flight_tests.tick_jolt(delta)
	flight_tests.tick_overlap(delta)
	ground_tests.tick_wreck(delta)
	ground_tests.tick_tank(delta)
	dev_options.tick_fx_2(delta)
	flight_tests.tick_turn(delta)
	dev_options.tick_run_for()


## Called from `World._tick_world`.
## Last in the frame, after the hull camera has eased.
func tick_end(delta: float) -> void:
	dev_options.tick_shot_zoom()
	dev_options.tick_shot_obj()
	dev_options.tick_shot_podmark(delta)
	dev_options.tick_hold_gun()
	dev_options.tick_look_from()
	dev_options.tick_shot()


#region Shared between groups

## Select a store by name, and say so plainly when the aeroplane is not
## carrying it. `maxi(find(w), 0)` quietly fell back to the first station --
## the gun -- so a test aimed at a Harpoon or a JDAM printed "release: refused"
## and looked like a broken weapon rather than the wrong aircraft.
func _arm_with(w: String) -> bool:
	if not is_instance_valid(world.player):
		return false
	var slot: int = world.player.weapon_types.find(w)
	if slot < 0:
		print("[test] %s does not carry %s — it has %s. Add --jet=NAME." % [
			world.player.spec.get("name", "?"), w, str(world.player.weapon_types)])
		return false
	world.player.set_weapon(slot)
	return true

## Synthesise a key for the harness, straight into the same handler the shell
## uses, so the test exercises the real path rather than calling chat methods.
func _press(code: Key, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	e.pressed = true
	world._shell_input(e)

func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := world.get_viewport().get_texture().get_image()
	img.save_png(world._shot)
	print("shot saved: ", world._shot)
	world.get_tree().quit()
#endregion
