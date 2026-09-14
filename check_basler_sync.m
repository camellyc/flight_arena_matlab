function r = check_basler_sync(matFile, thr_V)
% CHECK_BASLER_SYNC  Temporary check: is every Basler trigger pulse (ctr0 loop-back,
% AI9) followed by exactly one shutter/ExposureActive pulse (AI11)?
%
%   check_basler_sync                 % file picker
%   check_basler_sync(matFile)
%   r = check_basler_sync(matFile, thr_V)   % TTL threshold, default 2.5 V
%
% Pairs each trigger rising edge with the first shutter rising edge that occurs
% within one trigger period after it. Reports counts, unmatched triggers
% (trigger but no exposure), unmatched exposures (exposure without trigger),
% trigger-to-exposure latency and exposure width, then plots:
%   1) both signals around the first mismatch (or the first pulses if none)
%   2) latency of every matched pair vs time, mismatches marked
%   3) exposure width vs time
% Author: Yichen Luo, 2026-09 (temporary)

if nargin < 1 || isempty(matFile)
    [f, p] = uigetfile('*.mat', 'Select a session .mat file');
    if isequal(f, 0), r = []; return; end
    matFile = fullfile(p, f);
end
matFile = char(matFile);
if nargin < 2 || isempty(thr_V), thr_V = 2.5; end

S  = load(matFile, 'Data', 'variables', 'params');
dr = data_rows(matFile);
assert(isfield(dr, 'basler_trigger') && isfield(dr, 'basler_shutter'), ...
       'This file has no basler_trigger / basler_shutter rows (needs a run_session_unified file).');
fs   = S.variables.SampleRate;
trig = S.Data(dr.basler_trigger, :) > thr_V;
shut = S.Data(dr.basler_shutter, :) > thr_V;
tAbs = (0:numel(trig) - 1) / fs;                       % continuous time over all blocks (s)
fps  = NaN;
if isfield(S.params, 'basler') && isfield(S.params.basler, 'fps'), fps = S.params.basler.fps; end

trigUp = find(diff([false trig]) == 1);              % a signal already high at sample 1 counts as an edge
shutUp = find(diff([false shut]) == 1);
shutDn = find(diff(shut) == -1) + 1;
if isnan(fps), period = median(diff(trigUp)); else, period = fs / fps; end

% pair each trigger with the first unused shutter edge within one period after it
match   = nan(size(trigUp));                          % index into shutUp
used    = false(size(shutUp));
j = 1;
for i = 1:numel(trigUp)
    while j <= numel(shutUp) && shutUp(j) < trigUp(i), j = j + 1; end
    if j <= numel(shutUp) && shutUp(j) - trigUp(i) < period
        match(i) = j; used(j) = true; j = j + 1;
    end
end
missed = find(isnan(match));                          % triggers with no exposure
extra  = find(~used);                                 % exposures with no trigger
ok     = ~isnan(match);
lat_ms = nan(size(trigUp));
lat_ms(ok) = (shutUp(match(ok)) - trigUp(ok)) / fs * 1000;

% exposure width for each shutter rising edge
width_ms = nan(size(shutUp));
for k = 1:numel(shutUp)
    d = shutDn(find(shutDn > shutUp(k), 1));
    if ~isempty(d), width_ms(k) = (d - shutUp(k)) / fs * 1000; end
end

r = struct('file', matFile, 'fs', fs, 'fps', fps, 'n_trigger', numel(trigUp), 'n_shutter', numel(shutUp), ...
           'n_matched', sum(ok), 'missed_trigger_idx', missed, 'extra_shutter_idx', extra, ...
           'missed_trigger_t_s', tAbs(trigUp(missed)), 'extra_shutter_t_s', tAbs(shutUp(extra)), ...
           'latency_ms', lat_ms, 'exposure_ms', width_ms, 'trigger_t_s', tAbs(trigUp), 'shutter_t_s', tAbs(shutUp));

