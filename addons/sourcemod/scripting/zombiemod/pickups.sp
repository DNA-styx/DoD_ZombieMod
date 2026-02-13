/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Pickups Module
 * 
 * Spawns random pickups on the map that give humans temporary boosts
 * =============================================================================
 */

// ============================================================================
// CONSTANTS
// ============================================================================

// Pickup settings
#define PICKUP_MODEL           "models/props_misc/ration_box02.mdl"
#define PICKUP_SPRITE          "sprites/glow01.vmt"
#define PICKUP_SPAWN_INTERVAL  45.0
#define MAX_ACTIVE_PICKUPS     5

// Pickup spawn attempt settings
#define SPAWN_MIN_DISTANCE      200.0   // Min distance from players
#define SPAWN_MAX_DISTANCE      800.0   // Max distance from players
#define SPAWN_MAX_ATTEMPTS      10      // Max attempts to find valid spawn

// Boost durations
#define BOOST_DURATION          10.0

// ============================================================================
// ENUMS
// ============================================================================

enum PickupType
{
	Pickup_Health = 0,
	Pickup_Ammo,
	Pickup_Speed,
	Pickup_Damage,
	Pickup_MaxTypes
}

// ============================================================================
// GLOBALS
// ============================================================================

int g_iPickupCount = 0;
Handle g_hSpawnTimer = INVALID_HANDLE;

// Active boosts tracking
bool g_bHasSpeedBoost[MAXPLAYERS+1];
bool g_bHasDamageBoost[MAXPLAYERS+1];
float g_flOriginalSpeed[MAXPLAYERS+1];

// ============================================================================
// INITIALIZATION
// ============================================================================

void Pickups_Init()
{
	PrintToServer("[PICKUPS DEBUG] Pickups_Init() called");
	
	// Initialize player arrays
	for (int i = 0; i <= MAXPLAYERS; i++)
	{
		g_bHasSpeedBoost[i] = false;
		g_bHasDamageBoost[i] = false;
		g_flOriginalSpeed[i] = 0.0;
	}
	
	PrintToServer("[PICKUPS DEBUG] Player arrays initialized");
}

void Pickups_OnMapStart()
{
	PrintToServer("[PICKUPS DEBUG] Pickups_OnMapStart() called");
	
	// Precache model
	PrecacheModel(PICKUP_MODEL, true);
	PrintToServer("[PICKUPS DEBUG] Model precached: %s", PICKUP_MODEL);
	
	// Precache sprite
	PrecacheModel(PICKUP_SPRITE, true);
	PrintToServer("[PICKUPS DEBUG] Sprite precached: %s", PICKUP_SPRITE);
	
	// Precache sounds
	PrecacheSound("items/smallmedkit1.wav", true);
	PrintToServer("[PICKUPS DEBUG] Sound precached");
	
	// Kill existing timer if it exists
	if (g_hSpawnTimer != INVALID_HANDLE)
	{
		KillTimer(g_hSpawnTimer);
		g_hSpawnTimer = INVALID_HANDLE;
		PrintToServer("[PICKUPS DEBUG] Existing timer killed");
	}
	
	// Start spawn timer
	g_hSpawnTimer = CreateTimer(PICKUP_SPAWN_INTERVAL, Timer_SpawnPickup, _, TIMER_REPEAT);
	PrintToServer("[PICKUPS DEBUG] Spawn timer created with %.1f second interval", PICKUP_SPAWN_INTERVAL);
	PrintToServer("[PICKUPS DEBUG] Timer handle: %x", g_hSpawnTimer);
}

void Pickups_OnMapEnd()
{
	PrintToServer("[PICKUPS DEBUG] Pickups_OnMapEnd() called");
	
	if (g_hSpawnTimer != INVALID_HANDLE)
	{
		KillTimer(g_hSpawnTimer);
		g_hSpawnTimer = INVALID_HANDLE;
		PrintToServer("[PICKUPS DEBUG] Spawn timer killed");
	}
	
	g_iPickupCount = 0;
	PrintToServer("[PICKUPS DEBUG] Pickup count reset to 0");
}

