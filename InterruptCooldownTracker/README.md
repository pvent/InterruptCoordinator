# Interrupt Cooldown Tracker

Interrupt Cooldown Tracker is a standalone World of Warcraft addon for **The Burning Crusade Classic client 2.5.3** (`Interface: 20503`). It tracks interrupt cooldowns observed in the local party or raid combat log. It does not share data between clients.

## Install

Copy the `InterruptCooldownTracker` folder into:

`World of Warcraft/_classic_/Interface/AddOns/`

Enable **Interrupt Cooldown Tracker** from the character-select AddOns list, then reload the UI or log in.

## Use

- `/ict` opens or closes settings.
- The settings window contains one option: **Enable interrupt tracking**.
- `/ict tracking` (or `/ict toggle`) toggles tracking.
- `/ict show` and `/ict hide` enable or disable tracking.
- Hold **Shift** and drag an observed ability icon to move the whole icon grid. The position is saved per character.

The addon shows a flat grid of every cataloged interrupt cast observed in the local combat log. There is no primary recommendation icon or secondary-stop section. Each icon's cooldown is estimated from its observed cast time and the catalog's base cooldown. Estimates remain visible when ready. All spell icons stay in color, and estimates are not marked with a tilde.

This is local combat-log tracking only: the addon has no addon-message protocol, does not ask other players to report status, and does not inspect spellbooks. Interrupts that have not been observed by this client do not appear. Pet interrupts are attributed to their owner when the pet is identifiable from the local group roster. Missed combat-log events, talents, cooldown resets, range, target restrictions, and player availability can make estimates inaccurate.
