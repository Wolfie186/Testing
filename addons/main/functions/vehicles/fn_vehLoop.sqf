/* SAI_fnc_vehLoop - drives every AI-crewed vehicle local to this machine */
while {true} do {
    sleep ((missionNamespace getVariable ["SAI_tick", 3]) max 2);
    if (SAI_enabled && {SAI_vehicles}) then {
        {
            private _c = effectiveCommander _x;
            if (
                alive _x && {local _x} && {!isNull _c} && {alive _c}
                && {(crew _x) findIf {isPlayer _x} == -1}
                && {[group _c] call SAI_fnc_isValidGroup}
            ) then { [_x] call SAI_fnc_vehBrain };
            sleep 0.05;
        } forEach (vehicles select { (_x isKindOf "LandVehicle" || {_x isKindOf "Helicopter"}) && {!(_x isKindOf "StaticWeapon")} });
    };
};
