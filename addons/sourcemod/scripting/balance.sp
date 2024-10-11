#pragma semicolon 1

#include <sourcemod>
#include <left4dhooks>
#include <l4d2util>
#include <l4d2util_constants>

#define DEBUG 0

Database db = null;
Handle g_hClientToSteamID = null;
char g_sError[256];

public Plugin myinfo = 
{
	name = "Team Balancer",
	author = "pwnmonkey",
	description = "Simple sqlite3 backed team balancer",
	version = "1.0.0",
	url = "http://www.sourcemod.net/"
};

int teamOptions[] = {0x0F, 0x1E, 0x1D, 0x1B, 0x17, 0x2E, 0x2D, 0x2B, 0x27, 0x3C, 0x3A, 0x39, 0x36, 0x35, 0x33, 0x4E, 0x4D, 0x4B, 0x47, 0x5C, 0x5A, 0x59, 0x56, 0x55, 0x53, 0x6C, 0x6A, 0x69, 0x66, 0x65, 0x63, 0x78, 0x74, 0x72, 0x71, 0x8E, 0x8D, 0x8B, 0x87, 0x9C, 0x9A, 0x99, 0x96, 0x95, 0x93, 0xAC, 0xAA, 0xA9, 0xA6, 0xA5, 0xA3, 0xB8, 0xB4, 0xB2, 0xB1, 0xCC, 0xCA, 0xC9, 0xC6, 0xC5, 0xC3, 0xD8, 0xD4, 0xD2, 0xD1, 0xE8, 0xE4, 0xE2, 0xE1, 0xF0};

public void OnPluginStart()
{
    Handle kv = CreateKeyValues("");
    KvSetString(kv, "driver", "sqlite");
    KvSetString(kv, "database", "balance");

    db = SQL_ConnectCustom(kv, g_sError, sizeof(g_sError), false);
	if (db == null) {
		PrintToChatAll(g_sError);
    }

    SQL_Query(db, "create table if not exists player (id integer primary key, steamid64 text unique, mmr integer, rounds integer, wins integer, lastround timestamp)");

    delete kv;

    RegConsoleCmd("sm_balance", Balance);
    #if DEBUG
        RegConsoleCmd("sm_balance_test", BalanceTest);
    #endif
}

public int PlayerCount() {
    int players = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) || !IsFakeClient(i) || GetClientTeam(i) != 1) players++;
    }
    return players;
}

