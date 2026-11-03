/* SAI_fnc_vehOnHit ("Hit" on a vehicle) - remember the shooter, relocate */
params ["_veh", "_source", "_damage", "_instigator"];
if (!local _veh || {!SAI_enabled} || {!SAI_vehicles} || {!alive _veh}) exitWith {};
if ((crew _veh) findIf {isPlayer _x} != -1) exitWith {};
private _src = [_source, _instigator] select (!isNull _instigator);
if (isNull _src || {_damage < 0.05}) exitWith {};
(group effectiveCommander _veh) reveal [_src, 2.5];
_veh setVariable ["SAI_scoot", true];
if (damage _veh > 0.3) then { [_veh] call SAI_fnc_vehSmoke };
