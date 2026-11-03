// CBA Extended Event Handlers: preInit
call SAI_fnc_settings;
// Start only once CBA has synchronised the settings (server values in MP)
["CBA_settingsInitialized", { call SAI_fnc_init }] call CBA_fnc_addEventHandler;
