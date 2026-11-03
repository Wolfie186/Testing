/* SAI_fnc_vehDismount (spawn) - drive into cover, unload, troops deploy; trucks leave, IFVs give overwatch */
params ["_veh", "_crewGrp", "_cgs", "_ePos", "_type"];
private _cmdr = effectiveCommander _veh;
if (canMove _veh && {alive driver _veh}) then {
    private _spot = [_veh, _ePos, 120, "HIDDEN"] call SAI_fnc_vehFindPos;
    if (_spot isNotEqualTo []) then {
        _cmdr doMove _spot;
        private _t = time + 25;
        waitUntil { sleep 1; !alive _veh || {(_veh distance2D _spot) < 10} || {time > _t} };
    };
    _cmdr doMove (getPosATL _veh); // halt
    sleep 2;
};
if (!alive _veh) exitWith {};
if (SAI_smoke && {_type == "ifv"}) then { [_veh] call SAI_fnc_vehSmoke };
{
    private _g = _x;
    if (_g == _crewGrp) then {
        {
            if (vehicle _x == _veh && {((assignedVehicleRole _x) param [0, ""]) == "Cargo"}) then {
                unassignVehicle _x; [_x] orderGetIn false; doGetOut _x;
            };
        } forEach units _g;
    } else {
        _g leaveVehicle _veh;
        { if (vehicle _x == _veh) then { [_x] orderGetIn false; doGetOut _x } } forEach units _g;
    };
    _g setBehaviour "COMBAT";
    [_g, _ePos] spawn {
        params ["_g", "_p"];
        sleep 4;
        { if (alive _x && {isNull objectParent _x}) then { [_x, AGLToASL _p, random 2] spawn SAI_fnc_takeCover } } forEach units _g;
    };
    ["%1 dismounts from %2", groupId _g, typeOf _veh] call SAI_fnc_log;
} forEach _cgs;
sleep 8;
if (_type == "transport" && {alive _veh} && {canMove _veh}) then {
    _cmdr doMove ((getPosATL _veh) getPos [400, _ePos getDir _veh]);
};
_veh setVariable ["SAI_vstate", "IDLE"];
