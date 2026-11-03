/* SAI_fnc_vehBrain - per-vehicle decisions (called from SAI_fnc_vehLoop) */
params ["_veh"];
if !(_veh getVariable ["SAI_vinit", false]) then { [_veh] call SAI_fnc_vehInit };
private _type = _veh getVariable ["SAI_vtype", "other"];
if (_type == "other") exitWith {};
private _grp = group effectiveCommander _veh;

if (_type != "heli") then { [_grp, _veh] call SAI_fnc_vehicleBrain };
if (_veh getVariable ["SAI_bailed", false]) exitWith {};

private _enemies = [_grp, 2500, 40] call SAI_fnc_knownEnemies;
if (SAI_vehDismount) then { [_veh, _grp, _enemies, _type] call SAI_fnc_vehTransport };
switch (_type) do {
    case "armor":     { [_veh, _grp, _enemies, 700] call SAI_fnc_vehCombat };
    case "ifv":       { [_veh, _grp, _enemies, 450] call SAI_fnc_vehCombat };
    case "car_armed": { [_veh, _grp, _enemies, 350] call SAI_fnc_vehCombat };
    case "heli":      { if (SAI_heli) then { [_veh, _grp, _enemies] call SAI_fnc_vehHeli } };
};
