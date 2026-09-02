# Combined Arms

A jet flight simulator built for **Godot 4.8**. Four flyable airframes, a
rigid-body flight model with fly-by-wire, working internal weapons bays, and a
3 km runway you can actually take off from and land on.

Everything — aircraft, terrain, runway, effects — is generated procedurally in
GDScript. There are no imported art assets.

```
godot --path .          # or open the folder in the Godot editor and press F5
```

---

## The hangar

Twenty-one airframes across six nations plus civil traffic, filterable by
faction in the hangar. The hangar also has a **GROUND** tab (seven vehicles) and
a **NAVAL** tab (four crewable warships), so the whole fleet is selectable from
one place.

| NATO | | OPFOR | |
|---|---|---|---|
| **F-22A Raptor** (US) | ventral + cheek bays, thrust vectoring | **Su-57 Felon** (RU) | bays, vectored, big wing |
| **F-35B Lightning II** (US) | two bays, lift fan and a swivelling nozzle | **Su-35S Flanker-E** (RU) | vectored, enormous slow-speed turn |
| **F-16C Viper** (US) | pylons, fastest roll rate | **MiG-29 Fulcrum** (IR) | light, short legged, quick to point |
| **F-15E Strike Eagle** (US) | pylons, climbs like a rocket | **J-20 Mighty Dragon** (CN) | canards, bays, long reach |
| **Eurofighter Typhoon** (UK) | canard delta, huge instantaneous turn | | |
| **Dassault Rafale C** (FR) | close-coupled canards, sharp when slow | | |
| **AC-130J Ghostrider** (US) | 105 mm / 40 mm / 25 mm side battery, walkable hold | | |
| **C-130J Super Hercules** (US) | cargo ramp and a hold you can walk into | | |
| **AH-64E Apache** (US) · **Tiger HAD** (FR) | attack helicopters | **Mi-28N Havoc** (RU) · **Z-10** (CN) | attack helicopters |

Plus four civilian aircraft to fill the sky: the **A320-series airliner**, the
**Northwind 8Q** commuter turboprop, the **Skylane 172** light single and the
**Ranger 206** JetRanger.

The stealth jets carry everything inside and only expose it when the doors open.
External jets are always ready to fire but pay for it in drag and radar cross
section, which is what the AI uses to pick who to chase first.

The **AC-130** is flown as an orbit-and-shoot gunship. The 105 mm, 40 mm and
25 mm barrels run out through the port side of the belly — no pylons — and each
one fires from its own muzzle. Put the targeting pod on something, pick a gun
with `1`/`2`/`3` and the battery lobs shells at the designated point. The **C-130** is the same airframe without the guns — drop the
ramp and people can walk into the hold.

## Modes

*Quiet:* **Runway start** (cold on 36), **Free flight**, **Approach** (12 km
final), **Ramp walk** (start on foot beside the flight line), **Carrier trap**
(three miles behind the boat with the hook down).

*Fighting:* **Patrol**, **Conquest** (five sectors, ticket bleed),
**Rush** (sectors open one at a time), **Warlords** (sequential sectors paying
command points), **Team Deathmatch**, **Free For All**.

Opposition in the battle modes is a mixed package: three fighters from the
opposing bloc, a pair of attack helicopters working low over the sectors, and
SAM sites. Sector armour is crewed — the tanks traverse, lead their targets and
shoot, and the self propelled guns arc onto anything that comes into reach.

Battle modes lay out capture zones with garrisons — flip one by holding the ring
or by flattening everything inside it. Tickets, sector ownership and capture
progress are drawn across the top of the HUD.

**SANDBOX** is everything at once and nothing scoring: the vehicle park, the
flight line, hostile aircraft, gunships and shipping, and the satellites
overhead. The hostile side of that is *only* here and on the admin page — the
no-threat missions stay no-threat.

`F3` opens the admin page, which can put any of those sets into *any* mission,
and does it idempotently: it counts what is already there and spawns only the
shortfall, so asking twice tops the set up instead of laying down a second one.

## Multiplayer

Host/join over ENet from the hangar screen (enter an address, HOST or JOIN).
The hangar shows the **address to read out**, port included, for as long as the
session is up — `192.168.0.45:27015`, or the external address once the router
has forwarded it. It used to be a mission-log line that scrolled away thirty
seconds into the flight, and the label meant to carry it in the hangar was
never once written to.

Hosting failed outright if the port was already bound, with an engine error and
no explanation. Three things were wrong. The peer was never dropped before a new
one was made, so hosting twice in a sitting was fatal; the multiplayer signals
were connected on every host and disconnected on none, so they stacked up; and
nothing released the socket or the router mapping when the window was shut, so a
lingering process kept the port for the next session to trip over. The game
hands both back on the way out now, and if the port really is in use it says
which port and what is most likely holding it rather than failing silently. It
does not quietly move to another port — an address you read out to somebody has
to be the address they can type.
The host asks the router for a port mapping over **UPnP** when it starts, so a
game is reachable from outside the LAN without anyone editing a firewall — the
hangar prints the external address to pass to your friends, and falls back to
LAN-only with a note if the router refuses or has UPnP switched off. Discovery
runs on its own thread, so a router that never answers costs you nothing but a
line of text. The mapping is dropped again on quit.
The host runs whatever match is selected and tells joiners which one to load, so
both ends have the same sectors; sector ownership, capture progress and ticket
counts are then **authoritative on the host** and pushed to clients twice a
second rather than being simulated twice and drifting apart.
Aircraft state is broadcast at 20 Hz. Remote jets and vehicles are **kinematic
ghosts** — frozen rigid bodies moved on the physics tick, dead-reckoned along
their last reported velocity and eased onto the last reported pose, so Godot's
own physics interpolation smooths them for the renderer instead of them
stuttering between packets. Missile launches and hits replicate as events. Players on foot sync too,
including passengers riding in someone else's cargo hold — the hold owner is
sent with the packet so occupants stay attached to the right aircraft rather
than drifting in world space.

**Everything that comes apart, comes apart on every screen.** Four things were
being simulated on one machine and only hinted at on the others, all with the
same shape of fault — the packet carried a pose and an alive flag and nothing
about what the thing had *become*. A tank a remote player was driving simply
stopped, upright and intact, instead of losing its turret and burning; a jet you
had just shot down went still and stayed whole; a ship you had helped sink went
quietly rigid rather than breaking in two. The vehicle packet carries an alive
bit now, a downed aeroplane's ghost runs the same wreck it would at home (minus
the `died` signal, which scores the kill and must fire once in the session
rather than once per machine), a client breaks and settles a hull from the sink
fraction the host sends, and flare and chaff bits mean a remote aeroplane
defending itself looks like one.
Finding that needed a two-client run with the fleet fighting: the client showed
3 sunk and 2 broken in two while the host showed **seven ships and none of
either**, because the host had already cleaned its wrecks up and a client, never
running the sinking clock itself, kept every wreck it had ever seen. Ten hulls
on one end, seven on the other. A hull the host stops publishing is now dropped.
Both ends run 10 down to 7.

**The sky is host-authoritative.** The weather preset, the clock and the rate it
runs at all come from the host, pushed every couple of seconds and once more
whenever somebody joins. Two players flying the same sortie at different times
of day is not a cosmetic difference — it changes what you can see and what can
see you. Verified with a client started on `clear` joining a host on `dusk`: it
adopts the host's preset and the same 7541 puffs, and the two clocks stay within
a couple of degrees of sun elevation.

**The fleet replicates too.** Ships need no spawn roster: every peer lays the
same fleet down in the same order at load, so a hull is addressed by its index
in that plan and the host only has to say where it is and what state it is in.
Clients hold theirs as pictures -- posed, never simulated -- so the two ends
cannot drift apart, and the damage state travels with the pose so the fires and
the list look the same on every screen. Taking the conn of a ship in a session
hands the wheel over rather than forking the simulation: the orders go to the
host and the hull comes back, which at five degrees a second of turn rate is
not something you can feel.

**The host owns the match.** A joiner's mission buttons are disabled and its
LAUNCH reads HOST STARTS; the host's selection is pushed to every hangar as it
changes, so a joiner is always looking at what it is actually going to get and
cannot start something else on the same connection. Two separate messages do
this and sending only one of them was a regression worth recording: the lobby
message tells a joiner what the host has *selected*, and it takes a second
message to make it load the match already running. With only the first, three
clients sat in whatever they had launched locally, on identical default start
points, in a mission the host was not flying.

**Up to eight in a session**, not two. Verified with four peers: every one of
them reaches `roster=4` holding three ghosts.

Everyone gets their own **spawn slot**. Two players who pick the same aircraft
used to be handed the same start point and would begin the match inside each
other. Each peer takes a slot from its rank in the roster and is placed to
alternating sides of the leader, stepped down so nobody is directly above
anybody else. Ground starts keep their wheels on the apron — the offset is
applied across the ramp and then re-seated to local ground height — while air
starts take it whole.

Hashing the peer id, which was the first answer, is fine for two players and
hopeless for more: with four in the session two of them collided on the same
slot **65% of the time**. Ranking the roster gives a unique slot each, and
because every peer holds the same roster and sorts it the same way they all
reach the same answer without being told.

It also cannot be worked out at mission start. A joiner launches before its
connection has finished — its own id is still the default and its roster is
empty — so it decides it is number one and stays exactly where the host is.
Measured with four peers: all four on identical coordinates. The slot is
recomputed on every roster change instead, and always applied to the *original*
start point rather than to wherever the aeroplane has got to, so refining the
answer moves it to the right place instead of shifting it again. Four peers now
take slots 0, 1, 2 and 3.

## Helicopters

Four gunships on a rotary flight model: the main rotor makes thrust along the
disc axis, so you fly them the way you fly a real helicopter — tilt the aircraft
and the thrust vector goes with it. Collective is on the throttle keys, the tail
rotor holds the nose, translational lift makes the disc happier once you are
moving, and there is a ground cushion in the hover. The stability system trims
out main-rotor torque automatically; switch the assist off with `H` and you hold
the pedal yourself. Below translational speed the sideslip angle is meaningless,
so the pedal loop falls back to holding yaw rate.

## Support, and what an aircraft is for

Two aircraft were added whose entire stated role was unimplemented — a KC-135
that could not refuel anybody and an E-3 with no radar behind the rotodome — and
the satellites were targets that gave their owner nothing. All three now do
their job through one idea: **coverage**, which is how far a *side* can see, as
opposed to how far one aeroplane's own set reaches.

| | reach |
|---|---|
| the aeroplane's own radar | 40 km (10–80 selectable) |
| with a reconnaissance satellite up | 130 km |
| with an E-3 airborne | 190 km |

Which is what makes the ASAT worth firing: shoot the recon satellite down and
that side drops back to what it can see for itself.

**Aerial refuelling** is a formation problem, not a button. You have to get into
the box behind the boom — within thirty metres, inside a 26° cone off the
tanker's tail, and matched to within 26 m/s — and stay there. Drift out and the
boom disconnects. There is no switch: fuel goes in whenever you are in the box,
the same way it does on the real thing once the boom is flying.

**Ground servicing** closes the sortie loop, which was open: you could land and
there was nothing you could do about being empty. `rearm` and `restock` appeared
nowhere in the project, and the single mention of resupply was a comment on a
tank saying its rounds were "refilled on resupply", which nothing implemented.
Stop on the ground near a friendly base or a carrier deck and the crew come out —
fuel, hull, belted ammunition and stores, a bit at a time, so a turnaround takes
longer the emptier you come home.

## Satellites, and shooting them down

Both sides keep three satellites up — reconnaissance, communications and
navigation — on circular tracks above the map, and each of Russia, China and the
United States fields a **direct-ascent ASAT launcher** that can do something
about the other side's.

The orbit is an honest abstraction and worth saying so. Real low orbit is
7.5 km/s at 400 km, which crosses this entire world in eight seconds: you would
never see one, let alone shoot at one. These run at 70 km and 800 m/s — clearly
above everything, with no terrain within eighty kilometres of them, and fast
enough that the lead matters and slow enough that it can be led.

Getting the round there took four attempts and all four failures were
instructive. It began with 11.5 km/s of delta-v and went to **2298 km**, passing
the satellite by thirty-three; sized down it still reached 283 km; sized down
again it undershot at 64. And throughout, the round was being throttled to a
fifth of its rated g by the air-density term — correct for something that steers
with fins, wrong for a kill vehicle, which steers on divert thrusters and does
not care what the air is doing. With `vacuum_divert` set, the boost matched to
the climb it actually has to make, and the launcher laying on a lead point
rather than firing straight up, the round reaches 58 km and passes **15 m** from
the satellite.

A satellite that is hit comes apart — there is nothing up there to burn with —
and the pieces carry on along the track. Satellites are deliberately **not** in
the `hittable` group: that group is the radar picture, the lock list and the
blast sweep all at once, and putting something a hundred kilometres up in it
would have every fighter's AMRAAM considering it. They carry `hit_radius()`
instead, which is the path a round already uses to fuse on something that is not
a radar contact — the same way an interceptor kills a missile.

## Drones

Four unmanned aircraft, one to a faction: the **MQ-9A Reaper**, **Wing Loong
II**, **Shahed-129** and **Orion-E**. They are built round endurance rather than
performance — twenty metres of wing, a small pusher turboprop, hours of fuel and
a three g limit — and they are not going to win an argument with anything. What
they do is get somewhere and stay there.

That is what the autopilot is for. `TAB` gives you two modes:

- **Hold altitude** captures the height you are at and keeps it, wings level.
- **Loiter** does the same and holds a steady orbit, with **orbit direction**
  appearing below it so you can put the turn whichever side of the target you
  want.

The orbit is flown to a **radius**, not to a bank angle. A fixed bank looks
sensible until something fast uses it — radius is `V²/(g·tan(bank))`, so thirty
degrees at 250 m/s is an eleven kilometre circle and an F-16 asked to loiter
swept fifty-two degrees in a minute, a shape you cannot see the middle of.
Holding 1800 m instead banks according to speed, up to a fifty degree limit.
Measured over a minute: the MQ-9 comes round at 147°, the A-10 at 183°, the F-16
at 108° on its bank limit, and the altitude hold drifts 21, 34 and 38 metres
respectively over three quarters of a minute.

Taking hold of the stick disconnects it, the way every autopilot does — there is
no separate button to remember.

## Holding a hover

A helicopter's hover was a proportional-integral loop on vertical speed inside a
proportional loop on height. It held a *number* — it did not hold the aircraft.
Attitude was not in the loop anywhere, so a machine that had been tipped over
stayed tipped over and flew away from where you left it, and with no derivative
term what it did hold, it hunted.

**Auto hover** on the `TAB` menu is the proper cascade, the way a real stability
augmentation is built — outer loops slow, inner loops fast, so they do not fight
each other:

```
drift    ->  attitude demand  ->  cyclic
height   ->  vertical speed   ->  collective
heading  ->                       pedal
```

Seven `Pid` controllers, each with anti-windup and a derivative taken on the
error rather than the setpoint so a change of demand does not put a spike
through the control. It has the cyclic, the pedals and the lever, and gives them
straight back the moment you touch any of them — but it does **not** take the
rest of the cockpit, so you can work the weapons and the gear while it holds the
machine still.

`--hoverhold` throws an Apache sideways at 18 m/s with twenty degrees of bank
and a climb on, engages the hold and lets it settle. It comes back to **2.1 m
from the spot, 0.8° of bank, 0.4 m of height and 0.10 m/s**.

Getting there turned up two faults worth recording, both in the measuring rather
than the flying. The harness first seeded its height error with the *absolute*
altitude, and scored a perfect hover as 262 m out. Then it opened its
measurement window at fifteen seconds while the machine was still arresting
eighteen metres a second — and reported a hover that finished 1.3 m from the
spot as 33 m adrift. The instrumented trace is what settled it: the controller
had been working for two runs before the test agreed.

## Sensors

`ALT` + right click raises the targeting sensor as a full screen page and arms
it as a weapon station: `1`-`4` pick a store, `SPACE` releases at whatever the
pod is holding, `CTRL`+`T` point-tracks a vehicle or ground-stabilises a spot,
and `L` paints it with the laser so bombs and missiles guide onto the mark. The
same page is the helicopter's sight. A laser-guided bomb keeps steering onto a
point track as the ship under it moves, rather than at the patch of sea the
track started on, and the sensor page draws the falling bomb's predicted impact
mark so you can see whether the release is going to reach. Warheads that reach
water detonate there — a hit alongside a hull still shakes it, and you get the
column and the ring of spray instead of the round quietly vanishing.

The corner panels work like Arma's: `[` and `]` cycle the left and right slots
through off, sensor, radar and a north-up minimap, so you decide what sits in
your peripheral vision. Radar range steps through 10, 20, 40 and 80 km with
`-` and `=`, and both the RWR and the minimap scale to it.

**Gunships** have a proper gunner's station. Press `G` (or pick it from the TAB
menu) and the aircraft rolls into a left hand pylon turn on the autopilot while
you move back to the sight — measured holding a 24 degree bank at a steady
altitude and speed — with `1`/`2`/`3` selecting the 105 mm, the 40 mm or the
25 mm.

## Ground vehicles

Eighteen drivable vehicles, listed in the hangar alongside the aircraft — under
their own country's tab, or all together under GROUND. The ramp start parks **your own country's** vehicles on the apron —
everybody else's are deployed on ground that actually belongs to them, hostile
or friendly according to which bloc you are flying for — and every capture zone
garrisons two tanks and a patrol vehicle. Walk up and press `U` to get in.

