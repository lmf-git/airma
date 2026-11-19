class_name TestSuite
extends RefCounted
## One group of command-line tests. `TestHarness` builds one of each, offers
## them every argument it is given, and calls their per-frame work.

var world: World
var harness: TestHarness

func _init(w: World, h: TestHarness) -> void:
	world = w
	harness = h

## Claims a command-line flag; false if it is not one of this group's.
func parse_arg(_a: String) -> bool:
	return false