void Pickups_OnClientDisconnect(int client)
{
	g_bHasSpeedBoost[client] = false;
	g_bHasDamageBoost[client] = false;
	g_flOriginalSpeed[client] = 0.0;
}

// ============================================================================
// PICKUP SPAWNING
// ============================================================================

public Action Timer_SpawnPickup(Handle timer)
{
	PrintToServer("[PICKUPS DEBUG] Timer_SpawnPickup fired - g_bModActive=%d, g_bRoundEnded=%d", g_bModActive, g_bRoundEnded);
	
	// Only spawn if mod is active and game is running
	if (!g_bModActive)
	{
		PrintToServer("[PICKUPS DEBUG] Not spawning - mod not active");
		return Plugin_Continue;
	}
	
	if (g_bRoundEnded)
	{
		PrintToServer("[PICKUPS DEBUG] Not spawning - round ended");
		return Plugin_Continue;
	}
	
	// Check if we've hit the max
	if (g_iPickupCount >= MAX_ACTIVE_PICKUPS)
	{
		PrintToServer("[PICKUPS DEBUG] Not spawning - max active reached (%d/%d)", g_iPickupCount, MAX_ACTIVE_PICKUPS);
		return Plugin_Continue;
	}
	
	PrintToServer("[PICKUPS DEBUG] Attempting to find spawn location...");
	
	// Try to find a valid spawn location
	float spawnPos[3];
	if (FindPickupSpawnLocation(spawnPos))
	{
		PrintToServer("[PICKUPS DEBUG] Valid location found, creating pickup...");
		CreatePickup(spawnPos);
		PrintToServer("[PICKUPS DEBUG] Pickup created at %.1f, %.1f, %.1f - Total active: %d", 
			spawnPos[0], spawnPos[1], spawnPos[2], g_iPickupCount);
	}
	else
	{
		PrintToServer("[PICKUPS DEBUG] Failed to find valid spawn location");
	}
	
	return Plugin_Continue;
}

bool FindPickupSpawnLocation(float position[3])
{
	// Get all alive human players
	int[] alivePlayers = new int[MaxClients];
	int aliveCount = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == Team_Allies)
		{
			alivePlayers[aliveCount++] = i;
		}
	}
	
	PrintToServer("[PICKUPS DEBUG] Found %d alive human(s)", aliveCount);
	
	// Need at least one human to spawn near
	if (aliveCount == 0)
	{
		PrintToServer("[PICKUPS DEBUG] No alive humans - cannot spawn");
		return false;
	}
	
	// Try multiple times to find a valid location
	for (int attempt = 0; attempt < SPAWN_MAX_ATTEMPTS; attempt++)
	{
		// Pick random player
		int randomPlayer = alivePlayers[GetRandomInt(0, aliveCount - 1)];
		
		// Get their position
		float playerPos[3];
		GetClientAbsOrigin(randomPlayer, playerPos);
		
		// Random offset
		float distance = GetRandomFloat(SPAWN_MIN_DISTANCE, SPAWN_MAX_DISTANCE);
		float angle = GetRandomFloat(0.0, 360.0);
		
		position[0] = playerPos[0] + (distance * Cosine(DegToRad(angle)));
		position[1] = playerPos[1] + (distance * Sine(DegToRad(angle)));
		position[2] = playerPos[2] + 50.0;  // Start above ground
		
		PrintToServer("[PICKUPS DEBUG] Attempt %d: Testing position %.1f, %.1f, %.1f", 
			attempt + 1, position[0], position[1], position[2]);
		
		// Trace down to ground
		if (TraceToGround(position))
		{
			PrintToServer("[PICKUPS DEBUG] Ground trace successful");
			// Verify location is accessible (not in wall)
			if (IsLocationAccessible(position))
			{
				PrintToServer("[PICKUPS DEBUG] Location accessible - SUCCESS on attempt %d", attempt + 1);
				return true;
			}
			else
			{
				PrintToServer("[PICKUPS DEBUG] Location not accessible (in wall)");
			}
		}
		else
		{
			PrintToServer("[PICKUPS DEBUG] Ground trace failed");
		}
	}
	
	PrintToServer("[PICKUPS DEBUG] All %d spawn attempts failed", SPAWN_MAX_ATTEMPTS);
	return false;
}

