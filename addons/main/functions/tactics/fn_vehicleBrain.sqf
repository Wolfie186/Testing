/*
    SAI_fnc_vehicleBrain
    Crews of disabled ground vehicles bail out (the gunner keeps fighting if the gun works),
    and dismounted crews then use the normal infantry tactics.
*/
params ["_grp", "_veh"];
if (_veh isKindOf "Air" || {_veh isKindOf "Ship"} || {_veh isKindOf "StaticWeapon"}) exitWith {};
if (_veh getVariable ["SAI_bailed", false]) exitWith {};
if (canMove _veh && {damage _veh < 0.75} && {fuel _veh > 0}) exitWith {};

_veh setVariable ["SAI_bailed", true];
private _keepGunner = canFire _veh && {damage _veh < 0.75} && {alive gunner _veh};
private _crew = (crew _veh) select {group _x == _grp && {alive _x}};
{
    if !(_keepGunner && {_x == gunner _veh}) then {
        unassignVehicle _x;
        [_x] orderGetIn false;
        [_x] allowGetIn false;
        doGetOut _x;
    };
} forEach _crew;
["Group %1 bailing out of disabled %2", groupId _grp, typeOf _veh] call SAI_fnc_log;
