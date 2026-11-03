/*
    SAI_fnc_ambushSetup
    Line ambush across the kill zone: men spread out 7 m apart, go prone,
    hold fire. SAI_fnc_ambushSpring opens fire when the enemy walks in,
    spots us, or shoots at us.
*/
params ["_grp", "_pos", "_dir"];
private _units = (units _grp) select {alive _x && {vehicle _x == _x}};
_grp setCombatMode "GREEN";
_grp setBehaviour "STEALTH";
_grp setVariable ["SAI_state", "AMBUSH", true];
_grp setVariable ["SAI_ambushUntil", time + 600];
_grp setVariable ["SAI_ambushDir", _dir];
private _watch = _pos getPos [120, _dir];
{
    private _n = floor ((_forEachIndex + 1) / 2);
    private _off = _n * 7 * ([1, -1] select (_forEachIndex % 2 == 1));
    private _p = _pos getPos [_off, _dir + 90];
    _x setVariable ["SAI_busyUntil", time + 600];
    if (_x checkAIFeature "PATH") then { _x doMove _p };
} forEach _units;
[_units, _watch] spawn {
    params ["_units", "_watch"];
    sleep 20;
    { if (alive _x) then { doStop _x; _x setUnitPos "DOWN"; _x doWatch _watch } } forEach _units;
};
["Group %1 set an ambush", groupId _grp] call SAI_fnc_log;