bool TraceToGround(float position[3])
{
	float endPos[3];
	endPos[0] = position[0];
	endPos[1] = position[1];
	endPos[2] = position[2] - 500.0;  // Trace down 500 units
	
	Handle trace = TR_TraceRayFilterEx(position, endPos, MASK_SOLID, RayType_EndPoint, TraceFilter_World);
	
	if (TR_DidHit(trace))
	{
		TR_GetEndPosition(position, trace);
		position[2] += 5.0;  // Slightly above ground
		CloseHandle(trace);
		return true;
	}
	
	CloseHandle(trace);
	return false;
}

bool IsLocationAccessible(float position[3])
{
	// Check if there's enough space for the powerup (simple hull trace)
	float mins[3] = {-16.0, -16.0, 0.0};
	float maxs[3] = {16.0, 16.0, 32.0};
	
	Handle trace = TR_TraceHullFilterEx(position, position, mins, maxs, MASK_SOLID, TraceFilter_World);
	bool accessible = !TR_DidHit(trace);
	CloseHandle(trace);
	
	return accessible;
}

public bool TraceFilter_World(int entity, int contentsMask)
{
	// Only hit world geometry, not players or props
	return entity == 0;
}

// ============================================================================
// PICKUP CREATION
// ============================================================================

void GetPickupSpriteColor(PickupType type, int color[3])
{
	switch (type)
	{
		case Pickup_Health:  { color[0] = 0;   color[1] = 255; color[2] = 0;   }  // Green
		case Pickup_Ammo:    { color[0] = 255; color[1] = 255; color[2] = 0;   }  // Yellow
		case Pickup_Speed:   { color[0] = 0;   color[1] = 128; color[2] = 255; }  // Blue
		case Pickup_Damage:  { color[0] = 255; color[1] = 0;   color[2] = 0;   }  // Red
	}
}