| Main battle tanks | Self propelled guns | Rocket artillery |
|---|---|---|
| M1A2 Abrams · T-90M Proryv · ZTZ-99A | M109A7 Paladin · 2S19 Msta-S | M270 MLRS · BM-30 Smerch |

| Missile launchers | Light 4x4s |
|---|---|
| Kalibr · Zircon · Fattah · Khorramshahr · Oreshnik · DF-21D | M1151 HMMWV · Jackal 2 · Panhard VBL · GAZ-2330 Tigr · CSK-131 Mengshi · Safir |

A **MANPADS team** is not a vehicle and not an installation — three men, a tube
and a crate, sitting in a capture zone. It is the mirror image of a battery: a
SAM site cannot hold anything down in the ground clutter and therefore pushes
you low, and this is what is waiting when you get there. Five kilometres of
reach, a ceiling of 1800 m, no radar to warn you on the RWR, and an infrared
seeker a flare will pull off — if you saw it coming. Between the two of them,
neither altitude is safe.

| Air defence batteries | Infantry fighting vehicles | Anti-aircraft guns | Anti-satellite |
|---|---|---|---|
| Patriot · S-400 · HQ-9B · Bavar-373 · Sky Sabre · SAMP/T | M2A3 Bradley · BMP-3 · ZBD-04A · Warrior · VBCI · Boragh | M-SHORAD · Shilka · Gepard · PGZ-09 | GMD-A · Nudol · SC-19 |

An **air defence battery** is the first thing on the field that shoots back at
aircraft properly. It does not lay a gun: it acquires a contact, trains its
rails on the bearing, raises them and sends a round, and everything that makes
it dangerous is in the missile. An **anti-aircraft gun** does the short-range
half of the same job with a very fast shell. An **infantry fighting vehicle**
sits between the 4x4s and the tanks — an autocannon that will not trouble
frontal armour and ruins everything softer.

The **light 4x4s** are one per faction and they are not armour: a ladder
chassis, a crew cab, a load bed, and a ring mount on the roof with a heavy
machine gun on it. Seventy hit points against a tank's three hundred, and
nothing on them will trouble a tank — what they have is 70 km/h across country
and the ability to get somewhere a tracked vehicle cannot. They **steer on the
front axle** rather than by dragging a track, so they turn 180 degrees in about
five seconds at lock and they scrub speed doing it. The launchers steer the same
way, on their front bogie.

The howitzers and launchers fire **indirect**, laid by **bearing and range**
rather than by a crosshair: the mouse swings the bearing and walks the fall of
shot in and out, or you open the map with `M` and **right click** to call a fire
mission. Placing a crosshair on distant ground does not work for a gun that
depresses a few degrees — a tenth of a degree is a kilometre of range — so the
sight is a range dial and the barrel sits at the live firing solution. It does not use
the lofted root of the ballistic equation — that gives near vertical mortar arcs
— it holds about 40 degrees of quadrant elevation and solves for the propelling
charge, only flattening out at full charge beyond that. The HUD shows range,
quadrant elevation, charge percentage and time of flight; the M109 reaches about
32 km with a 20-70 second flight, and the MLRS ripples twelve rockets.

Every road wheel is an independent spring/damper contact against the terrain
with its own longitudinal and lateral friction, so the hull pitches over crests,
rolls in turns and squats under braking. Drive is power-limited rather than a
flat force — strong off the mark, tailing off with road speed — and a tracked
vehicle steers differentially, so it will neutral-steer on the spot with the
throttle closed. Measured: 0–31 km/h in two seconds, cruising about 42 km/h,
scrubbing to 29 km/h through a hard turn.

The springs are worked out from the vehicle rather than from a tank. Travel,
stiffness, lateral bite and the damping ratio all come from its class, and a
vehicle put on the ground is put down **standing on its own suspension and lying
along the slope** — `--susptest` measures the settling. It used to be dropped
from a flat 1.1 m onto a level basis, which for a launcher (whose wheel centres
sit a tyre radius *above* its origin) meant arriving a metre in the air; the
damping was 1.05·√(k·m/N), about a fifth of critical on fourteen wheels, so it
then bounced for several seconds. Measured swing on spawn: 1.44 m and still
moving at three seconds, against 0.02 m and settled inside a frame now.

`W`/`S` drive, `A`/`D` steer, `X` brake, mouse lays the turret (rate-limited
slew), `SPACE` main gun, `V` coax, `C` gunner sight, `U` to get out. A light
4x4 has no main gun and no coaxial: `SPACE` runs the gun on the roof.

## A tank that could not turn

Tracked vehicles swept five to nine degrees in five seconds of full lock at road
speed — a turning circle of about two kilometres. Three separate faults, and the
arithmetic said so before any of them was changed.

A skid steer yaws by shearing both track patches across the ground, and the
condition for it is that the thrust difference between the tracks beats
`mu·W·L/(4·B)`. For an M1A2 at the lateral coefficient of **2.4** this used to
carry, that is **488 kN** against the 240 kN the drivetrain can produce. The
vehicle was over-constrained by a factor of two: no amount of stick was ever
going to turn it. Real track-on-ground lateral resistance is 0.5 to 0.7; at 0.85
the same tank needs 173 kN, which it has.

**Every tracked vehicle weighed 62 tonnes** — an Abrams. An M109 is 28 and an
M270 is 25, and they were carrying an MBT's weight on half an MBT's power.

And **braking was limited by engine power**. The inner track of a skid steer is
being *held back*, which is a brake and does not ask the engine for anything;
clamping it to the power-limited tractive effort was the last thing keeping the
heavy, under-powered pieces from turning at all.

| | before | after |
|---|---|---|
| M1A2 | 9° | 135° |
| T-90M | 7° | 135° |
| M109A7 | 6° | 131° |
| 2S19 Msta | 6° | 106° |
| BM-30 | 5° | 100° |

The obvious risk of less lateral grip is a tank that slides down every hill it
parks on, so `--slopetest` measures exactly that: across a 17.9° side slope with
the brakes on, 0.71 m of drift in eight seconds — against 0.94 m at the old
figure. It holds slightly better than it did.

## Ships

Eleven classes plus the carrier, and every hull now carries a nation, so the
NAVAL tab and each national page list the right ones. China and Iran had no
vessel at all: they have a **Type 052D destroyer** and a **Moudge frigate**.

Two shapes the roster was missing entirely: the **Wasp amphibious assault ship**
— 257 m of flat deck and almost nothing that shoots, a very large thing that
needs somebody else to protect her — and the **Kaman missile boat**, forty-seven
metres doing 36 knots and carrying far more than it looks like it should,
because the missiles do not care how big the hull under them is.

Ten vessels work the eastern ocean: a carrier group with its screen, a hostile
surface action group, a submarine and civil traffic. They steam on their own
courses, take damage, and sink.

Every hull nobody is standing on **fights for itself**. A warship looks for a
contact, opens or closes to a range her battery can make, holds the enemy on
the beam so the whole broadside bears, and lays the mount with a real ballistic
and lead solution -- a shell at 820 m/s takes twelve seconds to reach ten
kilometres, so a ship making fifteen knots has moved the better part of two
hundred metres by the time it arrives. Aircraft get the tubes instead; a five
inch mount cannot track an aeroplane. Merchant traffic is left alone, and a ship
flooding badly breaks off rather than fighting the enemy and the sea at once.

Four of them are yours to command from the **NAVAL** tab, or by walking up to one
and pressing `U`:

| | |
|---|---|
| **Arleigh Burke** destroyer | 155 m, 30 kts, main mount and 32 vertical launch cells |
| **Type 45** destroyer | 152 m, 31 kts, main mount and 48 cells; the tallest mast in the fleet |
| **Type 23** frigate | 133 m, 29 kts, 16 cells |
| **Steregushchiy** corvette | 105 m, 26 kts, 8 cells |
| **Patrol boat** | 38 m, 35 kts, gun only |

The **launch tubes** are a flush deck of hatches forward of the mast, so a ship
reads as armed from the air; a boat carries hers in the casing forward of the
sail, and the round comes out of the cell it is drawn in.

