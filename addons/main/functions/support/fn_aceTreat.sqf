/*
    SAI_fnc_aceTreat (scheduled)
    Treats a patient with ACE medical, the same way ACE's own AI medic does
    (ace_medical_treatment_*Local events). Supplies are taken from the medic first,
    then from the patient.
    Order: stop bleeding -> CPR -> IV fluids -> epinephrine -> morphine.
    _medic may be the patient himself (self aid: bandages and morphine only).
*/
params ["_medic", "_patient"];
private _self = _medic == _patient;
private _end = time + 90;
private _parts = ["head", "body", "leftarm", "rightarm", "leftleg", "rightleg"];

private _take = {
    params ["_classes"];
    private _res = "";
    {
        if (_x in items _medic) exitWith { _medic removeItem _x; _res = _x };
        if (_x in items _patient) exitWith { _patient removeItem _x; _res = _x };
    } forEach _classes;
    _res
};

private _bleedingPart = {
    private _wounds = _patient getVariable ["ace_medical_openWounds", []];
    private _part = "";
    if (_wounds isEqualType createHashMap) then {
        // ACE >= 3.16: bodyPart -> [[class, amountOf, bleeding, damage], ...]
        {
            if ((_y findIf {(_x select 1) > 0 && {(_x select 2) > 0}}) != -1) exitWith { _part = _x };
        } forEach _wounds;
    } else {
        // older ACE: [[class, bodyPartIndex, amountOf, bleeding, damage], ...]
        private _i = _wounds findIf {(_x select 2) > 0 && {(_x select 3) > 0}};
        if (_i != -1) then { _part = _parts select ((_wounds select _i) select 1) };
    };
    _part
};

private _event = {
    params ["_name", "_args"];
    [format ["ace_medical_treatment_%1", _name], _args, _patient] call CBA_fnc_targetEvent;
};

_medic setUnitPos "MIDDLE";
while {
    alive _medic && {alive _patient} && {time < _end}
    && {_self || {_medic distance _patient < 4}}
    && {_self || {!(_medic getVariable ["ACE_isUnconscious", false])}}
    && {[_patient] call SAI_fnc_aceIsWounded > 0}
} do {
    private _did = false;
    private _wait = 4;
    _medic doWatch _patient;

    // 1. Bleeding
    private _part = call _bleedingPart;
    if (_part != "") then {
        private _item = [["ACE_quikclot", "ACE_elasticBandage", "ACE_packingBandage", "ACE_fieldDressing"]] call _take;
        if (_item != "") then {
            private _class = (createHashMapFromArray [
                ["ACE_quikclot", "QuikClot"], ["ACE_elasticBandage", "ElasticBandage"],
                ["ACE_packingBandage", "PackingBandage"], ["ACE_fieldDressing", "FieldDressing"]
            ]) get _item;
            ["bandageLocal", [_patient, _part, _class]] call _event;
            _did = true;
        };
    };

    if (!_did && {!_self}) then {
        // 2. CPR
        if (_patient getVariable ["ace_medical_inCardiacArrest", false]) then {
            ["cprLocal", [_medic, _patient]] call _event;
            _did = true;
            _wait = 8;
        } else {
            // 3. Fluids, once per bag
            if ((_patient getVariable ["ace_medical_bloodVolume", 6]) < 5 && {(_patient getVariable ["ace_medical_ivBags", []]) isEqualTo []}) then {
                private _item = [[
                    "ACE_bloodIV", "ACE_bloodIV_500", "ACE_bloodIV_250",
                    "ACE_plasmaIV", "ACE_plasmaIV_500", "ACE_plasmaIV_250",
                    "ACE_salineIV", "ACE_salineIV_500", "ACE_salineIV_250"
                ]] call _take;
                if (_item != "") then {
                    private _class = _item select [4];                        // "ACE_salineIV_500" -> "salineIV_500"
                    _class = (toUpper (_class select [0, 1])) + (_class select [1]); // -> "SalineIV_500"
                    ["ivBagLocal", [_patient, selectRandom ["leftarm", "rightarm"], _class]] call _event;
                    _did = true;
                };
            };
            // 4. Wake up (not bleeding any more, not in arrest)
            if (!_did && {_patient getVariable ["ACE_isUnconscious", false]} && {time > (_patient getVariable ["SAI_nextEpi", 0])}) then {
                if (([["ACE_epinephrine"]] call _take) != "") then {
                    ["medicationLocal", [_patient, selectRandom ["leftleg", "rightleg"], "Epinephrine"]] call _event;
                    _patient setVariable ["SAI_nextEpi", time + 60];
                    _did = true;
                };
            };
        };
    };

    // 5. Pain
    if (!_did && {(_patient getVariable ["ace_medical_pain", 0]) > 0.5} && {time > (_patient getVariable ["SAI_nextMorphine", 0])}) then {
        if (([["ACE_morphine"]] call _take) != "") then {
            ["medicationLocal", [_patient, selectRandom ["leftarm", "rightarm"], "Morphine"]] call _event;
            _patient setVariable ["SAI_nextMorphine", time + 300];
            _did = true;
        };
    };

    if (!_did) exitWith {}; // nothing more we can do with the supplies we have
    _medic playActionNow (["MedicOther", "Medic"] select _self);
    sleep _wait;
};
if (alive _medic) then { _medic doWatch objNull; _medic setUnitPos "AUTO" };
