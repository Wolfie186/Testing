/* SAI_fnc_receiveIntel - executed on every machine; applies intel to local groups in radio range */
params ["_side", "_pos", "_radius", "_payload", "_src"];
if (!SAI_enabled || {!SAI_intel}) exitWith {};
private _targets = allGroups select {
    _x != _src && {side _x == _side} && {[_x] call SAI_fnc_isValidGroup} && {(leader _x) distance2D _pos < _radius}
};
if (_targets isEqualTo []) exitWith {};

[_targets, _payload] spawn {
    params ["_targets", "_payload"];
    sleep (2 + random 4); // radio delay
    {
        private _g = _x;
        if (!isNull _g) then {
            { _x params ["_tgt", "_k"]; if (alive _tgt) then { _g reveal [_tgt, _k] } } forEach _payload;
            if ((_g getVariable ["SAI_state", "SAFE"]) == "SAFE") then {
                _g setVariable ["SAI_state", "ALERT"];
                _g setVariable ["SAI_lastContact", time];
                _g setBehaviour "AWARE";
            };
        };
    } forEach _targets;
};