`A`/`D` is the wheel and `W`/`S` the engine order. A ship answers slowly: the
wheel sets a rate of turn and the engines take time to build or shed way. The
mouse lays the battery -- up to 70 degrees, with the camera boom rising and
shortening as it elevates so a high angle shot is not taken through your own
superstructure. Left click fires; `\` swaps between the gun and the tubes.

### Damage control

A warship does not stop existing when the hull bar empties. A hit either opens
her up or starts a fire, depending on where it lands and how big it was, and
both of those are then a problem you live with. Fires burn the hull down at
about nine points a second at full intensity and slowly make water. Flooding
takes away her speed and lays her over -- the list comes straight off the free
surface, so a ship down twenty-eight percent is heeled seven degrees and two
knots slow. The damage control party fight both, at an effectiveness that scales
with what is left of the crew, and the crew scales with what is left of the
hull: a ship hit hard enough cannot save herself. They need a few seconds
without being hit again to make any headway at all.

Whatever the telegraph says, the water she has taken on decides what she
actually makes, and that applies to a hull under nobody's orders too. If the
flooding wins she founders whatever the hull bar reads, and then she goes down
over the better part of a minute: way comes off, the list opens out to sixty
degrees, and the deck goes under.

The **fleet carrier** is sailable too. Its flight deck is registered by
reference, so it goes on working as a landing platform while it is under way --
you can put it on a heading, get out, take an aeroplane up and trap on a deck
that has moved since you left it.

The submarine carries two strategic rounds. `K` calls a strike onto whatever is
designated: measured from 27 km, the round arrived **10 m from the aim point**
and flattened 504 structures.

## The opposition

Not everything in the air is trying to shoot you down.

**Fighters** patrol an orbit, run a lag-pursuit intercept, shoot, and defend
against incoming. **Mud movers** -- an A-10 or whatever the other bloc sends --
work the ground and the shipping instead: run in at height, push over inside
five kilometres, bombs at stand-off and then the gun, pull off, come round and
do it again. They fly a real re-attack rather than orbiting the target.
**Transports** are going somewhere, at height, on a route; if something shoots
at them they do the only thing a transport can, which is flares and down into
the weeds. All three can be shot down and all three count.

### Formation

Aeroplanes fly in **pairs**. Number one leads, number two flies his wing in a
slot ninety metres out and a little low, and the flight starts in formation
rather than spending the first minute of the match rejoining. A wingman leaves
the slot for a missile, for a leader who has broken off, or for anything close
enough to be his own business, and rejoins when it is over.

The slot is held by a controller working in the **leader's own frame**: the
along-track error goes to the throttle, the lateral error to the bank and the
vertical to the pitch, on top of simply matching his attitude. Steering at a
point cannot do this -- it is a bank-to-turn controller being asked to solve a
translation problem, and measured, it settled six hundred metres off the slot
and stayed there. The other half is damping on the closure rate: without it the
wingman drives at the slot, arrives with all that speed still on, sails through
and comes round again, swinging between three hundred metres and three
kilometres for ever.

### Terrain masking

A radar cannot see through a mountain. A contact in the next valley is not a
lock, and something sitting behind a ridge is hidden until one of you comes up;
anything within a couple of kilometres stays available so a target does not
blink out as it crosses a hedge.

The **scope** obeys the same rule, not just the lock. Painting a contact solid
and then refusing to lock it is worse than not painting it, because you can see
it and cannot understand what the radar is doing. A masked contact leaves a
faded trace where it was last seen and nothing more.

**Nothing shoots at what it cannot see.** A SAM battery will not engage through
the hill it is standing behind, and a ship's air search is taken from her
masthead — so an aeroplane down in the valley is not a contact, and flying the
low route to stay behind the ridge line is worth doing. A round already in the
air loses the track too: duck behind terrain with a missile chasing you and the
seeker gives up after half a second of no line, and does not get it back.
That check runs a few times a second rather than every frame, because it is a
ray march and there can be a lot of rounds up.

The AI uses the same fact the other way. An aeroplane being shot at, or running
in on something that can shoot back, checks how much lower it would have to be
for the ridge line to cover it -- and if there is something to get behind, goes
down behind it and comes up late. If the ground between is open it stays high,
because giving away the energy buys nothing.

## Identification, jamming and the objective

**IFF.** Everything filtered on `team` directly, so identification was perfect
and free — there was nothing that could be uncertain. A transponder
interrogation is good for 46 km: inside that a contact is friendly or hostile,
beyond it the return is painted in amber with no name against it.

**Jamming.** Chaff and flares were the only counters, so a radar round could be
decoyed but never denied. A jammer degrades a radar seeker looking at you — the
aim point wanders, and a seeker held in it long enough breaks lock altogether —
with burn-through as the round closes, because jamming does not save you from
something already on top of you. It also lights you up on every RWR for a
hundred miles, which is the trade.

**The objective marker.** Shift and click anywhere on the tactical map plants
one. It is drawn from *every* camera — cockpit, chase, a driver's seat, a
bridge — and when it is off the glass it becomes an arrow at the edge of the
screen pointing round to it, with the range. The autopilot will fly to it and
then hold overhead, which is the navigation the game never had: waypoints
existed for road routing and cruise-missile terrain following, never for the
pilot.

## Countermeasures

Two dispensers, 240 cartridges each, and they do different jobs. **Flares**
(`N`) seduce an infra-red seeker. **Chaff** (`B`) blooms a cloud of dipoles that
a radar seeker locks onto instead. Before chaff existed there was nothing at all
that worked against a radar round, so a SAM site that got a shot away was
unbeatable except by outrunning it — and pumping flares at it, which is what you
would instinctively do, did precisely nothing.

Measured against five SAM rounds in the air: dispensing **nothing** leaves all
five still tracking; **flares alone** also leave all five, which is correct and
is the point; **chaff** breaks four of the five. The AI works both dispensers
together when it is defending, because an aeroplane being shot at does not know
what is guiding the round any more than the pilot does.

## Wrecks

Nothing that dies stays intact.

A **vehicle** loses its turret — the ammunition goes up and the one silhouette
everybody recognises is the turret lying twenty metres away — the paint burns
off what is left, and the hull sits there on fire for about half a minute
before settling down to smoke. A handful of pieces are thrown clear with it.
There is no physics terrain in this project: the ground is a height field and
every vehicle does its own contact against it, so debris on a `RigidBody3D` had
nothing to land on and fell for ever. Measured, 640 m below the airfield and
still accelerating. Wreckage is ballistic against the height field instead,
bounces once or twice and comes to rest.

A **ship** over ninety metres **breaks her back**. The intact hull is put away
and two sections are lofted from the same station profile either side of the
fracture, each hung on a node at the break so it tips about the break rather
than about the middle of a ship that no longer exists. They go down at
different rates and different angles — the after section, where the machinery
and most of the water is, goes first and steeper — with torn plating on both
faces, fire that drowns before the smoke does, and flotsam left on the water.

## Chat

`/` opens a line at the bottom of the screen. Type, Enter sends it to everyone
in the session, Escape throws it away. The backlog holds for nine seconds and
then fades, so it is readable in a fight without permanently covering the left
of the canopy.

While the line is open every control goes quiet. Held keys keep reporting
through the input singleton no matter what consumes the event, so consuming the
key was not enough on its own -- typing "d" rolled the aeroplane right. Every
control surface in the game reads its actions through a gate that closes while
a line is open.

## Air traffic

`F3` opens a page for watching the aeroplane fly itself. Pick a type, call one
in on a twelve kilometre final or send one off the runway, and optionally follow
it with the camera. It is the same scripted pilot the test harness uses, driven
from inside the game: a flight of three called in line astern all landed.

## Walking around

The ramp start puts you on foot with a carbine. WASD walks, `SHIFT` runs,
`CTRL` crouches, `SPACE` jumps, left click fires (real ballistics — travel time
and drop), `P` swaps first and third person, and `U` climbs into any jet you are
standing next to. First and third person share one skeleton and one animation
set; first person simply puts the eye in the head joint. Long falls hurt, and a
killed pilot is handed to a jointed rigid-body ragdoll.

**Aircraft interiors** are solved in the aircraft's own frame. Step into a hold
and you become a child of that hold, so you inherit the aircraft's motion
exactly — walk around while it manoeuvres and nothing slides. Walk off the open
ramp and you are handed back to the world with the aircraft's velocity.

## Controls

| | |
|---|---|
| `W` / `S` | pitch down / up |
| `A` / `D` | roll |
| `Q` / `E` | rudder |
| `SHIFT` / `CTRL` | throttle (afterburner above 78 %) |
| `G` | landing gear |
| `F` | flaps |
| `X` | wheel brakes on the ground, airbrake in the air |
| `B` | open / close the weapon bay |
| `1` … `8` | select a weapon directly |
| `\` | cycle weapon |
| `T` | cycle target |
| left click or `SPACE` | fire the selected weapon |
| `K` | gun burst |
| `P` | cockpit / chase / orbit camera |
| `ALT` (hold) | free look |
| right click, or `O` | raise / stow the sensor page |
| `CTRL`+`T` | pod designates: point track a vehicle, or ground stabilise a spot |
| `L` | laser designator (bombs guide onto the spot) |
| `/` | chat line (Enter sends, Escape cancels) |
| `C` / `V` | flares / chaff |
| `N` | night vision |
| `N` (pod up) | sensor channel: TV, night, white hot, black hot |
| `[` / `]` | cycle the left / right corner panel: off, sensor, radar, minimap |
| `-` / `=` | radar range: 10, 20, 40 or 80 km |
| `Y` | weapon camera — ride the round you just released |
| `J` (in a hold) | take the gun station from inside a gunship |
| `M` | tactical map — baked relief, roads, towns, objectives, contacts |
| `L` | landing lamp |
| `TAB` | action menu — aircraft, vehicle or ship, whichever you are in; the lights and the autopilot are switched from here |
| `F3` | air traffic: call aircraft in to land and watch them do it |
| `Z` | look back |
| `;` | mouse stick on / off |
| `H` | fly-by-wire on / off (STOVL conversion on the F-35B) |
| `ESC` menu · `F2` hide the control legend |

### Flying with the mouse

Press `;` to take the mouse stick. The pointer is captured and behaves like a
spring-centred stick: **push forward for nose down, pull back for nose up**, left
and right to roll. How far the pointer sits from the centre of the screen is how
much deflection you are asking for, so small movements are small inputs. Let go
of nothing -- there is no button to hold -- and press `;` again to hand control
back to the keyboard. Holding `ALT` while the stick is on looks around instead of
flying, and releasing it returns the view to boresight.

With the fly-by-wire in (the default) the stick asks for a *rate* rather than a
surface deflection, so the aeroplane holds what you ask for and the law keeps it
inside its angle of attack and g limits. `H` switches the law out, at which point
the stick moves the surfaces directly and the aeroplane will depart if you ask it
to.

### Right click is not a trigger

The trigger is the left button. Right click raises the sensor page, and nothing
about it fires: a modifier chord for the pod turned out to be unreliable on a
Mac, and having the same button do both meant reaching for the sensors put a
missile off the rail. While the map or an action menu is up, weapons are
inhibited altogether -- the mouse belongs to the page.

## Weapons and bays

Internal stores are hidden until the doors run. Pressing `SPACE` with a shut bay
starts the doors and tells you so; the shot goes when they are open. Open doors
cost drag and multiply your radar cross section, so you do not fly around with
them hanging out.

* **AIM-9X** – short range IR, fire and forget, defeated by flares.
* **AIM-120C** – radar, needs a lock, 40 km.
* **GBU-32 JDAM** – unpowered, lofts onto a ground target (`T` cycles ground
  targets when the bomb is selected).
* **Gun** – hitscan tracers, every fourth round drawn.

Missiles fly proportional navigation, bleed energy after motor burnout and can
only pull their rated g while fast — a late, hard break with flares is a real
defence rather than a formality. Warheads use a swept proximity fuse with
damage falloff, so a near miss hurts instead of deleting you.

## Two countries that did not exist

The map assigns a nationality to every point — it is what decides a town's
architecture, its paint and whose kit belongs on the ground there. It did it by
averaging two noise fields and cutting the result into six equal bands of value.

That looks even and is not. The sum of two roughly independent fields is
triangular: piled up in the middle, thin at the ends. Measured over twenty
thousand samples of the old expression:

| | share of the map |
|---|---|
| Russia | 45.7 % |
| France | 31.5 % |
| China | 12.5 % |
| Britain | 9.8 % |
| United States | 0.6 % |
| **Iran** | **0 %** |

Two of the six nationalities did not exist anywhere in the world. There was no
Iranian town, no Iranian ground and nowhere for Iranian equipment to be — which
is how it surfaced: the ramp start tries to put every faction's vehicles in
their own country, and six of them had none to go to.

It picks on the *angle* of the noise pair now rather than what they add up to.
The joint distribution is roughly radially symmetric so the angle is very nearly
uniform, and it still moves smoothly with position, so the regions stay large
and organic instead of turning into a checkerboard. All six exist, between 7.7 %
and 22.2 % each.

## The world

A 1200 × 1200 km map generated from one analytic height field, held in the
native extension. The airfield sits in a north–south valley so both runway
approaches and the departure end stay clear of rising ground, with open ocean
off the eastern coast and further continents beyond it.

* **Chunked terrain, as a quadtree over the whole world.** A node's identity is
  its depth and grid index, so flying does not shift a single chunk boundary,
  and a node is rebuilt only when the detail it deserves changes. Nodes split on
  measured error against the height field, so open water and plains stop early
  and ridge lines keep going. Edges facing a coarser neighbour are conformed to
  the height that neighbour draws, so the seam is zero by construction rather
  than covered by a skirt; the skirt is a few centimetres, for the crack that is
  left. Every chunk samples the same height and biome fields, so neighbours line
  up and biome bands run continuously.
* **Ridge lines.** The mountains used to be the same rounded fractal field as
  the plains, only taller: a range was a row of domes with no crest and no col
  in it, so there was nothing for a road to look for a pass through and nothing
  for an aeroplane to fly between. The zero crossings of a second noise field
  are taken as the watersheds and laid over the high ground only, weighted by
  how mountainous the base already is — so the plains, the coast and the valley
  the airfield sits in are exactly as they were.
* **Biomes** — a temperature/moisture field blends snow, rock, forest, grass,
  steppe, sand and marsh. It drives terrain colour *and* the scatter, so forest
  belts, dry steppe and the snow line all read differently on the ground.
* **Water** at −35 m fills the basins as lakes, with sand blending along the
  shoreline. Ditching in a lake counts as a crash.
* **Settlements** — four towns and a small city, plus outlying farms. Placement
  is water-, slope- and road-aware, so nothing is built on a cliff or in a lake.
* **Roads** are both surfaced (hugging carriageway and kerb meshes) and painted
  wide into the terrain's vertex colours, so the network reads from altitude
  where the carriageway itself is sub-pixel. Town street grids are planned
  *before* the ground is generated, otherwise the terrain paints only the trunk
  roads and towns come out with invisible streets. Distance-to-road is answered
  exactly, from a uniform grid over the whole network held in the extension.
* **Military scenery** — a dispersal base with hardened hangars and revetments,
  parked jets on the home apron, vehicles, blast walls, radar and SAM sites.
* **Scatter** — ~33k trees, pines, bushes and rocks chosen by biome and placed
  by slope, batched into 1,700 MultiMesh cells with per-cell visibility ranges
  so distant ground cover stops drawing entirely.

## Sky and time of day

The sun is placed by the standard solar position formulae from a clock, rather
than being a fixed rotation per weather preset. It rises in the east, crosses to
the south at noon and sets in the west, and everything that depends on the light
hangs off its elevation: light energy and colour, ambient level, sky top and
horizon, fog colour, and how the clouds are lit. Below the horizon the sun goes
out, shadows switch off, the sky goes to a deep blue-black and the fill light
takes over as moonlight. A day runs in four hours by default.

Measured across a day at 45 degrees latitude:

| time | elevation | bearing | sun energy |
|---|---|---|---|
| 04:00 | −9.9° | 058 | 0.00 |
| 06:00 | +9.8° | 080 | 0.79 |
| 12:00 | +59.0° | 180 | 1.05 |
| 18:00 | +9.8° | 280 | 0.79 |
| 20:00 | −9.9° | 302 | 0.00 |

**Clouds are raymarched, not billboarded.** The deck of sixteen thousand quads
that used to stand in for weather could not be made to look like it: you saw
through it rather than into it, it needed a hand-built LOD scheme and 166 draw
calls to be affordable, and every peer had to be handed the same random seed to
see the same sky.

It is a density field now, marched in two places that share it:

* The **sky shader**, in Godot's half-resolution pass. A quarter of the pixels
  is cheaper and fine for the body of a cloud, but an edge drawn at a quarter
  resolution and filtered back up is a staircase, and the edge is the part you
  look at. It intersects a slab between the cloud base and tops, so it has real
  parallax as you climb rather than sitting at infinity. Fifty-eight to
  sixty-eight steps depending on the weather; most of the screen most of the
  time misses the slab entirely and costs nothing.

  The lighting is what stops a cloud reading as a grey blob with an outline.
  Sun visibility is marched with a growing step, so five samples reach 1.7 km
  into the deck rather than the 650 m a fixed step managed. A Henyey-Greenstein
  phase function makes cloud bright toward the sun and dark away from it —
  measured across the viewing angles that is a multiplier from **0.43 to 3.70**,
  which is the silver lining. Beer-powder darkens thin edges against lit cores,
  and the ambient term is a gradient rather than one colour, because the top of
  a cloud sees the sky and the bottom sees the ground. Together they take the
  range from flat to about **7:1**: 0.30 at a shaded base facing away from the
  sun, 0.69 side-on, 2.11 on a sunlit top facing into it.
* A **FogVolume** carrying the same field through Godot's froxel grid, centred
  on the camera and six kilometres deep. This is the half that matters when you
  fly into it: a sky is only drawn where there is no geometry, so from above the
  deck looking down at terrain the sky-shader cloud simply is not there. The fog
  volume sits between the camera and whatever it is looking at, so the cloud
  hides the ground, thickens as you enter it, and goes past the canopy.

**Zero draw calls and zero instances**, against 166 batches and up to sixteen
thousand billboards. And because the field is a pure function of world position
and a wind offset derived from the clock — which is already host-authoritative —
**two machines draw the same sky without a byte crossing the wire about it.**
Verified with a client started on `clear` joining a host on `overcast`: same
preset, same coverage, and the wind offset tracking to within one publish
interval.

Three things had to be undone after seeing it move. The march was dithered with a
per-pixel hash to break up banding, which at a quarter resolution is a quarter
resolution of *sparkle* — and it re-rolls as the camera turns, so the whole sky
boils. It uses a fixed offset and more steps instead; banding you cannot see
beats grain you can. And the drift was scaled straight off the clock, which runs
a day in four hours, so the cloud crossed the sky six times faster than it
looked like it should. And the sky shader was taking the camera from its own
`POSITION` built-in, which left the cloud welded to the view — swing the head
round with free-look and the whole sky came with it. The eye is a uniform now,
set every frame from whichever camera is actually current, so the cockpit, the
chase, the sensor pod and a ship's bridge all give the sky the right position.
The stepping took three goes and the middle one was the worst. It began as
`span / steps`, and looking nearly along the slab that span is tens of
kilometres, so samples ended up a kilometre apart and slid about with every
small movement — the distant shimmer. Replacing it with a fixed 55 m step cured
that and broke something far more visible: **a bounded number of 55 m steps only
reaches three kilometres**, so everything past that was never sampled at all and
the whole sky rearranged itself as you flew through it. The step grows
geometrically now, 55 m near and capped at 1200 m far — fine sampling where a
step has to be small against a cloud, coarse where it does not, which is the
same reasoning as any level of detail applied along a ray.

That mistake was invisible to every test here, because the reach of a geometric
series is a sum and nothing was computing it. The harness now mirrors the
shader's stepping and fails a preset that cannot march as far as it claims:
58 steps reach 14.6 km, 68 reach 17.6 km, against a 13 km limit.

Two more things came out of watching it rather than testing it. The far step was
capped at 1200 m, which cuts a fifteen-hundred-metre deck into three slices —
you could count the layers on the horizon. It is capped at 300 m now, and the
march reaches thirteen kilometres rather than twenty-six, because a deck fading
into haze at that range is what cloud does anyway and the steps are better spent
close in. And removing the dither to cure the sparkle left the remaining
banding bare: it is an ordered 4x4 Bayer pattern now, fixed to the screen, so a
still camera gives a still image and the steps break up into a texture too fine
to read as steps. The last of the banding was not a stepping problem at all but a sampling one.
A sample taken with a three hundred metre step stands in for three hundred
metres of cloud, and resolving detail finer than that is not extra quality: it
is what makes distant cloud crawl, because which side of a small feature a big
step lands on changes with every metre the camera moves. The noise now carries
fewer octaves as the step widens — four close in, three at nine hundred metres,
one past two kilometres — which is mip-mapping, applied along a ray.

That pattern has to be built arithmetically — a shader-stage
array literal is not something this language will take, and a sky shader that
fails to compile reports no uniforms and then quietly draws nothing rather than
saying so. The harness fails on that too now; it caught this one. The radiance cubemap pass skips the cloud march entirely: it
sweeps the whole sphere from somewhere that is not the camera, so marching in it
was both wrong and expensive.

## Weather## Weather

Four presets, selectable in the hangar: **clear**, **scattered**, **overcast**
and **dusk**. Each one drives the cloud deck density and altitude, fog distance,
ambient level, sun angle and colour, and the sky gradient. Clouds are billboard
puff clusters you can fly through.

## Crew

Picking the runway start plays the walk-out: the pilot crosses the apron, climbs
the boarding ladder, drops into the seat, and the canopy comes down before
control is handed over. Any key skips it. The figure is posed procedurally —
walk, climb and seated cycles — and when an aircraft is destroyed the crew is
handed to a jointed rigid-body **ragdoll** that tumbles clear of the wreck.

## Runway operations

Runway 18/36 is 3000 × 46 m with threshold bars, touchdown zone markers, edge
and approach lighting, and a **PAPI** on the left abeam the aiming point — two
white two red is on slope. The HUD adds an ILS-style cross whenever the gear is
down within 18 km, plus runway-remaining on rollout.

Touchdowns are graded on descent rate and centreline offset:
`GREASED` under 1.2 m/s, `GOOD`, `FIRM`, then `HARD` past 5 m/s. Above 7 m/s you
start breaking the aircraft.

## How it is put together

```
scripts/core/       sim.gd           autoload: terrain field, input map, scoring
                    meshkit.gd       procedural mesh helpers (lofts, prisms, boxes)
                    chase_camera.gd  cockpit / chase / orbit
scripts/aircraft/   jet_spec.gd      the airframe database (all tuning lives here)
                    jet_factory.gd   builds an airframe + its moving parts
                    aircraft.gd      flight model, gear, bays, stores, damage
                    player_jet.gd    human pilot + the scripted test pilot
scripts/weapons/    weapon_spec.gd   store database and store meshes
                    missile.gd       separation, boost, PN guidance, fuse
                    effects.gd       tracers, explosions, smoke, embers
scripts/world/      world.gd         main scene: env, missions, scoring, CLI
                    terrain.gd       a quadtree of chunks over the whole world
                    airbase.gd       runway, markings, lighting, PAPI
                    scenery.gd       towns, military sites, scatter, home base
                    weather.gd       cloud deck and environment presets
                    pilot.gd         posable aircrew figure
                    ragdoll.gd       jointed rigid-body crew
scripts/ai/         ai_plane.gd      patrol / engage / extend / defend
                    ground_target.gd hangars, radars, fuel, shooting SAM sites
scripts/ui/         hud.gd           world-referenced HUD
                    menu.gd          hangar screen

native/src/         field.rs         the land before anything is built on it
                    world.rs         platforms, aerodromes, the road corridor
                    router.rs        where a road goes: A* over the cost of one
                    survey.rs        what height it was built to
                    raster.rs        ground mask, climate, road ribbons, map
                    index.rs         cell keys and the segment grid
                    lib.rs           the `Terra` class the game calls
