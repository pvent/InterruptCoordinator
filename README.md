# Interrupt Coordinator

Interrupt Coordinator is a World of Warcraft addon for **The Burning Crusade Classic client 2.5.3** (`Interface: 20503`). The addon release is listed separately in `InterruptCoordinator.toc`.

## Install

Copy the entire `InterruptCoordinator` folder into:

`World of Warcraft/_classic_/Interface/AddOns/`

Enable **Interrupt Coordinator** from the character-select AddOns list, then reload the UI or log in. Each party or raid member must install and enable the addon to share their interrupt reports.

## Use

- `/ic` toggles the layout settings window. `/ic config` is an alias.
- `/ic bar` (or `/ic toggle`) toggles the interrupt bar.
- `/ic edit` toggles layout edit mode.
- `/ic show` and `/ic hide` explicitly show or hide it; visibility is saved, and first launch defaults to visible.
- `/ic report` sends your current cooldown report and requests reports from the group.
- `/ic versions` checks the addon version of party/raid members who respond.
- `/ic help` lists the slash commands.
- Hold **Shift** and drag an ability icon to move the whole layout. Dragging stops on mouse release; its position is saved per character.

The large icon shows the current primary interrupt recommendation. Below it, the bar separates other interrupts from **Secondary stops**, such as Intercept, Intimidating Shout, and class stuns/CC. Secondary stops show their cooldowns but are never counted in primary or backup rotation priority. The player's class-colored name appears below each icon. Abilities appear only after the player's addon reports them as known or the combat log observes a cast; the class alone is not used to assume that a player has learned a spell. Group changes trigger roster refreshes and status requests. Ready abilities are brighter; cooldowns show remaining seconds. Hover an icon for member, ability, and status details.

Cooldown countdowns work without OmniCC. The addon uses its own numeric countdown and standard cooldown sweep by default; if OmniCC is installed, its text styling is used on the same cooldown frame instead. OmniCC is not a dependency. Estimated cooldowns have a small `~` marker.

The config panel also has a **Check group versions** button. It shows a compact count summary; the per-member versions and no-reply names are printed in chat after a five-second response window. A member who does not reply may have the addon disabled, missing, or an incompatible version; clients without this addon cannot be queried.

The solid-dark base configuration panel adjusts the Primary icon and group-icon sizes, padding, and section spacing. Other interrupts and Secondary stops have separate controls for icons per row, maximum rows, and vertical row spacing. Use **Blacklist...** to toggle a side panel of Secondary stops with spell icons and individual checkboxes; **Show all** and **Hide all** quickly reset or clear the list, and choices are saved per character. **Layout editor** toggles its separate, movable side panel. The blacklist and layout editor share the side-panel space, so opening one closes the other. The layout editor contains whole-bar X/Y controls and lets you detach Other interrupts, toggle each header, and set each panel's backdrop color and opacity. By default the primary recommendation and Other interrupts share one backdrop; dragging either section or one of its icons moves them together. Reattaching Other interrupts aligns it with the Primary section without moving Primary. Secondary stops has its own backdrop and can be dragged independently. Each component has individual position controls and a **Reset** button. Any component offset disables the whole-bar position sliders; **Reset all positioning** restores the default stacked positions and re-enables those sliders. Secondary stops can be shown or hidden independently. Each section's maximum rows controls how many icons it shows before an overflow count appears. These settings persist between sessions.

Hunter Silencing Shot is tracked as an interrupt, and Scatter Shot and Freezing Trap as secondary stops. The Secondary stops list also tracks cooldown-based control such as Paladin Repentance, Rogue Sap and Blind, Warlock Banish, and Tauren War Stomp. These are conditional controls, not guaranteed interrupts: trap, crowd-control immunity, target type, and combat state may prevent their use. Warrior Shield Bash and Pummel share a cooldown; when either is on cooldown, the tracker applies each ability's corresponding remaining cooldown to the other reported ability so it is not presented as available. Warrior Intercept is tracked under **Secondary stops** (including all supported ranks). Disarm is also tracked as a secondary stop; it disarms weapon users but is not a general spell-cast interrupt. Intercept and Disarm appear only if reported by a compatible addon or observed in combat. Intercept is a stun that can stop casts susceptible to stuns, but unlike Pummel or Shield Bash it is not a spell-interrupt/silence effect and will not stop stun-immune casts. Warrior Intimidating Shout is also tracked as a fear-based secondary stop with a 3-minute cooldown. The addon cannot inspect another player's spellbook directly; each group's client reports its own known abilities in response to status requests. Players without a compatible addon are not assumed to have class spells; abilities observed in combat can still be tracked.

## Reporting and limitations

Each client checks its own tracked ability cooldown and shares it with the group. Reports are refreshed periodically and when cooldown or roster events occur. Combat-log interrupt casts also create estimated cooldown icons for group members, including pet interrupts attributed to their owner when the pet is identifiable. An estimate is marked with `~` and is not confirmed readiness. The bar omits members for whom it has neither a report nor an observed interrupt. The primary and backup ordering is calculated locally from the reports and estimates currently available.

The addon can report cooldown state, but it cannot confirm range, line of sight, or whether a player can react. It does not cast or assign protected actions. Enemy-cast detection and a single raid-leader assignment authority are not implemented yet.