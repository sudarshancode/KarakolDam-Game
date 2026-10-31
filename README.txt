BLACKOUT AT KARAKOL DAM
=======================
An original tactical stealth shooter for Linux (64-bit), made with Godot 4.3.
You are alone. A mercenary crew holds the Karakol hydroelectric dam.
Get in, sabotage it, and get out before it blows.


QUICK START
-----------
1. Extract the archive:      tar -xzf KarakolDam-linux-x86_64.tar.gz
2. Go into the folder:       cd KarakolDam-linux-x86_64
3. Either play right away:   ./play.sh
   or install for your user: ./install.sh      (then start it from your app menu,
                                                or type: karakol-dam)
To remove it again: ./uninstall.sh

(Banglay: tar -xzf diye extract koro, tarpor folder e dhuke ./play.sh chalaw,
 othoba ./install.sh diye install koro. Install korle app menu te
 "Blackout at Karakol Dam" name e pabe.)

If the scripts are not executable:  chmod +x play.sh install.sh uninstall.sh KarakolDam.x86_64


REQUIREMENTS
------------
- Linux, 64-bit Intel/AMD (x86_64)
- A GPU/driver with OpenGL 3.3 (Mesa, NVIDIA or AMD proprietary all work)
- About 200 MB of RAM. No other files or internet needed; all sound is generated in-game.

Troubleshooting:
- Black screen / crash at start:   ./play.sh --rendering-driver opengl3
- Still nothing (no GPU driver):   LIBGL_ALWAYS_SOFTWARE=1 ./play.sh      (slow but works)
- Wayland issues:                  ./play.sh --display-driver x11
- F11 toggles fullscreen.


THE MISSION
-----------
1. (Optional) Destroy the COMMS RELAY in the west shed.
   With the relay up, the first guard who spots you raises the alarm and four reinforcements
   arrive at the south gate. Destroying it cuts the alarm and stops any reinforcements.
2. Download the SABOTAGE PLANS from the terminal inside the control tower (east).
   This unlocks the coolant valves.
3. Plant charges on BOTH COOLANT VALVES at the north wall of the turbine hall.
   Once both are armed you have 150 seconds.
4. Reach EXTRACTION on the ridge in the east (the ramp starts outside the east fence).

Ways in: the main gate (south, two guards), or the service gap in the west fence
(a 3 m gap with rocks around it, patrolled along the inside).


CONTROLS
--------
W A S D        move              Left mouse    fire
Shift          sprint            Right mouse   aim down sights (steadier, slower)
Ctrl / C       crouch            R             reload
Space          jump              1 / 2 / wheel switch weapon
E (hold)       use / plant       M or Tab      tactical map (north is up)
Esc or P       pause             F11           fullscreen


TIPS
----
- The SILENCED PISTOL is nearly silent, and a headshot kills instantly. Body shots take three.
- The ASSAULT RIFLE is loud: everything within ~75 m hears it.
- Crouching halves how far guards can see you. Sprinting makes noise and makes you easier to notice.
- Guards have a vision cone, hear noise, and notice bodies. Hide the ones you take out.
- A "?" over a guard = suspicious/searching. A "!" = they have seen you and will fire.
- The DETECTION bar at the bottom shows how close a guard is to spotting you.
- Medkits (white box, red cross) and ammo crates (green box) are scattered around the base.
- You can walk behind the fence line outside the compound; fences block movement but not sight or bullets.


FOLDER CONTENTS
---------------
KarakolDam.x86_64   the game (single file, data embedded)
play.sh             run without installing
install.sh          install for the current user (no sudo)
uninstall.sh        remove it again
icon.svg            icon used by the menu entry
source/             the complete Godot 4.3 project. Open project.godot in Godot 4.3 to edit it.
                    Rebuild: Project > Export > Linux, or
                    godot --headless --export-release "Linux" build/KarakolDam.x86_64

Developer flags for the source/game (after "--"):
  --selftest    short automatic check, prints navigation/guard info, then quits
  --flowtest=win|lose|die|combat   scripted run through the mission rules
  --shot=FILE.png [--teleport=x,y,z,yawdeg,pitchdeg] [--map]   save a screenshot and quit

This is an original game: all code, levels and audio are generated in-game. It uses the free
and open-source Godot Engine (MIT license, https://godotengine.org).
