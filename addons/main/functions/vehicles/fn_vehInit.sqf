/*
    SAI_fnc_vehInit - classify the vehicle and hook its event handlers.
    Types: armor (tank), ifv (APC/IFV with troops), car_armed, transport, heli, other
*/
params ["_veh"];
_veh setVariable ["SAI_vinit", true];
private _cfg = configOf _veh;
private _cargoSeats = getNumber (_cfg >> "transportSoldier");
private _isWeapon = { params ["_w"]; private _l = toLower _w; (["smoke", "horn", "flare", "laserdesignator", "searchlight"] findIf {_x in _l}) == -1 };
private _armed = (([[-1]] + allTurrets [_veh, false]) findIf { ((_veh weaponsTurret _x) findIf { [_x] call _isWeapon }) != -1 }) != -1;
private _type = switch (true) do {
    case (_veh isKindOf "Helicopter"): {"heli"};
    case (_veh isKindOf "Tank"): { ["armor", "ifv"] select (_cargoSeats >= 4) };
    case (_veh isKindOf "Wheeled_APC_F"): {"ifv"};
    case (_veh isKindOf "Car"): { ["transport", "car_armed"] select _armed };
    default {"other"};
};
_veh setVariable ["SAI_vtype", _type];
_veh setVariable ["SAI_vstate", "IDLE"];
_veh setVariable ["SAI_mainGun", (_veh weaponsTurret [0]) param [0, ""]];

_veh addEventHandler ["IncomingMissile", { _this call SAI_fnc_vehOnIncoming }];
_veh addEventHandler ["Hit", { _this call SAI_fnc_vehOnHit }];
_veh addEventHandler ["Fired", {
    params ["_veh", "_weapon"];
    if (_weapon == (_veh getVariable ["SAI_mainGun", ""])) then { _veh setVariable ["SAI_shots", (_veh getVariable ["SAI_shots", 0]) + 1] };
}];
["Vehicle %1 classified as %2", typeOf _veh, _type] call SAI_fnc_log;
