/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Public API Module
 *
 * Registers all natives and forwards exposed to external plugins.
 * Native handlers are implemented in human_skills_modular.inc.
 * Include dod_zm.inc in external plugins to consume this API.
 * =============================================================================
 */

// ============================================================================
// NATIVE REGISTRATION - call from AskPluginLoad2
// ============================================================================

void API_Init()
{
	// Human skill system natives
	CreateNative("ZM_RegisterHumanSkill", Native_RegisterHumanSkill);
	CreateNative("ZM_GetClientSkill",     Native_GetClientSkill);

	// Team query natives
	CreateNative("ZM_IsClientHuman",  Native_IsClientHuman);
	CreateNative("ZM_IsClientZombie", Native_IsClientZombie);

	// Mod state native
	CreateNative("ZM_IsModActive", Native_IsModActive);

	// Zombie class system natives
	CreateNative("ZM_RegisterZombieClass",   Native_RegisterZombieClass);
	CreateNative("ZM_GetClientZombieClass",  Native_GetClientZombieClass);
	CreateNative("ZM_GetZombieClassName",    Native_GetZombieClassName);

	RegPluginLibrary("dod_zm_core");
}

// ============================================================================
// CLIENT VALIDATION
// ============================================================================

/**
 * Validates a client index for use in native handlers.
 * Throws a native error if the client is invalid or not in game.
 *
 * @param client    Client index to validate.
 */
stock void APIValidateClientIndex(int client)
{
    if (client < 1 || client > MaxClients)
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);

    if (!IsClientInGame(client))
        ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", client);
}

// ============================================================================
// FORWARD CREATION - call from OnPluginStart
// ============================================================================

void API_CreateForwards()
{
	g_Forward_OnSkillAssigned = CreateGlobalForward("ZM_OnSkillAssigned", ET_Ignore, Param_Cell, Param_Cell);
	g_Forward_OnRoundStart    = CreateGlobalForward("ZM_OnRoundStart",    ET_Ignore);
	g_Forward_OnRoundEnd      = CreateGlobalForward("ZM_OnRoundEnd",      ET_Ignore);
	g_Forward_OnClientDeath   = CreateGlobalForward("ZM_OnClientDeath",   ET_Ignore, Param_Cell);
	g_Forward_OnClientSpawn   = CreateGlobalForward("ZM_OnClientSpawn",   ET_Ignore, Param_Cell, Param_Cell);
	g_Forward_OnZombieDeath   = CreateGlobalForward("ZM_OnZombieDeath",   ET_Ignore, Param_Cell, Param_Cell);
}
