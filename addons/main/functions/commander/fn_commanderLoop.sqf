/* SAI_fnc_commanderLoop (server) - one commander per side, plans every SAI_cmdTick seconds */
if (!isServer) exitWith {};
SAI_picture = createHashMap;
SAI_recentTasks = createHashMap;
SAI_taskCounter = 0;
while {true} do {
    sleep ((missionNamespace getVariable ["SAI_cmdTick", 10]) max 5);
    if (SAI_enabled && {SAI_commander}) then {
        { [_x] call SAI_fnc_cmdPlan; sleep 0.1 } forEach [west, east, independent];
    };
};
