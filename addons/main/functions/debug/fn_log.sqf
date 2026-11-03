/* SAI_fnc_log - [format, args...] call SAI_fnc_log. Always to RPT; also systemChat in debug mode */
private _msg = "[SAI] " + (format _this);
diag_log text _msg;
if (!isNil "SAI_debug" && {SAI_debug} && {hasInterface}) then { systemChat _msg };
