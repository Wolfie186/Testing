/*
    SAI_fnc_suppressFire (spawn)
    Pin the enemy down: fire bursts into an area instead of waiting for a clean shot.
*/
params ["_unit", "_target"];
if (!alive _unit || {vehicle _unit != _unit} || {primaryWeapon _unit == ""}) exitWith {};
if (lifeState _unit == "INCAPACITATED") exitWith {};
if ((_unit ammo primaryWeapon _unit) == 0 && {primaryWeaponMagazine _unit isEqualTo []}) exitWith {};

private _pos = if (_target isEqualType objNull) then { getPosASL _target } else { _target };
_pos = _pos vectorAdd [(random 6) - 3, (random 6) - 3, 0.7 + random 0.6];
private _duration = [5, 9] select ([_unit] call SAI_fnc_isMG);

private _prevBusy = _unit getVariable ["SAI_busyUntil", 0];
_unit setVariable ["SAI_busyUntil", _prevBusy max (time + _duration + 2)];
_unit selectWeapon primaryWeapon _unit;
_unit doWatch (ASLToAGL _pos);
sleep (0.5 + random 0.8);
if (!alive _unit) exitWith {};
_unit doSuppressiveFire _pos;
_unit suppressFor _duration;
sleep _duration;
if (alive _unit) then { _unit doWatch objNull };
_unit setVariable ["SAI_busyUntil", _prevBusy];
