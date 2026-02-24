/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Zombie Classes Module
 * 
 * Handles special zombie classes with unique abilities
 * =============================================================================
 */

// ============================================================================
// CONSTANTS
// ============================================================================

// Gas cloud settings (hardcoded)
#define GAS_RADIUS      150.0
#define GAS_DURATION    10.0
#define GAS_DAMAGE      5
#define GAS_TICK_RATE   1.0
#define GAS_COLOR_R     50
#define GAS_COLOR_G     205
#define GAS_COLOR_B     50

// Explosion settings
#define EXPLODE_RADIUS       300.0
#define EXPLODE_DAMAGE       150
#define EXPLODE_SOUND        "ambient/explosions/explode_3.wav"

// Teleporter settings
#define TELEPORT_DELAY       60.0   // Seconds after round start before teleports activate
#define TELEPORT_SOUND       "buttons/spark6.wav"

// ============================================================================
// GLOBALS
// ============================================================================

Handle g_hGasCloudTimers[MAXPLAYERS+1];

// Teleporter globals
bool g_bTeleportActive = false;
ArrayList g_AlliedSpawns = null;

// Ghost zombie globals
#define GHOST_ALPHA_INTERVAL 0.05   // Update frequency (seconds)
#define GHOST_ALPHA_MIN 0.0         // Minimum alpha (fully invisible)
#define GHOST_ALPHA_RATE 2.0        // Alpha change per update

float g_fGhostAlpha[MAXPLAYERS+1];
bool g_bGhostAlphaIncreasing[MAXPLAYERS+1];
Handle g_hGhostAlphaTimers[MAXPLAYERS+1];

// Class selection menu
Menu g_ZombieClassMenu = null;

// ============================================================================
// INITIALIZATION
// ============================================================================

void ZombieClasses_Init()
{
	// Initialize arrays
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_iZombieClass[i] = view_as<int>(ZombieClass_Normal);
		g_hGasCloudTimers[i] = INVALID_HANDLE;
		g_hGhostAlphaTimers[i] = INVALID_HANDLE;
		g_fGhostAlpha[i] = GHOST_ALPHA_MIN;
		g_bGhostAlphaIncreasing[i] = true;
	}
	
	// Initialize teleporter spawn cache
	g_AlliedSpawns = new ArrayList(3);
	
	// Create zombie class selection menu
	CreateZombieClassMenu();
}

void CreateZombieClassMenu()
{
	g_ZombieClassMenu = new Menu(MenuHandler_ZombieClass);
	g_ZombieClassMenu.SetTitle("Select Zombie Class:");
	g_ZombieClassMenu.AddItem("0", "Random Class");
	g_ZombieClassMenu.AddItem("1", "Gas Zombie (Toxic cloud on death)");
	g_ZombieClassMenu.AddItem("2", "TNT Zombie (Explodes on death)");
	g_ZombieClassMenu.AddItem("3", "Ghost Zombie (Nearly invisible)");
	g_ZombieClassMenu.ExitButton = false;  // Force selection (or timeout)
}

void ZombieClasses_OnMapStart()
{
	// Precache explosion sound
	PrecacheSound(EXPLODE_SOUND, true);
	
	// Precache teleport sound
	PrecacheSound(TELEPORT_SOUND, true);
	
	// Cache Allied spawn points for teleporter
	g_AlliedSpawns.Clear();
	CacheAlliedSpawns();
}

void ZombieClasses_OnRoundStart()
{
	// Disable teleport at round start
	g_bTeleportActive = false;
	
	// Note: TELEPORT_DELAY timer is now started when mod becomes active (Timer_RestartRound)
	// This prevents teleports before the actual zombie mod game starts
}

void ZombieClasses_OnModActive()
{
	// Start teleport delay timer when mod becomes active
	g_bTeleportActive = false;
	CreateTimer(TELEPORT_DELAY, Timer_EnableTeleport, 0, TIMER_FLAG_NO_MAPCHANGE);
}

void ZombieClasses_OnRoundEnd()
{
	// Disable teleport when round ends - timer auto-cleans via TIMER_FLAG_NO_MAPCHANGE
	g_bTeleportActive = false;
}

public Action Timer_EnableTeleport(Handle timer)
{
	g_bTeleportActive = true;
	
	return Plugin_Stop;
}