void CreatePickup(float position[3])
{
	PrintToServer("[PICKUPS DEBUG] CreatePickup() called");
	
	// Create visual prop (prop_dynamic)
	int pickup = CreateEntityByName("prop_dynamic");
	
	if (pickup == -1)
	{
		PrintToServer("[PICKUPS DEBUG] ERROR: Failed to create entity!");
		return;
	}
	
	PrintToServer("[PICKUPS DEBUG] Entity created (prop_dynamic), index: %d", pickup);
	
	// Set model
	SetEntityModel(pickup, PICKUP_MODEL);
	PrintToServer("[PICKUPS DEBUG] Model set");
	
	// Choose random pickup type
	PickupType type = view_as<PickupType>(GetRandomInt(0, view_as<int>(Pickup_MaxTypes) - 1));
	PrintToServer("[PICKUPS DEBUG] Type chosen: %d", type);
	
	// Store type in entity
	SetEntProp(pickup, Prop_Data, "m_iHammerID", view_as<int>(type));
	
	// Set color based on type
	SetPickupColor(pickup, type);
	PrintToServer("[PICKUPS DEBUG] Color set");
	
	// Teleport to position BEFORE spawning
	TeleportEntity(pickup, position, NULL_VECTOR, NULL_VECTOR);
	
	// Spawn it
	DispatchSpawn(pickup);
	PrintToServer("[PICKUPS DEBUG] DispatchSpawn called");
	
	// Activate the entity
	ActivateEntity(pickup);
	PrintToServer("[PICKUPS DEBUG] Entity activated");
	
	// Create glowing sprite for visibility
	int sprite = CreateEntityByName("env_sprite");
	if (sprite != -1)
	{
		// Set sprite model
		DispatchKeyValue(sprite, "model", PICKUP_SPRITE);
		DispatchKeyValue(sprite, "classname", "env_sprite");
		DispatchKeyValue(sprite, "spawnflags", "1");  // Start on
		DispatchKeyValue(sprite, "rendermode", "9");  // Glow
		DispatchKeyValue(sprite, "renderamt", "255"); // Full brightness
		
		// Set sprite scale (make it visible but not huge)
		char scale[16];
		Format(scale, sizeof(scale), "0.5");
		DispatchKeyValue(sprite, "scale", scale);
		
		// Get color for this pickup type
		int color[3];
		GetPickupSpriteColor(type, color);
		
		char rendercolor[32];
		Format(rendercolor, sizeof(rendercolor), "%d %d %d", color[0], color[1], color[2]);
		DispatchKeyValue(sprite, "rendercolor", rendercolor);
		
		// Position sprite slightly above pickup
		float spritePos[3];
		spritePos[0] = position[0];
		spritePos[1] = position[1];
		spritePos[2] = position[2] + 20.0;  // 20 units above
		
		TeleportEntity(sprite, spritePos, NULL_VECTOR, NULL_VECTOR);
		
		// Spawn sprite
		DispatchSpawn(sprite);
		ActivateEntity(sprite);
		
		// Parent sprite to pickup so it moves with it
		SetVariantString("!activator");
		AcceptEntityInput(sprite, "SetParent", pickup, sprite);
		
		// Store sprite reference in pickup
		SetEntPropEnt(pickup, Prop_Data, "m_hEffectEntity", sprite);
		
		PrintToServer("[PICKUPS DEBUG] Sprite created at %.1f, %.1f, %.1f", spritePos[0], spritePos[1], spritePos[2]);
	}
	else
	{
		PrintToServer("[PICKUPS DEBUG] WARNING: Failed to create sprite!");
	}
	
	// Create a trigger for touch detection
	int trigger = CreateEntityByName("trigger_multiple");
	if (trigger != -1)
	{
		DispatchKeyValue(trigger, "spawnflags", "1");  // Clients only
		DispatchKeyValue(trigger, "wait", "0");         // No delay between touches
		
		// Set trigger size (64x64x64 box)
		float mins[3] = {-32.0, -32.0, -32.0};
		float maxs[3] = {32.0, 32.0, 32.0};
		
		// Teleport trigger to same position
		TeleportEntity(trigger, position, NULL_VECTOR, NULL_VECTOR);
		
		// Spawn and activate trigger
		DispatchSpawn(trigger);
		ActivateEntity(trigger);
		
		// Set trigger bounds
		SetEntPropVector(trigger, Prop_Send, "m_vecMins", mins);
		SetEntPropVector(trigger, Prop_Send, "m_vecMaxs", maxs);
		SetEntProp(trigger, Prop_Send, "m_nSolidType", 2);  // SOLID_BBOX
		
		// Link the trigger to the pickup (store trigger ref in pickup)
		SetEntPropEnt(pickup, Prop_Data, "m_hOwnerEntity", trigger);
		
		// Store pickup type in trigger too
		SetEntProp(trigger, Prop_Data, "m_iHammerID", view_as<int>(type));
		
		// Hook the trigger
		SDKHook(trigger, SDKHook_StartTouch, OnPickupTouched);
		
		PrintToServer("[PICKUPS DEBUG] Trigger created and hooked at %.1f, %.1f, %.1f", position[0], position[1], position[2]);
	}
	else
	{
		PrintToServer("[PICKUPS DEBUG] ERROR: Failed to create trigger!");
	}
	
	// Auto-destroy after lifetime from ConVar
	float lifetime = g_ConVarFloats[ConVar_Pickup_Timeout];
	CreateTimer(lifetime, Timer_RemovePickup, EntIndexToEntRef(pickup), TIMER_FLAG_NO_MAPCHANGE);
	PrintToServer("[PICKUPS DEBUG] Timer created (%.1f sec lifetime)", lifetime);
	
	// Increment count
	g_iPickupCount++;
	PrintToServer("[PICKUPS DEBUG] Pickup count incremented to %d", g_iPickupCount);
}

