/*
    SAI_fnc_cmdReport (server)
    Adds contact reports to the side's battle picture and estimates each
    contact's velocity from successive sightings (used for prediction).
*/
params ["_side", "_contacts"];
if (!isServer) exitWith {};
private _pic = SAI_picture getOrDefault [_side, createHashMap, true];
{
    _x params ["_tgt", "_pos", "_age"];
    if (alive _tgt) then {
        private _k = hashValue _tgt;
        private _t = time - _age;
        private _old = _pic getOrDefault [_k, []];
        private _vel = [0, 0];
        private _base = [_pos, _t];
        if (_old isNotEqualTo []) then {
            _old params ["", "", "_ot", "_ov", "", "_ob"];
            _vel = _ov;
            _base = _ob;
            _ob params ["_bp", "_bt"];
            private _dt = _t - _bt;
            if (_dt > 4) then {
                private _v = [((_pos select 0) - (_bp select 0)) / _dt, ((_pos select 1) - (_bp select 1)) / _dt];
                _vel = [((_ov select 0) * 0.4) + ((_v select 0) * 0.6), ((_ov select 1) * 0.4) + ((_v select 1) * 0.6)];
                if ((vectorMagnitude (_vel + [0])) > 20) then { _vel = [0, 0] }; // bad estimate
                _base = [_pos, _t];
            };
        };
        if (_old isEqualTo [] || {_t >= (_old select 2)}) then {
            // [target, posAGL, time, velocity, type, velocityBaseline]
            _pic set [_k, [_tgt, _pos, _t, _vel, [_tgt] call SAI_fnc_targetType, _base]];
        };
    };
} forEach _contacts;
