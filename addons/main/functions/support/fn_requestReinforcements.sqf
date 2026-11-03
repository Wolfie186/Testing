/* SAI_fnc_requestReinforcements - outnumbered group calls for help over the radio */
params ["_grp", "_ePos"];
_grp setVariable ["SAI_nextReinforce", time + 180];
private _args = [side _grp, _ePos, _grp];
if (isMultiplayer) then {
    _args remoteExecCall ["SAI_fnc_handleReinforceRequest", 0];
} else {
    _args call SAI_fnc_handleReinforceRequest;
};
["Group %1 requests reinforcements", groupId _grp] call SAI_fnc_log;
