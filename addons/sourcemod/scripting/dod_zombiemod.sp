/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source
 *
 * By: Andersso
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 */

#include <sdktools>
#include <sdkhooks>
#include <dodhooks>

#undef REQUIRE_EXTENSIONS
#tryinclude <steamtools>

/**
 * Include order is intentional — do not reorder without good reason.
 *
 * consts.inc  - All #defines and enums used across files. Must be first.
 * globals.inc - All shared variables and forward handles. Must precede any
 *               file that references them.
 * util.inc    - Helper functions with no dependencies on other modules.
 * api.inc     - Native registration and forward creation. Must load early
 *               so natives are available in AskPluginLoad2 before any
 *               implementation file tries to reference them.
 *
 * Implementation files follow in dependency order below.
 */
#include "zombiemod/consts.inc"
#include "zombiemod/globals.inc"
#include "zombiemod/util.inc"
#include "zombiemod/api.inc"
#include "zombiemod/offsets.inc"
#include "zombiemod/convars.inc"
#include "zombiemod/config.inc"
#include "zombiemod/gamerules.inc"
#include "zombiemod/equipmenu.inc"
#include "zombiemod/human_skills_core.inc"
#include "zombiemod/human_skills_modular.inc"
#include "zombiemod/killrewards.inc"
#include "zombiemod/player.inc"
#include "zombiemod/commands.inc"
#include "zombiemod/zombie_classes_core.inc"
#include "zombiemod/zombie_classes_modular.inc"
#include "zombiemod/hud_messages.inc"
#include "zombiemod/pickups.inc"
#include "zombiemod/sounds.inc"

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = "Andersso, Root, Colster, claude.ai guided by DNA.styx", 
	description = "Zombie Mod for Day of Defeat: Source", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/DNA-styx/DoD_ZombieMod"
};


public void OnPluginStart()
{
	LoadTranslations("dod_zombiemod.phrases");
	
	API_CreateForwards();
	
	Offsets_OnPluginStart();
	ConVars_OnPluginStart();
	EquipMenu_OnPluginStart();
	HumanSkills_OnPluginStart();
	ModularSkills_OnPluginStart();
	Players_OnPluginStart();
	Commands_OnPluginStart();
	GameRules_OnPluginStart();
	ModularClasses_OnPluginStart();
	ZombieClasses_OnPluginStart();
	Pickups_OnPluginStart();
	
	AutoExecConfig(true, "zombiemod_config", "zombiemod");
	
	#if defined _steamtools_included
	g_bUseSteamTools = LibraryExists("SteamTools");
	#endif
}

public void OnMapEnd()
{
	Pickups_OnMapEnd();
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Steam_SetGameDescription");
	
	API_Init();
	
	return APLRes_Success;
}

public void OnConfigsExecuted()
{
	#if defined _steamtools_included
	if (g_bUseSteamTools)
	{
		Steam_SetGameDescription(PLUGIN_NAME);
	}
	#endif
	
	g_iRoundWins = g_iNumZombieSpawns = g_bModActive = g_bRoundEnded = false;
	
	g_hRoundTimer = null;
	
	g_iZombie = -1;
	
	LoadConfig();
	
	int entity = -1;
	
	if (!g_bWhiteListed[WhiteList_Environment])
	{
		SetLightStyle(0, "c");
		DispatchKeyValue(0, "skyname", "sky_borealis01");
		
		if ((entity = FindEntityByClassname(entity, "env_sun")) != -1)
		{
			AcceptEntityInput(entity, "TurnOff");
		}
	}
	
	PrecacheSound(SOUND_BLIP);
	
	g_iBeamSprite = PrecacheModel("materials/sprites/laser.vmt");
	g_iHaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
	
	while ((entity = FindEntityByClassname(entity, "info_player_axis")) != -1)
	{
		GetEntityOrigin(entity, g_vecZombieSpawnOrigin[g_iNumZombieSpawns++]);
		
		if (g_iNumZombieSpawns >= MAX_SPAWNPOINTS)
		{
			LogError("Spawn point limit reached!");
			break;
		}
	}
}

public void OnMapStart()
{
	// Recreate pickup timer and precache
	Pickups_OnMapStart();

	// Precache zombie class sounds/effects
	ZombieClasses_OnMapStart();

	// Recreate HUD timers
	HUD_OnMapStart();

	// Remove any skill registrations from unloaded plugins
	ModularSkills_OnMapStart();

	// Precache and register ambience sound
	Sounds_OnMapStart();
}
