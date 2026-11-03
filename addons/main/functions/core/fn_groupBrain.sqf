/*
    SAI_fnc_groupBrain
    Squad-level decision making, called every tick on the machine owning the group.
    States: SAFE, ALERT, MANOEUVRE (moving on a commander task), AMBUSH,
            ENGAGED, FLANKING, FALLBACK, SEARCH, REINFORCING.
    In contact the squad scores its options (assault / flank / fall back / hold)
    from the situation and its own personality instead of fixed rules.
    Must stay fast: anything that waits is spawned.
*/
params ["_grp"];
if !(_grp getVariable ["SAI_init", false]) then { [_grp] call SAI_fnc_initGroup };

private _units = (units _grp) select {alive _x};
if (_units isEqualTo []) exitWith {};
{ if !(_x getVariable ["SAI_init", false]) then { [_x] call SAI_fnc_initUnit } } forEach _units;

private _leader = leader _grp;
private _now = time;
private _prevState = _grp getVariable ["SAI_state", "SAFE"];
private _state = _prevState;
private _onFoot = vehicle _leader == _leader;
private _canFire = combatMode _grp in ["YELLOW", "RED"];
(_grp getVariable ["SAI_profile", [0.5, 0.5, 0.5]]) params ["_aggr", "_caut", "_disc"];

// Contact = enemies seen/heard in the last 30 s
private _enemies = [_grp, 1000, 30] call SAI_fnc_knownEnemies;
if (_enemies isNotEqualTo []) then { [_grp, _enemies] call SAI_fnc_reportContacts };

// Fire mission requested by an attacking group (synchronised assault)
private _fm = _grp getVariable ["SAI_fireMission", []];
if (_fm isNotEqualTo []) then {
    _grp setVariable ["SAI_fireMission", []];
    if (_canFire && {_onFoot}) then {
        private _p = AGLToASL (_fm select 0);
        { if (vehicle _x == _x && {(_x getVariable ["SAI_busyUntil", 0]) < _now}) then { [_x, _p] spawn SAI_fnc_suppressFire } } forEach _units;
        ["Group %1 fire mission!", groupId _grp] call SAI_fnc_log;
    };
};

// ======================================================================= AMBUSH
if (_state == "AMBUSH") exitWith {
    private _spring = _now > (_grp getVariable ["SAI_ambushUntil", 0]);
    private _target = [];
    if (_enemies isNotEqualTo []) then {
        (_enemies select 0) params ["_d", "_tgt", "_ePos"];
        _target = _ePos;
        // let them walk in; aggressive groups open fire earlier
        if (_d < (60 + _aggr * 60)) then { _spring = true };
        if ((_tgt knowsAbout _leader) > 1.5) then { _spring = true }; // we've been spotted
    };
    if ((_units findIf { (_x getVariable ["SAI_supp", 0]) > 0.2 && {(_now - (_x getVariable ["SAI_suppTime", -1e6])) < 6} }) != -1) then { _spring = true };
    if (_spring) then {
        if (_target isEqualTo [] && {_now > (_grp getVariable ["SAI_ambushUntil", 0])}) then {
            // nobody came: stand down quietly
            _grp setCombatMode "YELLOW";
            _grp setBehaviour "AWARE";
            _grp setVariable ["SAI_state", "ALERT", true];
            { _x setVariable ["SAI_busyUntil", 0]; _x setUnitPos "AUTO"; if (leader _x != _x) then { _x doFollow leader _x } } forEach _units;
        } else {
            [_grp, _target] call SAI_fnc_ambushSpring;
        };
    };
    if (SAI_debug) then { [_grp, _grp getVariable ["SAI_state", _state]] call SAI_fnc_debugMarker };
};