void SetPickupColor(int pickup, PickupType type)
{
	switch (type)
	{
		case Pickup_Health:  SetEntityRenderColor(pickup, 0, 255, 0, 255);     // Green
		case Pickup_Ammo:    SetEntityRenderColor(pickup, 255, 255, 0, 255);   // Yellow
		case Pickup_Speed:   SetEntityRenderColor(pickup, 0, 128, 255, 255);   // Blue
		case Pickup_Damage:  SetEntityRenderColor(pickup, 255, 0, 0, 255);     // Red
	}
}

public Action Timer_RemovePickup(Handle timer, int ref)
{
	int pickup = EntRefToEntIndex(ref);
	
	if (pickup != INVALID_ENT_REFERENCE && IsValidEntity(pickup))
	{
		// Get and remove the sprite
		int sprite = GetEntPropEnt(pickup, Prop_Data, "m_hEffectEntity");
		if (sprite != -1 && IsValidEntity(sprite))
		{
			RemoveEntity(sprite);
			PrintToServer("[PICKUPS DEBUG] Sprite removed (timeout)");
		}
		
		// Get and remove the trigger too
		int trigger = GetEntPropEnt(pickup, Prop_Data, "m_hOwnerEntity");
		if (trigger != -1 && IsValidEntity(trigger))
		{
			SDKUnhook(trigger, SDKHook_StartTouch, OnPickupTouched);
			RemoveEntity(trigger);
			PrintToServer("[PICKUPS DEBUG] Trigger removed (timeout)");
		}
		
		RemoveEntity(pickup);
		PrintToServer("[PICKUPS DEBUG] Pickup removed (timeout)");
		g_iPickupCount--;
		
		if (g_iPickupCount < 0)
			g_iPickupCount = 0;
	}
	
	return Plugin_Stop;
}

// ============================================================================
// PICKUP TOUCH
// ============================================================================

public Action OnPickupTouched(int trigger, int client)
{
	PrintToServer("[PICKUPS DEBUG] OnPickupTouched called - trigger: %d, client: %d", trigger, client);
	
	// Validate client
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		PrintToServer("[PICKUPS DEBUG] Invalid client or not alive");
		return Plugin_Continue;
	}
	
	int team = GetClientTeam(client);
	PrintToServer("[PICKUPS DEBUG] Client %d touched trigger, team: %d", client, team);
	
	// Get the pickup entity from the trigger
	int pickup = -1;
	for (int i = MaxClients + 1; i < GetMaxEntities(); i++)
	{
		if (IsValidEntity(i))
		{
			int owner = GetEntPropEnt(i, Prop_Data, "m_hOwnerEntity");
			if (owner == trigger)
			{
				pickup = i;
				break;
			}
		}
	}
	
	if (pickup == -1)
	{
		PrintToServer("[PICKUPS DEBUG] ERROR: Could not find pickup entity for trigger!");
		return Plugin_Continue;
	}
	
	PrintToServer("[PICKUPS DEBUG] Found pickup entity: %d", pickup);
	
	// Humans get the pickup
	if (team == Team_Allies)
	{
		PickupType type = view_as<PickupType>(GetEntProp(trigger, Prop_Data, "m_iHammerID"));
		PrintToServer("[PICKUPS DEBUG] Human touched pickup, type: %d", type);
		ApplyPickup(client, type);
		
		// Remove sprite
		int sprite = GetEntPropEnt(pickup, Prop_Data, "m_hEffectEntity");
		if (sprite != -1 && IsValidEntity(sprite))
		{
			RemoveEntity(sprite);
		}
		
		// Remove both trigger and pickup
		SDKUnhook(trigger, SDKHook_StartTouch, OnPickupTouched);
		RemoveEntity(trigger);
		RemoveEntity(pickup);
		g_iPickupCount--;
		PrintToServer("[PICKUPS DEBUG] Pickup, sprite, and trigger removed (collected by human)");
	}
	// Zombies destroy it
	else if (team == Team_Axis)
	{
		PrintToServer("[PICKUPS DEBUG] Zombie touched pickup, destroying");
		
		// Remove sprite
		int sprite = GetEntPropEnt(pickup, Prop_Data, "m_hEffectEntity");
		if (sprite != -1 && IsValidEntity(sprite))
		{
			RemoveEntity(sprite);
		}
		
		SDKUnhook(trigger, SDKHook_StartTouch, OnPickupTouched);
		RemoveEntity(trigger);
		RemoveEntity(pickup);
		g_iPickupCount--;
		PrintToServer("[PICKUPS DEBUG] Pickup, sprite, and trigger removed (destroyed by zombie)");
	}
	
	return Plugin_Handled;
}

