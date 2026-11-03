/*
    SAI_fnc_debugTest
    Quick sandbox fight. From the debug console (local exec):
        [] call SAI_fnc_debugTest;            // enemy squad 350 m ahead
        [500, east, true] call SAI_fnc_debugTest; // also spawn a friendly AI squad next to you
*/
params [["_dist", 350], ["_enemySide", east], ["_withFriends", false]];
if (!isServer) exitWith { systemChat "SAI_fnc_debugTest must run on the server (or in SP)" };
SAI_debug = true;

private _squadCfg = {
    params ["_side"];
    switch (_side) do {
        case west:        { configFile >> "CfgGroups" >> "West" >> "BLU_F" >> "Infantry" >> "BUS_InfSquad" };
        case independent: { configFile >> "CfgGroups" >> "Indep" >> "IND_F" >> "Infantry" >> "HAF_InfSquad" };
        default           { configFile >> "CfgGroups" >> "East" >> "OPF_F" >> "Infantry" >> "OIA_InfSquad" };
    };
};
private _origin = getPosATL player;
private _ePos = _origin getPos [_dist, getDir player];
private _enemy = [_ePos, _enemySide, [_enemySide] call _squadCfg] call BIS_fnc_spawnGroup;
private _wp = _enemy addWaypoint [_origin, 50];
_wp setWaypointType "SAD";
systemChat format ["[SAI] Enemy squad (%1 men) spawned %2 m ahead", count units _enemy, _dist];

if (_withFriends) then {
    private _fSide = side group player;
    private _friends = [_origin getPos [25, (getDir player) + 180], _fSide, [_fSide] call _squadCfg] call BIS_fnc_spawnGroup;
    systemChat format ["[SAI] Friendly squad (%1 men) spawned behind you", count units _friends];
};
_enemy
