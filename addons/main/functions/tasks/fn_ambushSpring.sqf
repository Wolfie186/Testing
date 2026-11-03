/* SAI_fnc_ambushSpring - open fire from the ambush: everybody shoots at once at the kill zone */
params ["_grp", ["_targetPos", []]];
if ((_grp getVariable ["SAI_state", ""]) != "AMBUSH") exitWith {};
_grp setVariable ["SAI_state", "ENGAGED", true];
_grp setCombatMode "RED";
_grp setBehaviour "COMBAT";
if (_targetPos isEqualTo []) then { _targetPos = (getPosATL leader _grp) getPos [100, _grp getVariable ["SAI_ambushDir", 0]] };
{
    if (alive _x) then {
        _x setVariable ["SAI_busyUntil", 0];
        _x setUnitPos "MIDDLE";
        _x doWatch objNull;
        if (SAI_suppression) then { [_x, AGLToASL _targetPos] spawn SAI_fnc_suppressFire };
    };
} forEach units _grp;
[units _grp] spawn {
    sleep 12;
    { if (alive _x) then { _x setUnitPos "AUTO"; if (leader _x != _x) then { _x doFollow leader _x } } } forEach (_this select 0);
};
["Group %1 springs the ambush!", groupId _grp] call SAI_fnc_log;
