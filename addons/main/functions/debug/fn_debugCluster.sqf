/* SAI_fnc_debugCluster - commander's view: enemy elements and their predicted movement (local markers on the server/host) */
params ["_side", "_idx", "_cluster"];
if (!hasInterface) exitWith {};
_cluster params ["_cPos", "_strength", "_lastT", "_vel"];
private _name = format ["SAI_cl_%1_%2", _side, _idx];
if (markerType _name == "") then {
    createMarkerLocal [_name, _cPos];
    _name setMarkerTypeLocal "mil_warning";
};
_name setMarkerPosLocal _cPos;
_name setMarkerColorLocal (switch (_side) do { case west: {"ColorBLUFOR"}; case east: {"ColorOPFOR"}; default {"ColorIndependent"} });
_name setMarkerTextLocal format ["%1 intel: str %2, %3 s ago, %4 m/s", _side, _strength, round (time - _lastT), (round ((vectorMagnitude (_vel + [0])) * 10)) / 10];
private _arrow = _name + "_v";
deleteMarkerLocal _arrow;
if ((vectorMagnitude (_vel + [0])) > 0.5) then {
    createMarkerLocal [_arrow, _cPos];
    _arrow setMarkerShapeLocal "POLYLINE";
    private _to = _cPos vectorAdd ((_vel + [0]) vectorMultiply 90);
    _arrow setMarkerPolylineLocal [_cPos select 0, _cPos select 1, _to select 0, _to select 1];
    _arrow setMarkerColorLocal "ColorYellow";
};
