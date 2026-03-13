/**
 * =============================================================================
 * Zombie Mod for Day of Defeat Source - Modular Zombie Class System
 *
 * Handles registration and name lookup for zombie classes.
 * Built-in classes (Normal/Gas/TNT/Ghost) are pre-registered at startup
 * so their IDs match the ZombieClass enum values in globals.inc.
 * External class plugins (future) register via ZM_RegisterZombieClass().
 * Native handlers live here; registration is wired in api.inc.
 * =============================================================================
 */

// ============================================================================
// CONSTANTS
// ============================================================================

#define MAX_CLASSES     32

// ============================================================================
// STRUCTURES
// ============================================================================

enum struct ClassInfo
{
    char name[ZM_MAX_CLASS_NAME];
    char description[ZM_MAX_CLASS_DESC];
    Handle plugin;  /* null = built-in */
}

// ============================================================================
// GLOBALS
// ============================================================================

ClassInfo g_RegisteredClasses[MAX_CLASSES];
int g_ClassCount = 0;

// ============================================================================
// INITIALIZATION
// ============================================================================

void ModularClasses_OnPluginStart()
{
    /* Built-in class registration is performed by zombie_classes_core.inc
     * via ModularClasses_RegisterBuiltIn() to keep class definitions
     * co-located with their behaviour. */
}

/**
 * Register a single built-in zombie class.
 * Called by zombie_classes_core.inc during initialisation.
 * Built-in classes are registered with plugin = null to mark them as internal.
 *
 * @param name          Class name
 * @param description   Class description
 */
void ModularClasses_RegisterBuiltIn(const char[] name, const char[] description)
{
    if (g_ClassCount >= MAX_CLASSES)
        return;

    strcopy(g_RegisteredClasses[g_ClassCount].name,        ZM_MAX_CLASS_NAME, name);
    strcopy(g_RegisteredClasses[g_ClassCount].description, ZM_MAX_CLASS_DESC, description);
    g_RegisteredClasses[g_ClassCount].plugin = null;
    g_ClassCount++;
}

// ============================================================================
// NAME LOOKUP - single canonical function used by all internal modules
// ============================================================================

/**
 * Writes the display name for a class ID into buffer.
 * Falls back to "Zombie" for unknown IDs.
 *
 * @param classID       Class ID (matches ZombieClass enum for built-ins)
 * @param buffer        Output buffer
 * @param maxlength     Size of output buffer
 */
void ModularClasses_GetClassName(int classID, char[] buffer, int maxlength)
{
    if (classID >= 0 && classID < g_ClassCount)
        strcopy(buffer, maxlength, g_RegisteredClasses[classID].name);
    else
        strcopy(buffer, maxlength, "Zombie");
}

// ============================================================================
// NATIVE HANDLERS
// ============================================================================

public int Native_RegisterZombieClass(Handle plugin, int numParams)
{
    if (g_ClassCount >= MAX_CLASSES)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Maximum zombie classes (%d) reached", MAX_CLASSES);
        return -1;
    }

    char name[ZM_MAX_CLASS_NAME];
    char description[ZM_MAX_CLASS_DESC];
    GetNativeString(1, name, sizeof(name));
    GetNativeString(2, description, sizeof(description));

    /* Check for existing slot by name (catches built-in claim or plugin reload)
     * or by plugin handle (catches sm plugins reload with same .smx).
     * Update in-place and return the existing ID rather than appending. */
    for (int i = 0; i < g_ClassCount; i++)
    {
        bool sameHandle = (g_RegisteredClasses[i].plugin == plugin);
        bool sameName   = (strcmp(g_RegisteredClasses[i].name, name, false) == 0);

        if (sameHandle || sameName)
        {
            strcopy(g_RegisteredClasses[i].name,        ZM_MAX_CLASS_NAME, name);
            strcopy(g_RegisteredClasses[i].description, ZM_MAX_CLASS_DESC, description);
            g_RegisteredClasses[i].plugin = plugin;

            PrintToServer("[Zombie Mod] Updated zombie class '%s' (ID %d)", name, i);
            return i;
        }
    }

    /* New class */
    int classID = g_ClassCount;
    strcopy(g_RegisteredClasses[classID].name,        ZM_MAX_CLASS_NAME, name);
    strcopy(g_RegisteredClasses[classID].description, ZM_MAX_CLASS_DESC, description);
    g_RegisteredClasses[classID].plugin = plugin;
    g_ClassCount++;

    PrintToServer("[Zombie Mod] Registered new zombie class '%s' (ID %d)", name, classID);
    return classID;
}

public int Native_GetClientZombieClass(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    APIValidateClientIndex(client);
    return g_iZombieClass[client];
}

public int Native_GetZombieClassName(Handle plugin, int numParams)
{
    int classID    = GetNativeCell(1);
    int maxlength  = GetNativeCell(3);

    char buffer[ZM_MAX_CLASS_NAME];
    ModularClasses_GetClassName(classID, buffer, sizeof(buffer));
    SetNativeString(2, buffer, maxlength);
    return 0;
}
