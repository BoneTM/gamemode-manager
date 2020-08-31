#include <sourcemod>
#include <adminmenu>
#include "include/restorecvars.inc"

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name = "Gamemode Manager",
	author = "Bone",
	description = "A plugin to help automate gamemode shuffling on a multimod server.",
	version = "1.0",
	url = "https://bonetm.github.io/"
};

StringMap g_ModePlugins;
char g_currentModeKey[256];
ArrayList g_CvarRestore = null;

public void OnPluginStart()
{
	LoadGamemodeConfig();
}

public void OnMapStart(){
	ExecCurrentModeCfg();
}

void ExecCurrentModeCfg()
{
	if (g_CvarRestore != null) {
		RestoreCvars(g_CvarRestore);
		CloseCvarStorage(g_CvarRestore);
		g_CvarRestore = null;
	}

	char cvarPath[256];
	char buffer[2][128];
	ExplodeString(g_currentModeKey, ";", buffer, sizeof(buffer), sizeof(buffer[]));
	Format(cvarPath, sizeof(cvarPath), "sourcemod/gamemodes/%s.cfg", buffer[0]);

	g_CvarRestore = ExecuteAndSaveCvars(cvarPath);

	if (g_CvarRestore == null) {
    	LogError("Failed to save cvar values when executing %s", cvarPath);
  	}
}

public void ChangeGameMode(char[] modekey)
{
	ServerCommand("sm plugins load_unlock");

	ArrayList pluginsList;
	StringMapSnapshot snap = g_ModePlugins.Snapshot();
	char key[256];
	for (int i = 0; i < snap.Length; i++)
	{
		snap.GetKey(i, key, sizeof(key));
		g_ModePlugins.GetValue(key, pluginsList);

		if (pluginsList == null) continue;

		for (int k = 0; k < pluginsList.Length; k++){
			char pluginName[255];
			pluginsList.GetString(k, pluginName, sizeof(pluginName));

			ServerCommand("sm plugins unload %s", pluginName);
		}
	}
	g_ModePlugins.GetValue(modekey, pluginsList);
	for (int i = 0; i < pluginsList.Length; i++){
		char pluginName[255];
		pluginsList.GetString(i, pluginName, sizeof(pluginName));

		ServerCommand("sm plugins load %s", pluginName);
	}
	
	ServerCommand("sm plugins load_lock");

	strcopy(g_currentModeKey, sizeof(g_currentModeKey), modekey);

	ExecCurrentModeCfg();
}

void LoadGamemodeConfig() {
	char configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof(configPath), "configs/gamemodes/gamemodes.cfg");
	
	if(!FileExists(configPath))
	{
		SetFailState("Could not find a config file for gamemodes.");
	}

	KeyValues kv = new KeyValues("gamemodes");
	FileToKeyValues(kv, configPath);
	
	if (!KvGotoFirstSubKey(kv, false))
	{
		SetFailState("CFG File not found: %s", configPath);
		CloseHandle(kv);
	}

	g_ModePlugins = new StringMap();
	char first[256];

	do {
		char buffer[2][128];
		KvGetSectionName(kv, buffer[0], sizeof(buffer[]));
		KvGetString(kv, NULL_STRING, buffer[1], sizeof(buffer[]));

		char key[256];
		ImplodeStrings(buffer, sizeof(buffer), ";", key, sizeof(key));

		// reader
		char line[192];
		File file;
		ArrayList pluginList;
		
		// read plugins each mode
		char pluginsListPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, pluginsListPath, sizeof(pluginsListPath), "configs/gamemodes/%s_plugins.ini", buffer[0]);

		file = OpenFile(pluginsListPath, "r");
		pluginList = new ArrayList(ByteCountToCells(255));

		if(file != INVALID_HANDLE) {
			while (!file.EndOfFile()) {
				if(!file.ReadLine(line, sizeof(line))) {
					break;
				}
				
				TrimString(line);
				if(strlen(line) > 0) {
					pluginList.PushString(line);
				}
			}

			file.Close();
		} else {
			LogError("[SM] no plugin list file found for %s (configs/gamemodes/%s_plugins.ini)", buffer[1], buffer[0]);
		}

		g_ModePlugins.SetValue(key, pluginList);

		if (!first[0])
		{
			strcopy(first, sizeof(first), key);
		}
	} while (KvGotoNextKey(kv, false));

	ChangeGameMode(first);
}

Menu CreateModeMenu()
{
	Menu menu = new Menu(MenuHandler_Mode);
	menu.SetTitle("更换模式:");
	StringMapSnapshot snap = g_ModePlugins.Snapshot();
	char key[256];
	char buffer[2][128];
	for (int i = 0; i < snap.Length; i++)
	{
		snap.GetKey(i, key, sizeof(key));
		ExplodeString(key, ";", buffer, sizeof(buffer), sizeof(buffer[]));
		menu.AddItem(key, buffer[1], StrEqual(key, g_currentModeKey) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}
	
	menu.ExitBackButton = true;

	return menu;
}

public int MenuHandler_Mode(Menu menu, MenuAction action, int param1, int selection)
{
	switch(action) {
		case MenuAction_Select:
		{
			char key[256];
			GetMenuItem(menu, selection, key, sizeof(key));
			ChangeGameMode(key);
		}
	}
}

// Add menu to adminMenu
public void OnAdminMenuCreated(Handle topmenu)
{
	TopMenuObject adminServerMenu = FindTopMenuCategory(topmenu, ADMINMENU_SERVERCOMMANDS);

	if (adminServerMenu != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(topmenu, "Gamemode Manager", TopMenuObject_Item, GamemodeAdminMenuHandler, adminServerMenu, "sm_gamemodemenu", ADMFLAG_CONFIG);
	}
}

public void GamemodeAdminMenuHandler(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int client, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "切换模式");
	}
	else if (action == TopMenuAction_SelectOption)
	{
		CreateModeMenu().Display(client, MENU_TIME_FOREVER);
	}
}