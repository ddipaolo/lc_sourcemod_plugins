#include <sourcemod>
#include <string>
#include <dbi>

#define PLUGIN_VERSION "0.1"

new Handle:db = INVALID_HANDLE;
new MinMatchLength = 4;
new String:errors[255];
new String:user_rep_table_name[] = "user_rep";
new String:user_rep_rep_column_name[] = "rep";
new String:user_rep_steamid_column_name[] = "steam_id";
//new String:user_votes_table_name[] = "user_votes";

public Plugin:myinfo  =
{
    name = "LCs Reputation Plugin",
    author = "diddlypow",
    description = "Don''t be read",
    version = PLUGIN_VERSION,
    url = "http://lmgtfy.com"
};

public OnPluginStart()
{
    if (InitDb()) {
        RegConsoleCmd("down", DownVote, "Lowers someone''s reputation", 0);
        RegConsoleCmd("up", UpVote, "Raises someone''s reputation", 0);
    } else {
        PrintToServer("Could not load reputation plugin");
    }
    AutoExecConfig();
}

public OnPluginEnd()
{
    CloseHandle(db);
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

public bool:DbExists()
{
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "select name from sqlite_master where type='table' and tbl_name=?");
    new Handle:query = SQL_PrepareQuery(db, queryStr, errors, sizeof(errors));
    SQL_BindParamString(query, 0, user_rep_table_name, true);
    PrintToServer("Calling query: %s with param %s", queryStr, user_rep_table_name);
    if (!SQL_Execute(query)) {
        PrintToServer("Failed executing query checking for existing tables");
        return false;
    }
    if (query == INVALID_HANDLE) {
        PrintToServer("Received invalid handle result from check for existing tables");
        return false;
    } else {
        new String:tableName[255];
        while (SQL_FetchRow(query)) {
            SQL_FetchString(query, 0, tableName, 255);
            PrintToServer("In table check, found table: %s", tableName);
            return (tableName[0] != EOS);
        }
    }
    return false;
}

public CreateDb()
{
    PrintToServer("Creating user_rep table");
    SQL_FastQuery(db, "CREATE TABLE user_rep(steam_id TEXT, rep INTEGER)");
    // other tables here 
}

public InitDb()
{
    db = SQL_DefConnect(errors, sizeof(errors));
    if (db == INVALID_HANDLE) {
        PrintToServer("Could not connect: %s", errors);
        return false;
    } else {
        if (!DbExists()) {
            CreateDb();
        }
        PrintToServer("LCs reputation plugin loaded");
        return true;
    }
}

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
            PrintToServer("Comparing against %s", clientName);
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
                PrintToServer("Found better match: %s", clientName);
                bestMatch = clientName;
                clientMatch = i;
                longestMatchLength = currentMatchLength;
            }
        }
    }
    if (longestMatchLength < MinMatchLength)
    {
        new String:empty[1] = "";
        strcopy(resultName, sizeof(empty), empty);
        PrintToServer("No suitable match found");
        return -1;
    } else {
        strcopy(resultName, sizeof(bestMatch), bestMatch);
        PrintToServer("Best match = %s", bestMatch);
        return clientMatch;
    }
}

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

public UpdateRepByName(client, String:name[], amount) {
    new String:playerName[256];
    new targetClient = GetUserNameFromSubString(name, playerName);
    if (targetClient == -1) {
        PrintToChat(client, "Did not match at least %d characters", MinMatchLength);
    } else {
        new String:mappedSteamId[256];
        if (GetClientAuthString(targetClient, mappedSteamId, sizeof(mappedSteamId))) {
            PrintToServer("Found steamId for %s: %s", playerName, mappedSteamId);
            new rep = AddToRep(mappedSteamId, amount);
            PrintToChatAll("%s repuation is now: %d", playerName, rep);
        } else {
            PrintToServer("Unable to get SteamID for %s", playerName);
        }
    }
}

public AddToRep(String:steamId[], amount)
{
    AddUserIfNotPresent(steamId);
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "update %s set %s = %s + (%d) where %s = ?", user_rep_table_name, user_rep_rep_column_name, user_rep_rep_column_name, amount, user_rep_steamid_column_name);
    new Handle:query = SQL_PrepareQuery(db, queryStr, errors, sizeof(errors));
    SQL_BindParamString(query, 0, steamId, true);
    PrintToServer("Calling query: %s with param %s", queryStr, steamId);
    if (!SQL_Execute(query)) {
        PrintToServer("Failed executing rep update query");
        return 0;
    } else if (query == INVALID_HANDLE) {
        PrintToServer("Received invalid handle result from rep update query");
        return 0;
    } else {
        // check result??
        Format(queryStr, sizeof(queryStr), "select %s from %s where %s = ?", 
            user_rep_rep_column_name, user_rep_table_name, user_rep_steamid_column_name);
        query = SQL_PrepareQuery(db, queryStr, errors, sizeof(errors));
        SQL_BindParamString(query, 0, steamId, true);
        PrintToServer("Calling query: %s with param %s", queryStr, steamId);
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
        PrintToServer("User %s not present, adding", steamId);
        Format(queryStr, sizeof(queryStr), "insert into %s(%s, %s) values(0, ?)",
            user_rep_table_name, user_rep_rep_column_name, user_rep_steamid_column_name);
        new Handle:query = SQL_PrepareQuery(db, queryStr, errors, sizeof(errors));
        SQL_BindParamString(query, 0, steamId, true);
        PrintToServer("Calling query: %s with param %s", queryStr, steamId);
        new success = SQL_Execute(query);
        if (!success) {
            PrintToServer("Failed executing user creation query");
        } else if (query == INVALID_HANDLE) {
            PrintToServer("Received invalid handle result from user creation query");
        } else {
            PrintToServer("Successfully created user with id: %s, result: %s", steamId, success);
        }
    }
}

public bool:IsUserPresent(String:steamId[])
{
    // queryStr will hold all our prepared queries
    decl String:queryStr[512];
    Format(queryStr, sizeof(queryStr), "select count(1) from %s where %s = ?", user_rep_table_name, user_rep_steamid_column_name);
    new Handle:query = SQL_PrepareQuery(db, queryStr, errors, sizeof(errors));
    SQL_BindParamString(query, 0, steamId, true);
    PrintToServer("Calling query: %s with param %s", queryStr, steamId);
    if (!SQL_Execute(query)) {
        PrintToServer("Failed executing user check query");
        return false;
    } else if (query == INVALID_HANDLE) {
        PrintToServer("Received invalid handle result from user check query");
        return false;
    } else {
        SQL_FetchRow(query);
        new rowCount = SQL_FetchInt(query, 0);
        return (rowCount != 0);
    }
}