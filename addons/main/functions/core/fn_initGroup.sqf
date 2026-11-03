/* SAI_fnc_initGroup - one-time setup for a group */
params ["_grp"];
SAI_groupCounter = SAI_groupCounter + 1;
_grp setVariable ["SAI_init", true];
_grp setVariable ["SAI_id", SAI_groupCounter];
_grp setVariable ["SAI_state", "SAFE"];
_grp setVariable ["SAI_startSize", {alive _x} count units _grp];
_grp setVariable ["SAI_lastContact", -1e6];
_grp setVariable ["SAI_nextFlank", time + 10 + random 10];
{ [_x] call SAI_fnc_initUnit } forEach units _grp;
