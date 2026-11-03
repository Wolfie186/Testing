/*
    SAI_fnc_shareIntel
    Radio contact report: nearby friendly groups learn roughly where the enemy is.
    (Knowledge is passed as a low "reveal" value - they still have to find and see the enemy.)
*/
params ["_grp", "_enemies"];
if (time < _grp getVariable ["SAI_nextIntel", 0]) exitWith {};
_grp setVariable ["SAI_nextIntel", time + 12];

private _leader = leader _grp;
private _payload = ((_enemies select {(_x select 3) < 20}) select [0, 8]) apply {
    [_x select 1, ((_leader knowsAbout (_x select 1)) min 1.5) max 0.5]
};
if (_payload isEqualTo []) exitWith {};

private _args = [side _grp, getPosATL _leader, SAI_intelRadius, _payload, _grp];
if (isMultiplayer) then {
    _args remoteExecCall ["SAI_fnc_receiveIntel", 0];
} else {
    _args call SAI_fnc_receiveIntel;
};
