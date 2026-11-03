/*
    SAI_fnc_grenadeCheck
    Enemy close and hiding behind cover / inside a building -> flush them out with a grenade.
*/
params ["_grp", "_units", "_enemies"];
private _now = time;
if (_now < _grp getVariable ["SAI_nextNade", 0]) exitWith {};
_grp setVariable ["SAI_nextNade", _now + 4];

private _done = false;
{
    if (_done) exitWith {};
    _x params ["_d", "_tgt", "_ePos", "_age"];
    if (_age < 20 && {_d < 80}) then {
        private _tPosASL = AGLToASL _ePos;
        private _thrower = objNull;
        {
            private _td = _x distance2D _ePos;
            if (
                isNull objectParent _x && {_td > 12} && {_td < 38}
                && {(_x getVariable ["SAI_busyUntil", 0]) < _now}
                && {lifeState _x != "INCAPACITATED"}
            ) exitWith { _thrower = _x };
        } forEach _units;

        if (!isNull _thrower) then {
            private _vis = [_thrower, "VIEW", _tgt] checkVisibility [eyePos _thrower, _tPosASL vectorAdd [0, 0, 1]];
            private _underRoof = (lineIntersectsSurfaces [_tPosASL vectorAdd [0, 0, 1], _tPosASL vectorAdd [0, 0, 15], _tgt, objNull, true, 1]) isNotEqualTo [];
            if ((_vis < 0.4 || {_underRoof} || {random 1 < 0.15}) && {[_thrower, _tPosASL] call SAI_fnc_throwGrenade}) then {
                _done = true;
                _grp setVariable ["SAI_nextNade", _now + 12 + random 15];
            };
        };
    };
} forEach _enemies;
