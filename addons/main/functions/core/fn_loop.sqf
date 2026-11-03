/*
    SAI_fnc_loop
    Main scheduler. Every SAI_tick seconds evaluates every valid local AI group.
    Work is spread across the tick so large missions don't hitch.
*/
while {true} do {
    private _tick = (missionNamespace getVariable ["SAI_tick", 3]) max 1;
    if (missionNamespace getVariable ["SAI_enabled", true]) then {
        private _groups = allGroups select { [_x] call SAI_fnc_isValidGroup };
        private _delay = if (_groups isEqualTo []) then {0} else {(_tick / count _groups) min 0.2};
        {
            if (!isNull _x) then { [_x] call SAI_fnc_groupBrain };
            if (_delay > 0) then { sleep _delay };
        } forEach _groups;
    };
    sleep _tick;
};