// ============================================================================
// CLIENT EVENTS
// ============================================================================

void ZombieClasses_OnClientDisconnect(int client)
{
	g_iZombieClass[client] = view_as<int>(ZombieClass_Normal);
	
	// Clean up any active gas timer
	if (g_hGasCloudTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_hGasCloudTimers[client]);
		g_hGasCloudTimers[client] = INVALID_HANDLE;
	}
	
	// Clean up any active ghost alpha timer
	if (g_hGhostAlphaTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_hGhostAlphaTimers[client]);
		g_hGhostAlphaTimers[client] = INVALID_HANDLE;
	}
}

// ============================================================================
// CLASS ASSIGNMENT
// ============================================================================

void ZombieClasses_OnSpawn(int client)
{
	// Only assign class for zombies
	if (GetClientTeam(client) != Team_Axis)
		return;
	
	// Check if classes are enabled
	int chance = g_ConVarInts[ConVar_Class_Chance];
	if (chance <= 0)
	{
		g_iZombieClass[client] = view_as<int>(ZombieClass_Normal);
		ApplyZombieClassEffects(client);
		return;
	}
	
	// Bots always get random class immediately
	if (IsFakeClient(client))
	{
		AssignRandomZombieClass(client, chance);
		ApplyZombieClassEffects(client);
		return;
	}
	
	// Real players: Start as Normal and show class selection menu
	g_iZombieClass[client] = view_as<int>(ZombieClass_Normal);
	
	// Teleport chance still applies immediately (before menu selection)
	CheckAndApplyTeleport(client);
	
	// Show class selection menu (30 second timeout)
	CreateTimer(1.0, Timer_ShowZombieClassMenu, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ShowZombieClassMenu(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	// Verify client is still valid and is a zombie
	if (client && IsClientInGame(client) && GetClientTeam(client) == Team_Axis)
	{
		g_ZombieClassMenu.Display(client, 30);  // 30 second timeout
	}
	
	return Plugin_Stop;
}

void AssignRandomZombieClass(int client, int chance)
{
	// Random chance for special class
	int roll = GetRandomInt(1, 100);
	
	if (roll <= chance)
	{
		// Choose between special classes: Gas, TNT, Ghost
		int specialClass = GetRandomInt(1, 3);  // 1=Gas, 2=TNT, 3=Ghost
		
		if (specialClass == 1)
		{
			g_iZombieClass[client] = view_as<int>(ZombieClass_Gas);
		}
		else if (specialClass == 2)
		{
			g_iZombieClass[client] = view_as<int>(ZombieClass_TNT);
		}
		else  // specialClass == 3
		{
			g_iZombieClass[client] = view_as<int>(ZombieClass_Ghost);
		}
	}
	else
	{
		g_iZombieClass[client] = view_as<int>(ZombieClass_Normal);
	}
}

void ApplyZombieClassEffects(int client)
{
	// Activate Ghost effect if Ghost class
	if (g_iZombieClass[client] == view_as<int>(ZombieClass_Ghost))
	{
		ActivateGhostEffect(client);
	}
}

void CheckAndApplyTeleport(int client)
{
	// Teleport chance (applies to ALL zombie classes after 60s delay)
	// Check if teleportation is available and roll for chance
	if (g_bTeleportActive && g_bModActive && !g_bRoundEnded)
	{
		int teleportChance = g_ConVarInts[ConVar_Teleport_Chance];
		if (teleportChance > 0)
		{
			int teleportRoll = GetRandomInt(1, 100);
			if (teleportRoll <= teleportChance)
			{
				// Teleport this zombie and announce it
				if (TeleportToRandomAlliedSpawn(client))
				{
					// Get player name
					char name[MAX_NAME_LENGTH];
					GetClientName(client, name, sizeof(name));
					
					// Announce to all players
					PrintToChatAll("%t%t", ZM_PREFIX, "Player Teleported", name);
				}
			}
		}
	}
}

void ZombieClasses_OnDeath(int client)
{
	// Only process zombie deaths
	if (GetClientTeam(client) != Team_Axis)
		return;
	
	ZombieClass class = view_as<ZombieClass>(g_iZombieClass[client]);
	
	switch (class)
	{
		case ZombieClass_Gas:
		{
			CreateGasCloudAtDeath(client);
		}
		case ZombieClass_TNT:
		{
			CreateExplosionAtDeath(client);
		}
		case ZombieClass_Ghost:
		{
			DeactivateGhostEffect(client);
		}
	}
}

// ============================================================================
// GAS ZOMBIE - DEATH EFFECT
// ============================================================================

void CreateGasCloudAtDeath(int client)
{
	// Get death location
	float location[3];
	GetClientAbsOrigin(client, location);
	
	// Create gas cloud entity
	int gascloud = CreateEntityByName("env_smokestack");
	
	if (gascloud == -1)
	{
		LogError("[Zombie Classes] Failed to create gas cloud entity");
		return;
	}
	
	// Format location and color strings
	char originData[64];
	Format(originData, sizeof(originData), "%f %f %f", 
		location[0], location[1], location[2] + 10.0);  // Slightly elevated
	
	char colorData[64];
	Format(colorData, sizeof(colorData), "%i %i %i", GAS_COLOR_R, GAS_COLOR_G, GAS_COLOR_B);
	
	// Configure gas cloud visual
	DispatchKeyValue(gascloud, "Origin", originData);
	DispatchKeyValue(gascloud, "BaseSpread", "50");      // Spread area
	DispatchKeyValue(gascloud, "SpreadSpeed", "10");     // Spread speed
	DispatchKeyValue(gascloud, "Speed", "50");           // Upward velocity
	DispatchKeyValue(gascloud, "StartSize", "100");      // Initial particle size
	DispatchKeyValue(gascloud, "EndSize", "1");          // Final particle size
	DispatchKeyValue(gascloud, "Rate", "15");            // Particles per second
	DispatchKeyValue(gascloud, "JetLength", "200");      // Height of cloud
	DispatchKeyValue(gascloud, "Twist", "2");            // Swirl effect
	DispatchKeyValue(gascloud, "RenderColor", colorData);
	DispatchKeyValue(gascloud, "RenderAmt", "100");      // Opacity
	DispatchKeyValue(gascloud, "SmokeMaterial", "particle/particle_smokegrenade1.vmt");
	
	// Spawn and activate
	DispatchSpawn(gascloud);
	AcceptEntityInput(gascloud, "TurnOn");
	
	// Create data pack for damage timer
	Handle pack = CreateDataPack();
	WritePackCell(pack, client);  // Original zombie who died
	WritePackFloat(pack, location[0]);
	WritePackFloat(pack, location[1]);
	WritePackFloat(pack, location[2]);
	WritePackCell(pack, gascloud);  // Gas cloud entity
	WritePackFloat(pack, GetGameTime());  // Start time
	
	// Start damage timer
	CreateTimer(GAS_TICK_RATE, Timer_GasDamage, pack, 
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
	
	// Schedule gas cloud removal
	Handle cleanupPack = CreateDataPack();
	WritePackCell(cleanupPack, gascloud);
	
	CreateTimer(GAS_DURATION, Timer_RemoveGas, cleanupPack, TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// GAS DAMAGE TIMER
// ============================================================================

public Action Timer_GasDamage(Handle timer, Handle pack)
{
	ResetPack(pack);
	int client = ReadPackCell(pack);
	float location[3];
	location[0] = ReadPackFloat(pack);
	location[1] = ReadPackFloat(pack);
	location[2] = ReadPackFloat(pack);
	int gascloud = ReadPackCell(pack);
	float startTime = ReadPackFloat(pack);
	
	// Check if gas cloud still exists
	if (!IsValidEntity(gascloud))
		return Plugin_Stop;
	
	// Check if duration exceeded
	float elapsed = GetGameTime() - startTime;
	
	if (elapsed >= GAS_DURATION)
		return Plugin_Stop;
	
	// Damage all humans in radius
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
			
		// Only damage humans (Allies)
		if (GetClientTeam(i) != Team_Allies)
			continue;
		
		// Check distance from gas center
		float playerPos[3];
		GetClientAbsOrigin(i, playerPos);
		
		float distance = GetVectorDistance(location, playerPos);
		
		if (distance <= GAS_RADIUS)
		{
			// Deal damage (DMG_NERVEGAS = poison damage type)
			SDKHooks_TakeDamage(i, gascloud, client, float(GAS_DAMAGE), DMG_NERVEGAS);
		}
	}
	
	return Plugin_Continue;
}

// ============================================================================
// GAS CLOUD CLEANUP
// ============================================================================

public Action Timer_RemoveGas(Handle timer, Handle pack)
{
	ResetPack(pack);
	int gascloud = ReadPackCell(pack);
	CloseHandle(pack);
	
	if (IsValidEntity(gascloud))
	{
		// Turn off gas emission
		AcceptEntityInput(gascloud, "TurnOff");
		
		// Kill entity after visual fade
		CreateTimer(3.0, Timer_KillGasEntity, gascloud, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Stop;
}

public Action Timer_KillGasEntity(Handle timer, int entity)
{
	if (IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
	return Plugin_Stop;
}

// ============================================================================
// TNT ZOMBIE
// ============================================================================

void CreateExplosionAtDeath(int client)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	// Play explosion sound (full 3 second sound will play)
	EmitAmbientSound(EXPLODE_SOUND, origin, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);
	
	// Create explosion visual effect (TE_SetupExplosion)
	TE_SetupExplosion(
		origin,                 // Position
		PrecacheModel("sprites/sprite_fire01.vmt"),  // Sprite
		10.0,                   // Scale
		15,                     // Framerate
		0,                      // Flags
		RoundFloat(EXPLODE_RADIUS),  // Radius (convert float to int)
		EXPLODE_DAMAGE          // Magnitude (already an int)
	);
	TE_SendToAll();
	
	// Create localized screen shake using env_shake
	int shake = CreateEntityByName("env_shake");
	if (shake != -1)
	{
		DispatchKeyValueFloat(shake, "amplitude", 20.0);      // Shake intensity
		DispatchKeyValueFloat(shake, "radius", EXPLODE_RADIUS); // Shake radius
		DispatchKeyValueFloat(shake, "duration", 1.5);         // Shake duration
		DispatchKeyValueFloat(shake, "frequency", 100.0);      // Shake frequency
		DispatchKeyValue(shake, "spawnflags", "12");           // 4 (Everyone) + 8 (Physics objects)
		
		// Position and activate
		TeleportEntity(shake, origin, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(shake);
		ActivateEntity(shake);
		
		// Trigger the shake
		AcceptEntityInput(shake, "StartShake");
		
		// Remove after duration
		CreateTimer(1.5, Timer_RemoveShake, EntIndexToEntRef(shake), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	// Damage nearby humans and zombies
	DamageNearbyEntities(origin, EXPLODE_RADIUS, EXPLODE_DAMAGE, client);
}

public Action Timer_RemoveShake(Handle timer, int ref)
{
	int shake = EntRefToEntIndex(ref);
	
	if (shake != INVALID_ENT_REFERENCE && IsValidEntity(shake))
	{
		AcceptEntityInput(shake, "StopShake");
		RemoveEntity(shake);
	}
	
	return Plugin_Stop;
}

void DamageNearbyEntities(float origin[3], float radius, int damage, int attacker)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		// Skip the TNT zombie that exploded
		if (i == attacker)
			continue;
		
		// Damage both humans (Allies) and other zombies (Axis)
		// Note: Mod forces all players onto teams, no spectators/unassigned in game
		
		float targetPos[3];
		GetClientAbsOrigin(i, targetPos);
		
		float distance = GetVectorDistance(origin, targetPos);
		
		if (distance <= radius)
		{
			// Calculate damage falloff (full damage at center, less at edges)
			float damageScale = 1.0 - (distance / radius);
			int finalDamage = RoundFloat(float(damage) * damageScale);
			
			if (finalDamage > 0)
			{
				// Apply damage
				SDKHooks_TakeDamage(i, attacker, attacker, float(finalDamage), DMG_BLAST, -1, NULL_VECTOR, origin);
			}
		}
	}
	
	// Damage props in radius
	int entity = -1;
	while ((entity = FindEntityByClassname(entity, "prop_*")) != -1)
	{
		float propPos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", propPos);
		
		float distance = GetVectorDistance(origin, propPos);
		
		if (distance <= radius)
		{
			// Break the prop
			AcceptEntityInput(entity, "Break");
		}
	}
}

// ============================================================================
// TELEPORTER ZOMBIE
// Code based on "Zombies Behind Us!" plugin by ChatGPT, Claude AI, guided by DNA.styx
// ============================================================================

void CacheAlliedSpawns()
{
	int entity = -1;
	float origin[3];
	
	// Find all Allied spawn points
	while ((entity = FindEntityByClassname(entity, "info_player_allies")) != -1)
	{
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
		g_AlliedSpawns.PushArray(origin);
	}
}

bool TeleportToRandomAlliedSpawn(int client)
{
	// Check if mod is active and round hasn't ended
	if (!g_bModActive || g_bRoundEnded)
		return false;
	
	// Check if teleport is active (delay has passed)
	if (!g_bTeleportActive)
		return false;
	
	int spawnCount = g_AlliedSpawns.Length;
	
	if (spawnCount == 0)
		return false;
	
	// Pick random spawn point
	int index = GetRandomInt(0, spawnCount - 1);
	float spawnPos[3];
	g_AlliedSpawns.GetArray(index, spawnPos);
	
	// Use exact Allied spawn position (known good spawn point)
	TeleportEntity(client, spawnPos, NULL_VECTOR, NULL_VECTOR);
	
	// Play spark sound to nearby players
	EmitAmbientSound(TELEPORT_SOUND, spawnPos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, 0.0);
	
	// Create green sparks shooting upward
	CreateTeleportSparkEffect(spawnPos);
	
	return true;  // Successfully teleported
}

void CreateTeleportSparkEffect(float position[3])
{
	int spark = CreateEntityByName("env_spark");
	
	if (spark == -1)
		return;
	
	// Set spark properties
	DispatchKeyValue(spark, "spawnflags", "128");     // Shoot upward
	DispatchKeyValue(spark, "MaxDelay", "0");         // No delay
	DispatchKeyValue(spark, "Magnitude", "2");        // Size
	DispatchKeyValue(spark, "TrailLength", "2");      // Trail length
	
	// Teleport to position
	TeleportEntity(spark, position, NULL_VECTOR, NULL_VECTOR);
	
	// Spawn and activate
	DispatchSpawn(spark);
	ActivateEntity(spark);
	
	// Trigger spark once
	AcceptEntityInput(spark, "StartSpark");
	
	// Remove after 1 second
	CreateTimer(1.0, Timer_RemoveTeleportSpark, EntIndexToEntRef(spark), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RemoveTeleportSpark(Handle timer, int ref)
{
	int spark = EntRefToEntIndex(ref);
	
	if (spark != INVALID_ENT_REFERENCE && IsValidEntity(spark))
	{
		AcceptEntityInput(spark, "StopSpark");
		RemoveEntity(spark);
	}
	
	return Plugin_Stop;
}

// ============================================================================
// GHOST ZOMBIE
// ============================================================================

void ActivateGhostEffect(int client)
{
	// Initialize alpha values
	g_fGhostAlpha[client] = GHOST_ALPHA_MIN;
	g_bGhostAlphaIncreasing[client] = true;
	
	// Only set render mode if spawn protection is NOT active
	// Calling SetEntityRenderMode resets alpha to 255, which would override spawn protection alpha
	// Spawn protection has already set RENDER_TRANSCOLOR, so we can skip this
	if (!SpawnProtection_IsProtected(client))
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	}
	
	// Make weapon invisible (same alpha as body)
	int weapon = GetPlayerWeaponSlot(client, 2);  // Slot 2 = melee (spade)
	if (weapon > 0 && IsValidEntity(weapon))
	{
		SetEntityRenderMode(weapon, RENDER_TRANSCOLOR);
		SetEntityRenderColor(weapon, 255, 255, 255, RoundToNearest(GHOST_ALPHA_MIN));
	}
	
	// Only create alpha timer if spawn protection is NOT active
	// If spawn protection is active, it's already handling alpha oscillation
	// and will transition to Ghost alpha when protection ends
	if (!SpawnProtection_IsProtected(client))
	{
		// Create ghost alpha oscillation timer
		int userid = GetClientUserId(client);
		g_hGhostAlphaTimers[client] = CreateTimer(GHOST_ALPHA_INTERVAL, Timer_GhostAlpha, userid, 
			TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DeactivateGhostEffect(int client)
{
	// Kill timer if active
	if (g_hGhostAlphaTimers[client] != INVALID_HANDLE)
	{
		KillTimer(g_hGhostAlphaTimers[client]);
		g_hGhostAlphaTimers[client] = INVALID_HANDLE;
	}
	
	// Reset alpha values
	g_fGhostAlpha[client] = GHOST_ALPHA_MIN;
	g_bGhostAlphaIncreasing[client] = true;
	
	// Reset player render mode to normal
	SetEntityRenderMode(client, RENDER_NORMAL);
	SetEntityRenderColor(client, 255, 255, 255, 255);
	
	// Reset weapon render mode
	int weapon = GetPlayerWeaponSlot(client, 2);
	if (weapon > 0 && IsValidEntity(weapon))
	{
		SetEntityRenderMode(weapon, RENDER_NORMAL);
		SetEntityRenderColor(weapon, 255, 255, 255, 255);
	}
}

public Action Timer_GhostAlpha(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	// Stop timer if client invalid or no longer zombie or no longer ghost class
	if (!client || !IsClientInGame(client) || 
	    GetClientTeam(client) != Team_Axis || 
	    g_iZombieClass[client] != view_as<int>(ZombieClass_Ghost))
	{
		if (client)
			g_hGhostAlphaTimers[client] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	// Oscillate alpha between min and max
	if (g_bGhostAlphaIncreasing[client])
	{
		g_fGhostAlpha[client] += GHOST_ALPHA_RATE;
		if (g_fGhostAlpha[client] >= g_ConVarFloats[ConVar_Ghost_Alpha_Max])
			g_bGhostAlphaIncreasing[client] = false;
	}
	else
	{
		g_fGhostAlpha[client] -= GHOST_ALPHA_RATE;
		if (g_fGhostAlpha[client] <= GHOST_ALPHA_MIN)
			g_bGhostAlphaIncreasing[client] = true;
	}
	
	int alpha = RoundToNearest(g_fGhostAlpha[client]);
	
	// Apply alpha to player
	SetEntityRenderColor(client, 255, 255, 255, alpha);
	
	// Apply same alpha to weapon
	int weapon = GetPlayerWeaponSlot(client, 2);
	if (weapon > 0 && IsValidEntity(weapon))
	{
		SetEntityRenderColor(weapon, 255, 255, 255, alpha);
	}
	
	return Plugin_Continue;
}

// ============================================================================
// CLASS SELECTION MENU
// ============================================================================

public int MenuHandler_ZombieClass(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		// Verify client is still a zombie
		if (!IsClientInGame(client) || GetClientTeam(client) != Team_Axis)
			return 0;
		
		// Get class choice from menu
		char info[8];
		menu.GetItem(selection, info, sizeof(info));
		int choice = StringToInt(info);
		
		// Get class chance for random calculation
		int chance = g_ConVarInts[ConVar_Class_Chance];
		
		// Apply class based on selection
		switch (choice)
		{
			case 0:  // Random
			{
				AssignRandomZombieClass(client, chance);
			}
			case 1:  // Gas
			{
				g_iZombieClass[client] = view_as<int>(ZombieClass_Gas);
			}
			case 2:  // TNT
			{
				g_iZombieClass[client] = view_as<int>(ZombieClass_TNT);
			}
			case 3:  // Ghost
			{
				g_iZombieClass[client] = view_as<int>(ZombieClass_Ghost);
			}
		}
		
		// Apply class effects
		ApplyZombieClassEffects(client);
		
		// Update HUD to show new class
		HUD_ShowZombieSpawnInfo(GetClientUserId(client));
	}
	else if (action == MenuAction_Cancel && selection == MenuCancel_Timeout)
	{
		// Timeout - assign random class
		if (IsClientInGame(client) && GetClientTeam(client) == Team_Axis)
		{
			int chance = g_ConVarInts[ConVar_Class_Chance];
			AssignRandomZombieClass(client, chance);
			ApplyZombieClassEffects(client);
			
			// Update HUD to show class
			HUD_ShowZombieSpawnInfo(GetClientUserId(client));
		}
	}
	
	return 0;
}

// ============================================================================
// DISPLAY HELPERS
// ============================================================================

ZombieClass ZombieClasses_GetClass(int client)
{
	return view_as<ZombieClass>(g_iZombieClass[client]);
}
