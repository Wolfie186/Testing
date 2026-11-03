/* SAI_fnc_onKilled ("Killed" event handler) - squad mates react to a loss */
params ["_unit", "_killer", "_instigator"];
private _grp = _unit getVariable ["SAI_group", grpNull];
if (isNull _grp || {!local _grp} || {!SAI_enabled}) exitWith {};
private _src = [_killer, _instigator] select (!isNull _instigator);
if (isNull _src || {_src == _unit} || {(side _grp getFriend side group _src) >= 0.6}) exitWith {};

_grp reveal [_src, 1];
private _srcPos = (getPosASL _src) vectorAdd [(random 20) - 10, (random 20) - 10, 0];
// Nearby mates go to cover
{
    if (alive _x && {vehicle _x == _x} && {_x distance _unit < 30} && {random 1 < 0.6}) then {
        [_x, _srcPos, random 1.5] spawn SAI_fnc_takeCover;
    };
} forEach units _grp;