public Action:Balance(int client, int args)
{
    int total = 0;
    int[] players = new int[MaxClients];
    g_hClientToSteamID = CreateKeyValues("");
    Handle hClientToMMR = CreateKeyValues("");

    PrintToChatAll("Test");

    // Add all players to the db
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == 1)
            continue;

        char steamid[25];
        GetClientAuthId(i, AuthId_SteamID64, steamid, sizeof(steamid));

        Handle hPlayerAddStmt = SQL_PrepareQuery(db, "insert or ignore into player (steamid64, mmr, rounds, wins) values (?, 1500, 0, 0)", g_sError, sizeof(g_sError));
        SQL_BindParamString(hPlayerAddStmt, 0, steamid, false);
        SQL_Execute(hPlayerAddStmt);

        delete hPlayerAddStmt;

        char sClient[5];
        IntToString(i, sClient, sizeof(sClient));
        KvSetString(g_hClientToSteamID, sClient, steamid);

        // Grab MMR and put it in our map
        KvSetNum(hClientToMMR, sClient, GetMMR(i));
        // PrintToChatAll("%d", KvGetNum(hClientToMMR, sClient));

        players[total++] = i;
    }

    PrintToChatAll("Total players %d", total);

    // Shuffle(players, total);
    // SortCustom1D(players, total, SortDescendingMMR);
    // AlternateTeams(players, total);
    int survivors[4];
    int infected[4];
    float minDiff = 99999.0;

    int bestSurvivors[4];
    int bestInfected[4];

    // Try all combinations
    for (int comboIndex = 0; comboIndex < 64; comboIndex++) {
        int option = teamOptions[comboIndex];
        int flag = 0x80;
        int playerIndex = 0;

        PrintToChatAll("%x", option);

        int sIndex = 0;
        int iIndex = 0;

        while(flag) {
            PrintToChatAll("%d %d %d %d", flag, sIndex, iIndex, playerIndex);
            if (flag & option > 1) {
                PrintToChatAll("Adding to survivor team");
                survivors[sIndex++] = players[playerIndex];
            }
            else {
                PrintToChatAll("Added to infected team");
                infected[iIndex++] = players[playerIndex];
            }

            playerIndex++;
            flag = flag >> 1;
            PrintToChatAll("Moving flag %x", flag);
        }

        // Ignore teams with +1 diff
        if ((sIndex > iIndex) ? (sIndex - iIndex) : (iIndex - sIndex) > 1) continue;
        PrintToChatAll("Getting diff");

        float diff = MmrDiff(survivors, sIndex, infected, iIndex, hClientToMMR);
        PrintToChatAll("%f", diff);
        
        if (diff < minDiff) {
            // For some reason we don't have arraycopy...
            for (int i = 0; i < 4; i++) {
                bestSurvivors[i] = 0;
                bestInfected[i] = 0;
            }
            for (int i = 0; i < sIndex; i++) {
                bestSurvivors[i] = survivors[i];
            }
            for (int i = 0; i < iIndex; i++) {
                bestInfected[i] = infected[i];
            }
            minDiff = diff;
        }
    }
    
    for (int i = 0; i < 4; i++) {
        PlaceOnTeam(bestInfected[i], TEAM_ZOMBIE);
    }
    for (int i = 0; i < 4; i++) {
        PlaceOnTeam(bestSurvivors[i], TEAM_SURVIVOR);
    }

    PrintToChatAll("Balanced! (%f)", minDiff);

    delete g_hClientToSteamID;
    delete hClientToMMR;

    return Plugin_Handled;
}

#if DEBUG
public Action:BalanceTest(int client, int args)
{
    int total = 0;
    int[] players = new int[8];
    g_hClientToSteamID = CreateKeyValues("");

    // This is assuming there is [1..8] steamid64s in the db to test against.
    for (int i = 1; i <= 8; i++)
    {
        char steamid[25];
        IntToString(i, steamid, sizeof(steamid));

        char sClient[5];
        IntToString(i, sClient, sizeof(sClient));
        KvSetString(g_hClientToSteamID, sClient, steamid);

        players[total++] = i;
    }

    Shuffle(players, total);
    SortCustom1D(players, total, SortDescendingMMR);
    AlternateTeams(players, total);

    delete g_hClientToSteamID;

    return Plugin_Handled;
}
#endif

float MmrDiff(int []team1, int team1Size, int []team2, int team2Size, Handle hClientToMMR) {
    float team1Mmr = 0;
    float team2Mmr = 0;
    char sClient[5];

    for (int i = 0; i < team1Size; i++) {
        IntToString(team1[i], sClient, sizeof(sClient));
        team1Mmr += KvGetNum(hClientToMMR, sClient, 1500);
    }

    for (int i = 0; i < team2Size; i++) {
        IntToString(team2[i], sClient, sizeof(sClient));
        team2Mmr += KvGetNum(hClientToMMR, sClient, 1500);
    }

    float averageTeam1 = (team1Size > 0) ? (team1Mmr / team1Size) : 0;
    float averageTeam2 = (team2Size > 0) ? (team2Mmr / team2Size) : 0;
    float diff = (averageTeam1 > averageTeam2) ? (averageTeam1 - averageTeam2) : (averageTeam2 - averageTeam1);
    return diff;
}

