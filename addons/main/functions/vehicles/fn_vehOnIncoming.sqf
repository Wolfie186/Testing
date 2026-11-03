/* SAI_fnc_vehOnIncoming ("IncomingMissile") - smoke, counter-fire at the shooter, break line of sight */
params ["_veh", "_ammo", "_shooter", "_instigator"];
if (!local _veh || {!SAI_enabled} || {!SAI_vehicles}) exitWith {};
if ((crew _veh) findIf {isPlayer _x} != -1) exitWith {};
private _src = [_shooter, _instigator] select (!isNull _instigator);

if (_veh isKindOf "LandVehicle") then {
    [_veh] call SAI_fnc_vehSmoke;
    _veh setVariable ["SAI_scoot", true];
    if (!isNull _src) then {
        (group effectiveCommander _veh) reveal [_src, 3];
        if (alive gunner _veh) then { gunner _veh doTarget _src; gunner _veh doFire _src };
        if (canMove _veh && {(_veh getVariable ["SAI_vstate", ""]) != "MOVING"} && {[group effectiveCommander _veh] call SAI_fnc_canMove}) then {
            [_veh, getPosATL _src, "BACKOFF"] spawn SAI_fnc_vehReposition;
        };
    };
} else {
    if (!isNull _src) then { _veh setVariable ["SAI_aaThreat", [getPosATL _src, time]] };
};