// ============================================================================
// PICKUP EFFECTS
// ============================================================================

void ApplyPickup(int client, PickupType type)
{
	switch (type)
	{
		case Pickup_Health:
		{
			int health = GetClientHealth(client);
			int newHealth = health + 50;
			
			// Cap at 150
			if (newHealth > 150)
				newHealth = 150;
			
			SetEntityHealth(client, newHealth);
			PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Health");
		}
		case Pickup_Ammo:
		{
			GiveFullAmmo(client);
			PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Ammo");
		}
		case Pickup_Speed:
		{
			// Don't stack speed boosts
			if (g_bHasSpeedBoost[client])
			{
				PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Already Active");
				return;
			}
			
			// Store original speed
			g_flOriginalSpeed[client] = GetPlayerLaggedMovementValue(client);
			
			// Apply speed boost
			SetPlayerLaggedMovementValue(client, g_flOriginalSpeed[client] * 1.2);
			g_bHasSpeedBoost[client] = true;
			
			// Remove after duration
			CreateTimer(BOOST_DURATION, Timer_RemoveSpeedBoost, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			
			PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Speed");
		}
		case Pickup_Damage:
		{
			if (g_bHasDamageBoost[client])
			{
				PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Already Active");
				return;
			}
			
			g_bHasDamageBoost[client] = true;
			
			CreateTimer(BOOST_DURATION, Timer_RemoveDamageBoost, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			
			PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Damage");
		}
	}
	
	// Play pickup sound
	EmitSoundToClient(client, "items/smallmedkit1.wav");
}

void GiveFullAmmo(int client)
{
	// Give one clip for primary weapon (uses killrewards.sp code)
	bool gavePrimary = GiveOneClipPrimaryAmmo(client);
	
	// Give one clip for pistol (uses killrewards.sp code)
	bool gavePistol = GiveOneClipPistolAmmo(client);
	
	PrintToServer("[PICKUPS DEBUG] Gave ammo - Primary: %d, Pistol: %d", gavePrimary, gavePistol);
}

// ============================================================================
// BOOST TIMERS
// ============================================================================

public Action Timer_RemoveSpeedBoost(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (client && IsClientInGame(client) && g_bHasSpeedBoost[client])
	{
		// Restore original speed
		SetPlayerLaggedMovementValue(client, g_flOriginalSpeed[client]);
		g_bHasSpeedBoost[client] = false;
		
		PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Expired Speed");
	}
	
	return Plugin_Stop;
}

public Action Timer_RemoveDamageBoost(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (client && IsClientInGame(client))
	{
		g_bHasDamageBoost[client] = false;
		PrintToChat(client, "%t%t", ZM_PREFIX, "Pickup Expired Damage");
	}
	
	return Plugin_Stop;
}

// ============================================================================
// DAMAGE MODIFICATION
// ============================================================================

float Pickups_ModifyDamage(int attacker, float damage)
{
	// Damage boost for attacker
	if (g_bHasDamageBoost[attacker])
	{
		damage *= 1.25;  // +25% damage
	}
	
	return damage;
}
