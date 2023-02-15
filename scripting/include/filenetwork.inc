#if defined _filenetwork_included
	#endinput
#endif
#define _filenetwork_included

#pragma semicolon 1
#pragma newdecls required

/**
 * Called when parsing is started.
 */
typeset FileNet_SendFileResult
{
	/**
	 * @param client	Client index
	 * @param file		Filepath of sent file
	 * @param success	If the file was sent
	 * @param data		Value that was passed
	 * 
	 * @noreturn
	 */
	function void(int client, const char[] file, bool success, any data);

	/**
	 * @param client	Client index
	 * @param file		Filepath of sent file
	 * @param success	If the file was sent
	 * 
	 * @noreturn
	 */
	function void(int client, const char[] file, bool success);
};

/**
 * If a file is currently in queue for that client
 * 
 * @param client	Client index
 * @param file		Filepath of sent file
 * 
 * @return			True if the file in is queue, false otherwise
 */
native bool FileNet_IsFileInWaitingList(int client, const char[] file);

/**
 * Adds a file in a queue to be sent over to the client
 * 
 * @param client	Client index
 * @param file		Filepath of sent file
 * @param callback	Optional callback when file is done
 * @param data		Optional value to pass to the callback function
 * 
 * @error			Invalid client index, client is not in game, or a fake client
 * 
 * @return			True if the file is now queued to be sent, false otherwise
 */
native bool FileNet_SendFile(int client, const char[] file, FileNet_SendFileResult callback = INVALID_FUNCTION, any data = 0);

public SharedPlugin __pl_filenetwork =
{
	name = "filenetwork",
	file = "filenetwork.smx",
	#if defined REQUIRE_PLUGIN
		required = 1,
	#else
		required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_filenetwork_SetNTVOptional()
{
	MarkNativeAsOptional("FileNet_SendFile");
	MarkNativeAsOptional("FileNet_IsFileInWaitingList");
}
#endif
