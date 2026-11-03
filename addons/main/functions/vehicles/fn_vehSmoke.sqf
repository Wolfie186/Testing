/* SAI_fnc_vehSmoke - fire the vehicle's smoke launchers (any turret, vanilla or mod names containing "smoke") */
params ["_veh"];
if (!SAI_smoke || {time < _veh getVariable ["SAI_nextSmoke", 0]}) exitWith {false};
private _done = false;
{
    private _turret = _x;
    if (!_done) then {
        private _w = (_veh weaponsTurret _turret) select { "smoke" in toLower _x };
        if (_w isNotEqualTo []) then {
            [_veh, _w select 0, _turret] call BIS_fnc_fire;
            _done = true;
        };
    };
} forEach ([[-1]] + allTurrets [_veh, false]);
if (_done) then { _veh setVariable ["SAI_nextSmoke", time + 30] };
_done