fprintf('\n%s\n', matFile);
fprintf('Trigger rising edges : %d\n', r.n_trigger);
fprintf('Shutter rising edges : %d\n', r.n_shutter);
fprintf('Matched pairs        : %d\n', r.n_matched);
fprintf('Trigger w/o exposure : %d\n', numel(missed));
fprintf('Exposure w/o trigger : %d\n', numel(extra));
if ~isnan(fps)
    fprintf('Trigger rate         : %.3f Hz measured (%g Hz set)\n', fs / median(diff(trigUp)), fps);
end
if any(ok)
    fprintf('Latency trig->expose : mean %.3f, sd %.3f, min %.3f, max %.3f ms\n', ...
            mean(lat_ms(ok)), std(lat_ms(ok)), min(lat_ms(ok)), max(lat_ms(ok)));
end
if any(~isnan(width_ms))
    fprintf('Exposure width       : mean %.3f, sd %.3f, min %.3f, max %.3f ms\n', ...
            nanmean(width_ms), nanstd(width_ms), min(width_ms), max(width_ms));
end
if isempty(missed) && isempty(extra) && r.n_trigger == r.n_shutter
    fprintf('RESULT: one-to-one match.\n');
else
    fprintf('RESULT: NOT one-to-one.');
    if ~isempty(missed), fprintf(' First trigger without exposure at %.4f s.', tAbs(trigUp(missed(1)))); end
    if ~isempty(extra),  fprintf(' First exposure without trigger at %.4f s.', tAbs(shutUp(extra(1)))); end
    fprintf('\n');
end

% ---- figure ----
if ~isempty(missed) || ~isempty(extra)
    cands = [tAbs(trigUp(missed)), tAbs(shutUp(extra))];
    tc = min(cands);
else
    tc = tAbs(trigUp(min(3, end)));
end
win = 4 * period / fs;
sel = tAbs >= tc - win & tAbs <= tc + win;
figure('Name', 'check_basler_sync', 'NumberTitle', 'off', 'Color', 'w', 'Position', [80 80 1200 800]);
ax1 = subplot(3, 1, 1); hold on
hT = plot(tAbs(sel), S.Data(dr.basler_trigger, sel), 'Color', [0 0.5 1]);
hS = plot(tAbs(sel), S.Data(dr.basler_shutter, sel), 'Color', [1 0.3 0.3]);
if ~isempty(missed), plot(tAbs(trigUp(missed)), thr_V, 'kv', 'MarkerFaceColor', 'k'); end
if ~isempty(extra),  plot(tAbs(shutUp(extra)),  thr_V, 'k^', 'MarkerFaceColor', 'y'); end
xlim([tc - win, tc + win]); ylabel('V'); legend([hT hS], {'basler trigger', 'basler shutter'});
if isempty(missed) && isempty(extra), title(ax1, 'Raw signals (first pulses)', 'Interpreter', 'none');
else, title(ax1, 'Raw signals around the first mismatch (v = trigger w/o exposure, ^ = exposure w/o trigger)', 'Interpreter', 'none'); end
ax2 = subplot(3, 1, 2); hold on
plot(tAbs(trigUp), lat_ms, '.', 'Color', [0 0.5 1]);
if ~isempty(missed), plot(tAbs(trigUp(missed)), zeros(size(missed)), 'kv', 'MarkerFaceColor', 'k'); end
if ~isempty(extra),  plot(tAbs(shutUp(extra)),  zeros(size(extra)),  'k^', 'MarkerFaceColor', 'y'); end
ylabel('latency (ms)'); title('Trigger -> exposure latency per pulse (0 = mismatch marker)'); grid on
ax3 = subplot(3, 1, 3);
plot(tAbs(shutUp), width_ms, '.', 'Color', [1 0.3 0.3]);
ylabel('exposure (ms)'); xlabel('Time (s)'); title('Exposure width per pulse'); grid on
linkaxes([ax2 ax3], 'x');
if nargout == 0, clear r; end
end
