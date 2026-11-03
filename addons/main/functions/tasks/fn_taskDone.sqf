/* SAI_fnc_taskDone - finish a task and tell the commander the group is free again */
params ["_grp", "_id"];
if (isNull _grp) exitWith {};
if ((_grp getVariable ["SAI_state", ""]) == "MANOEUVRE") then {
    [_grp] call SAI_fnc_clearTempWPs;
    _grp setVariable ["SAI_state", "ALERT", true];
};
private _task = _grp getVariable ["SAI_task", []];
if (_task isNotEqualTo [] && {(_task select 0) == _id}) then {
    _grp setVariable ["SAI_task", [], true];
};
