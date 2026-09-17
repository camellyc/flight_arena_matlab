function [led_on_indices, nRemoved, windowRanges] = exclude_window_stims(led_on_indices, matFile, fs, margin_s)
% EXCLUDE_WINDOW_STIMS  Remove LED-on events that belong to "window" opto stimuli.
%
%   [idx, nRemoved, windowRanges] = exclude_window_stims(idx, matFile, fs)
%   [...] = exclude_window_stims(idx, matFile, fs, margin_s)
%
%   Sessions recorded with run_session_unified.m (opto.mode 'windows' or
%   'both') save a stimTable in the .mat whose 'source' column is 1 for
%   randomized stimuli and 2 for explicit window stimuli. Windowed stimuli are
%   NOT part of the standard analysis: this function drops every LED-on sample
%   index that falls inside a window stimulus (plus a small margin), so that
%   only randomized stimuli remain to be paired with allRandomizedStimOrders.
%
%   Legacy .mat files without a stimTable are returned unchanged.
%
%   Inputs
%     led_on_indices : sample indices into Data (vector), e.g. from the LED-on
%                      detection loop in summarize_*.m
%     matFile        : path to the session .mat file
%     fs             : sample rate in Hz (params.acq.SampleRate)
%     margin_s       : optional tolerance around each window, default 0.05 s
%   Outputs
%     led_on_indices : filtered indices (same orientation as the input)
%     nRemoved       : number of events removed
%     windowRanges   : [start end] global sample index of each window, with margin
%
%   Example (inside summarize_WBF.m, right after LED-on detection):
%     [led_on_indices, nWin] = exclude_window_stims(led_on_indices, dataFile, fs);
%
%   Author: Yichen Luo, 2026-09

if nargin < 4 || isempty(margin_s), margin_s = 0.05; end
nRemoved = 0;
windowRanges = zeros(0, 2);

if isempty(whos('-file', matFile, 'stimTable')), return; end
vars = {'stimTable'};
if ~isempty(whos('-file', matFile, 'params')), vars{end + 1} = 'params'; end
S = load(matFile, vars{:});
st = S.stimTable;
if isempty(st), return; end

% Column lookup by name; falls back to the run_session_unified default order.
cols = {'block', 'stim_idx', 'onset_s', 'offset_s', 'duration_ms', 'amplitude_V', ...
        'onset_global_s', 'source_1randomized_2window'};
if isfield(S, 'params') && isfield(S.params, 'stimTable_columns')
    cols = S.params.stimTable_columns;
end
cSrc = find(strncmp(cols, 'source', 6), 1);
cOn  = find(strcmp(cols, 'onset_s'), 1);
cOff = find(strcmp(cols, 'offset_s'), 1);
cOnG = find(strcmp(cols, 'onset_global_s'), 1);
if isempty(cSrc) || isempty(cOn) || isempty(cOff) || isempty(cOnG) || size(st, 2) < max([cSrc cOn cOff cOnG])
    return;   % no source column: nothing to exclude
end

win = st(st(:, cSrc) == 2, :);
if isempty(win), return; end

margin  = round(margin_s * fs);
onsetG  = round(win(:, cOnG) * fs) + 1;                          % 1-based global sample index
offsetG = onsetG + round((win(:, cOff) - win(:, cOn)) * fs);
windowRanges = [onsetG - margin, offsetG + margin];

keep = true(size(led_on_indices));
for w = 1:size(windowRanges, 1)
    keep = keep & ~(led_on_indices >= windowRanges(w, 1) & led_on_indices <= windowRanges(w, 2));
end
nRemoved = sum(~keep);
led_on_indices = led_on_indices(keep);
end
