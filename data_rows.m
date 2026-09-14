function dr = data_rows(matFile)
% DATA_ROWS  Row indices into Data for the signals the analysis scripts use.
%
%   dr = data_rows(matFile) returns a struct with fields
%       led   : LED driver monitor
%       wbf   : wingbeat frequency
%       wbaL  : wingbeat amplitude, left
%       wbaR  : wingbeat amplitude, right
%   plus one field per named channel found in params.data_rows (e.g. arena_x,
%   EMG, basler_trigger, phantom_recording), each giving the Data row.
%
%   Sessions from run_session_unified.m save the channel names in
%   params.data_rows, so the rows follow the wiring recorded in the file.
%   Legacy files (no params) get the historical layout:
%   row 2 WBA left, 3 WBA right, 4 WBF, 7 LED driver.
%
%   Usage inside an analysis script, after loading the .mat:
%       dr  = data_rows(dataFile);
%       led = Data(dr.led, :);
%
%   Author: Yichen Luo, 2026-09

dr = struct('led', 7, 'wbf', 4, 'wbaL', 2, 'wbaR', 3);          % legacy layout
if isempty(whos('-file', matFile, 'params')), return; end
S = load(matFile, 'params');
if ~isfield(S.params, 'data_rows'), return; end
names = S.params.data_rows;                                       % {'time_s', <ai_names>...}

alias = {'led', 'LED_driver'; 'wbf', 'WBF'; 'wbaL', 'WBA_left'; 'wbaR', 'WBA_right'};
for i = 1:size(alias, 1)
    k = find(strcmp(names, alias{i, 2}), 1);
    if ~isempty(k), dr.(alias{i, 1}) = k; end
end
for k = 2:numel(names)                                            % every named channel by its own name
    f = matlab.lang.makeValidName(names{k});
    if ~isfield(dr, f), dr.(f) = k; end
end
end
