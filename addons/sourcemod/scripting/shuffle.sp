#pragma semicolon 1
#include <sourcemod>
#include <l4d2util>
#include <l4d2util_constants>

public Plugin myinfo =
{
	name		= "Shuffle",
	author		= "devan",
	description = "",
	version		= "0.1",
	url			= "https://github.com/SirPlease/L4D2-Competitive-Rework"
};


public OnPluginStart()
{
    RegConsoleCmd("sm_shuf", Shuffle);
	RegConsoleCmd("sm_shuffle", Shuffle);
}

stock bool IsClientAndInGame(int index)
{
	return (index > 0 && index <= MaxClients && IsClientInGame(index));
}

public Action:Shuffle(client, argCount)
{
    PrintToChatAll("shuffing...");
    ArrayList array = new ArrayList();

	for (int i = 1; i <= MaxClients; i++)
	{
        // Push everyone who's not spectating and not a bot into array
		if (IsClientAndInGame(i) && !IsFakeClient(i))
		{
			array.Push(i);
		}
	}

    // Move all clients to spectator
    // Todo: check if admin
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientAndInGame(i) && !IsFakeClient(i)) {
            ChangeClientTeam(i, 1);
        }
    }

    ShuffleArrayList(array);

    // Put half on surv, the other half on inf
    int half = RoundToFloor(array.Length / 2.0) + 1;
    for (int i = 0; i < array.Length; i++) {
        if (i < half) {
            PrintToChatAll("Placing client %d on survivor", array.Get(i));
            ClientCommand(array.Get(i), "jointeam 2");
        }
        else {
            PrintToChatAll("Placing client %d on infected", array.Get(i));
            ChangeClientTeam(array.Get(i), TEAM_ZOMBIE);
        }
    }

	return Plugin_Handled;
}

public Action:Timer_Kick(Handle:timer, any:bot) {
	KickClient(bot, "Fake Player");
	return Plugin_Stop;
}

public void ShuffleArrayList(ArrayList array) {
    int size = array.Length;
    for (int i = size - 1; i > 0; i--) {
        int j = GetRandomInt(0, i);
        any temp = array.Get(i);
        array.Set(i, array.Get(j));
        array.Set(j, temp);
    }
}