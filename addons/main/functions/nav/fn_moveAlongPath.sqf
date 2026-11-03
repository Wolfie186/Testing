/*
    SAI_fnc_moveAlongPath
    Turns a tactical path into a chain of group waypoints.
    Params: group, path (AGL list), final waypoint type, behaviour, speed, final statement
*/
params ["_grp", "_path", ["_finalType", "MOVE"], ["_behaviour", "AWARE"], ["_speed", "NORMAL"], ["_statement", ""]];
if (_path isEqualTo []) exitWith {};
[_grp] call SAI_fnc_clearTempWPs;
private _wps = [];
{
    private _last = _forEachIndex == (count _path - 1);
    private _wp = _grp addWaypoint [_x, 0];
    _wp setWaypointType (["MOVE", _finalType] select _last);
    _wp setWaypointBehaviour _behaviour;
    _wp setWaypointSpeed _speed;
    _wp setWaypointCompletionRadius ([15, 25] select _last);
    if (_last && {_statement != ""}) then { _wp setWaypointStatements ["true", _statement] };
    _wps pushBack _wp;
} forEach _path;
_grp setVariable ["SAI_tempWPs", _wps];
_grp setCurrentWaypoint (_wps select 0);

if (SAI_debug && {hasInterface}) then {
    private _name = format ["SAI_path_%1_%2", clientOwner, _grp getVariable ["SAI_id", 0]];
    deleteMarkerLocal _name;
    private _line = [];
    { _line append [_x select 0, _x select 1] } forEach ([getPosATL leader _grp] + _path);
    if (count _line >= 4) then {
        createMarkerLocal [_name, _path select 0];
        _name setMarkerShapeLocal "POLYLINE";
        _name setMarkerPolylineLocal _line;
        _name setMarkerColorLocal "ColorOrange";
    };
};
