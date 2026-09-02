class_name Pid
extends RefCounted
## A closed loop controller with the three terms and the two things that make
## the difference between one that works and one that oscillates: anti-windup,
## and a derivative that does not kick.
##
## The helicopter's hover was a proportional-integral loop on vertical speed
## with no derivative at all, wrapped in a bare proportional loop on height. It
## held a number; it did not hold the aircraft. Attitude was not in the loop
## anywhere, so a machine that had been tipped over stayed tipped over and flew
## away from where it was told to stop.

var kp := 1.0
var ki := 0.0
var kd := 0.0
## How much authority the integral alone may command. An integrator that can
## saturate the output on its own is what makes a loop hunt.
var i_limit := 0.5
var out_limit := 1.0

var _i := 0.0
var _last_err := 0.0
var _started := false

func _init(p := 1.0, i := 0.0, d := 0.0, ilim := 0.5, olim := 1.0) -> void:
	kp = p
	ki = i
	kd = d
	i_limit = ilim
	out_limit = olim

func reset() -> void:
	_i = 0.0
	_last_err = 0.0
	_started = false

## One step. `err` is where you want to be minus where you are.
func step(err: float, dt: float) -> float:
	if dt <= 0.0:
		return clampf(kp * err, -out_limit, out_limit)
	# Rate of change of the error, not of the setpoint: a step change in what
	# you are asking for would otherwise put a spike through the derivative and
	# slam the control against its stop.
	var d := 0.0
	if _started:
		d = (err - _last_err) / dt
	_last_err = err
	_started = true
	var i_try: float = clampf(_i + err * dt, -i_limit / maxf(ki, 0.0001),
		i_limit / maxf(ki, 0.0001))
	var out: float = kp * err + ki * i_try + kd * d
	# Anti-windup: only keep the integration if the output is not already
	# against its stop and being pushed further into it.
	if absf(out) <= out_limit or signf(out) != signf(err):
		_i = i_try
	else:
		out = kp * err + ki * _i + kd * d
	return clampf(out, -out_limit, out_limit)
