#include <sourcemod>
#include <string>
#include <dbi>

#define PLUGIN_VERSION "0.1"


// Global vars
new Handle:g_dbHandle = INVALID_HANDLE;
new String:g_errorBuffer[255];

// Config vars
new cfg_minMatchLength = 4;
new String:cfg_userRepTableName[] = "user_rep";
new String:cfg_userRepRepColumnName[] = "rep";
new String:cfg_userRepSteamIdColumnName[] = "steam_id";
new String:cfg_timeFormat[] = "%Y-%m-%d- %H:%M:%S";
new String:cfg_logPrefix[] = "[LCREP]"

public Plugin:myinfo  =
{
    name = "LCs Reputation Plugin",
    author = "diddlypow",
    description = "Don''t be read",
    version = PLUGIN_VERSION,
    url = "http://lmgtfy.com"
};

//  SourceMod plugin hooks
public OnPluginStart()
{
    if (InitDb()) {
        RegConsoleCmd("down", DownVote, "Lowers someone''s reputation", 0);
        RegConsoleCmd("up", UpVote, "Raises someone''s reputation", 0);
    } else {
        Log("Could not load reputation plugin");
    }
    AutoExecConfig();
}

public OnPluginEnd()
{
    CloseHandle(g_dbHandle);
}

public OnClientPostAdminCheck(client) 
{
    new String:clientName[255];
    GetClientName(client, clientName, sizeof(clientName));
    PrintToServer("Checking for %s in database", clientName);
    new String:steamId[255];
    if (IsClientConnected(client) && !IsFakeClient(client) && IsClientInGame(client) &&
        GetClientAuthString(client, steamId, sizeof(steamId))) {
            AddUserIfNotPresent(steamId);
    }
}

// Command callbacks
public Action:DownVote(client, args)
{
    new String:full[256];
    GetCmdArgString(full, sizeof(full));
    UpdateRepByName(client, full, -1);
    return Plugin_Handled;
}

public Action:UpVote(client, args)
{
    new String:full[256];
    GetCmdArgString(full, sizeof(full));
    UpdateRepByName(client, full, 1);
    return Plugin_Handled;
}

// DB utility functions
public InitDb()
{
    g_dbHandle = SQL_DefConnect(g_errorBuffer, sizeof(g_errorBuffer));
    if (g_dbHandle == INVALID_HANDLE) {
        Log("Could not connect: %s", g_errorBuffer);
        return false;
    } else {
        if (!DbExists()) {
            CreateDb();
        }
        Log("LCs reputation plugin loaded");
        return true;
    }
}

public CreateDb()
{
    Log("Creating user_rep table");
    SQL_FastQuery(g_dbHandle, "CREATE TABLE user_rep(steam_id TEXT, rep INTEGER)");
}

public bool:DbExists()
{
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "select name from sqlite_master where type='table' and tbl_name=?");
    new Handle:query = SQL_PrepareQuery(g_dbHandle, queryStr, g_errorBuffer, sizeof(g_errorBuffer));
    SQL_BindParamString(query, 0, cfg_userRepTableName, true);
    Log("Calling query: %s with param %s", queryStr, cfg_userRepTableName);
    if (!SQL_Execute(query)) {
        Log("Failed executing query checking for existing tables");
        return false;
    }
    if (query == INVALID_HANDLE) {
        Log("Received invalid handle result from check for existing tables");
        return false;
    } else {
        new String:tableName[255];
        while (SQL_FetchRow(query)) {
            SQL_FetchString(query, 0, tableName, 255);
            Log("In table check, found table: %s", tableName);
            return (tableName[0] != EOS);
        }
    }
    return false;
}

// General utility functions
public min (a, b) 
{
    if (a > b) {
        return b;
    } else {
        return a;
    }
}

