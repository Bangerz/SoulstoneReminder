# Soulstone Reminder

World of Warcraft **retail** add-on that warns when your group has **warlocks** and **healers**, but **no healer** appears to have a **Soulstone resurrection** buff—so you can fix it before a pull.

Standalone port of the WeakAura **Raidwide Soulstone Checker** ([wago.io/Cmo8tr2hv](https://wago.io/Cmo8tr2hv)).

**Repository:** [github.com/Bangerz/SoulstoneReminder](https://github.com/Bangerz/SoulstoneReminder)

## Install

1. Copy this folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. The folder name **must** be `SoulstoneReminder` (same as `SoulstoneReminder.toc`).
3. Enable **Soulstone Reminder** in the AddOns list and `/reload`.

## What you see

- A **banner** near the top of the screen when the check applies and a soulstone on a healer is missing.
- **Drag** to reposition (when unlocked). Position is saved in **SavedVariables**.
- **Click** the banner to send announcements (if you have raid/party or whisper options enabled).

## Behavior notes

- **Combat & encounters:** The banner and automatic ready-check announce are **disabled** while you are in combat or a **boss encounter** is in progress. Ally aura data is unreliable there (secret spell IDs, etc.), which used to cause false positives.
- **Ready check window (default on):** With **`bannerOnlyAfterReadyCheck`**, the banner only appears for **30 seconds** after a **ready check** fires. Turn off with `/ssr rcbanner off` to show whenever the condition is met (still subject to combat/encounter rules).
- **Soulstone detection:** Uses known Soulstone resurrection spell IDs via `C_UnitAuras`. If Blizzard hides an ID on another player, that aura may not be detected.

## Slash commands (`/ssr`)

| Command | Purpose |
|--------|---------|
| `/ssr help` | List commands |
| `/ssr on` / `off` | Master enable for reminders |
| `/ssr raid on` / `off` | Send your message to raid/party on click or `/ssr send` |
| `/ssr whisper on` / `off` | Whisper warlocks with healer names |
| `/ssr send` | Announce now (cooldown applies) |
| `/ssr msg <text>` | Set the raid/party line |
| `/ssr cooldown <sec>` | Minimum seconds between sends (10–600, default 45) |
| `/ssr lock` / `unlock` | Lock or unlock banner dragging |
| `/ssr resetpos` | Reset banner position |
| `/ssr readycheck on` / `off` | Auto announce when a ready check starts (if stone missing) |
| `/ssr rcbanner on` / `off` | Only show banner for 30s after a ready check (default **on**) |

## Saved variables

Stored in **`SoulstoneReminderDB`** (global saved by the client). Includes options above, plus saved frame position (`framePoint`, `frameX`, `frameY`, etc.).

## Requirements

- **Retail** WoW (TOC targets Midnight-era interface builds listed in the `.toc` file).

## License

Project license is in **`LICENSE`** in the repository (CC0). Add-on code is contributed under those terms unless noted otherwise.

## Author

Bangerz–Dark Iron