```

**The extension.** Anything that is one piece of arithmetic asked for a very
large number of points lives in `native/`, behind a single `RefCounted` called
`Terra`. That is the whole height field and everything derived from it: a
terrain chunk asks for its 289 heights in one call rather than 289; the road
survey hands over fifty thousand stations once and gets a finished alignment
back; the ground mask, the climate texture, the road surfaces and the map
relief are each one call. Every one of them runs across all the cores inside.

What is left in script is the part that is decisions rather than arithmetic:
where a town goes, what a road is for, what a chunk of terrain is called. The
rule of thumb is that a loop over a lot of points does not belong on this side
of the boundary — not because GDScript is slow at the arithmetic, but because
each crossing costs more than the arithmetic does, and there is no way to spread
it over the cores from there.

Build it with `cd native && GODOT4_BIN=<godot> cargo build --release`.

**Flight model.** Aerodynamics run in `_integrate_forces`: lift from a
CL/α curve with a stall break and ground effect, induced plus parasitic drag
with configuration penalties, sideslip side force, and separate damping and
static-stability moments. Control power is deliberately large — what keeps it
flyable is the fly-by-wire law, which converts stick position into a *rate*
command and closes the loop on measured body rates with AoA and g protection.
Turn it off with `H` and you get the bare relaxed-stability airframe.

**Ground handling.** Three suspension legs with spring/damper struts, tyre
friction split into rolling and lateral, nose-wheel steering, and surface grip
that drops off the paved area. Terrain height comes from one analytic field
(`Sim.height_at`, which is the extension's `ground`) shared by the visual mesh,
the gear and the crash test, so there is no collision mesh for the world at all.

## Test harness

The game can fly itself, which is how the flight model was tuned. Arguments go
after `--`:

```
godot --headless --path . --quit-after 9000 -- --preset=landing --auto=land --dump=100
```

| flag | meaning |
|---|---|
| `--preset=takeoff\|free\|landing\|combat` | start that mission immediately |
| `--jet=f22\|f35\|f16\|f15` | pick the airframe |
| `--auto=takeoff\|land\|fight\|cruise` | run the scripted pilot |
| `--dump=N` | print telemetry every N/120 s (speed, AoA, β, g, rates…) |
| `--shot=PATH` | render a frame to a PNG and quit |
| `--view=cockpit\|chase\|orbit`, `--dist=`, `--orbit=x,y` | camera for screenshots |
| `--weather=clear\|scattered\|overcast\|dusk` | weather preset |
| `--frames=N` | render the screenshot after N frames |
| `--openbay`, `--fx`, `--nocockpit`, `--noboard` | debug helpers |
| `--host`, `--join=ADDR`, `--mission=ID` | start a session; `--mission` picks what the host runs |
| `--netlog` | print roster, ghosts, replicated AI and packet counts every 2 s |
| `--fpslog` | print averaged fps and render monitors every 2 s |
| `--runfor=SECONDS` | quit after that many **wall clock** seconds |
| `--turntest=SPEED` | sustained level turn at that entry speed, prints g, rate and radius |
| `--noassist` | fly-by-wire off from the start |
| `--tvctest=SPEED` | full aft stick at that speed; reports pitch rate, AoA and nozzle angle |
| `--boardtest` | stand at every boardable in turn and check the walk-up offers that one |
| `--jolttest` | tumble through every attitude and report the worst single-frame camera roll |
| `--overlaptest` | audit every vehicle, aircraft and structure on the ramp for overlapping spawns |
| `--artytest=KIND` | mount that piece, designate 100 deg off the hull, and report the fall of shot |
| `--admintest` | call a flight of three in and check they all land |
| `--restarttest` | restart three times and count what is left in the world |
| `--shiptest=1` | take a ship, run the helm and the battery, report the conn |
| `--navaltest` | bomb a warship and check the hull takes it |
| `--subtest` | strategic launch from the submarine onto a built up area |
| `--fleettest` | count the shipping and check it floats at its draught |
| `--seamtest` | measure the T junction gaps between terrain rings |
| `--seatest` | map where the water is deep enough to float in |
| `--locktest` | can a warship be locked, and does the box know about terrain |
| `--triggertest` | which mouse button fires, and does the map inhibit it |
| `--firetest` | unlocked launch, and cancelling a shot queued behind the doors |
| `--aimtest` | hand to grip error and elbow position across the aim range |
| `--seattest` | where the pilot sits relative to the cockpit sill |
| `--boardtest` | stand at every boardable in turn and check the offer |
| `--flaptest` | both flaps down together |
| `--viewtest` | cockpit furniture against the eye line, and the glazing profile |
| `--hudtest=VIEW` | does the flight page draw from that camera |
| `--lasertest` | laser stows on exit, point track survives |
| `--navaltest` | laser-guided bomb against a moving ship, hull before and after |
| `--battletest` | two hostile warships put in gun range and left to it |
| `--dctest` | a hull hurt on purpose, then the party against the fire and the water |
| `--castest` | do the mud movers find, attack and hurt something; does the transport get anywhere |
| `--formtest` | how far off the slot a wingman actually sits |
| `--masktest` | does terrain block a line, and does the radar respect it |
| `--chattest` | `/`, a line of text, and whether the stick moved while typing |
| `--shipnet` | what each end of a session thinks the fleet is doing |
| `--cmtest=WHAT` | flares, chaff, both or none against a SAM shot |
| `--nettest` | host, host again without leaving, leave, host again; and the address shown |
| `--cluttertest=AGL` | what a SAM battery can do about a target at that height |
| `--breaktest=RNG[,ALT[,WEAPON]]` | a shot, then a full-power break: closest approach |
| `--salvotest` | three JDAMs at one lased mark, and where each of them lands |
| `--shaketest` | how steady the sensor head is on the aeroplane carrying it |
| `--navsensor` | a ship's sensor: point track, area track, laser, scope, tubes and armament |
| `--geomtest` | every airframe's built mesh against the dimensions it flies on |
| `--tanksensor` | the commander's sight on an armoured vehicle: does it open, where does it sit, who has the mouse, does lasing lay the piece |
| `--culltest` | fire rays at every airframe, vehicle and hull and count the ones that meet a face turned away — a hole you see through |
| `--roadtest` | the trunk network's gradient, cross fall and earthworks |
| `--skirttest` | how far terrain hangs below the ground at the ring seams, which is what a submarine is looking at |
| `--lodtest` | ask the chunks either side of every ring boundary how high the ground is at the same point, and compare |
| `--salvotest=WEAPON` | that weapon at a lased mark, and where each round lands |
| `--skytest` | cloud settings, how far the march reaches, and the sun across a day |
| `--splashtest` | a bomb into open water: is the fireball anywhere you could see it |
| `--vlstest` | do a ship's tubes actually reach an aeroplane twelve kilometres out |
| `--townstest` | where the towns ended up, how level, and whether the streets are buried |
| `--navaltest=WEAPON` | that weapon against a ship, hull before and after |
| `--adminfrom=WHERE` | call traffic in while crewing a ship or a tank, and follow it |
| `--autodiag` | what the autoland is commanding all the way down, and where it touches |
| `--podch=N` | force a sensor channel and render it |
| `--keytest=1` | driver seat keys: map, panels, and what the trigger does |
| `--helitest` | hands off altitude drift, then the collective both ways |
| `--hovertest` | STOVL conversion and a hover |
| `--ctltest=SPEED` | roll and pitch authority, assisted and raw |
| `--wrecktest` | destroy every vehicle and watch where the hulks end up |
| `--susptest` | stand one of every ground vehicle on the terrain: how far it swings settling, how long until it is still, and whether it then drives and steers |
| `--navalship=KIND`, `--navallow` | which hostile hull `--navaltest` attacks, and whether it is a dive from 1500 m or a flat run from the deck |
| `--fleetfire` | what the fleet does with its tubes over a hundred seconds: how many rounds go up, at how many contacts, and how close they ever get |
| `--tacnuke`, `--tacnukesea`, `--tacnukenociws` | a tactical nuclear bomb onto a locked group of armour, or onto a squadron at sea with and without its close-in guns: where it bursts, how far up, and what walks away |
| `--aptest` | the autopilot: how far the altitude hold drifts, whether the orbit goes round, and whether reversing it sends the aeroplane the other way |
| `--adtest` | a battery and an anti-aircraft gun against an aeroplane flown at them: do the rails come up, does anything leave them, does it hurt |
| `--asattest` | a launcher on the ground against something in orbit: how high the round gets and how close it passes |
| `--manpadstest` | a shoulder-launched team against an aeroplane in the weeds and then against one that has climbed out of reach |
| `--hoverhold` | throw a helicopter sideways at 18 m/s with 20 degrees of bank on, engage the hover, and measure where it ends up |
| `--slopetest` | park a tracked vehicle across a side slope with the brakes on and see whether it stays there |
| `--svctest` | the support systems: what the side can see with its own radar, with a satellite and with an E-3; taking fuel from a tanker; and being rearmed on the ground |
| `--wingtest` | every pylon, wingtip rail and navigation lamp measured against the wing planform it is bolted to |
| `--lighttest` | the lighting controls: are they in the TAB menu, and do the lamps actually go out |
| `--gtest=STRAIN` | pin the grey-out veil at that strain, for looking at it |
| `--debugweapons` | trace every round: guidance, why a seeker dropped its target, and the closest it ever got |

`--runfor` deliberately reads the wall clock rather than sim time: `--fixed-fps`
decouples the two, and a two-process network test only means anything if both
ends are alive at the same real moment.

`--auto=takeoff` rolls, rotates, climbs and levels off; `--auto=land` flies the
3° slope, flares and rolls to a stop on the centreline.

## What has been measured

*The entries below are in rough order of when they were established; the newest
work is at the end of this section.*

The sim can fly and drive itself, and the numbers below came out of the headless
harness rather than off the screen:

* **Top speed** — the F-22 holds about 900 KIAS at full burner across the
  envelope: Mach 1.5 down at 1500 m where dynamic pressure limits it, Mach 2.05
  at 7000 m and Mach 2.5 at 11000 m. Drag is modelled as a wave-drag hump
  centred just past Mach 1 that falls away again, plus a steep rise past Mach
  1.5 for skin friction and heating; a flat supersonic penalty pinned every jet
  at Mach 1.2 no matter how much thrust it had. Past the never-exceed speed the
  airframe takes damage, and the fly-by-wire pulls the throttle back before it
  gets there — switch the assist off and you can tear the wings off.
* **Turn performance** — sustained level turn at 80 deg of bank with the entry
  speed held, which is the only way to measure this: leave the burner in and the
  jet simply accelerates out of the turn and reports nothing useful. At 250 m/s
  and 6000 m the fleet now reads:

  | | g | rate | radius | AoA |
  |---|---|---|---|---|
  | Typhoon | 7.63 | 20.8 deg/s | 677 m | 20.6 |
  | Rafale | 7.32 | 20.9 | 670 m | 23.5 |
  | Su-57 | 6.96 | 20.8 | 675 m | 26.0 |
  | F-22 | 6.98 | 20.6 | 685 m | 25.6 |
  | MiG-29 | 6.81 | 19.6 | 723 m | 26.7 |
  | Su-35 | 6.18 | 19.0 | 743 m | 30.5 |
  | J-20 | 6.43 | 19.3 | 732 m | 26.2 |
  | F-15E | 6.73 | 18.0 | 803 m | 23.4 |
  | F-16 | 6.15 | 16.9 | 845 m | 24.7 |
  | F-35 | 4.80 | 13.3 | 1082 m | 25.9 |

  The light canard deltas turn best and the F-35 turns worst, which is the right
  order. Every one is angle-of-attack limited rather than short of thrust.
  Four separate faults were sitting under those numbers:
  - The fly-by-wire rate loop was proportional only, so it settled with a
    standing error: at 250 m/s it commanded 0.36 rad/s of pitch rate, held 0.28,
    and left the stabilator at a quarter deflection while the stick was on the
    back stop. An integral term with anti-windup closes the loop, worth about
    23% more turn rate on its own, and the same term went on the roll axis.
  - The F-35's thrust was **124 billion newtons** in military power and 211
    trillion in burner, a botched multiply from an earlier speed pass. The
    airframe diverged numerically within five seconds of every mission: it was
    completely unflyable and nothing had caught it.
  - The rest of the fleet was inconsistent in the same way, quietly. The F-22
    and Su-35 had been boosted during that pass and everything else was left at
    real-world figures, so the F-16 was flying with **one nineteenth** of the
    F-22's afterburner. Thrust is now referenced off the F-22, whose top speed
    was measured and accepted, with every other jet keeping its real ratio to
    it.
  - Most of the fleet was flying at maximum takeoff weight. `mass` is the dry
    airframe with fuel added on top, and it had been set near *combat* weight
    for several types, so a full bag put them over gross. Empty weights and
    internal fuel loads are now the published figures. This alone was worth
    +80% turn rate on the F-15E and +37% on the F-16.
* **Banked flight** — with the stick centred in pitch the load factor tracks the
  bank exactly: 0.9 g wings level, 0.5 g at 60 deg, and **0.0 g at 90 deg**,
  where the jet falls away at a clean 1 g and the heading stops changing. The
  lift vector really is doing what it should.
* **Takeoff** — F-22 rotates at ~150 kt and unsticks around 160, climbing away
  at 14 deg with the gear coming up through 40 m.
* **Autoland** — flies the 3 deg slope from twelve miles, flares and rolls to a
  full stop on the centreline.
* **Tank** — 0-31 km/h in two seconds, ~42 km/h cruise, scrubbing to 29 km/h
  through a hard turn, hull level throughout.
* **Helicopter** — lifts off and holds a straight climb with the heading locked
  and zero sideslip drift.
* **Chase camera** — constant 17.2 m boom and 0.00 deg off-axis through a full
  free-look sweep.
* **Sector capture** — flattening a hostile garrison drives the sector from
  fully theirs, through neutral, to ours in 5.4 seconds.
* **Multiplayer** — two headless instances on the loopback: the joiner is told
  which match to load, both ends reach `roster=2`, and state flows both ways
  (client tx=275/rx=546, host tx=309/rx=290) with each holding the other's
  ghost at the correct position. Getting there found a real bug: restarting into
  the host's mission swept the network ghosts into the general cleanup, and the
  dangling entries aborted the sync loop on a typed read every frame.
* **Shared opposition** — the AI is host-authoritative. Clients no longer spawn
  bandits of their own; the host announces the set and pushes pose and velocity
  ten times a second, and says once, reliably, when one is gone. Measured over a
  40 second session: the host simulating five bandits, the client holding five
  ghosts that track them and dropping to four as the first was shot down, while
  the host held the client's own aircraft at the right place the whole time.
  Two bugs came out of it. The roster was announced only to whoever was already
  connected, so a late joiner saw an empty sky — it is re-sent on every join
  now. And a ghost whose owner stopped reporting dead reckoned along its last
  velocity for ever: a disconnected peer ended up 3.6 x 10^18 m from the field.
  Ghosts now coast to a halt after a second without an update.
* **Reachable games and separate spawns** — hosting on a real network asked the
  router for a port mapping and got one back, printing the external address to
  hand out; discovery is threaded, so the wait never stalls the hangar. With
  that up, two peers who both picked the F-22 were checked into the same free
  match: the host started at (-17369, 2512, 4947) and the joiner at
  (-17406, 2510, 3903), a kilometre of clear air apart instead of the shared
  start point that used to put one inside the other. The test also caught
  something dumber than either feature — a host left running from a previous
  run still held the port, the new host's `create_server` failed, and the
  joiner happily connected to the *old* game. Worth knowing the failure looks
  like success from the client end.
* **Cross-client kills** — the whole damage chain, end to end on the loopback:
  a client's AMRAAM detonates 8.3 m from its ghost of a bandit the host is
  simulating, the client reports 47, 37 and 66 points of damage, the host walks
  the real aircraft down 100 -> 53.3 -> 16.5 -> 0.0, announces it gone, and the
  client removes the ghost. Ghosts no longer take damage locally at all: a ghost
  is a picture of an aircraft somebody else is simulating and has no standing to
  decide whether it just died, so every hit is reported to the owner and comes
  back as replicated state. Four bugs came out of building this:
  - Damage was never wired up. `net_hit` and `net_fire` existed and nothing
    called either of them, so in a session nobody could hurt anybody.
  - A joiner's ghost was created over the airfield and was a valid target before
    its first position arrived, so in a contested match it was shot to pieces on
    arrival — and once damage was authoritative that killed the real aircraft
    too, in 0.7 seconds. Ghosts are now invisible and untargetable until their
    first fix, which also stops them flying in from the spawn point.
  - A frozen kinematic body has its `linear_velocity` recomputed by the physics
    server from however far it was teleported last tick, so the replicated value
    did not survive being assigned. The dead reckoning read that derived value
    back and extrapolated along it, which is a feedback loop: ghosts wound up at
    20 km climbing at Mach 2.5, and missiles led them into empty sky. The
    reported velocity now lives where physics cannot touch it, and guidance
    leads that.
  - The scripted pilot chose its weapon by range but fired regardless of which
    one was selected, so it emptied both Sidewinder rails at seven miles where
    they cannot reach and then spent the rest of the fight pulling the trigger
    on empty rails.
* **Shared ground war** — garrison assets follow the same rule as aircraft. Both
  ends build a sector's garrison in the same order, so the sector label plus the
  slot number is a key neither side has to be told, and a client that shoots a
  hangar reports the hit rather than deciding it fell over. Measured on a
  conquest session: a client flattens all six assets in sector A, its own copies
  stay standing because it has no authority to kill them, all six reports reach
  the host, the host destroys the real ones, and the next objectives packet
  brings the client's copies down and hands it a sector that went from fully
  hostile to captured in 4.2 seconds. The objectives packet now carries a
  per-sector bitmask of what is still standing, so nobody is left shooting at a
  structure that fell over minutes ago.
* **Thrust vectoring** — it used to be a fudge: a floor under the control
  authority so vectoring aircraft kept some response at low speed. It is now
  the actual mechanism. The nozzles take the same commands as the tails, swivel
  at 80 deg/s, and the moment falls out of where they sit relative to the
  centre of mass rather than being a number invented for the purpose. Fitted to
  the aircraft that have it and nobody else: F-22 20 deg in pitch (its nozzles
  are two dimensional, so no yaw), Su-57 16 deg in both axes, Su-35 15 in both,
  J-20 10 in pitch. The F-35A had a token value and now has none, because it
  has none.
  Full aft stick at 90 m/s with the assist off, which is where vectoring earns
  its keep: **F-22 330 deg/s of pitch rate, Su-35 313, Su-57 297, J-20 215,
  against 146 for an F-16 and 96 for an F-15E**. The ordering follows nozzle
  deflection, and sustained turn rate at 250 m/s is unchanged, which is right --
  at fighting speed the wing does the work.
  One trap worth recording: the moment has to be worked out from a *real*
  thrust figure. Engine thrust here is about fifteen times life so the jets feel
  right against a 140 km map, with drag scaled to match, but a moment arm has no
  such compensation. Feeding the inflated number through eight metres of tail
  gave the Raptor **four thousand degrees a second**, about twelve rolls a
  second, before that was caught.
  The cans move too: vectoring aircraft get each nozzle on its own pivot, with
  the burner glow riding it, and everything else keeps them baked into the one
  mesh. Verified the pivots track the commanded deflection exactly, and that
  non-vectoring types build no pivots at all.
* **Walking up to things on the ramp** — reach was measured from the walker to
  the machine's *origin* with a flat eleven metre limit, which only works if
  everything is the same size. It is not: standing against the flank of an
  AC-130 you are twenty-two metres from the point it is measured from, so the
  aeroplane offered nothing at all, while a transport parked near a tank could
  win the prompt over the tank you were touching. Reach is now measured to the
  hull -- each machine caches its own model bounds and answers how far a point
  is from the box, not from the centre. Tested by standing two metres off the
  flank of every boardable on the ramp in turn: **11 of 11 correct**, against
  10 of 11 with a large aircraft present before. The pilot also used to be put
  down at a fixed fourteen metres to one side, which is outside an F-22 and
  *inside* an AC-130's wing; they now start clear of the nose whatever the
  aeroplane is, and the ramp audits clean for every airframe.
* **Camera roll through the vertical** — the chase rig blended the airframe up
  vector toward world up with a straight lerp to level the horizon. Near
  inverted flight the two are nearly opposite, so the blend collapsed to a
  tenth of a unit and whatever sideways component survived decided the camera
  roll. Measured with a scripted tumble that rolls continuously while the nose
  traces a loop, so the rig meets every attitude there is: **161 degrees of
  camera roll in a single frame**, on every jet, every time it went over the
  top. Three changes, each verified against that number. The blend is done by
  angle in the plane across the view rather than by lerping two nearly opposite
  vectors. The levelling fades out as the aircraft rolls past knife edge, since
  "55% of the way to world up" has no continuous answer once the airframe up is
  pointing down -- inverted, the rig simply rides the airframe, which is always
  well defined. And the roll reference is rate limited to 200 deg/s, so the
  remaining switches between references read as a short sweep instead of a
  snap. 161 deg per frame down to 4-5, and what is left is the deliberate rate
  limit rather than a discontinuity. The free-look sweep is unchanged: constant
  17.2 m boom, 0.00 deg off axis.
* **Artillery actually goes where you send it** — designating on the map and
  firing put the rounds kilometres from the target, and four separate faults
  were responsible. The ground aim point is cached for a few frames because
  marching the height field is expensive, but the cache was keyed on time
  alone: designate a target and pull the trigger in the same breath and the
  tubes laid on the new bearing while the rounds flew to the old one. The cache
  now knows what it was computed from. The piece also fired the instant you
  asked, though the traverse takes 0.9 rad/s, so the rounds left on the correct
  bearing while the launcher was still swinging round -- it now holds the shot
  and sends it the moment it is laid, and the HUD says LAYING with the angle to
  go and whether a round is queued. Worst of the four: a fuse arms at the
  muzzle, so a howitzer parked in a line of vehicles detonated its own round
  nine metres out, on the tank standing beside it, every single time. Rounds
  now arm after ninety metres of flight. Measured at 6 km with the target
  designated a hundred degrees off the hull: **M109 11 m, Msta 10 m**, and the
  launchers spread as area weapons should at **110-131 m**.
* **One rocket at a time** — a launcher used to commit its whole pod to a single
  trigger press. Each press now sends one round and holding the trigger walks
  the rest out at the ripple rate, so a fire mission is yours to place.
* **The menu turntable was a real vehicle** — picking a ground vehicle and any
  mission put the player 256 m in the air. The preview model on the menu card
  sits in a rig high above the world and it had been taken out of the
  "boardable" and "hittable" groups but left in "vehicles", so the code that
  went looking for "the M109" found the turntable first and mounted the player
  in it. It is out of that group now, and the handover picks from the vehicles
  just parked on the ramp rather than searching a group at all. This is also
  the answer to an older report that spawning as an MLRS "breaks the game",
  which could never be reproduced at the time.
* **Nothing falls out of the world** — two separate versions of the same fault.
  A knocked out tank skipped its whole physics step because the crew was dead,
  and since there is no world collision mesh -- the ground only exists because
  the road wheels look up the height field -- the hulk sank through the terrain
  for ever. Wrecks now keep their suspension and roll to a stop: measured at a
  steady 0.49 m ride height for as long as you care to watch. Separately, the
  rotary flight model was missing the fixed wing's catch-all crash test, and its
  only other one needed the aircraft to be banked past 47 degrees, so an upright
  helicopter that got below the terrain kept going. Bandit gunships were ending
  up **190 km underground while still reporting themselves alive**, which is why
  a client in a co-op dogfight would watch its opponents sink out of the sky.
  The rotary AI was also stowing its undercarriage on spawn, copied from the
  fixed wing bandit -- skids do not retract, and with no gear there was no
  ground contact to stand on in the first place.
* **Target selection** — the radar ranked contacts purely on angle off
  boresight, so anything dead ahead won however far away it was: a fighter would
  lock something 95 km away and opening in preference to a bandit two
  kilometres off the nose, and sit there with a full load of missiles. Ranking
  now weighs range alongside angle and ignores anything outside the selected
  radar range.
* **Fuel** — thrust is scaled well above real figures so the jets feel right
  against a 140 km map, but the consumption divisor was never scaled with it.
  Burning fuel against the inflated thrust emptied an F-22 in eighty seconds of
  afterburner, and the high altitude dash test had been quietly measuring a
  glider. Full burner is now about seven minutes.
* **Approach speed** — the autoland flew a fixed 160 kt, which was right for one
  weight and wrong for every other; at the corrected weights a light fighter has
  so much surplus lift that it climbs away from the slope at idle. Threshold
  speed is now 1.3 times the stall speed at the current weight, and the flap
  lift increment is per airframe -- a fighter's plain flap is not an airliner's
  slats and triple slotted flaps, and giving the transports a fighter's
  increment is what made them need a fighter's runway.
* **Approach stability** — the scripted pilot's roll loop was tuned on fighters
  and had no notion of how fast a given aeroplane can actually roll. Commanding
  43 degrees of bank on a transport that rolls at 0.95 rad/s means the
  correction is still going in long after it was needed: a Hercules on approach
  wallowed through plus and minus sixty degrees at about 1.5 Hz, at nearly full
  aileron, all the way to the ground. Bank authority, the bank loop gain, the
  roll rate damping and the fly-by-wire integrator wind-in rate are all now
  scaled by the airframe's own roll and pitch authority, normalised to the F-22
  so the fighters are unchanged by construction. The approach entry speed comes
  from the airframe too -- a fixed 148 m/s is a fighter's approach and roughly
  twice what a Hercules flies, and no controller tunes its way out of starting a
  hundred knots fast with the throttle already closed. Every fighter and the
  Cessna now roll to a full stop on the centreline; the wallow is gone from the
  heavy transports, which fly a stable wings-level slope but still arrive high
  and go around. That last part is the scripted pilot, not the flight model:
  they take off and hand-fly correctly, so it is recorded here rather than
  papered over.
* **Ground handling** — an aircraft on its wheels is held straight by the tyres,
  not the fin, and the damping did not rise with speed. The F-35 lands at 170 kt
  and would swing 20 degrees off the centreline and cartwheel. Yaw and roll
  damping now scale with speed and the dihedral effect is suppressed while the
  undercarriage is loaded; every fighter in the hangar now rolls to a full stop
  on the centreline.
* **Grey-out** — sustained g costs you your sight. Tolerance is 5.5 g and the
  rate of onset goes with the *square* of the overage, because a linear rate
  that greys you out at nine also greys you out at six, which is wrong: a suited
  pilot holding a good strain sits at six g more or less indefinitely. Measured
  in the turn test, eight seconds at 6.13 g costs 10% of your vision and eight
  seconds at 8.31 g blacks you out completely. The veil was checked by rendering
  the same frame at three strain settings and measuring it rather than looking
  at it: at rest the frame is unchanged, at 0.55 the mean drops from 109 to 55
  and the edge-to-centre brightness ratio falls from 0.688 to 0.345 -- the
  periphery going twice as fast as the middle, which is what tunnel vision is --
  and at 0.95 the whole frame is down to 7. Negative g fills the view with blood
  instead, and it arrives much faster because there is far less headroom.
  Finding this also turned up why nothing appeared at first: a Control parented
  straight to a CanvasLayer has nothing for its anchors to resolve against, so
  it is zero-sized and draws nothing.
* **Replicated garrisons** — sector armour drives itself, so unlike a structure
  its pose has to be sent or a client ends up shooting at where its own copy
  wandered off to. Six garrison tanks across a conquest map track the host's
  positions to within 0.01-0.03 m.
* **Frame rate** — 1600x900 on an M3: 85-87 fps rolling down the runway, 90-93
  airborne over the valley, 84-87 low over the city in overcast with a conquest
  match running, 88-90 on foot at the ramp with every vehicle spawned. Around
  1100 draw calls and 1.85M primitives, 115 MB peak.
* **Gun** — a bandit shot down from 500 m astern in 1.6 seconds.
* **JDAM** — released from 1.5 km slant, tracks the designated target and
  detonates 1.2 m from it. Getting there needed three fixes: the guidance was
  leading a ballistic drop and aiming hundreds of metres short, the energy model
  scaled a bomb's turn rate against a missile's reference speed so it could not
  hold its own weight, and the fuse and lethal radius were tuned for a missile
  rather than a thousand pounder.
* **Artillery** — 40 degree quadrant elevation with the charge scaling from 25 %
  at 2 km to 97 % at 30 km, times of flight from 18 to 72 seconds. Measured fall
  of shot at 4 km: the M109 lands 7-29 m from the aim point, the M270 spreads
  its salvo over 54-122 m as an area weapon should.
* **Heavy takeoffs** — the airliner and the AC-130 both rotate around 150-170 kt
  and climb away at 13 degrees. Both needed their main gear moved close to the
  centre of mass first: with the mains a metre and a half aft, the weight moment
  is larger than anything the tailplane can produce at rotation speed.

* **Nothing spawns inside anything else** — a self check runs at mission start,
  takes the world space footprint of every vehicle, aircraft and structure, and
  names any two that overlap. It immediately found two: the airbase parked four
  hangars along x=150, which is exactly the line the ramp start parks its
  aircraft on, so a jet spawned inside a hangar; and `_clear_mission`
  deliberately skipped the aircraft you were flying, so swapping type and
  restarting left the old one standing on the apron for the next mission to park
  a fresh one through. Both fixed; three restarts in a row now leave four
  aircraft in the world and zero conflicts. The check stays in, so the next one
  announces itself rather than waiting to be noticed.
* **Weapons that outlive their shooter** — passing a freed object to a typed
  `Node` parameter does not quietly pass null, it raises, and the raise aborted
  the rest of the damage loop. A bomb whose shooter had died therefore detonated
  1.1 m from its target and did **nothing at all**. It affected every weapon:
  bombs, missiles, cannon rounds, blast. Four call sites now resolve a dead
  shooter to null. The F-16 JDAM test went from "no kill, target at 80 hp" to a
  kill at t=8.1, and a busy conquest run went from eight runtime errors to zero.
* **Terrain seams, measured rather than looked at** — at every ring boundary the
  coarser ring has a vertex only at every second one of the finer ring's, so its
  edge runs straight past the odd ones: **mean 10.33 m, worst 257.67 m** of gap
  across 3072 samples. The skirts were hiding a quarter kilometre crack rather
  than fixing it. Chunk edges facing a coarser ring now drop their odd vertices
  onto the chord between their neighbours, so the two edges are the same line and
  the residual is **0.00006 m**, which is float rounding.
* **Weapons and water** — the terminal check tested only the height field, so a
  round aimed at a ship swam down to the seabed a couple of hundred metres below
  and went off there. They now detonate at the surface: a JDAM on a corvette took
  its hull from **1100 to 258**.
* **The trigger** — left click fires, everywhere. Right click is deliberately not
  a weapon: it raises the sensor page. Weapons are polled straight from the input
  actions rather than through the GUI, so a click on the map used to fire as
  well; a modal flag now inhibits them while a full screen page is up. Verified:
  with the map up, `fired=false`.
* **Ships under command** — helm, telegraph, battery and tubes: an Arleigh Burke
  made 119 m in eight seconds (29.9 kts), answered the wheel, laid its mount on
  068 when ordered to 068, and fired.
* **The lock that let go just before you shot** — an AMRAAM fired at a ship was
  arriving unguided. The fuse fix below was real but it was not the whole story:
  the lock itself was being dropped half a second before the trigger. The gate
  was the *missile's* seeker field of view, which is a different instrument from
  the aircraft's radar, and on any look-down attack the target slides below the
  nose as you close. Measured on a run-in from 1500 m: lock acquired at 29.8
  degrees down, held to 32.4, and **dropped at 33.2 — the AIM-120's gate —
  with the shot due at 33.5**. The round then left the rail with nothing to
  follow and flew where it was pointed. The gate is the aircraft's own radar
  gimbal now, and a targeting pod holding a point track keeps the lock whatever
  the nose is doing, which is the entire purpose of putting a sensor on a
  gimbal. Worth noting the harness had been quietly papering over this: it
  re-asserted the lock at release, so the test passed while the game did not.
* **A fuse that measured to the wrong place** — a Sidewinder arriving at a
  destroyer's bow was seventy metres from the ship's origin amidships, which is
  the point the proximity fuse was measuring against. It flew through the ship
  and went off in the sea beyond. The fuse now works against the target's
  surface: measured, an AIM-9X 14.5 m from a corvette's origin with a 9.1 m
  hull radius detonates on a 9 m fuse, and an AMRAAM at 15.7 m on a 13 m fuse.
  The same arithmetic had been quietly under-fusing every large target in the
  game.
* **A ship's magazine** — the tubes fired AMRAAMs, and fired them straight up.
  Vertically launched, at six hundred metres a second pulling a few g, the turn
  radius is kilometres: the round simply carries on being vertical. Measured
  closest approach to an aeroplane twelve kilometres out, **4584 m**, with nine
  rounds wasted and the target untouched. Launched leaning at the contact
  instead, on a dedicated naval round with the booster a ship can afford —
  faster, longer burning, four times the reach and more than twice the warhead
  — the closest approach is **6 m** and the aeroplane does not come home.
* **The sea drew over the explosions** — a bomb into the water made a splash
  with no fireball. Two things. The burst was drawn at the round's own position,
  which by the time the water check trips is already under the surface. And
  more importantly the sea and the fireball are both alpha transparent, and
  transparent surfaces do not write depth — they are sorted, by object origin.
  The sea is one mesh sixty kilometres across whose origin is the middle of the
  world, so from anywhere out over the water it sorted in front and composited
  86% opaque sea over the top of the explosion. It is drawn last now, and the
  burst stands clear of the surface: measured 4.4 m above it instead of 0.3 m
  below.
* **The weapon camera** — see below; the same class of bug, and the same fix.
* **Where towns go** — the settlements were dropped on fixed coordinates and
  draped over whatever gradient ran through them, which on this terrain means a
  street grid laid up a hillside and buildings climbing it. Each town is now
  moved onto the flattest ground within reach of where it was wanted and stands
  on a platform levelled into the height field. Measured across all four:
  gradient **0.0022 to 0.0000**, worst height step across a building footprint
  **9.34 m to 0.00 m**, and street sample points buried in the ground **486 of
  1404 down to 12**, deepest **6.29 m to 1.97 m**.
* **Roads nobody could see** — the network was there the whole time: 47 trunk
  legs, 117 streets, 43,532 triangles of carriageway, every mesh present and
  visible. What was missing was the stain the terrain paints under them, which
  is what actually draws the network from any distance at all — at altitude the
  carriageway mesh is sub-pixel. That stain is keyed on distance-to-road, and
  distance-to-road came from a field baked at 256 samples over 36 km: **141 m
  to a cell, for a carriageway fifteen metres wide**. It could not resolve a
  road. Measured standing on the centreline, it reported a mean of **30.3 m
  away and up to 84.7 m**, and at **303 of 1476** centreline points it said far
  enough that the terrain painted no road there at all. The result was a faint
  broken smear rather than a road network. The field is a broad phase now and
  the segments are walked properly anywhere the answer is close enough to
  matter: **0.0 m mean error, 0.0 m worst, 0 of 1476 points unpainted**, for
  about 1.4 s more at world generation.
* **A measurement that was measuring nothing** — the cloud altitudes read back
  as 0 to 0 m however they were sampled, through three rewrites of the sampling
  code and two of the build order. A two-instance MultiMesh built and read in
  isolation settled it: `set_instance_transform` writes through the rendering
  server, which is a stub in headless, so **every instance reads back as
  identity there**. The write was correct the whole time — printing the source
  transform gave (−29617, 2642, −28050) and the read-back gave zero on the next
  line. Anything in this project that measures a MultiMesh by reading it back
  is measuring the stub; the band is recorded as the field is built instead.
* **Roads through the airfield, and buildings standing in them** — two faults
  that both came down to one number being asked to cover every case.
  The trunk network ran across the airfield: **362 of 4784** sample points
  inside the keep-out, and once the router was told to avoid it, four points
  ended up on the runway itself — worse in the most visible way. Penalising
  the middle of a leg cannot help when the *ends* are the problem: a road that
  starts beside an airfield and heads south-west is inside the keep-out within
  a few hundred metres whatever the relaxation does, because the relaxation
  moves waypoints and not endpoints. The network hangs off a bypass down the
  east side of the field instead, and the towns join whichever end of it is
  nearer: **0 points on the field, 0 on the runway**, with the 95 that remain
  all out in the extended-centreline strip, kilometres from the threshold,
  where a road crossing an approach is what real airfields look like.
  Buildings stood in the road because the clearance was a flat 16 m measured
  from the centreline — the carriageway and its kerbs and nothing else — so a
  24 m building placed at exactly 16 m had four metres of itself in the road:
  **62 of 3641**. Making that one number wide enough for a motorway then
  deleted **more than half the town**, because a ten metre street was demanding
  a motorway's clearance. Each road is checked against its own width now, and
  the building is sized before it is sited: **0 of 2936 overlap a carriageway**,
  and one solitary building still stands on painted tarmac. It costs about 19%
  of the buildings, which is the price of not building in the road.
  The denser network is a fringe benefit: 47 legs and 57 km became 103 legs and
  93 km, with the towns joined to each other in a ring rather than only to the
  field, and the climb per kilometre came *down* — 41.0 to 31.8 m/km — once
  every leg was subdivided. Legs short enough to be left as a single straight
  segment had no waypoints to relax and took whatever gradient lay between
  their ends, which is where a 53% pitch had appeared.
* **Roads drawn per fragment instead of per vertex** — the sharpest a road
  could ever be was one terrain cell, and the cell size is set by distance from
  the *airfield*, not from the camera, because the rings are built once around
  the origin. Measured: Vane gets 60 m cells, Kestrel and Rampart City 120 m,
  **Northgate 240 m** — against a street grid of 128 m. Northgate had roughly
  one vertex every two blocks to say "street" with. Smaller cells cannot rescue
  this: 15 m cells out at ten kilometres is about three and a half million
  triangles for a single ring, against 215 thousand for the whole world now.
  The network and the built-up ground are baked once into a 4096² two-channel
  mask — **8.79 m to a texel** — and sampled per fragment, so the geometry stops
  mattering. It is stamped capsule by capsule rather than sampled point by
  point: asking a distance field for sixteen million texels would take minutes,
  drawing 164 capsules into a byte array takes **509 ms**. Tarmac now covers
  **28.9%** of a town's area rather than 66.8%, and world generation came out
  *faster* — 8.57 s to 7.22 s — because the per-vertex segment walk it replaces
  was costing more than the bake does.
  The innermost cell was halved to 15 m anyway (a level added so the outer ring
  still reaches as far): 366 chunks to 421, 187k triangles to 215k, seam
  residual unchanged at 0.00006 m.
* **Towns that looked like fields with buildings in them** — two separate
  faults, and the first guess about each was wrong. Buildings at the edge stood
  on grass because nothing ever changed the *ground* under a settlement: it was
  whatever biome the terrain painter decided on, houses or no houses. Towns now
  stand on made ground that fades into the country beyond the last building —
  measured at **1.00 across the footprint and 1.00 in the outer ring** where
  the buildings meet open land, where before it was pasture throughout.
  Separately, the road stain used one 46 m band for everything. That is right
  for a trunk road, whose carriageway mesh is sub-pixel from any height, and far
  too wide for a town street: they run every 128 m, so **66.8% of the built-up
  area was painted tarmac**. Each kind has its own band now and it is **41.2%**,
  with the contrast between a street and mid-block going from 1.00/0.57 to
  1.00/0.40 — and then to 28.9% once the painting moved off the vertices
  entirely, which is the entry above. The first attempt was bounded by the
  terrain resolution; the second removed the bound.
  Checking the carriageway mesh itself first was worth it — the suspicion that
  it was buried turned out to be wrong. Against the *drawn* ground rather than
  the height field, only **253 of 21,938** points sit under it, by a mean of
  0.11 m.
* **Roads that go round things** — the trunk network was straight legs between
  fixed points, which on this terrain climbs a ridge, drops into a valley and
  climbs the next one. It is laid between the towns as they actually ended up —
  they move as much as 2.9 km, so roads drawn to the old sites ended in a field
  — and each leg's waypoints are relaxed sideways toward lower ground, the way
  a surveyor would. Cost is climb plus the square of the gradient plus a mild
  charge per metre of tarmac, so a road goes a long way round a mountain and
  not one metre round a molehill. Measured: **61.7 to 41.0 m of climb per km**
  and the steepest pitch **49.4% to 41.1%**, for 23% more tarmac. Dropping the
  gradient term brought the climb down but left a 59.9% wall in it, which is
  what happens when you only count the total.
* **Where the wheels go** — the autoland flew the glide slope to the aiming
  point itself, so the aeroplane was eighteen metres up three hundred metres
  out, the flare began before the runway and the wheels arrived on the
  threshold lip. Measured, an F-22 touching at z=+1474 with the paved surface
  ending at 1500 — landing on the runway to look at, and reported as a
  touchdown off the paved surface because a few metres either way put it
  outside. The slope is anchored on the threshold now, as a real three degree
  approach is, and the flare starts higher, shallower, and keeps some thrust
  until four metres. Across four types: touchdown moved 130 m further in and
  the arrival softened from 7.85 to 5.31 m/s (F-22), 3.45 to 1.35 (C-130),
  4.87 to 3.98 (A-10), with 614 m of runway to spare instead of 461.
* **Watching the traffic from somewhere else** — called-in aircraft fly their
  approach identically whether the player is in an aeroplane, a ship or a tank:
  same position and throttle to the decimal. What did not work was looking at
  them. A player on a ship is seeing through *that* vehicle's camera, so
  pointing the aircraft camera at a landing aeroplane moved nothing, and the
  traffic appeared not to be flying at all.
* **Ships that fight** — an Arleigh Burke and a Steregushchiy put eight
  kilometres apart and left alone. Both opened fire, the corvette went down at
  9.2 s and a patrol boat with her, and the destroyer came out at sixty percent
  with forty-one percent flooding. Then the interesting part: over the next
  thirty seconds the party pumped her out, the list came off and she worked back
  up from 11.7 to 15.4 knots. Finding this needed the merchants excluding from
  the target list — the first run had one side shelling neutral container ships
  while the other side shelled them, and the scoreline looked like a rout.
* **Damage control** — a destroyer given a thousand points of a 2200 point hull:
  fire at 73%, hull down to 55%. The fire then burned for a minute, cost another
  two hundred points of hull and 1.4 knots while it did, and the party had it out
  by fifty seconds. Both channels are tuned to a match rather than to life: about
  half a minute to fight a fire and a minute and a half to pump out flooding,
  with a full party.
* **Close air support** — a mud mover pair against four targets. The run-in
  measured 12.6 km to 900 m in one continuous descent, bombs away, off target,
  out to eight kilometres and back in again; three targets damaged. Three
  separate things had to be fixed to get there. The nose-on abort fired on the
  first frame of every attack, because straight off an egress turn the aeroplane
  is pointed the wrong way — no run ever got past one second. Re-attacking on a
  timer alone put it back in with the target three kilometres *below* it, which
  is not a run but a vertical scissors: measured pulling up through ten thousand
  metres and stalling there. And the goal was held sixty metres above the target
  for terrain clearance, which left the nose that much high — the best gun angle
  measured 11.4°, just outside the trigger gate, so it never fired a round.
* **Formation** — a wingman holds **120 to 140 m mean and about 200 m worst**
  off a 151 m slot, over 4200 samples per run, while the flight is patrolling. Before the controller was
  rewritten to work in the leader's frame it settled at 1.3 km and oscillated
  between three hundred metres and three kilometres. Turning the position gains
  up from the stable set made it worse, not better — 1626 m — which is what an
  under-damped loop does.
* **Terrain masking, end to end** — the highest ground within a 14 km box is
  1644 m. Every consumer of the line was checked against it: the radar refuses
  the lock behind the ridge and takes it over the top; the scope paints nothing
  behind and paints it over; a SAM battery fires 0 rounds at a masked aeroplane
  and 1 at an exposed one; a destroyer 19.7 km out to sea fires 0 at a target
  three kilometres behind the coastal ridge and 1 at the same target above it;
  and a round in flight holds the track with a clear line and drops it once
  masked. Two things came out of building the test rather than the feature. A
  missile at five thousand metres looks *down* over a ridge and is not masked by
  it — correct, and it makes for a useless test, so the probe has to be flown
  low. And a round that has already detonated answers every question with
  whatever it last held, which is how the first version of this passed while
  measuring nothing.
* **Terrain masking, the primitive** — the highest ground within a 14 km box is
  1644 m. Two
  points 40 m above the deck either side of it: line blocked, and the ray passes
  938 m *inside* the hill. The same two points 2500 m up: clear. A bandit parked
  behind that ridge cannot be locked; lift both aircraft over it and the lock
  takes.
* **Ships in a session** — the fleet reaches a client with the hull states exact:
  499, 2200 and 1304 on both ends, two of those having been damaged in a fight
  the host simulated. The client's ghost is on the identical track — the
  host-to-client position delta normalises to (0.877, −0.479), which is heading
  61° to the decimal.
* **The chat line** — `/` opens it, sixteen characters go in, "wasd on the deck"
  comes out the far end, and the stick reads +0.00 roll and +0.00 pitch the whole
  time it is being typed.
* **The weapon camera** — riding a round, the boom vector wobbled a **mean of
  4.81 m and a worst of 6.16 m every frame**: the camera was placed from the
  round's stepped physics position while the round itself was drawn interpolated
  to the render frame, so the thing being followed jittered by exactly one tick
  of travel. Reading the interpolated pose instead, and smoothing the boom
  offset rather than the world position, takes it to **0.001 m mean, 0.005 m
  worst** over 2280 frames.
* **A bomb onto a moving ship** — designate a corvette from the pod, release a
  GBU, and the hull goes 1100 -> 255. Three separate things were wrong before it
  worked. The bomb steered at the coordinates the point track was *created* at,
  so the ship sailed out from under it. The ship's origin sat below the
  waterline, so a hit at the hull detonated in the air above the deck. And the
  laser, having only a height field to intersect, painted the seabed 35 m under
  the target instead of the ship on it.

## Locking a target

`T` cycles the radar through hostile contacts. Four things stopped that working
properly, and only one of them was the key.

**Your own carrier was a valid target.** It carries no `team` at all and sits in
the `hittable` group, so the hostility test — *does it have a team, and is that
team mine?* — skipped it entirely and let it through. Press `T` near the fleet
and you locked your own ship. A contact needs an explicit, differing team now.

**So were laser designation spots.** They belong in `hittable` so a bomb's fuse
finds them, but they are a place rather than a contact, and the radar cycled
onto them.

**Terrain masking rejected too much.** The line-of-sight ray began four metres
above the aeroplane, so at low level or on the runway it marched straight
through the ground underneath and reported every contact as masked. It ignores
the first 250 m now.

**And a duplicate name is not a name.** Set on a node before it joins the tree,
a name that collides with a sibling is not suffixed by Godot — it is thrown away
and replaced with a generated one. The second Type 45 and the second patrol boat
were on the radar as `@Node3D@194` and `@Node3D@197`. Ships are numbered when
they are built, and everything that puts a contact on screen asks for its
display name rather than its node name.

The **sensor head** had the same fault the weapon camera did. It is placed once
per rendered frame from the aircraft's transform, and it was reading the stepped
physics value while the aeroplane itself is drawn interpolated — so the pod view
shook against a wing you can see in your own periphery. Measured against the
aeroplane as drawn: **1.13 m of frame-to-frame wobble, worst 1.24 m**, now
**0.0000 m**. The first version of that measurement compared the head to its own
transform source, which is self-referential and reads zero however wrong it is.

Discrete key presses are also latched from the input event rather than polled
from `_physics_process`. `Input.is_action_just_pressed` is true only during the
frame the press was registered, and physics runs at 120 Hz whether or not the
renderer keeps up, so a press could in principle land between ticks and be gone
before anything looked. Measured at 15, 30 and 120 fps, both approaches deliver
all twelve presses of twelve — the latch is a guarantee rather than a
demonstrated repair.

## A salvo of bombs

Dropping several JDAMs on one lased point turned up three faults stacked on top
of each other, and two of them were self-inflicted.

**Induced drag was being charged to a bomb.** The steering term for a guided
bomb carried `+ UP * 9.81` to hold gravity off, which on a flat trajectory is
almost entirely *lateral* — so the new turn-costs-energy rule read it as a
permanent hard turn and billed it accordingly. The charge grows as the inverse
square of speed, so the slower it got the harder it braked: a bomb released from
seven kilometres decelerated to **40 m/s two thousand metres up**, tripped the
"this round has stopped flying" self-destruct and went off five kilometres
short. Bombs are exempt; their lift-induced drag is already in a drag
coefficient an order of magnitude above a missile's.

**Cancelling gravity was wrong anyway.** With it held off the bomb glides flat
instead of nosing over, and with a bomb's drag it simply bleeds out — it reached
the target's neighbourhood doing 59 m/s and expired at the end of its seventy
second life, still two hundred metres short. It steers the *direction* of its
velocity onto the line of sight now and leaves the magnitude to gravity, which
is what a falling thing does. The same JDAM that used to take a corvette from
1100 to 433 now takes it to below zero.

**And the first bomb was disarming the rest.** When it killed what they were all
aimed at, every round still in the air lost its target and finished wherever it
happened to be pointed — the leader landing at 19 m and the follower at 145. A
laser spot is a *place*: a bomb whose target has gone keeps flying the last
position it had. Measured on a three-round salvo at one mark: **19 m and 8 m**,
arriving six seconds apart.

## A missile slower than the aeroplane that fired it

`boost` and `drag` had been set independently, and `ref_speed` — the speed a
round is built around, and the speed its agility term is measured against — had
no say in either. Both were wrong, and at the midpoint of a short shot the two
errors cancelled, which is why it had survived.

An AIM-120 was boosted to **1704 m/s — Mach 5.3 — and then braked at 35 g**.
Forty seconds later it was doing 201 m/s: slower than the F-16 that fired it,
and far below the speed at which its own energy term gives it any turn left. A
HARM sent at a battery at its rated 48 km arrived at 196 m/s. The rounds that go
a long way were the ones it ruined, and the AMRAAM's own comment about pulling
its rated g "near its peak" was being defeated by drag before the round got
anywhere.

Both numbers follow from `ref_speed` now: `boost * burn` is what the motor adds,
so a rocket burns out *near* its design speed rather than at three times it; and
`drag * ref_speed²` is what the round costs itself at that speed, which for a
slender missile is a couple of g, not thirty.

| | dragged at ref | burnout | at its rated range |
|---|---|---|---|
| AIM-9X | 29 g → 1.6 g | 1900 → 914 m/s | 12 km at 842 m/s |
| AIM-120C | 35 g → 1.6 g | 3660 → 1099 m/s | 40 km at 883 m/s |
| AGM-88 HARM | 25 g → 1.6 g | 4980 → 897 m/s | 48 km at 602 m/s |
| SM-2 | 64 g → 1.6 g | 10220 → 1537 m/s | 74 km at 1273 m/s |
| AGM-65 Maverick | 21 g → 1.6 g | 1600 → 655 m/s | 22 km at 430 m/s |

Traced through a 32 km shot, an AMRAAM now leaves the rail at 373 m/s, burns out
at 1065 and is still doing 976 twenty-two seconds later — against a target
holding 380 to 424 the whole way. It was the *parasitic* drag that was wrong;
the induced drag that makes a late hard break work is a separate term and is
untouched, and countermeasures still break the lock exactly as they did.

A break alone no longer beats an AMRAAM inside 32 km, which is the point of the
weapon.

**The Harpoon is meant to be slower than you**, and is: a sea-skimming turbojet
holding Mach 0.85 while the aeroplane that dropped it does Mach 1.2. What was
wrong there was different — the motor stopped. `burn` was 240 s of a 428 second
run to the weapon's own stated range, so it coasted the last third against 2.6 g
of drag and was self-destructed in mid-air at 300 s. Its real reach was 70 km
against a table entry of 124. A turbojet runs for as long as the flight lasts;
the throttle already decides when it is actually lit. The Kalibr and the Mk-48
had the same fault — a torpedo rated at 38 km could swim nine.

| | stated range | could actually reach |
|---|---|---|
| AGM-84 Harpoon | 124 km | 70 km → 124 km, arriving at 428 s of a 520 s life |
| 3M-14 Kalibr | 150 km | 73 km → 150 km |
| Mk-48 torpedo | 38 km | 9 km → 38 km |

## A weapon that could not reach its own range

Two of the numbers in the store table are not independent of the rest, and
checking each round against its own entry turned up four weapons that could not
do what they claimed.

**The SLBM reached 44 km of a stated 90.** Range on a ballistic arc is
`v² sin(2a) / g`, so the burnout speed sets it and nothing else can. The
strategic round simply fell out of the sky less than half way to anything it was
aimed at — which is why `--nuketest` had been failing by 18 km and `--subtest`
had never destroyed a single structure. Both pass now.

**The Harpoon's motor stopped at 70 km of a stated 124.** A turbojet runs for
as long as the flight lasts; `burn` was 240 s of a 428 second run, so it coasted
the last third against its own drag and was self-destructed in mid-air at 300 s.
The Kalibr and the Mk-48 had the same fault — a torpedo rated at 38 km could
swim nine.

Ranges are now set from the speed each round can actually reach, and the map is
1200 km across, so they use it: the Oreshnik goes 500 km, the Khorramshahr 1000.

## The hypersonic that was not

The Oreshnik cut its motor **six seconds into a hundred and ten second stage**.
The rule was to stop burning the moment the arc the round is already on reaches
the target, which is right at maximum range and a disaster well inside it: fired
72 km — 40% of its rated reach — it peaked at 937 m/s against a design speed of
2400 and went over the top at 315. A lobbed shell, from a weapon whose own entry
calls it hypersonic.

On a ballistic arc that cannot be tuned away. Range is `v² sin(2a)/g` and apogee
is `v² sin²(a)/2g`, so at a fixed range more speed means a steeper arc and a very
much higher one — holding 2400 m/s over 72 km needs an 85 degree launch and takes
the round 200 km up. The way out is the one the real weapons use: depress the
trajectory, burn the whole stage, fly low and fast. Three things had to change
together — the flat root of the arc rather than the steep one, a motor that may
not cut below the speed the arc was solved for, and a midcourse loft that does
not aim twenty kilometres above a target it is trying to stay low to reach.

| | before | after |
|---|---|---|
| peak speed | 937 m/s | 3423 m/s (Mach 10) |
| speed at the target | 315 m/s | 1769 m/s |
| apogee on a 72 km shot | 18 km | 2.4 km |

## Independently targetable

A MIRV bus was releasing on height while doing 1780 m/s, so its load had forty
seconds of falling in which to cover sixty-eight kilometres against the five
that were left. And the warheads were rated at 8 g against the bus's 15 —
scaled by air density and by how far off their design speed they were, that came
to **1.7 g**, so they could not steer at all and fell wherever the bus had thrown
them. Measured, the six came down **19 km** from the aiming point.

A guided re-entry vehicle separates on *range*, while it still has room to fly
itself down, and it needs the authority to do it. `--teltest` had only ever
checked that the bus opened; it measures where the load lands now.

| | mean miss | worst |
|---|---|---|
| before | 19132 m | 19445 m |
| after | 550 m | 764 m |
| with each warhead given its own mark | 43 m | 53 m |

That last row is the point of the letters. Shift and right click on the map
assigns a mark to a warhead; the bus deals them out as it opens, the primary
mark first. Without any, it spreads its load over the footprint as before.

## Defeating a missile

Three things decide whether a break works, and the interesting part is which
one turned out to matter.

**Air density.** A fin makes its side force from dynamic pressure, so the same
round is far less agile high up. An AMRAAM at its peak speed has 35 g on the
deck, 17 g at six thousand metres and 7.7 g at fifteen thousand — and a shot
that has to climb to reach you arrives slower as well as thinner.

**Ground clutter.** A radar seeker looking down at a target near the ground is
picking it out of the return from every field and roof behind it. A couple of
seconds in the notch and the track is gone, and a SAM battery will not spend a
round on something it cannot hold in the first place — measured, it fires none
at all at an aircraft at 250 m and four at the same aircraft at 4000 m.

**Induced drag**, which is the one that was missing. Instrumenting a whole
engagement showed the round asking for **0.1 to 4.4 g while it had 17.4** — the
g limit never once engaged, which is why raising and lowering it changed nothing
whatsoever. What the missile could do was turn as hard as it liked for free, so
a defensive break bled the aeroplane's energy and none of the missile's. A turn
now costs speed, as the square of the side force and inversely with the air it
has to work in: a gentle correction at 5 g costs 3 m/s per second, a hard
endgame turn at 25 g down low costs over 170. That is the whole reason a late
break works in reality.

None of it stops a missile killing something that flies straight: three bandits
still go down in the standard dogfight.

## Does the model match the numbers?

An aeroplane's aerodynamics read the spec; its shape is built from a separate
set of polygons in the same entry, and nothing ever compared the two. The A-10's
wing was written on the wrong axes — `(chord, span)` where every other airframe
uses `(span, chord)` — which built a metre-and-a-half stub with ten metres of
chord, and the flight model went on using 17.53 m of span regardless. Nothing
said a word.

`--geomtest` builds every airframe and measures the mesh against its own figures.
All twenty-one now agree to a fraction of a percent: the A-10 builds **17.5 m
against a spec of 17.5**.

Getting the check right took a second pass. Comparing a helicopter's width to
its `span` failed all five of them by a factor of three, because the widest
thing on a helicopter is the rotor disc and `span` refers to the stub wing.
Rotary airframes are measured against rotor diameter instead.

## The curtain under the seabed

"I can see skirts of terrain when in a submarine." Each chunk carries a vertical
curtain around its edge so a coarser neighbour cannot show daylight through the
ring seam. It was `cell * 0.35`, and on the outer rings a cell is nearly two
kilometres — so the curtain hung **12 m under every chunk edge, 9 m on average**.
Above water you never see it. Under water it is the only thing down there.

The stitching that pulls a fine edge onto its coarse neighbour leaves a seam of
**0.000061 m**. The curtain was covering a crack four orders of magnitude
smaller than itself. `--skirttest` measures both, taking each chunk's lowest
vertex against the ground at the chunk's own vertex positions:

| | worst drop | mean | seam |
|---|---|---|---|
| before | 12.00 m | 9.16 m | 0.000061 m |
| after | 0.60 m | 0.50 m | 0.000061 m |

Getting the measurement right mattered as much as the fix. Sampling the ground
on a ten-by-ten grid over each chunk's footprint reported **51.95 m**: on a ring
with 1.9 km cells that grid misses the low ground entirely, and the difference
was read as curtain. Sampled at the chunk's own vertices it comes out at exactly
the `clampf(cell * 0.35, 1, 12)` the code asks for.

### Does the stitching hold across a change of detail?

The seam stat is not evidence that it does. It checks that a fine chunk's own
edge vertex sits on the line between its neighbours — that the edge is
*straight*. It never asks the coarse chunk on the other side where **its** edge
is, and it only looks at two of the four sides.

`--lodtest` reads the built meshes and asks both chunks how high the ground is
at the same point on the boundary:

```
ring 0 -> 1 (cell   15 m ->   30 m): worst 0.0000 m
ring 6 -> 7 (cell  960 m -> 1920 m): worst 0.0000 m
560 boundary points had two chunks drawing them, 0 had only one
disagreement between the two sides: mean 0.00000 m, worst 0.0000 m
```

Exact agreement at every boundary, every ring — so the ring seams are watertight
and the curtain under them is covering nothing at all. The 0.6 m that remains is
insurance for the outermost ring, which has no neighbour to be stitched to.

Getting *that* measurement right took a correction too. The first run reported a
**1249 m** disagreement, which reads as terrain tearing itself apart. The chunks
were fine — `C-15360_-3840` and `C-23040_-7680` both answered 1214.8 m. The water
plane is a child of the terrain as well, and it was answering "the ground is at
-35 m" at every point on every boundary.

`--seamtest` was reporting "T junction gaps: mean 8.86 m, worst 257.67 m", which
reads as though the terrain were full of two hundred metre holes and made
shrinking the curtain look reckless. It measures the *raw height field*: how far
the fine chunk's extra vertex sits off the straight edge its coarse neighbour
draws — the deviation the stitching then takes out by putting that vertex
exactly on the line. Both figures are printed together now, so the 257 m and the
0.000061 m can be read as the same sentence.

## A commander's sight

Armour had a sensor page it could never reach. `_process` shut the pod on any
frame a tank was crewed, so opening it closed it again in the same frame, and
the action menu never offered it in the first place.

The pod already generalises to whatever is carrying it, but two things assumed
an aeroplane and one assumed a ship. `_draw_contacts` returned early on a null
`jet`, so a crewed hull — ship or tank — drew no contacts at all. `_sensor_input`
read the aeroplane's stores, so with the page up on a ship, pressing `1` changed
the weapon on the jet parked back at the field. And the sight was hung at
`mast_height`, eighteen metres, which on a tank is eighteen metres above its own
turret.

Lasing hands the mark to whatever is holding the sensor: a ship lays its tubes
on it, and a tank writes it to the fire-mission slot the map view already uses,
which is what a self-propelled gun does with a laser. While the page is up the
mouse belongs to the sight — unguarded, looking around walked the fall of shot
out and threw away the mission the sight had just handed over.

| | before | after |
|---|---|---|
| page stays open in a tank | closed the same frame | open across 12 frames |
| sight height above the hull | 18.00 m | 2.65 m |
| turret under a mouse sweep, sight up | 0.572 rad | 0.000 rad |
| lasing sets the fire mission | no path at all | set, 0.0 m from the target |
| contacts drawn on the sight | 0 | 9 |

## Roads that are built, not draped

The routing already took a road round the worst of the ground. What happened
after that was nothing: the carriageway followed whatever the noise field put
under it, so a trunk road pitched **34.7% at its worst** and fell **6.0% across
its own width** on average — a switchback with a camber like a ditch.

A road is surveyed now. Each route is chained at 110 m, the ground height read
along it, and the profile put through a cut-and-fill cone filter: nothing may
rise faster than the ruling gradient of 6.2%, and once that has pulled the
profile down through the hills, nothing may fall faster either, which raises it
across the dips. `height_at` then blends the land toward that surface over the
carriageway and grades the spoil out over a 24 m shoulder.

Three things had to be added before it read as one network rather than a dozen
separate cuttings:

- **Junctions.** Two routes crossing at a shallow angle were surveyed
  independently and disagreed by 8 m five metres apart — a step down the middle
  of the road. Comparing waypoint to waypoint missed it entirely, because their
  nearest waypoints were fifty metres apart. Every vertex is now measured
  against the nearest *stretch* of every other road, including the road itself
  where it doubles back, and pulled toward the common height.
- **Parallel runs.** Two routes converging on the same town ran 9 m apart for a
  stretch and each cut its own corridor. They are drawn onto each other.
- **Towns.** A settlement is already levelled. The corridor fought the platform
  and left a **13.98 m step under Northgate's buildings**; the pad wins inside
  the town now.

| | before | after |
|---|---|---|
| gradient along the road | mean 2.9%, worst 34.7% | mean 2.7%, 95th 6.2%, worst 7.8% |
| cross fall over the carriageway | mean 6.0%, worst 108.6% | mean 0.1%, 95th 0.1% |
| worst town footprint step | 13.98 m | 0.00 m, all four towns |

`height_at` is called for every terrain vertex and every wheel on the ground, so
the corridor is answered from a 64 m grid index rather than by walking all 846
legs. Terrain build cost is unchanged.

## The road that could not be built

The network had been surveyed to a ruling gradient of 6.2% and it held it
everywhere, which sounds like success and was not. Holding a fixed gradient
against rolling country puts the design surface a long way from the ground, and
the earthworks then have to make up the difference: **1040 km of a 2021 km
network was classified as tunnel** — more than half of it underground — with a
120 km "viaduct" standing in open sea where a route between two continents had
decided the cheapest way across was to pave it.

Three things were wrong, and the first one caused the other two.

**The profile was all cut and no fill.** The grade rule ran four sweeps: two
taking minima and two taking maxima. Composed in that order what comes out is
the *highest* profile that never stands above the ground — every metre of the
road in a cutting, nowhere on an embankment. Over hills that is a cutting nearly
the whole way, and past a cutting's depth the classifier had no choice but to
call it a tunnel.

There is exactly one right answer here and it is cheap. Among all profiles
obeying a gradient limit, the one nearest the ground is the midpoint of two
envelopes: `U[i] = min_j(g[j] + G·d(i,j))`, the highest such profile below the
ground, and `L[i] = max_j(g[j] - G·d(i,j))`, the lowest above it. Both are two
sweeps. Their midpoint has the smallest possible worst earthwork, and that worst
earthwork is `(L - U)/2` — so the same arithmetic that draws the road also says
whether it can be built at all.

**Clamping and smoothing fought each other.** The profile was clamped into the
cut-and-fill band, then re-graded, then clamped again, twenty-odd times. Those
are two convex sets and alternating between them converges — in the limit, and
slowly where they barely meet. Measured, the design surface ended up **70 m
under a hillside** at a station the classifier had left as open ground, and the
corridor dutifully carved a cliff trying to reach it. Both constraints are
applied at once now: propagating the band edges along the line at the gradient
allowance makes each edge Lipschitz in its own right, and the median of three
Lipschitz functions is Lipschitz — so clamping the wanted profile between the
propagated edges satisfies both in a single pass. Where the two edges *cross*,
no road can be built there at all, and that crossing is what marks out the
country a structure exists for.

**The aerodrome was applied after the road.** The survey read the ground with
the airfield already levelled into it — which is what lets a road run onto an
apron instead of stopping at a cliff beside it — and then the corridor was
applied to the hillside underneath. The survey believed it was cutting five
metres where it was in fact carving ninety-five.

Along with those: water is charged by depth rather than at a flat rate, and a
leg whose route needs more than an eight kilometre crossing is abandoned rather
than built; the router samples the midpoint of every search step, because a
ridge crest is narrower than a 400 m grid cell and a step measured end to end
runs straight over the top of one; a road that meets another is *pinned* to a
shared height and the pin is propagated back along both roads at whatever
gradient each is allowed, rather than being tugged toward the mean locally; and
two stretches of road in the same place at the same height take the same
classification, so a deck cannot stand on its twin's embankment.

| | before | after |
|---|---|---|
| trunk network | 2021 km | 2203 km, every town on it |
| bored | 1040 km (51%) | 55 km (2.5%) |
| carried on a deck | 323 km, incl. a 120 km ocean span | 104 km, none over 3.2 km |
| gradient along the road | 95th 7.7%, worst 59.5% | 95th 7.6%, worst 15.8% |
| cross fall over the carriageway | 95th 0.0%, worst 41.7% | 95th 0.0%, worst 26.8% |
| finished ground vs the design surface | 4.70 m high, 30.58 m low | 0.00 m, 0.00 m |
| junctions disagreeing about the height | 22.6 m | 5.2 m |
| earth moved | mean 5.43 m, worst 38.5 m | mean 2.63 m, worst 45.7 m |
| spans standing on made ground | — | 0 of 113 |

The worst cutting is deeper than it was, and deliberately: a run that wants a
tunnel and does not earn one is allowed a 45 m cutting rather than being held to
34 m and then dragged back out of the band by the next pass. `--roadtest` reads
the limits out of the survey itself so the bars move with them.

## The country, before the hangar

The menu used to open on a turntable with a vehicle already standing on it,
forty metres from the camera against a backdrop of nothing much — after nine
seconds of building a twelve hundred kilometre world. It now opens on the world:
a slow circuit under the cloud deck over the home valley, with the hangar fading
in over it a couple of seconds later. Nothing stands on the turntable until
somebody asks to look at something, and choosing a card is what cuts to it.

## The helicopter that sank when you let go

Release the collective after a climb and the machine dropped seventeen metres
through the height it was at before settling. The altitude hold was grabbing the
current altitude the moment the lever centred — but the aircraft is still going
up at six metres a second at that point, so the loop was instantly six metres a
second fast at a target it had already left behind. It chopped the collective to
arrest a climb it should have been letting run out, overshot the other way, and
the trim wound up during the climb took seconds to come back. Holding the height
the machine is going to *reach* rather than the one it is passing through leaves
the loop nothing to fight.

| | before | after |
|---|---|---|
| sag on releasing the lever | 17.4 m | 0.0 m |

`--helitest` had never once measured any of this. Two faults in the test itself:
its `elif` chain fell through to "collective up" for the four seconds before the
hands-off window and never let go, so the twenty seconds it exists to measure
were flown on full up collective — and it drove the lever through the input map,
which in a headless session reports the shift key as held from the moment the
process starts. It drives the lever directly now, and gates on the drift and on
the sag.

Hands off for twenty seconds, the hold was always right: 1.3 m of drift.

## Three aeroplanes that could not do their job

**The flying wings could not take off.** The B-2 and the H-20 rolled the full
three kilometres and went off the far end at 159 knots with the pitch rate
reading exactly zero. Two faults, and the first hid the second: they were the
only aeroplanes in the game with less than a quarter of their peers' pitch
authority — 1.35 rad/s² against 6.2 for an F-16 — and the B-2 was rolling at
201 t against a real maximum take-off weight of 170, so she needed 159 knots to
rotate and could not reach it inside the runway. At an operating weight and with
elevons that can lift the nose, she is off at 149 knots with 750 m to spare.

**A helicopter left on the pad flew away by itself.** The world sets
`auto = "wait"` while the pilot is walking out and climbing in. The fixed wing
side has always understood that; the rotary pilot did not look at the value at
all, so any autopilot state fell straight through to the hover hold and the
aircraft climbed to a hundred and twenty metres with nobody in it.

**The gunship's barrels had nothing to do with its fire.** The side battery was
merged into the airframe mesh, so it pointed wherever it had been modelled while
the rounds flew off to wherever the sensor was looking. The guns are on trunnions
now, they train onto the sight whether or not the trigger is down, and the fire
comes out along the bore — so a mount that cannot reach the mark is a shot that
is not taken, which is what banking a gunship into its orbit is for. `--gunnertest`
reports whether the battery is on the mark through the orbit.

And the targeting pod's azimuth was clamped to ±137°, a stop the hardware does
not have — a head on a roll gimbal can look anywhere the airframe is not in the
way. Anything behind you could be point-tracked by the ship sensor, which sets
the angle directly, and could not be reached with the mouse.

## Parts you could see through

"A lot of the vehicle engines and parts don't have backface culling so I can see
through them from some angles." Culling was not missing; the faces were pointing
the wrong way, and a face pointing away is not drawn at all.

`--culltest` fires 220 rays at each model from all round it and counts the ones
whose nearest triangle faces away — which is exactly a hole. It found four
separate faults:

- `prism` decided which way a face pointed by comparing it with the polygon
  centroid. On a concave planform — a wing with a root extension — the centroid
  is outside the outline, and panels came out inside out. **The F-16's wings
  failed 4.2% of all viewing angles.** Faces are given their outward normal
  explicitly now, from the winding of the outline.
- `loft` used one centre for a whole hull. On anything long and thin — a
  nacelle, a duct — a face's normal is nearly perpendicular to the line from
  that centre and the sign came down to rounding. It uses the local section
  axis instead.
- The intake ducts were lofted **open at both ends**, so where one ran into the
  fuselage there was a hole straight into the airframe, and the well behind the
  lip had no inner skin.
- Nozzle shrouds and the A-10's nacelles were tubes open at the back.

Rays that see through the skin: **27 in 3402 → 10 in 6137** with the vehicles
and ships included. Every airframe that was bad is now at zero, and airframe
dimensions are unchanged.

## A ship is not a sphere

`hit_radius()` returned the ship's **beam**. A Steregushchiy is 105 m long and
11 m wide, so a round that arrived on the forecastle was scored as a 20 m miss.
Worse, the fuse measured to the skin while the damage falloff still divided by
the distance to the *origin*, and divided it by the fuse radius rather than the
warhead's lethal radius — so a round always detonated near the edge of its own
fuse envelope and therefore always did the floor.

And the sea was checked before the fuse. A Harpoon crossing the surface a few
metres from a corvette was killed by the water and went off as a splash.

Four fixes: ships answer `surface_gap()` against an oriented hull box; the miss
handed to the warhead is that gap; falloff scales on the lethal radius; and the
fuse is asked before the sea is. The round also holds for its closest approach
rather than going off the moment the target enters the envelope, and the cruise
terminal phase leads the ship instead of chasing where it was.

A Harpoon from an F-16, released at 16 km from 4200 m, sea-skimming at 33 m:

| | gap off the hull | hull |
|---|---|---|
| before | went off in the sea | 1100 → 987 |
| after | **0.4 m** | 1100 → 523, flooding |

## A ship's armament, on the bridge

The armament line lived inside a `has_gun()` test, so a **submarine — whose only
weapon is its tubes — was told nothing at all**: not what was selected, not
whether it could fire. It is always drawn now, the readiness shown belongs to
the *selected* weapon rather than always to the gun, and the bridge says what
the sensor has the ship laid on and how far away it is.

Switching itself was never broken: with the sensor page shut, cycling runs
`main -> vls -> main -> vls` and the number keys select directly. There was
simply nothing on screen to say so.

## A ship's sensor

A crewed hull sets the pod's `host` and leaves `jet` as whatever it was — which,
once the player has walked off an aeroplane, is null. Every guard in the sensor
read `jet`, so on a ship `_process` returned at the first line and `designate()`
at the second: **no point track, no area track, no laser, nothing**. The sensor
now works off whatever is carrying it, aeroplane or hull, and hands what it is
holding to that thing — an aeroplane keeps it as a radar target, a ship as what
its tubes and battery are laid on.

Firing the tubes from the conn also ignored the designation entirely and shot at
whatever happened to be nearest, which makes a targeting sensor decorative.

And a warship has a mast full of antennas and no scope. The radar panel was
written against the aeroplane and read `jet` for position, heading, team and
target, so there was nothing to put on the bridge. It takes a source now, and
the bridge draws one: measured, **10 contacts inside 40 km** from a destroyer,
with the same terrain masking the cockpit page uses.

## The strategic round, and what stopped it

A submarine launch was flattening nothing at all. Three faults in a row, two of
them mine from this session.

The **seeker's terrain masking** dropped the track nine tenths of a second off
the rail: a lofted shot at a target twenty-two kilometres away has the horizon
in the way by definition. Masking now applies only to a round homing on
something that has to be *seen* — an aeroplane or a vehicle. A weapon flying to
a coordinate does not care what is between it and the place.

**Proportional navigation flies an intercept, not an arc.** With the track back,
the round nosed over off the rail, threw away the loft it launched with and flew
into a mountain six kilometres short. It has a lofted midcourse now — the aim
point is raised in proportion to the distance still to run and comes down as it
closes — and it steers by pointing its velocity vector rather than by leading,
because leading a patch of ground at Mach four carried it four kilometres past.

The loft had to be applied **before the line of sight is taken**. Putting it
after was the same as not having it: proportional navigation steers on `los` and
never looks at the target position again, which is why three consecutive changes
produced byte-identical results.

Measured on the same target: **0 of 1912 structures destroyed, then 1402**.

## Skirts you could see from the sea

The terrain hides the cracks where two LOD rings meet behind vertical skirts,
and the skirt depth was `cell * 3` with nothing capping it. On the outermost
ring a cell is 1920 m, so every chunk out there trailed a **five and a half
kilometre curtain** beneath it — invisible from above and unmissable from a
submarine. It is clamped to twelve metres now, which is far more than the
boundary stitching leaves to cover: the T-junction residual is 0.00006 m.

    ring 0    15 m cell     45 m  ->   5 m
    ring 7  1920 m cell   5760 m  ->  12 m

The reference project in `refenrece/PlanetTerrain (Best)` does the same thing —
`clampf(cell_m * skirt_cells, 0.4, 5.0)` — and reaches the same conclusion in a
comment: "LOD gaps are only ever a few meters."

## Nine seconds to two and a half

World generation was 9.9 s cold. Almost all of it was arithmetic being asked for
one point at a time across the extension boundary, from script, on one thread.

| phase | before | after |
|---|---|---|
| road network (site, route, survey) | 3204 ms | 889 ms |
| terrain (chunks, ground mask, climate) | 1898 ms | 437 ms |
| scenery (towns, road surfaces, scatter) | 3645 ms | 954 ms |
| map relief | 906 ms | 95 ms |
| **total** | **9.9 s** | **2.6 s** |

What actually moved the numbers, largest first:

- **Road surfaces, 2620 → 313 ms.** Four height samples every eleven metres of
  every road and street on the map, each one its own boundary crossing, from
  eight workers that then queued at it. Both vertex lists are built in one call.
- **The survey tail, ~1070 → 0 ms.** Classify, hold, grade, settle and float
  were a dozen passes over eighty thousand stations, alternating between script
  and the extension. It is one call now, and the passes that were serial in it
  — welding and tying — run over the stations across every core.
- **The relaxation index.** Rebuilt once per pass, and building it is the one
  part that cannot be spread over the cores. Welding moves a station a couple of
  metres against a 34 m reach, so it is rebuilt every fourth pass instead:
  598 → 284 ms, with the measured junction disagreement unchanged.
- **The ground mask, 605 → 28 ms.** Sixteen million texels against nine thousand
  capsules. Bucketed by row and clipped to the band of each row before scanning,
  so a road running diagonally across the map is no longer scanned from one side
  of every row it touches to the other — and the coverage is counted where it is
  drawn, because a script loop over sixteen million texels cost more than
  drawing the whole thing did.
- **The map relief, 906 → 95 ms**, and **the climate texture, 523 → 12 ms**.
  Both were per-pixel loops over a worker pool asking the extension for a height
  or a noise value at a time.
- **Terrain nodes and chunk borders.** Measuring a node's deviation was 353
  separate height queries, on the main thread, the first time the tree ever
  looked at one. Conforming a chunk's edges, measuring the residual and reading
  the field either side of every border vertex was another six hundred. Both are
  one call each now.
- **Road distance.** A 256 x 256 raster of the distance field over an 18 km box,
  guarded by walking the segments wherever the answer mattered — because at
  141 m to a cell it could not resolve a 15 m carriageway, and reported a mean
  of 30 m away while standing on the centreline. Replaced by a grid-indexed
  exact query over the whole map, which is faster than the guard was: measured
  standing on the centreline, mean 0.0 m, worst 0.0 m, and no point on any road
  where the terrain paints nothing.

Two things came out of the script side entirely: the second copy of the height
field, which was still being set up and could have drifted from the real one
without anything noticing, and the script-side spatial indexes for the road
network, which the extension now owns because it is the only side that needs
them.

## A sky full of missiles going nowhere

Friendly warships were firing constantly, in every direction, at nothing you
could see. `--fleetfire` counts what the fleet actually does with its tubes over
a hundred seconds of a running engagement, and the first run said it plainly: 98
rounds away, 87 of which never came within a kilometre of what they were sent
at, and ten of them chasing one contact.

Three separate faults, and they compounded.

**Nothing counted how many tubes were already on a target.** The anti-missile
picture had always capped itself at two rounds a threat; the *air* picture had
no cap at all, so every hull in the fleet fired at whatever was nearest, every
few seconds, for as long as it lived.

**Nothing asked whether the shot was possible.** An SM-2 will fly seventy
kilometres, so anything inside thirty-eight was fair game — including fighters
twenty to thirty kilometres out, jinking and opening. Broken down by the range
the shot was taken at:

| launched at | rounds | got within a kilometre |
|---|---|---|
| under 8 km | 8 | 6 (75 %) |
| 8–15 km | 18 | 1 (6 %) |
| 15–25 km | 46 | 4 (9 %) |
| over 25 km | 23 | 2 (9 %) |

Seventy-three per cent of everything fired went beyond fifteen kilometres, where
it has no realistic chance. The engagement now stops at twelve kilometres, which
is where it stops working, and the interceptor picture gets the comparison it
always needed: a cell leaves the tube at a standstill and averages about seven
hundred metres a second, so from twenty kilometres it is half a minute from the
intercept — fired at a round that arrives before then it is simply thrown away.

**And a round whose contact died flew on for a minute and a half.** Losing the
target meant coasting to the last known position and then just carrying on:
SM-2s alive for ninety to a hundred and eight seconds whose closest approach to
anything was fourteen to thirty kilometres, several of which were at their
closest three tenths of a second after launch — they flew away from the target
and never came back. From the deck that is the whole complaint. A real one
destroys itself, and so does this now, at the closest it gets to the last place
it saw the target. Rounds sent to a *place* — bombs, cruise weapons and
ballistic shots — are excluded, because arriving without ever seeing anything is
the entire point of an inertial mark.

Measured over the same hundred seconds: **98 rounds down to 20**, the most at any
one contact down from ten to four, and four of the seven shots taken at aircraft
now get within a kilometre. `--vlstest`, `--cmtest`, `--navaltest` and
`--breaktest` are unchanged.

## A missile that flew into the sea

A Maverick locked to a warship, fired from low level, went into the water 1.4 km
short — with LOCKED on the glass the whole way down. Instrumented, the round's
height told the story on its own: 95 m, 73, 44, 16, and then a splash.

Proportional navigation works out the turn that closes the line of sight and
nothing else. It does not know the round is also falling. Against an aeroplane
that barely shows — both bodies are in free fall, so gravity is very nearly
common-mode and the geometry is forgiving. Against a ship it is the *whole* miss,
because a hull's origin sits exactly at sea level: every centimetre the round
sags under its own commanded course is a centimetre nearer the water, and there
is no altitude left to spend. The steeper the shot the more it gets away with,
which is why a dive from 1500 m hit and a flat run from 120 m did not — the dive
had 1.1 m to spare inside an 11 m fuse, so it was never far from failing either.

A real autopilot trims gravity out, and this project's own cruise profile always
has — it is the `+ Vector3.UP * 9.81` in its steering. Every homing round now
gets the same trim: the component of gravity across the flight path is added to
the acceleration command, before the g limit takes its cut, so a round short of
speed or short of air still droops, which is correct. Ballistic and cruise
rounds are excluded — the first flies an arc on purpose and the second already
does this.

Measured, same shot: height 98, 86, 73, 58, 41, 23, 4 and a hit, closest
approach 3.2 m against 1368 m before. Air-to-air is unchanged — three runs each
way against a target breaking at full power from 12 km, an AMRAAM closes to a
mean 11.7 m with the trim and 12.3 m without, a Sidewinder 10.7 and 10.3, all
inside the run-to-run spread of the endgame.

`--navaltest` was scoring that shot a **hit**, because it compared the hull's
health before and after and the ambient battle was hurting the ship while the
round was in the air. It now tracks the round's own closest approach to the
hull's *surface* and calls a miss a miss.

## A gun that hit like a rifle

The A-10 is an aeroplane built around a gun, and its rounds landed with the same
puff of dust as a rifle bullet. A GAU-8 fires 30 mm high explosive incendiary: a
burst of it walking across a target is a string of small detonations. Cannon
impacts now take a burst scale from the gun's own entry — flash, fireball and
the dirty smoke that hangs afterwards, built from the same cheap pieces a bomb
burst uses, because a hundred rounds a second of these have to stay affordable.
Solid shot still puffs dust; only the A-10 is tagged, and any other gun is one
key in its spec.

## Key labels that told you to press the wrong key

The countermeasures moved — flares off `N` onto `C`, chaff off `B` onto `V`, to
get the chaff off the bomb bay key. The help page was updated to match. The
flight strip was not, and neither was the hangar's control line nor this file:
between them they went on naming `N` and `B` for the countermeasures, `V` for a
gun that is on `K`, `C` for a camera that is on `P` and `M` for a mouse stick
that is on `;`.

Labels are read off the bindings now, through `Sim.key_label()`, so a key that
moves takes its label with it. `--hudtest` also walks the help page and compares
every control it names against the action it is really bound to, which is the
check that was missing when this drifted the first time.

## Things hanging in the air beside the aeroplane

The F-16 carried two Sidewinders that were not on it. Its wingtip rails were
authored at x = ±4.85 and z = 0.40; the wing's planform ends at x = 4.55, and at
that station its chord runs from z = 2.20 to z = 3.30. So the rails sat thirty
centimetres outboard of the tip and nearly two metres ahead of the wing, and the
missiles floated in clear air. The navigation lamps were worse: they were placed
at half the span from the data table — 4.98, not 4.55 — and at 0.6 of the
*leading edge z of the second poly vertex*, which on a swept wing is a number
with no geometric meaning at all. The port lamp ended up 3.32 m off the wing.

None of this was an F-16 problem. Every station and every lamp was positioned by
eye against numbers that only line up on a straight wing, and `--wingtest` — which
asks each fitting whether its mounting point is inboard of the tip and between
the leading and trailing edges at that station — found something adrift on 22 of
the 23 airframes.

The fix is to stop guessing. `JetFactory` now reads the planform: `_tip_x` for
where the wing ends, and `_chord_at` for where its leading and trailing edges are
at any half-span station, walking the two edge chains of the wing polygon. A
pylon store is snapped to the chord at its own station and hung far enough below
the skin for its pylon to reach; a wingtip rail goes on the tip, with its round
positioned so the tail sits level with the trailing edge and the nose overhangs
forward, which is what a wingtip missile actually looks like. The lamps go on the
tip, and the tip vortex leaves the trailing edge of the tip rather than a point
abeam it. All 23 airframes pass, and the aeroplanes carry what they are holding.

## A launcher that would not stop bouncing

A TEL arriving on the ground bounced for several seconds. Two faults, and they
compounded.

Every ground spawn put the hull at `Sim.height_at(...) + 1.1`. For a tank that is
about half a metre of drop, which is survivable. For a launcher it is not: its
wheel *centres* sit a tyre radius above the body origin, so the origin belongs at
ground level, and 1.1 m meant dropping fourteen tonnes of lorry a full metre
before anything touched. The vehicle now asks its own running gear where it
belongs — `rest_height()` takes the largest `r - rest_y` across its wheels and
subtracts the static deflection the springs will take — and `ground_pose()` also
lays the hull along the terrain normal instead of level with the horizon, so one
side of the running gear is not buried while the other is in the air.

Then the damping. It was `1.05 * sqrt(k * mass / N)`, which reads like a critical
damping expression and is not one. The hull sits on all N springs at once: the
whole vehicle sees `2k` and `2c`, so the ratio that matters is `c / sqrt(2*k*m)`,
and the old figure works out at `0.742 / sqrt(N)` — 0.20 on fourteen wheels. A
vehicle damped at a fifth of critical does not settle, it oscillates. Solving the
same expression for `c` at a chosen ratio (0.75 tracked, 0.95 for a launcher,
0.80 for a 4x4) is a three-line change and the pogoing stops.

`--susptest` measures it: peak swing on spawn and how long until the hull is
still. Before, a launcher swung 1.44 m and was still moving at three seconds.
Now it swings 0.02 m and is settled inside a frame. It then drives the vehicle
away, because a suspension that never moves is also a way to pass this test.

## Code health

Godot will not report every warning from a headless run. A standalone ternary
is raised by `GDScript::reload` only in a real windowed session, so the first
anyone hears of it is a warning on somebody's screen — `--editor --quit` says
nothing, a headless run says nothing, and `--check-only --script` cannot resolve
the autoloads to get that far. `tools/lint_gd.py` catches that class statically.

    python3 tools/lint_gd.py

It took three attempts to be worth having. Matching a ternary by regex flagged
every wrapped argument list in the project — 38 of them — until it tracked
bracket depth across lines. Then it caught nothing at all, because the rule that
skipped "lines which are a call" threw the real fault away with the false ones;
the test that works is whether the `if` and `else` sit at bracket depth zero,
since inside brackets they belong to somebody else's expression and
`print("a" if b else "c")` is a perfectly good line. And two slice comparisons
were off by one, so `line[i:i + 4] == "if "` could never be true.

`project.godot` promotes the analyser's style warnings to **errors** — shadowed
identifiers, unused variables and parameters, integer division, incompatible
ternaries, confusable declarations, uncast enums. Nothing is silenced; the
project builds clean under that setting, and any new slip fails the parse rather
than scrolling past in the output panel.

To check every file from the command line:

```
godot --headless --path . --editor --quit          # build the class cache first
for f in scripts/**/*.gd; do godot --headless --path . --check-only --script $f; done
```

The cache step matters: without it every file reports its `class_name`
dependencies as missing and the real warnings are buried.

## Sound

Everything is synthesised at startup, nothing is loaded from disk. Fixed wing
aircraft get a turbine core plus a broadband afterburner layer; helicopters get
a blade slap thump train at the blade passing frequency over a turbine whine and
rotor wash, so a Havoc does not sound like a Flanker. On top of that: airflow
that rises with dynamic pressure and gets louder with the gear or bay out, tyre
roll, gun buzz, a short rifle crack, missile launches, positional explosions,
gear and bay servos, a touchdown thump, stall buffet and a missile warning tone.

## Simplifications

Nothing is textured from an image: surfaces get procedural panel lines and
mottling, and the afterburner is a shaded plume rather than a bitmap. No
compressor/engine modelling beyond spool and altitude lapse, no wind or
weather, no fuel burn effects on CG, IR/radar detection is a single
cross-section number, and the AI does not fly formation or use terrain masking.
