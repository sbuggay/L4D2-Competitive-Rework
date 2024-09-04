#pragma semicolon 1

#include <sourcemod>
#include <left4dhooks>
#include <l4d2util>
#include <l4d2util_constants>

#define DEBUG 1;

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

public void OnPluginStart()
{
    Handle kv = CreateKeyValues("");
    KvSetString(kv, "driver", "sqlite");
    KvSetString(kv, "database", "test");

    db = SQL_ConnectCustom(kv, g_sError, sizeof(g_sError), false);
	if (db == null) {
		PrintToChatAll(g_sError);
	}

	SQL_Query(db, "create table if not exists players (id integer primary key, steamid64 text unique, mmr integer, rounds integer, wins integer, lastround timestamp)");

    delete kv;

	RegConsoleCmd("sm_balance", Balance);
	#if defined DEBUG
		RegConsoleCmd("sm_balance_test", BalanceTest);
	#endif
}

public Action:Balance(int client, int args)
{
	int total = 0;
	int[] players = new int[MaxClients];
	g_hClientToSteamID = CreateKeyValues("");

	// Add all players to the db
	for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) == TEAM_SPECTATOR)
            continue;
		
		char steamid[25];
		GetClientAuthId(i, AuthId_SteamID64, steamid, sizeof(steamid));

		Handle hPlayerAddStmt = SQL_PrepareQuery(db, "insert or ignore into players (steamid64, mmr, rounds, wins) values (?, 1500, 0, 0)", g_sError, sizeof(g_sError));
		SQL_BindParamString(hPlayerAddStmt, 0, steamid, false);
		SQL_Execute(hPlayerAddStmt);

		delete hPlayerAddStmt;

		char sClient[5];
		IntToString(i, sClient, sizeof(sClient));
		KvSetString(g_hClientToSteamID, sClient, steamid);
		PrintToChatAll("%s -> %s", sClient, steamid);

		players[total++] = i;
    }

	SortCustom1D(players, total, SortDescendingMMR);
	AlternateTeams(players, total);

	delete g_hClientToSteamID;

	return Plugin_Handled;
}

#if defined DEBUG
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

	SortCustom1D(players, total, SortDescendingMMR);
	AlternateTeams(players, total);

	delete g_hClientToSteamID;

	return Plugin_Handled;
}
#endif

public void L4D2_OnEndVersusModeRound_Post()
{
	if (!InSecondHalfOfRound()) {
		return;
	}

	bool survivorsAreWinning = SurvivorsAreWinning();
	int winnerTeam = survivorsAreWinning ? TEAM_SURVIVOR : TEAM_ZOMBIE;
	int losersTeam = survivorsAreWinning ? TEAM_ZOMBIE : TEAM_SURVIVOR;

	// TODO: Need to exclude players who were not in the game when the round started.
	UpdateMMR(winnerTeam, 15);
	UpdateMMR(losersTeam, -15);
}

void UpdateMMR(int team, int delta) {
	for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != team)
            continue;

		Handle hPlayerUpdateStmt = SQL_PrepareQuery(db, "update players set mmr = mmr + ?, rounds = rounds + 1, wins = wins + ?, lastround = current_timestamp where steamid64 = ?", g_sError, sizeof(g_sError));
		
		char steamid[25];
		GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
		SQL_BindParamInt(hPlayerUpdateStmt, 0, delta, false);
		SQL_BindParamInt(hPlayerUpdateStmt, 1, delta > 0 ? 1 : 0, false); // Assume a positive delta means a win, maybe a bad assumption.
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
	char steamid[25];
	char sClient[5];
	IntToString(client, sClient, sizeof(sClient));
	KvGetString(g_hClientToSteamID, sClient, steamid, sizeof(steamid));

	Handle hPlayerScore = SQL_PrepareQuery(db, "select mmr from players where steamid64 = ?", g_sError, sizeof(g_sError));
	int result = 1500;

	SQL_BindParamString(hPlayerScore, 0, steamid, false);

	if (SQL_Execute(hPlayerScore)) {
		SQL_FetchRow(hPlayerScore);
		result = SQL_FetchInt(hPlayerScore, 0);
		PrintToChatAll("%s mmr = %d", steamid, result);
	}

	delete hPlayerScore;
	return result;
}

void AlternateTeams(int []clients, int total) {
	for (int i = 0; i < total; i++) {
		if (i % 2 == 0) {
			#if defined DEBUG
				PrintToChatAll("Placing %d on survivors", clients[i]);
			#endif
			ClientCommand(clients[i], "jointeam 2");
        }
        else {
			#if defined DEBUG
				PrintToChatAll("Placing %d on infected", clients[i]);
			#endif
			ChangeClientTeam(clients[i], TEAM_ZOMBIE);
        }
	}
}