public max(a, b)
{
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

public GetUserNameFromSubString(String:partialName[], String:resultName[]) 
{
    new String:bestMatch[255];
    new longestMatchLength = 0;

    new String:clientName[255];
    new clientMatch;
    new currentMatchLength;
    for (new i = 1; i < MaxClients; i++) 
    {
        currentMatchLength = 0;
        if (IsClientConnected(i) && !IsFakeClient(i) && IsClientInGame(i) &&
            GetClientName(i, clientName, sizeof(clientName))) {
            Log("Comparing against %s", clientName);
            new minLength = min(strlen(clientName), strlen(partialName));
            new clientChar, argChar;
            for (new c = 0; c < minLength; c++) 
            {
                clientChar = clientName[c];
                argChar = partialName[c];
                if (clientChar == argChar) 
                {
                    currentMatchLength++;
                } else {
                    break;
                }
            }
            if (currentMatchLength >= longestMatchLength) {
                Log("Found better match: %s", clientName);
                bestMatch = clientName;
                clientMatch = i;
                longestMatchLength = currentMatchLength;
            }
        }
    }
    if (longestMatchLength < cfg_minMatchLength)
    {
        new String:empty[1] = "";
        strcopy(resultName, sizeof(empty), empty);
        Log("No suitable match found");
        return -1;
    } else {
        strcopy(resultName, sizeof(bestMatch), bestMatch);
        Log("Best match = %s", bestMatch);
        return clientMatch;
    }
}

public UpdateRepByName(client, String:name[], amount) {
    new String:playerName[256];
    new targetClient = GetUserNameFromSubString(name, playerName);
    if (targetClient == -1) {
        PrintToChat(client, "Did not match at least %d characters", cfg_minMatchLength);
    } else {
        new String:mappedSteamId[256];
        if (GetClientAuthString(targetClient, mappedSteamId, sizeof(mappedSteamId))) {
            Log("Found steamId for %s: %s", playerName, mappedSteamId);
            new rep = AddToRep(mappedSteamId, amount);
            PrintToChatAll("%s repuation is now: %d", playerName, rep);
        } else {
            Log("Unable to get SteamID for %s", playerName);
        }
    }
}

public AddToRep(String:steamId[], amount)
{
    AddUserIfNotPresent(steamId);
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "update %s set %s = %s + (%d) where %s = ?", cfg_userRepTableName, cfg_userRepRepColumnName, cfg_userRepRepColumnName, amount, cfg_userRepSteamIdColumnName);
    new Handle:query = SQL_PrepareQuery(g_dbHandle, queryStr, g_errorBuffer, sizeof(g_errorBuffer));
    SQL_BindParamString(query, 0, steamId, true);
    Log("Calling query: %s with param %s", queryStr, steamId);
    if (!SQL_Execute(query)) {
        Log("Failed executing rep update query");
        return 0;
    } else if (query == INVALID_HANDLE) {
        Log("Received invalid handle result from rep update query");
        return 0;
    } else {
        // check result??
        Format(queryStr, sizeof(queryStr), "select %s from %s where %s = ?", 
            cfg_userRepRepColumnName, cfg_userRepTableName, cfg_userRepSteamIdColumnName);
        query = SQL_PrepareQuery(g_dbHandle, queryStr, g_errorBuffer, sizeof(g_errorBuffer));
        SQL_BindParamString(query, 0, steamId, true);
        Log("Calling query: %s with param %s", queryStr, steamId);
        SQL_Execute(query);
        while (SQL_FetchRow(query)) {
            return SQL_FetchInt(query, 0);
        }
        return 0;
    }
}

public AddUserIfNotPresent(String:steamId[])
{
    if (!IsUserPresent(steamId)) {
        decl String:queryStr[512];
        Log("User %s not present, adding", steamId);
        Format(queryStr, sizeof(queryStr), "insert into %s(%s, %s) values(0, ?)",
            cfg_userRepTableName, cfg_userRepRepColumnName, cfg_userRepSteamIdColumnName);
        new Handle:query = SQL_PrepareQuery(g_dbHandle, queryStr, g_errorBuffer, sizeof(g_errorBuffer));
        SQL_BindParamString(query, 0, steamId, true);
        Log("Calling query: %s with param %s", queryStr, steamId);
        new success = SQL_Execute(query);
        if (!success) {
            Log("Failed executing user creation query");
        } else if (query == INVALID_HANDLE) {
            Log("Received invalid handle result from user creation query");
        } else {
            Log("Successfully created user with id: %s, result: %s", steamId, success);
        }
    }
}

public bool:IsUserPresent(String:steamId[])
{
    // queryStr will hold all our prepared queries
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "select count(1) from %s where %s = ?", cfg_userRepTableName, cfg_userRepSteamIdColumnName);
    new Handle:query = SQL_PrepareQuery(g_dbHandle, queryStr, g_errorBuffer, sizeof(g_errorBuffer));
    SQL_BindParamString(query, 0, steamId, true);
    Log("Calling query: %s with param %s", queryStr, steamId);
    if (!SQL_Execute(query)) {
        Log("Failed executing user check query");
        return false;
    } else if (query == INVALID_HANDLE) {
        Log("Received invalid handle result from user check query");
        return false;
    } else {
        SQL_FetchRow(query);
        new rowCount = SQL_FetchInt(query, 0);
        return (rowCount != 0);
    }
}

public Log(const String:msg[], any:...) {
    decl String:timeString[50];
    FormatTime(timeString, sizeof(timeString), cfg_timeFormat);

    decl String:formattedMsg[1024];
    VFormat(formattedMsg, sizeof(formattedMsg), msg, 2);

    decl String:logMsg[1024];
    Format(logMsg, sizeof(logMsg), "%s %s %s", cfg_logPrefix, timeString, formattedMsg);
    PrintToServer(logMsg);
}
