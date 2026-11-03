/* SAI_fnc_onHit ("Hit" event handler) - wounded units get out of the line of fire */
params ["_unit", "_source", "_damage", "_instigator"];
if (!SAI_enabled || {!alive _unit} || {!local _unit} || {isPlayer _unit}) exitWith {};
if (!isNull objectParent _unit) exitWith {};
if !([group _unit] call SAI_fnc_isValidGroup) exitWith {};
private _src = [_source, _instigator] select (!isNull _instigator);
if (isNull _src || {_src == _unit}) exitWith {};

group _unit reveal [_src, 1.5];
_unit setVariable ["SAI_supp", 1];
_unit setVariable ["SAI_suppTime", time];
if (SAI_cover) then {
    _unit setVariable ["SAI_busyUntil", 0]; // getting shot overrides whatever we were doing
    [_unit, getPosASL _src] spawn SAI_fnc_takeCover;
};
