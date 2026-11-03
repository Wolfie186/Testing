/*
    SAI_fnc_vehTransport
    Troops are not driven into the kill zone: when the enemy is close the vehicle
    pulls into dead ground and the passengers dismount there.
*/
params ["_veh", "_grp", "_enemies", "_type"];
if (_type in ["armor", "heli"]) exitWith {};
private _cargo = ((fullCrew [_veh, "", false]) select { (_x select 1) == "cargo" || {_x select 4} }) apply { _x select 0 };
_cargo = _cargo select { alive _x && {!isPlayer _x} };
if (_cargo isEqualTo []) exitWith { _veh setVariable ["SAI_dismounted", false] };
if (_veh getVariable ["SAI_dismounted", false] || {_enemies isEqualTo []}) exitWith {};
(_enemies select 0) params ["_d", "_tgt", "_ePos"];
private _thr = switch (_type) do { case "transport": {700}; case "car_armed": {500}; default {400} };
if (_d > _thr) exitWith {};
private _cgs = [];
{ _cgs pushBackUnique group _x } forEach _cargo;
_cgs = _cgs select { (units _x findIf {isPlayer _x}) == -1 && {!(_x getVariable ["SAI_disable", false])} };
if (_cgs isEqualTo []) exitWith {};
_veh setVariable ["SAI_dismounted", true];
[_veh, _grp, _cgs, _ePos, _type] spawn SAI_fnc_vehDismount;
