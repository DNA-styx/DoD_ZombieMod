# DoD:S Zombie Mod — Server Operator Guide

**Version:** 0.9.62 BETA  
**Last Updated:** 2026-05-30

---

## Table of Contents

1. [Overview](#overview)
2. [Plugin Inventory](#plugin-inventory)
3. [Installation](#installation)
4. [Configuration Files](#configuration-files)
   - [Main Config — zombiemod_config.cfg](#main-config)
   - [Human Skill — TNT](#human-skill-tnt)
   - [Zombie Class — TNT Zombie](#zombie-class-tnt-zombie)
   - [Flame Rockets](#flame-rockets)
5. [Map Whitelist](#map-whitelist)
6. [Sounds, Models, and Overlays](#sounds-models-and-overlays)
7. [HLStatsX Integration](#hlstatsx-integration)
   - [Actions](#actions-to-configure-in-hlstatsx)
   - [Kill Logging by Weapon](#kill-logging-by-weapon)
8. [Troubleshooting](#troubleshooting)

---

## Overview

DoD:S Zombie Mod converts Day of Defeat: Source into a team survival gamemode. One player spawns as a zombie; killing humans converts them. The last human team standing wins. The system is modular — human skills and zombie classes are loaded as separate plugins that register against the main plugin at runtime.

---

## Plugin Inventory

All plugins reside in `addons/sourcemod/plugins/`.

### Core

| Plugin | Version | Description |
|---|---|---|
| `dod_zombiemod.smx` | 0.9.62 BETA | Main plugin. Required by all others. |

### Human Skills

Human skills are selectable by players from the equipment menu each spawn.

| Plugin | Version | Description |
|---|---|---|
| `dod_zm_human_tnt.smx` | 1.3.0 | Remote TNT packs. Right-click pistol to place, hold to detonate. |
| `dod_zm_barricade.smx` | 1.0.7 | Barricade Builder. Right-click knife or pistol to move props. |
| `dod_zm_flamerockets.smx` | 1.0.3 | Flame Rockets. Rocket launchers ignite zombies on hit. Not a selectable skill — applies passively to all rocket launcher users. |

### Zombie Classes

Zombie classes are assigned at spawn based on chance settings.

| Plugin | Version | Description |
|---|---|---|
| `dod_zm_zombie_tnt.smx` | 1.1.3 | TNT Zombie. Explodes on death with blast damage and screen shake. Provides the visual TNT chest model. |

> **Note:** Normal, Gas, and Ghost zombie classes are built into the main plugin. Only TNT requires a separate plugin as an example of an external Zombie Class.

---

## Installation

1. Install [SourceMod](https://www.sourcemod.net/) and [Metamod:Source](https://www.metamodsource.net/).
2. Install the [DoD Hooks extension](https://github.com/DNA-styx/DoD_ZombieMod) (`dodhooks.ext`).
3. Copy the contents of the release archive to your `game/` directory.
4. Restart the server. Configuration files are generated automatically on first load under `cfg/sourcemod/zombiemod/`.
5. Edit the generated configs as required (see below).

---

## Configuration Files

All config files are generated to `cfg/sourcemod/zombiemod/` on first load. Values shown below are defaults.

---

### Main Config

**File:** `cfg/sourcemod/zombiemod/zombiemod_config.cfg`

#### General

| ConVar | Default | Description |
|---|---|---|
| `dod_zombiemod_enabled` | `1` | Enable the mod. Set to `0` to disable without unloading. |
| `dod_zombiemod_winlimit` | `3` | Rounds played before a map change is triggered. |
| `dod_zombiemod_minplayers` | `3` | Minimum connected players required to start a round. |
| `dod_zombiemod_roundtime` | `600` | Round duration in seconds. |
| `dod_zombiemod_beacon_interval` | `8` | Seconds between beacon pulses on the last human. |

#### Human

| ConVar | Default | Description |
|---|---|---|
| `dod_zombiemod_human_maxhealth` | `150` | Maximum health humans can reach through kill rewards. |
| `dod_zombiemod_human_pistol_maxammo` | `21` | Maximum pistol ammo (Colt / P38) on spawn. |
| `dod_zombiemod_spawn_noclip_time` | `15.0` | Seconds after spawn during which humans pass through teammates. Prevents spawn blocking. |
| `dod_zombiemod_pickup_timeout` | `30.0` | Seconds before an uncollected pickup auto-destroys. |

#### Zombie

| ConVar | Default | Description |
|---|---|---|
| `dod_zombiemod_zombie_health` | `8000` | Zombie health on spawn. |
| `dod_zombiemod_crit_reward` | `250` | Health granted to a zombie that lands a critical kill. |
| `dod_zombiemod_zombie_speed` | `0.65` | Zombie movement speed on spawn, as a proportion of normal player speed. `1.0` = normal speed, `0.65` = 65% of normal. |
| `dod_zombiemod_zombie_maxspeed` | `0.85` | Maximum zombie movement speed after kill rewards. Each kill reward increases speed by 10% until this ceiling is reached. `0.85` = 85% of normal player speed. |
| `dod_zombiemod_class_chance` | `50` | Percentage chance a zombie spawns as a special class. Set to `0` to disable special classes. |
| `dod_zombiemod_zombie_class_cooldown` | `120` | Seconds before a real player can re-select the same zombie class. Set to `0` to disable. |
| `dod_zombiemod_gas_cooldown` | `15.0` | Seconds between Gas Zombie ability uses. |
| `dod_zombiemod_ghost_alpha_max` | `50.0` | Ghost Zombie maximum visibility. `0` = invisible, `255` = fully visible. |
| `dod_zombiemod_teleport_chance` | `25` | Percentage chance a zombie teleports to a human spawn on respawn. Set to `0` to disable. |
| `dod_zombiemod_zombie_show_weapon` | `1` | Show the spade weapon on zombie spawn. Set to `0` to hide. |

#### Visuals

| ConVar | Default | Description |
|---|---|---|
| `dod_zombiemod_barrier_health_display` | `1` | Show prop health to the zombie damaging it. |

---

### Human Skill — TNT

**File:** `cfg/sourcemod/zombiemod/dod_zm_human_tnt.cfg`

| ConVar | Default | Description |
|---|---|---|
| `dod_zm_human_tnt_max` | `2` | Maximum TNT packs a player may have active at one time. Oldest pack is silently removed when limit is exceeded. |
| `dod_zm_human_tnt_cooldown` | `3` | Seconds between pack placements per player. |
| `dod_zm_human_tnt_radius` | `300.0` | Blast radius in units. |
| `dod_zm_human_tnt_damage` | `250.0` | Maximum blast damage at point of detonation. Damage falls off with distance. |
| `dod_zm_human_tnt_model` | `models/weapons/w_tnt.mdl` | Model used for the placed pack prop. |

**Usage:** Select TNT from the equipment menu. With a pistol active, right-click tap to place a pack. Right-click hold to detonate all placed packs simultaneously.

---

### Zombie Class — TNT Zombie

**File:** `cfg/sourcemod/zombiemod/zombiemod_zombie_tnt.cfg`

| ConVar | Default | Description |
|---|---|---|
| `zm_zombie_tnt_radius` | `300.0` | Blast radius of the death explosion in units. |
| `zm_zombie_tnt_damage` | `150` | Maximum blast damage at the explosion origin. Falls off linearly with distance. |

---

### Flame Rockets

**File:** `cfg/sourcemod/zombiemod/dod_zm_flamerockets.cfg`

This plugin applies passively to all players carrying a rocket launcher. No skill selection is required.

| ConVar | Default | Description |
|---|---|---|
| `zm_flamerocket_time` | `3.0` | Burn duration in seconds applied on any rocket hit. |
| `zm_flamerocket_multi` | `3.0` | Damage multiplier applied to rocket hits. `1.0` applies no change. |
| `zm_flamerocket_ammo` | `10` | Reserve rocket ammo granted on spawn to players carrying a launcher. |

---

## Map Whitelist

**File:** `addons/sourcemod/configs/zombiemod/zombiemod_whitelist.cfg`

By default the mod removes objectives, environmental entities, and team blockers on all maps. The whitelist allows per-map overrides for maps that require these elements.

```
"ZombieMod_WhiteList"
{
    "dod_your_map"
    {
        "Objectives"    "1"   // Preserve capture points and bomb targets
        "Environment"   "1"   // Preserve lighting and env_sun
        "TriggerHurts"  "1"   // Preserve trigger_hurt volumes
        "TeamBlockers"  "1"   // Preserve func_team_wall entities
        "Ambience"      "1"   // Suppress ZM ambient track, leave map audio alone
    }
}
```

All keys default to `0` when absent. The ZM ambient track plays on any map that does not explicitly set `"Ambience" "1"`.

---

## Sounds, Models, and Overlays

**File:** `addons/sourcemod/configs/zombiemod/zombiemod.cfg`

This KeyValues file configures all sounds, zombie player models, and win-screen overlays.

### Sounds

```
"Sounds"
{
    "Sound_JoinServer"       "SAS_ZombieMod/zombie_join.mp3"
    "Sound_Zombies_Win"      "SAS_ZombieMod/zombie_win.mp3"
    "Sound_Zombies_Start"    "SAS_ZombieMod/zombie_start.mp3"
    "Sound_Zombie_Spawn"     "SAS_ZombieMod/zombie_spawn.mp3"
    "Sound_Zombie_Death"     "SAS_ZombieMod/zombie_death.mp3"
    "Sound_Zombie_Critical"  "SAS_ZombieMod/zombie_critical.mp3"
    "Sound_Humans_Win"       "EM_ZombieMod/human_win.mp3"
    "Sound_LastManStanding"  "EM_ZombieMod/last_human.mp3"
    "Sound_End"              "SAS_ZombieMod/zombie_end.mp3"
    "Sound_FinishHim"        "SAS_ZombieMod/finishhim.mp3"
    "Sound_Ambience"         "DoD_ZombieMod/zr_ambience.mp3"
}
```

Paths are relative to the `sound/` directory. All listed files are automatically precached and added to the downloads table.

The ambience track (`Sound_Ambience`) should be exactly 60 seconds long. The plugin restarts it on a 60-second timer to create a seamless loop.

### Models

```
"Models"
{
    "Model_Zombie_Default"  "models/player/em_zombiebody.mdl"
    "Model_Zombie_Custom1"  "models/player/german_zombie.mdl"
    "Model_Zombie_Custom2"  "models/player/russianarmy/zombie/american_zombie.mdl"
    "Model_Zombie_Custom3"  "models/player/russianarmy/zombie/german_zombie.mdl"
    "Model_Zombie_Custom4"  ""
    "Model_Zombie_Custom5"  ""
    "Model_Zombie_Custom6"  ""
}
```

If multiple slots are populated, a random model is selected per zombie spawn.

### Overlays

```
"Overlays"
{
    "Overlay_Humans_Win"   "overlays/EM_ZombieMod/human_win"
    "Overlay_Zombies_Win"  "overlays/EM_ZombieMod/zombie_win"
}
```

Paths are relative to `materials/` and should be provided without file extension.

---

## HLStatsX Integration

The main plugin writes custom events to the game log in standard HLStatsX format. No additional plugin or extension is required on the server side.

### Actions to Configure in HLStatsX

Log into the HLStatsX web panel and navigate to **Games > Day of Defeat: Source > Actions**. Add the following entries.

---

#### `zm_last_human_standing`

| Field | Value |
|---|---|
| Action Code | `zm_last_human_standing` |
| Description | Awarded to the last surviving human on the team |
| Team | Allies |
| Action | Player Action |
| Player Points Reward | `1` |

**When fired:** Once per round, at the moment the player count on the human team reaches one. Fires for both real players and bots. Bot entries use `BOT` in place of the Steam ID; HLStatsX identifies bots by name.

---

#### `zm_human_survived`

| Field | Value |
|---|---|
| Action Code | `zm_human_survived` |
| Description | Awarded to each human alive when the time limit expires |
| Team | Allies |
| Action | Player Action |
| Player Points Reward | `1` |

**When fired:** At round end when the human team wins by time limit expiry. Fires once per surviving human.

---

#### `zm_killed_last_human`

| Field | Value |
|---|---|
| Action Code | `zm_killed_last_human` |
| Description | Awarded to the zombie that kills the last human and ends the round |
| Team | Axis |
| Action | PlyrPlyr Action |
| Player Points Reward | `1` |

**When fired:** Once per round, when the zombie kill that reduces the human team to zero is confirmed. Includes both the attacker and the victim in the log line.

---

### Kill Logging by Weapon

All kills are written to the game log as standard kill lines and are tracked by HLStatsX automatically. No additional configuration is required beyond setting display names in the HLStatsX weapons panel (**Games > Day of Defeat: Source > Weapons**).

#### Zombie Kills a Human

All zombie kills on human players are logged with the weapon string `zm_zombie_kill` regardless of which zombie class is active.

#### Human Triggers a Critical Shot

When a human lands a headshot with a crit-eligible weapon on a zombie, two log lines are written.

The first is written immediately when the crit shot lands, using a `zm_crit_` prefixed weapon string to identify which weapon triggered the critical state. The second is the standard kill line written by the engine when the zombie subsequently dies, using the real weapon name of whoever lands the final blow.

These two entries are distinct in HLStatsX — for example `zm_crit_colt` tracks who triggered the critical headshot; `colt` tracks who finished the kill.

#### Crit-Eligible Weapons and Log Strings

The following weapons can trigger a critical state on a headshot. Add each string that appears in your logs to the HLStatsX weapons panel with a suitable display name.

| Log String | Weapon |
|---|---|
| `zm_crit_amerknife` | American Knife |
| `zm_crit_colt` | Colt M1911 |
| `zm_crit_p38` | P38 |
| `zm_crit_spring` | Springfield (scoped) |
| `zm_crit_k98_scoped` | K98 Scoped |
| `zm_crit_bazooka` | Bazooka |
| `zm_crit_pschreck` | Panzerschreck |
| `zm_crit_thompson` | Thompson (punch shot) |
| `zm_crit_mp40` | MP40 (punch shot) |

---

## Troubleshooting

**Mod does not start / rounds do not begin.**  
Check that `dod_zombiemod_minplayers` is met and `dod_zombiemod_enabled` is set to `1`. Review `addons/sourcemod/logs/` for errors from `dod_zombiemod`.

**Skills do not appear in the equipment menu.**  
Each skill plugin must load successfully and the main plugin must be running. Run `sm plugins list` in console to verify all `.smx` files are loaded without errors.

**HLStatsX awards are not being credited.**  
Confirm the action names in the HLStatsX panel match exactly (case-sensitive). Verify the game log path in HLStatsX points to the correct server log directory. Check that HLStatsX is configured for the correct game (Day of Defeat: Source).

**Zombie class menu does not appear.**  
The class chance ConVar (`dod_zombiemod_class_chance`) must be greater than `0`. The menu appears one second after the player spawns on the zombie team and times out after 30 seconds.

**Teleport does not trigger.**  
Teleports are disabled for the first 60 seconds of each round regardless of ConVar setting. After that window, `dod_zombiemod_teleport_chance` controls the probability per respawn.

**Ambient track does not play on a specific map.**  
Check `zombiemod_whitelist.cfg`. If the map has `"Ambience" "1"`, the ZM track is suppressed on that map by design. Remove or set to `"0"` to restore it.

---

*DoD:S Zombie Mod — github.com/DNA-styx/DoD_ZombieMod*

*Original mod by Andersso, Root, Colster. Documentation and updated code by Claude.ai guided by DNA.styx.*
