/*
    SAI_fnc_flank
    Classic "fix and flank": the base-of-fire team (with the machine gunners)
    suppresses, the manoeuvre team moves around the side with the most
    cover / least exposure and assaults from an angle.
    Returns true if a flank was started.
*/
params ["_grp", "_units", "_ePos"];
private _leader = leader _grp;
private _now = time;
private _gPos = getPosATL _leader;
private _dist = _gPos distance2D _ePos;
private _dirToEnemy = _gPos getDir _ePos;
private _eEye = (AGLToASL _ePos) vectorAdd [0, 0, 1.6];

// Pick the better side
private _best = [];
private _bestScore = -1e9;
{
    private _fp = _ePos getPos [((_dist * 0.55) max 40) min 160, (_dirToEnemy + 180) + _x * (65 + random 20)];
    if (!surfaceIsWater _fp) then {
        private _mid = _gPos getPos [(_gPos distance2D _fp) / 2, _gPos getDir _fp];
        private _cover = count (nearestTerrainObjects [_mid, ["TREE", "BUSH", "SMALL TREE", "ROCK", "ROCKS", "WALL", "BUILDING", "HOUSE", "HIDE"], 40, false, true]);
        private _concealed = 0;
        {
            _concealed = _concealed + (1 - ([objNull, "VIEW"] checkVisibility [_eEye, (AGLToASL _x) vectorAdd [0, 0, 1.2]]));
        } forEach [_mid, _fp];
        private _score = (_cover min 30) + _concealed * 15 + random 5;
        if (_score > _bestScore) then { _bestScore = _score; _best = _fp };
    };
} forEach [-1, 1];
if (_best isEqualTo []) exitWith { _grp setVariable ["SAI_nextFlank", _now + 30]; false };

// Split the group
private _pool = (_units - [_leader]) select {
    vehicle _x == _x && {(_x getVariable ["SAI_busyUntil", 0]) < _now} && {_x checkAIFeature "PATH"} && {lifeState _x != "INCAPACITATED"}
};
private _mgs = _pool select { [_x] call SAI_fnc_isMG };
private _riflemen = _pool - _mgs;
private _teamSize = (floor (count _units / 2)) max 2;
if (count _riflemen < 2) exitWith { _grp setVariable ["SAI_nextFlank", _now + 30]; false };

private _flankTeam = _riflemen select [0, _teamSize];
private _baseTeam = _units - _flankTeam;

_grp setVariable ["SAI_flankUntil", _now + 100];
_grp setVariable ["SAI_nextFlank", _now + 150 + random 90];
_grp setVariable ["SAI_flankPos", _best];
{ _x assignTeam "RED" } forEach _flankTeam;
{ _x assignTeam "BLUE" } forEach _baseTeam;

// Base of fire: MGs first, up to 3 shooters, staggered
if (SAI_suppression) then {
    private _shooters = ((_mgs + (_baseTeam - _mgs)) - [_leader]) select [0, 3];
    {
        [_x, AGLToASL _ePos, _forEachIndex] spawn {
            params ["_u", "_p", "_i"];
            sleep (_i * 1.5);
            [_u, _p] call SAI_fnc_suppressFire;
        };
    } forEach _shooters;
};

[_flankTeam, _best, _ePos, _grp] spawn SAI_fnc_flankMove;
["Group %1 flanking with %2 men", groupId _grp, count _flankTeam] call SAI_fnc_log;
true
