# Setting up an IADS

## Skynet IADS elements

![Skynet IADS overview](images/skynet-overview.jpg)

### IADS

A Skynet IADS is a complete operational network. You can have multiple Skynet IADS instances per
coalition in a DCS mission. A simple setup would be one IADS for the blue side and one IADS for the
red side.

### Track files

Skynet keeps a global track file of all detected targets. It queries all its units with radars and
deduplicates contacts. By default lost contacts are stored up to 32 seconds in memory.

### Command centers

You can add multiple command centers to a Skynet IADS. Once all command centers are destroyed the
IADS will go into autonomous mode.

### SAM sites

Skynet can handle multiple SAM sites, it will try and keep emissions to a minimum, therefore by
default SAM sites will be turned on only if a target is in range.
Every single launcher and radar unit's distance of a SAM site is analysed individually.
If at least one launcher and radar is within range, the SAM Site will become active.
This allows for a scattered placement of radar and launcher units as in real life.

If SAM sites or radar guided AAA run out of ammo they will go dark. In the case of a SAM site it
will wait with going dark as long as the last fired missile is still in the air.

If an EW radar or a SAM site acting as EW radar is destroyed surrounding SAM sites can be left
without EW radar coverage. This can also happen if a SAM site is outside of AWACS coverage.
SAM sites will go autonomous in such a case meaning they will use their organic radars or just stay
dark depending on setup.
Once a SAM site is within EW radar coverage again it will be updated by the IADS.

### Early Warning Radars

Skynet can handle 0-n EW radars. For detection of a target the DCS radar detection logic is used.
You can use any type of radar listed in
[skynet-iads-supported-types.lua](https://github.com/VEAF/Skynet-IADS/blob/master/skynet-iads-source/skynet-iads-supported-types.lua)
in an EW role in Skynet.
Some modern SAM radars have a greater detection range than older EW radars, e.g. the S-300PS 64H6E
(160 km) vs EWR 55G6 (120 km).

You can also designate SAM sites to act as EW radars, in this case a SAM site will constantly have
their radar on. Long range systems like the S-300 are used as EW radars in real life.
SAM sites that are out of ammo will stay live if they are set to act as EW radars.

Nice to know: terrain elevation around an EW radar will create blind spots, allowing low and fast
movers to penetrate radar networks through valleys.

### Power sources

By default Skynet IADS will run without having to add power sources. You can add multiple power
sources to SAM sites, EW radars and command centers.
Once a power source is fully damaged the Skynet IADS unit will stop working.

Nice to know: taking out the power source of a command center is a real life tactic used in SEAD
(Suppression of Enemy Air Defence).

### Connection nodes

By default Skynet IADS will run without having to add connection nodes. You can add multiple
connection nodes to SAM sites, EW radars and command centers.

When all the unit's connection nodes are fully damaged an EW radar or SAM site will go into
autonomous mode. For a SAM site this means it will behave in its autonomous mode setting.
If an EW Radar loses its node it will no longer contribute information to the IADS but otherwise
the IADS will still work. Command centers do not have an autonomous mode.

Nice to know: a single node can be used to connect an arbitrary number of Skynet IADS units. This
way you can add a single point of failure in to an IADS.

### AWACS (Airborne Early Warning and Control System)

Any aircraft with an air to air radar can be added as AWACS. Contacts detected will be added to the
IADS. The AWACS will also detect ground units like ships.
These will however not be passed to the SAM sites.

You can add a connection node for the AWACS like an antenna, if it is destroyed, the AWACS will no
longer be able to contribute contacts to the IADS.
Technically you can also add a power source. In this context it would represent the power source
for the connection node, since an aircraft provides its own power.

### Ships

Ships will contribute to the IADS the same way AWACS units do. Add them as a regular EW radar.

## Using Skynet in the mission editor

It's quite simple to set up an IADS, have a look at the setup scripts in
[demo-missions/](https://github.com/VEAF/Skynet-IADS/tree/master/demo-missions) — and at the demo
missions themselves, which come [attached to a release](https://github.com/VEAF/Skynet-IADS/releases)
rather than committed to the repository. See the [Quick start](index.md#quick-start) for why, and for
how to assemble one from a clone.

### Placing units

This tutorial assumes you are familiar with how to set up a SAM site in DCS. If not I suggest you
watch [this video](https://www.youtube.com/watch?v=YZPh-JNf6Ww) by the Grim Reapers.
Place the IADS elements you wish to add on the map.

![Mission Editor IADS Setup](images/iads-setup.png)

### Preparing a SAM site

There may only be **one type of SAM site per group**. More than one type of SAM site per group will
result in Skynet not being able to properly control the group. Also please refrain from adding
units to the SAM group that are not required for the SAM like trucks, tanks and soldiers.
The skill level you set on a SAM group is retained by Skynet. Make sure you name the **SAM site
group** in a consistent manner with a prefix e.g. `SAM-SA-2`.

![Mission Editor add SAM site](images/add-sam-site.png)

### Preparing an EW radar

You can use any type of radar as an EW radar. Make sure you **name the unit** in a consistent
manner with a prefix, e.g. `EW-center3`. Make sure you have only **one EW radar in a group**
otherwise Skynet will not be able to control single EW radars.

![Mission Editor EW radar](images/ew-setup.png)

### Adding the Skynet code

Load the compiled skynet code into a mission. Skynet itself no longer requires MIST — the
[skynet-iads-compiled.lua](https://github.com/VEAF/Skynet-IADS/releases) attached to each release is
a drop-in script. However, the demo missions bundle `mist_4_5_107.lua` for other functionality, and
you can download the current MIST version
[here](https://github.com/mrSkortch/MissionScriptingTools) if needed.

I recommend you create a text file e.g. `my-iads-setup.lua` and then add the code needed to get the
IADS running. When updating the setup remember to reload the file in the mission editor. Otherwise
changes will not become effective.
You can also add the code directly in the mission editor, however that input field is quite small
if you write more than a few lines of code.

![Mission Editor IADS Setup](images/load-scripts.png)

### Adding the Skynet IADS

For the IADS to work you need four lines of code.

Create an instance of the IADS, the name string is optional and will be displayed in status output:

```lua
redIADS = SkynetIADS:create('name')
```

Give all SAM groups you want to add a common prefix in the mission editor eg: `SAM-SA-10 west`,
then add this line of code:

```lua
redIADS:addSAMSitesByPrefix('SAM')
```

Same for the EW radars, name all units with a common prefix in the mission editor eg:
`EW-radar-south`:

```lua
redIADS:addEarlyWarningRadarsByPrefix('EW')
```

Activate the IADS:

```lua
redIADS:activate()
```

See the [API reference](api.md) for everything else — command centers, power sources, connection
nodes, go-live constraints, the jammer, and the full example setup.
