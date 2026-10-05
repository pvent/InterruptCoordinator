# Interrupt Cooldown Tracker

Interrupt Cooldown Tracker is a standalone addon for **The Burning Crusade Classic client 2.5.3** (`Interface: 20503`). It estimates interrupt cooldowns from combat-log casts visible to this client. It does not exchange addon messages or use spellbook/cooldown reports.

## Install

Copy the `InterruptCooldownTracker` folder into `World of Warcraft/_classic_/Interface/AddOns/` and enable **Interrupt Cooldown Tracker** at the character-select screen.

## Use

- `/ict` opens or closes the settings window. `/ictracker`, `/interrupttracker`, and `/interruptcooldowntracker` are aliases.
- `/ict show` and `/ict hide` enable or disable combat-log tracking.
- `/ict tracking` toggles tracking.
- `/ict reset` returns the bar to screen center.
- Hold **Shift** and drag the bar or one of its icons to reposition it.

The visible bar starts at login and displays **Waiting for casts** until a tracked interrupt is observed. It uses one flat row-based icon grid; there is no primary recommendation. Main interrupts are tracked by default. Enable **Track secondary stops** to include cooldown-based stuns and control spells from the original catalog. **Interrupt filters...** opens a separate two-column panel for main interrupts and secondary stops; each column has its own Show all and Hide all buttons.

The config window lets you choose icons per row and maximum rows, set icon size (24–64 px) and player-name font size (8–18 px), and adjust horizontal/vertical position with both sliders and +/- buttons. Shift-dragging the tracker updates those position controls, and adjusting a slider/button starts from the tracker's current position. **Cell padding per side** controls the empty space around icons: for example, 8 px adds 16 px to each cell's width and height, keeping icons centered while resizing the bar background and spacing. Enable **Hide tracker when empty** to hide the waiting message; enable **Show tracker only in combat** to hide the bar outside combat.

Cooldowns are local estimates based on the catalog's base durations. The event handler accepts both the modern combat-log payload and the older TBC payload layout. Missed events, talent reductions, resets, and spells cast outside this client's observable combat log may make an estimate inaccurate. Spell icons stay in color, including while on cooldown. An observed spell stays visible after its cooldown expires.
