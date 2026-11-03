/* SAI_fnc_debugMarker - local map marker showing each group's tactical state */
params ["_grp", "_state"];
private _name = format ["SAI_dbg_%1_%2", clientOwner, _grp getVariable ["SAI_id", 0]];
if (markerType _name == "") then {
    createMarkerLocal [_name, getPosATL leader _grp];
    _name setMarkerTypeLocal "mil_dot";
    _grp addEventHandler ["Deleted", compile format ["deleteMarkerLocal '%1'", _name]];
};
_name setMarkerPosLocal (getPosATL leader _grp);
_name setMarkerColorLocal (switch (_state) do {
    case "ENGAGED":     {"ColorRed"};
    case "FLANKING":    {"ColorOrange"};
    case "FALLBACK":    {"ColorPink"};
    case "SEARCH":      {"ColorYellow"};
    case "REINFORCING": {"ColorBlue"};
    case "ALERT":       {"ColorKhaki"};
    default             {"ColorGreen"};
});
_name setMarkerTextLocal format ["%1 %2 (%3)", groupId _grp, _state, {alive _x} count units _grp];
