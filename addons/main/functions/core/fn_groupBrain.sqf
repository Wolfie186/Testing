/*
    SAI_fnc_groupBrain
    Tactical decision making for one group, called every tick.
    States: SAFE -> ALERT -> ENGAGED <-> FLANKING -> SEARCH -> ALERT -> SAFE
            plus REINFORCING and FALLBACK.
    Must stay fast: anything that waits is spawned.
*/
params ["_grp"];
if !(_grp getVariable ["SAI_init", false]) then { [_grp] call SAI_fnc_initGroup };

private _units = (units _grp) select {alive _x};
if (_units isEqualTo []) exitWith {};
{ if !(_x getVariable ["SAI_init", false]) then { [_x] call SAI_fnc_initUnit } } forEach _units;

private _leader = leader _grp;
private _now = time;
private _state = _grp getVariable ["SAI_state", "SAFE"];
private _onFoot = vehicle _leader == _leader;
private _canFire = combatMode _grp in ["YELLOW", "RED"];

if (!_onFoot) then { [_grp, vehicle _leader] call SAI_fnc_vehicleBrain };

// Contact = enemies seen/heard in the last 30 s
private _enemies = [_grp, 1000, 30] call SAI_fnc_knownEnemies;

if (_enemies isEqualTo []) then {
    // ---------------------------------------------------------------- no contact
    switch (_state) do {
        case "ENGAGED";
        case "FLANKING": {
            private _lkp = _grp getVariable ["SAI_lastEnemyPos", []];
            if (SAI_search && {_onFoot} && {_lkp isNotEqualTo []} && {[_grp] call SAI_fnc_canMove}) then {
                [_grp, _lkp] call SAI_fnc_search;
                _state = "SEARCH";
            } else {
                _state = "ALERT";
            };
        };
        case "SEARCH": {
            if (_now > _grp getVariable ["SAI_searchUntil", 0]) then { _state = "ALERT" };
        };
        case "REINFORCING": {
            if (_now > _grp getVariable ["SAI_reinforceUntil", 0]) then { _state = "ALERT" };
        };
        case "FALLBACK": {
            if (_now > _grp getVariable ["SAI_fallbackUntil", 0]) then { _state = "ALERT" };
        };
        case "ALERT": {
            if (_now > (_grp getVariable ["SAI_lastContact", 0]) + 240) then {
                _state = "SAFE";
                _grp setVariable ["SAI_startSize", count _units]; // regrouped: morale restored
            };
        };
    };
} else {
    // ---------------------------------------------------------------- contact
    (_enemies select 0) params ["_dist", "_tgt", "_ePos", "_age"];
    _grp setVariable ["SAI_lastEnemyPos", _ePos];
    _grp setVariable ["SAI_lastContact", _now];

    if (_state in ["SAFE", "ALERT", "SEARCH", "REINFORCING"]) then {
        _state = "ENGAGED";
        _grp setVariable ["SAI_nextIntel", 0]; // report contact immediately
        if (_onFoot) then { [_grp, _units, _ePos, _canFire] call SAI_fnc_onContact };
    };
    if (_state == "FLANKING" && {_now > _grp getVariable ["SAI_flankUntil", 0]}) then { _state = "ENGAGED" };
    if (_state == "FALLBACK" && {_now > _grp getVariable ["SAI_fallbackUntil", 0]}) then { _state = "ENGAGED" };

    if (SAI_intel) then { [_grp, _enemies] call SAI_fnc_shareIntel };

    // Rough strength estimate of what we are facing
    private _threat = 0;
    {
        _x params ["_d", "_t"];
        if (_d < 700) then {
            _threat = _threat + (switch (true) do {
                case (_t isKindOf "Tank"): {6};
                case (_t isKindOf "Wheeled_APC_F"): {4};
                case (_t isKindOf "Car"): { [1, 2] select (!isNull gunner _t) };
                default {1};
            });
        };
    } forEach _enemies;
    private _strength = count _units;
    private _losses = 1 - (_strength / ((_grp getVariable ["SAI_startSize", _strength]) max 1));

    if (_onFoot) then {
        // Fall back when beaten up and outgunned
        if (
            SAI_fallback && {_state != "FALLBACK"}
            && {_losses >= 0.5} && {_threat > _strength * 1.2} && {_dist < 300}
            && {_now > _grp getVariable ["SAI_nextFallback", 0]}
            && {random 1 > (_leader skill "courage") * 0.5}
            && {[_grp] call SAI_fnc_canMove}
        ) then {
            [_grp, _units, _ePos] call SAI_fnc_fallback;
            _state = "FALLBACK";
        };

        // Fix and flank
        if (
            SAI_flanking && {_canFire} && {_state == "ENGAGED"}
            && {_now > _grp getVariable ["SAI_nextFlank", 0]}
            && {_strength >= 4} && {_dist > 50} && {_dist < 450}
            && {_threat <= _strength * 1.5}
        ) then {
            if ([_grp, _units, _ePos] call SAI_fnc_flank) then { _state = "FLANKING" };
        };

        if (SAI_grenades && {_canFire} && {_state != "FALLBACK"}) then { [_grp, _units, _enemies] call SAI_fnc_grenadeCheck };
        if (SAI_buddyAid && {!SAI_hasACEMedical}) then { [_grp, _units, _ePos] call SAI_fnc_buddyAidCheck };
    };

    if (SAI_reinforce && {_threat >= _strength * 0.8} && {_now > _grp getVariable ["SAI_nextReinforce", 0]}) then {
        [_grp, _ePos] call SAI_fnc_requestReinforcements;
    };
};

_grp setVariable ["SAI_state", _state];
if (SAI_debug) then { [_grp, _state] call SAI_fnc_debugMarker };
