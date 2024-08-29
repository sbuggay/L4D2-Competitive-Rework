#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <l4d2util_rounds>


public Plugin myinfo =
{
	name = "Random Rifle",
	author = "devan",
	description = "",
	version = "0.2",
	url = "https://github.com/SirPlease/L4D2-Competitive-Rework"
};


public void OnRoundIsLive()
{
	GiveStartingItems();
}

stock bool IsClientAndInGame(int index)
{
	return (index > 0 && index <= MaxClients && IsClientInGame(index));
}

stock bool IsSurvivor(int client)
{
	return IsClientAndInGame(client) && GetClientTeam(client) == 2;
}

void GiveStartingItems()
{
	ArrayList array = new ArrayList();
		
	for (int i = 1; i <= MaxClients; i++) {
		if (IsSurvivor(i) && !IsFakeClient(i)) {
			array.Push(i);
		}
	}

	if (array.Length > 0) {
		int client = array.Get(GetRandomInt(0, array.Length - 1));
		int slot = GetPlayerWeaponSlot(client, 0);
		if (slot != -1) {
			RemovePlayerItem(client, slot);
		}
		GivePlayerItem(client, "weapon_hunting_rifle"); // Fixed only in the latest version of sourcemod 1.11
	}

	delete array;
}
