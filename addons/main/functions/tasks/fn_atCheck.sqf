/*
    SAI_fnc_atCheck
    AT gunners go after known enemy armour: move to a firing spot that sees the
    vehicle, prefer its side/rear, then engage. Riflemen keep its infantry busy.
*/
params ["_grp", "_units", "_enemies"];
private _now = time;
if (_now < _grp getVariable ["SAI_nextAT", 0]) exitWith {};
_grp setVariable ["SAI_nextAT", _now + 15];
private _armor = _enemies select { (_x select 0) < 600 && {([_x select 1] call SAI_fnc_targetType) in ["armor", "car"]} && {canMove (_x select 1) || {canFire (_x select 1)}} };
if (_armor isEqualTo []) exitWith {};
(_armor select 0) params ["_d", "_veh"];

{
    if (vehicle _x == _x && {([_x] call SAI_fnc_launcherType) == "AT"} && {(_x getVariable ["SAI_busyUntil", 0]) < _now} && {lifeState _x != "INCAPACITATED"}) then {
        [_x, _veh] spawn {
            params ["_u", "_veh"];
            _u setVariable ["SAI_busyUntil", time + 40];
            private _vPos = getPosATL _veh;
            private _vDir = getDir _veh;
            // find a spot (within 40 m) that sees the vehicle, scoring flank/rear aspect higher
            private _best = [];
            private _bestScore = -1e9;
            for "_i" from 0 to 11 do {
                private _p = (getPosATL _u) getPos [5 + random 35, random 360];
                if (!surfaceIsWater _p && {(_p distance2D _vPos) > 60} && {(_p distance2D _vPos) < 450}) then {
                    private _vis = [_u, "VIEW", _veh] checkVisibility [(AGLToASL _p) vectorAdd [0, 0, 1.3], (getPosASL _veh) vectorAdd [0, 0, 1.5]];
                    if (_vis > 0.5) then {
                        private _aspect = abs (((_vPos getDir _p) - _vDir + 540) % 360 - 180); // 0 = front, 180 = rear
                        private _score = _aspect - ((_p distance2D getPosATL _u) * 1.5);
                        if (_score > _bestScore) then { _bestScore = _score; _best = _p };
                    };
                };
            };
            if (_best isNotEqualTo [] && {_u checkAIFeature "PATH"}) then {
                _u doMove _best;
                private _t = time + 20;
                waitUntil { sleep 0.5; !alive _u || {_u distance2D _best < 2} || {time > _t} };
                doStop _u;
            };
            if (alive _u && {alive _veh}) then {
                _u selectWeapon secondaryWeapon _u;
                _u setUnitPos "MIDDLE";
                _u reveal [_veh, 4];
                _u doTarget _veh;
                sleep 3;
                _u doFire _veh;
                sleep 12;
            };
            if (alive _u) then {
                _u setUnitPos "AUTO";
                _u setVariable ["SAI_busyUntil", 0];
                if (leader _u != _u) then { _u doFollow leader _u };
            };
        };
    };
} forEach _units;
