/* SAI_fnc_memKey - 50 m world cell key for the memory maps */
params ["_pos"];
(floor ((_pos select 0) / 50)) * 100000 + floor ((_pos select 1) / 50)