if (_enemies isEqualTo []) then {
    // ======================================================================= NO CONTACT
    switch (_state) do {
        case "ENGAGED";
        case "FLANKING": {
            private _lkp = _grp getVariable ["SAI_lastEnemyPos", []];
            if (SAI_search && {_onFoot} && {_lkp isNotEqualTo []} && {(_grp getVariable ["SAI_task", []]) isEqualTo []} && {[_grp] call SAI_fnc_canMove}) then {
                [_grp, _lkp] call SAI_fnc_search;
                _state = "SEARCH";
            } else {
                _state = "ALERT";
            };
        };
        case "SEARCH":      { if (_now > _grp getVariable ["SAI_searchUntil", 0]) then { _state = "ALERT" } };
        case "REINFORCING": { if (_now > _grp getVariable ["SAI_reinforceUntil", 0]) then { _state = "ALERT" } };
        case "FALLBACK":    { if (_now > _grp getVariable ["SAI_fallbackUntil", 0]) then { _state = "ALERT" } };
        case "ALERT": {
            // Recon by fire: an MG rakes a spot the enemy shot from before
            if (SAI_memory && {_canFire} && {_onFoot} && {random 1 < 0.08 * (0.5 + _aggr)}) then {
                private _nests = [side _grp, getPosATL _leader, 350] call SAI_fnc_memNests;
                if (_nests isNotEqualTo []) then {
                    private _mg = _units select { [_x] call SAI_fnc_isMG && {(_x getVariable ["SAI_busyUntil", 0]) < _now} };
                    if (_mg isNotEqualTo []) then {
                        [_mg select 0, AGLToASL (selectRandom _nests)] spawn SAI_fnc_suppressFire;
                        ["Group %1 recon by fire", groupId _grp] call SAI_fnc_log;
                    };
                };
            };
            if (_now > (_grp getVariable ["SAI_lastContact", 0]) + 240 && {(_grp getVariable ["SAI_task", []]) isEqualTo []}) then {
                _state = "SAFE";
                _grp setVariable ["SAI_startSize", count _units]; // regrouped: morale restored
            };
        };
    };
    if (SAI_commander) then { [_grp] call SAI_fnc_taskExec };
} else {
    // ======================================================================= CONTACT
    (_enemies select 0) params ["_dist", "_tgt", "_ePos", "_age"];
    _grp setVariable ["SAI_lastEnemyPos", _ePos];
    _grp setVariable ["SAI_lastContact", _now];

    if (_state in ["SAFE", "ALERT", "SEARCH", "REINFORCING", "MANOEUVRE"]) then {
        // a group on a commander task only breaks off for close contact
        if (_state != "MANOEUVRE" || {_dist < 250}) then {
            _state = "ENGAGED";
            _grp setVariable ["SAI_nextIntel", 0];
            if (_onFoot) then { [_grp, _units, _ePos, _canFire] call SAI_fnc_onContact };
        };
    };
    if (_state == "FLANKING" && {_now > _grp getVariable ["SAI_flankUntil", 0]}) then { _state = "ENGAGED" };
    if (_state == "FALLBACK" && {_now > _grp getVariable ["SAI_fallbackUntil", 0]}) then { _state = "ENGAGED" };
    if (SAI_commander) then { [_grp] call SAI_fnc_taskExec };

    if (SAI_intel) then { [_grp, _enemies] call SAI_fnc_shareIntel };

    // What are we up against?
    private _threat = 0;
    {
        _x params ["_d", "_t"];
        if (_d < 700) then {
            _threat = _threat + (switch ([_t] call SAI_fnc_targetType) do { case "armor": {6}; case "car": { [1, 2] select (!isNull gunner _t) }; case "air": {4}; default {1} });
        };
    } forEach _enemies;
    private _strength = count _units;
    private _losses = 1 - (_strength / ((_grp getVariable ["SAI_startSize", _strength]) max 1));
    private _ratio = _strength / (_threat max 1); // > 1: we outnumber them

    if (_onFoot && {_state in ["ENGAGED", "FLANKING"]} && {!(_grp getVariable ["SAI_bounding", false])}) then {
        // ---- utility scores (personality + situation + a little randomness)
        private _sFallback = (_losses * 1.6) + ((1 / (_ratio max 0.2)) * 0.25) - (_disc * 0.7) + random 0.2;
        private _sAssault = (_aggr * 0.6) + ((_ratio - 1) * 0.4) + ([0, 0.4] select (_dist < 70)) - (_caut * 0.3) + random 0.2;
        private _sFlank = (_aggr * 0.5) + ((_ratio min 2) * 0.25) + ([0, 0.2] select (_strength >= 6)) - (_caut * 0.15) + random 0.3;

        private _choice = "HOLD";
        if (SAI_fallback && {_sFallback > 0.6} && {_losses >= 0.3} && {_dist < 350} && {_now > _grp getVariable ["SAI_nextFallback", 0]} && {[_grp] call SAI_fnc_canMove}) then {
            _choice = "FALLBACK";
        } else {
            if (_canFire && {_state == "ENGAGED"}) then {
                if (_sAssault > 0.8 && {_dist < 150} && {_strength >= 3} && {_now > _grp getVariable ["SAI_nextAssault", 0]}) then { _choice = "ASSAULT" };
                if (_choice == "HOLD" && {SAI_flanking} && {_sFlank > 0.6} && {_strength >= 4} && {_dist > 50} && {_dist < 450} && {_now > _grp getVariable ["SAI_nextFlank", 0]}) then { _choice = "FLANK" };
            };
        };

        switch (_choice) do {
            case "FALLBACK": { [_grp, _units, _ePos] call SAI_fnc_fallback; _state = "FALLBACK" };
            case "ASSAULT": {
                _grp setVariable ["SAI_nextAssault", _now + 90 + random 60];
                [_grp, _ePos, 90] spawn SAI_fnc_bound;
                ["Group %1 assaults (bounding overwatch)", groupId _grp] call SAI_fnc_log;
            };
            case "FLANK": { if ([_grp, _units, _ePos] call SAI_fnc_flank) then { _state = "FLANKING" } };
        };
    };

    if (_onFoot) then {
        if (SAI_grenades && {_canFire} && {_state != "FALLBACK"}) then { [_grp, _units, _enemies] call SAI_fnc_grenadeCheck };
        if (SAI_antiTank && {_canFire}) then { [_grp, _units, _enemies] call SAI_fnc_atCheck };
        if (SAI_statics && {_canFire} && {_state == "ENGAGED"}) then { [_grp, _units, _ePos] call SAI_fnc_manStatics };
        if (SAI_buddyAid && {!SAI_hasACEMedical || {SAI_aceMedical}}) then { [_grp, _units, _ePos] call SAI_fnc_buddyAidCheck };
    };

    // Without a commander, groups still call each other for help directly
    if (!SAI_commander && {SAI_reinforce} && {_threat >= _strength * 0.8} && {_now > _grp getVariable ["SAI_nextReinforce", 0]}) then {
        [_grp, _ePos] call SAI_fnc_requestReinforcements;
    };
};

if (_state != _prevState) then { _grp setVariable ["SAI_state", _state, true] };
if (SAI_debug) then { [_grp, _state] call SAI_fnc_debugMarker };