public void L4D2_OnEndVersusModeRound_Post()
{
    if (!InSecondHalfOfRound()) {
        return;
    }

    int iSurvivorIndex = GameRules_GetProp("m_bAreTeamsFlipped");
    int iSurvivorScore = L4D2Direct_GetVSCampaignScore(iSurvivorIndex);
    int iInfectedScore = L4D2Direct_GetVSCampaignScore(1 - iSurvivorIndex);

    if (iSurvivorScore == iInfectedScore) {
        return;
    }

    bool bSurvivorsAreWinning = iSurvivorScore > iInfectedScore;
    int iWinnerTeam = bSurvivorsAreWinning ? TEAM_SURVIVOR : TEAM_ZOMBIE;
    int iLosersTeam = bSurvivorsAreWinning ? TEAM_ZOMBIE : TEAM_SURVIVOR;

    // TODO: Need to exclude players who were not in the game when the round started.
    UpdateMMR(iWinnerTeam, 15);
    UpdateMMR(iLosersTeam, -15);
}

void UpdateMMR(int team, int delta) {
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
            continue;

        Handle hPlayerUpdateStmt = SQL_PrepareQuery(db, "update player set mmr = mmr + ?, rounds = rounds + 1, wins = wins + ?, lastround = current_timestamp where steamid64 = ?", g_sError, sizeof(g_sError));
        
        char steamid[25];
        GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
        SQL_BindParamInt(hPlayerUpdateStmt, 0, delta, false);
        SQL_BindParamInt(hPlayerUpdateStmt, 1, delta > 0 ? 1 : 0, false); // Assume a positive delta means a win, maybe a bad assumption.
        SQL_BindParamString(hPlayerUpdateStmt, 2, steamid, false);
        SQL_Execute(hPlayerUpdateStmt);

        delete hPlayerUpdateStmt;
    }
}

int SortDescendingMMR(int client1, int client2, int[] array, Handle hndl) {
    int elo1 = GetMMR(client1);
    int elo2 = GetMMR(client2);
    if (elo1 < elo2) {
        return 1;
    } else if (elo1 > elo2) {
        return -1;
    }
    return 0;
}

int GetMMR(int client) {
    char steamid[25];
    char sClient[5];
    IntToString(client, sClient, sizeof(sClient));
    KvGetString(g_hClientToSteamID, sClient, steamid, sizeof(steamid));

    Handle hPlayerScore = SQL_PrepareQuery(db, "select mmr from player where steamid64 = ?", g_sError, sizeof(g_sError));
    int result = 1500;

    SQL_BindParamString(hPlayerScore, 0, steamid, false);

    if (SQL_Execute(hPlayerScore)) {
        SQL_FetchRow(hPlayerScore);
        result = SQL_FetchInt(hPlayerScore, 0);
        #if DEBUG
        PrintToChatAll("%s mmr = %d", steamid, result);
        #endif
    }

    delete hPlayerScore;
    return result;
}

void PlaceOnTeam(int client, int team) {
    if (client == 0 || !IsClientInGame(client) || IsFakeClient(client)) return;

    if (team == TEAM_SURVIVOR) {
        ClientCommand(client, "jointeam 2");
    }
    else if (team == TEAM_ZOMBIE) {
        ChangeClientTeam(client, TEAM_ZOMBIE);
    }
}

void AlternateTeams(int []clients, int total) {
    for (int i = 0; i < total; i++) {
        if (i % 2 == 0) {
            #if DEBUG
                PrintToChatAll("Placing %d on survivors", clients[i]);
            #endif
            ClientCommand(clients[i], "jointeam 2");
        }
        else {
            #if DEBUG
                PrintToChatAll("Placing %d on infected", clients[i]);
            #endif
            ChangeClientTeam(clients[i], TEAM_ZOMBIE);
        }
    }
}

void Shuffle(any[] array, int size) {
    for (int i = size - 1; i > 0; i--) {
        int j = GetRandomInt(0, i);
        any temp = array[i];
        array[i] = array[j];
        array[j] = temp;
    }
}