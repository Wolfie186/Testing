/*
    SAI_fnc_initGroup - one-time setup for a group.
    Every group gets a "personality" [aggression, caution, discipline] (0..1),
    so two squads in the same situation won't necessarily do the same thing.
    Mission override:  _grp setVariable ["SAI_profile", [0.9, 0.2, 0.8], true];
*/
params ["_grp"];
SAI_groupCounter = SAI_groupCounter + 1;
_grp setVariable ["SAI_init", true];
_grp setVariable ["SAI_id", SAI_groupCounter];
if (isNil {_grp getVariable "SAI_state"}) then { _grp setVariable ["SAI_state", "SAFE", true] };
_grp setVariable ["SAI_startSize", {alive _x} count units _grp];
_grp setVariable ["SAI_lastContact", -1e6];
_grp setVariable ["SAI_nextFlank", time + 10 + random 10];
if (isNil {_grp getVariable "SAI_profile"}) then {
    private _avgSkill = 0;
    { _avgSkill = _avgSkill + skill _x } forEach units _grp;
    _avgSkill = _avgSkill / ((count units _grp) max 1);
    _grp setVariable ["SAI_profile", [
        0.25 + random 0.75,                         // aggression
        0.25 + random 0.75,                         // caution
        ((0.3 + random 0.4) + _avgSkill * 0.3) min 1 // discipline (better troops hold together)
    ]];
};
{ [_x] call SAI_fnc_initUnit } forEach units _grp;
