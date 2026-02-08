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

// ============================================================================
// ENUMS
// ============================================================================

enum ZombieClass
{
	ZombieClass_Normal = 0,
	ZombieClass_Gas
}

// ============================================================================
// GLOBALS
// ============================================================================

int g_iZombieClass[MAXPLAYERS+1];
Handle g_hGasCloudTimers[MAXPLAYERS+1];

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
	}
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
		return;
	}
	
	// Random chance for special class
	int roll = GetRandomInt(1, 100);
	
	if (roll <= chance)
	{
		// Assign gas zombie class
		g_iZombieClass[client] = view_as<int>(ZombieClass_Gas);
	}
	else
	{
		g_iZombieClass[client] = view_as<int>(ZombieClass_Normal);
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
// DISPLAY HELPERS
// ============================================================================

ZombieClass ZombieClasses_GetClass(int client)
{
	return view_as<ZombieClass>(g_iZombieClass[client]);
}
