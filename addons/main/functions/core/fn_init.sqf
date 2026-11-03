/*
    SAI_fnc_init (on CBA_settingsInitialized)
    Starts the Smart AI manager. Runs on every machine (server, headless
    clients, players); each machine only drives the AI groups local to it.
*/
if (!isNil "SAI_running") exitWith {};
SAI_running = true;
SAI_groupCounter = 0;
SAI_hasACEMedical = isClass (configFile >> "CfgPatches" >> "ace_medical");

[] spawn SAI_fnc_loop;
[] spawn SAI_fnc_vehLoop;
if (isServer) then { [] spawn SAI_fnc_commanderLoop };
["Smart AI initialized (ACE medical: %1)", SAI_hasACEMedical] call SAI_fnc_log;
