/* SAI_fnc_reportContacts - a group sends what it knows to its side's commander (server). Throttled. */
params ["_grp", "_enemies"];
if (!SAI_commander || {time < _grp getVariable ["SAI_nextReport", 0]}) exitWith {};
_grp setVariable ["SAI_nextReport", time + 5];
private _contacts = (_enemies select [0, 12]) apply { [_x select 1, _x select 2, _x select 3] };
if (_contacts isEqualTo []) exitWith {};
if (isServer) then {
    [side _grp, _contacts] call SAI_fnc_cmdReport;
} else {
    [side _grp, _contacts] remoteExecCall ["SAI_fnc_cmdReport", 2];
};
