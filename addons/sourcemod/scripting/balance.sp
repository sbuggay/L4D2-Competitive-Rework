#pragma semicolon 1

#include <sourcemod>
#include <left4dhooks>
#include <l4d2util>
#include <l4d2util_constants>

Database db = null;

Handle clientToSteamID = null;

public void OnPluginStart()
{
    Handle kv = CreateKeyValues("");
    KvSetString(kv, "driver", "sqlite");
    KvSetString(kv, "database", "test");

	char error[256];

    db = SQL_ConnectCustom(kv, error, sizeof(error), false);
	if (db == null) {
		PrintToChatAll(error);
	}

	SQL_Query(db, "create table if not exists players (id integer primary key, steamid64 text unique, mmr integer, rounds integer, wins integer, lastround timestamp)");

    CloseHandle(kv);

	RegConsoleCmd("sm_balance", Balance);
}


public Action:Balance(int client, int args)
{
	char error[256];
	int total = 0;
	int[] players = new int[MaxClients];
	clientToSteamID = CreateKeyValues("");

	// Add all players to the db
	for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == TEAM_SPECTATOR)
            continue;
		
		char steamid[25];
		GetClientAuthId(i, AuthId_SteamID64, steamid, sizeof(steamid));

		Handle hPlayerAddStmt = SQL_PrepareQuery(db, "insert or ignore into players (steamid64, mmr, rounds, wins) values (?, 1500, 0, 0)", error, sizeof(error));
		if (hPlayerAddStmt == null) {
			PrintToChatAll(error);
		}

		SQL_BindParamString(hPlayerAddStmt, 0, steamid, false);
		SQL_Execute(hPlayerAddStmt);

		delete hPlayerAddStmt;

		char sClient[5];
		IntToString(i, sClient, sizeof(sClient));
		KvSetString(clientToSteamID, sClient, steamid);
		PrintToChatAll("%s -> %s", sClient, steamid);

		players[total++] = i;
    }

	SortCustom1D(players, total, SortDescendingMMR);

	for (int i = 0; i < total; i++) {
		PrintToChatAll("%d", players[i]);

		if (i % 2 == 0) {
            ChangeClientTeam(array.Get(i), TEAM_ZOMBIE);
        }
        else {
            ClientCommand(array.Get(i), "jointeam 2");
        }
	}

	return Plugin_Handled;
}

public void L4D2_OnEndVersusModeRound_Post()
{
	if (InSecondHalfOfRound()) {
		bool survivorsAreWinning = SurvivorsAreWinning();
		
		int winnerTeam = survivorsAreWinning ? TEAM_SURVIVOR : TEAM_ZOMBIE;
		int losersTeam = survivorsAreWinning ? TEAM_ZOMBIE : TEAM_SURVIVOR;
		UpdateMMR(winnerTeam, 15);
		UpdateMMR(losersTeam, -15);
	}
}

void UpdateMMR(int team, int delta) {
	
	char error[255];

	for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
            continue;

		Handle hPlayerUpdateStmt = SQL_PrepareQuery(db, "update players set mmr = mmr + ?, rounds = rounds + 1, wins = wins + ?, lastround = current_timestamp where steamid64 = ?", error, sizeof(error));
		
		char steamid[25];
		GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
		SQL_BindParamInt(hPlayerUpdateStmt, 0, delta, false);
		SQL_BindParamInt(hPlayerUpdateStmt, 1, delta > 0 ? 1 : 0, false); // Assume a positive delta means a win, maybe a bad assumption
		SQL_BindParamString(hPlayerUpdateStmt, 2, steamid, false);
		SQL_Execute(hPlayerUpdateStmt);

		delete hPlayerUpdateStmt;
    }
}

bool SurvivorsAreWinning()
{
	int flipped = GameRules_GetProp("m_bAreTeamsFlipped");

	int survivorIndex = flipped ? 1 : 0;
	int infectedIndex = flipped ? 0 : 1;

	int survivorScore = L4D2Direct_GetVSCampaignScore(survivorIndex);
	int infectedScore = L4D2Direct_GetVSCampaignScore(infectedIndex);

	return survivorScore >= infectedScore;
}

int SortDescendingMMR(int client1, int client2, int[] array, Handle hndl) {
    int elo1 = GetMMR(client1);
    int elo2 = GetMMR(client2);
    if (elo1 < elo2) {
        return 1;
    } else if (elo1 > elo2) {
        return -1;
    } else {
        return 0;
    }
}

int GetMMR(int client) {
	char error[255]; // Horribly inefficient, we just need to do this once and store in a map

	char steamid[25];
	char sClient[5];
	IntToString(client, sClient, sizeof(sClient));
	KvGetString(clientToSteamID, sClient, steamid, sizeof(steamid));

	Handle hPlayerScore = SQL_PrepareQuery(db, "select mmr from players where steamid64 = ?", error, sizeof(error));
	int result = 1500;

	SQL_BindParamString(hPlayerScore, 0, steamid, false);

	if (SQL_Execute(hPlayerScore)) {
		while (SQL_FetchRow(hPlayerScore))
		{
			result = SQL_FetchInt(hPlayerScore, 0);
			PrintToChatAll("%s mmr = %d", steamid, result);
		}
	}

	delete hPlayerScore;

	return result;
}