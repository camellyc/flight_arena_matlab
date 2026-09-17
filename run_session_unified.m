function out = run_session_unified(overrides)
% RUN_SESSION_UNIFIED  Flight-arena experiment: NI DAQ acquisition, optogenetic
% LED stimulation, Basler top/side cameras, Phantom KT810 high-speed camera,
% real-time summary plot, and a single .mat output per experiment.
%
% Synthesised from run_session_oscillating_vert_2cam_phantom_framesync.m,
% run_session_randomizedCL_2cam*.m, run_session_immobilizedfly.m (Yichen Luo)
% and runexpt_kt*.m / runexpt_sc.m (Kyle Thieringer, Sanjana).
%
% USAGE
%   run_session_unified                 % edit session_defaults.m, then run
%   run_session_unified(ov)             % ov = struct of overrides, e.g.
%                                       %   ov.opto.mode = 'randomized';
%                                       %   ov.basler.side.enable = false;
%                                       % Every override field must already exist in
%                                       % session_defaults.m: an unknown or misspelled one
%                                       % is an error, not a silently ignored default.
%   out = run_session_unified(...)      % returns Data, params and results (in ans if not captured)
%   S = run_session_unified('defaults') % the settings of session_defaults.m as one struct; runs nothing
%   run_session_gui                     % window for editing session_defaults.m, then Run
%
% MODES (all selected in session_defaults.m)
%   visual.mode : 'closed_loop_stripe'      pattern + closed-loop X gain
%                 'closed_loop_oscillating' pattern + Y velocity function
%                 'none'                    arena untouched (immobilised fly)
%   opto.mode   : 'randomized'  durations (optionally paired intensities),
%                               evenly spaced in the block, shuffled per block
%                 'windows'     explicit [onset offset] rows in seconds
%                 'both'        randomized train plus the explicit windows on top
%                               (a warning is printed if they overlap)
%                 'none'
%                 Window stimuli are saved in stimTable (source = 2); they are EXCLUDED
%                 from the summarize_* analyses (exclude_window_stims.m) and never
%                 appear in allRandomizedStimOrders.
%   phantom.mode: 'framesync'   external F-Sync clock; PCC owns sync mode, fps
%                               and pre-trigger; capture starts at window_s(1),
%                               HW trigger at window_s(2) stores the cine
%                 'fixed_fps'   internal clock; MATLAB sets fps and post-trigger
%                               frames; trigger at window start or end
%   basler.top / basler.side : independent enable flags; cameras are selected by
%                 serial number and an enabled camera that is not enumerated is an error
%   hw.simulate : no hardware; synthetic data through the same plot/save path
%
% WIRING / CHANNEL MAP (SCB-68A, all AI single-ended; Data rows, row 1 = within-block time)
%    2  AI0  LED driver monitor (AO0 split)     9  AI7  Arena Y position
%    3  AI1  Wingbeat frequency                10  AI8  EMG
%    4  AI2  WBA left                          11  AI9  Basler trigger loop-back (PFI12 split)
%    5  AI3  WBA right                         12  AI10 Phantom F-Sync clock (external generator split)
%    6  AI4  Left Hutchen                      13  AI11 Basler shutter (side camera ExposureActive, high = exposing)
%    7  AI5  Right Hutchen                     14  AI14 Phantom "Recording" output
%    8  AI6  Arena X position
%   AO0 -> LED driver           AO1 -> Phantom "1 Trigger" in
%   ctr0 (PFI12) -> Basler Line4 (both cameras)
%   Analysis scripts resolve rows by name through params.data_rows (see data_rows.m).
%
% OUTPUT FILES (all in saveFolder, one shared time-stamped base name)
%   <base>.mat             Data (14 x N), allRandomizedStimOrders, stimTable, params
%                          (settings, code version and source text), phantom, baslerInfo
%   <base>_log.txt         everything printed to the command window during the run
%   <base>_plot.svg/.png   summary figure
%   <base>_TopCamera.mp4, <base>_SideCamera.mp4   (H.264). During the run the frames
%                          stream as uncompressed Grayscale AVI to
%                          basler.video_scratch_folder on a local NVMe; after the .mat is
%                          saved, ffmpeg compresses each file (basler.h264), applying the
%                          rotate_deg that could not be done on-camera, and the mp4 is
%                          moved here. Check baslerInfo.<cam>.rotate_deg_pending: 0 means
%                          the video is already oriented as configured.
%   Phantom sequence: <phantom.saveRoot>\<experiment_name>\<base>_PhantomCamera
%
% Author: Yichen Luo, 2026-09 (unified version)
% edits: Kyle Thieringer, 2026-09

if nargin < 1 || isempty(overrides), overrides = struct(); end
defaultsOnly = (ischar(overrides) || isstring(overrides)) && strcmpi(overrides, 'defaults');
if ~defaultsOnly, close all; clc; end

%% ---------------- settings: session_defaults.m, then overrides ----------
% Every setting lives in session_defaults.m, which is also the file run_session_gui
% edits and rewrites. Nothing is derived or validated until the overrides are in.
S = session_defaults();
if defaultsOnly, out = S; return; end   % the settings file, exactly as overrides take them; nothing run
S = mergeStruct(S, overrides);
saveFolder = S.saveFolder; meta = S.meta; hw = S.hw; acq = S.acq; visual = S.visual;
opto = S.opto; basler = S.basler; phantom = S.phantom; plotting = S.plotting;
nameOf = fileNameParts(meta);   % metadata as file-name tokens: text, with characters Windows refuses replaced

scriptStart = datetime('now', 'TimeZone', 'local');

phantomPlanned = phantom.enable;        % planned capture window is drawn even in simulation
if hw.simulate
    fprintf('*** SIMULATION MODE: no DAQ, cameras, Phantom or arena ***\n');
    basler.top.enable = false; basler.side.enable = false; phantom.enable = false;
end
arenaActive = ~hw.simulate && ~strcmpi(visual.mode, 'none');
anyCam      = basler.top.enable || basler.side.enable;

fs      = acq.SampleRate;
N_block = round(acq.TrialLength * fs);
N_total = N_block * acq.blocks;
nAI     = numel(acq.ai_channels);
assert(numel(acq.ai_names) == nAI, 'acq.ai_names must have one entry per AI channel.');
% Data row 1 holds block-relative time in single precision. Single's spacing grows
% with magnitude, so a long enough block would make consecutive timestamps collide.
assert(eps(single(acq.TrialLength)) < 1 / fs, ...
    ['acq.TrialLength = %g s at %g Hz cannot be time-stamped in single precision: ' ...
     'the spacing at %g s is %g s, coarser than the %g s sample period. Shorten ' ...
     'TrialLength (max ~%.0f s at this rate) or store Data as double.'], ...
    acq.TrialLength, fs, acq.TrialLength, eps(single(acq.TrialLength)), 1 / fs, ...
    double(acq.TrialLength) * (1 / fs) / double(eps(single(acq.TrialLength))));
% Columns of the signals the live plot and the simulator refer to, resolved by name
% from acq.ai_names: a rewire is a one-line change there and nothing can point at the
% wrong row. Saved in params.plotting.ch like the settings it derives from.
plotting.ch = channelColumns(acq.ai_names);

% Basler stream format (see session_defaults for why it is not a setting), rotation
% values and exposure clamp (90 % of frame period)
basler.video_profile = 'Grayscale AVI';
assert(any(basler.top.rotate_deg  == [0 90 180 270]), 'basler.top.rotate_deg must be 0, 90, 180 or 270.');
assert(any(basler.side.rotate_deg == [0 90 180 270]), 'basler.side.rotate_deg must be 0, 90, 180 or 270.');
max_exposure = (1e6 / basler.fps) * 0.9;
if basler.Exposure_time > max_exposure
    fprintf('Exposure time reduced from %g to %g us to fit %g fps\n', basler.Exposure_time, max_exposure, basler.fps);
    basler.Exposure_time = max_exposure;
end

% Opto pulse geometry
opto.mode = lower(opto.mode);
assert(any(strcmp(opto.mode, {'randomized', 'windows', 'both', 'none'})), 'opto.mode must be randomized | windows | both | none');
% Carrier geometry. duty_cycle is exact rather than quantised to whole samples:
% the shared pulseTrain kernel uses a modular phase, so the realised pulse rate
% matches opto.Frequency even when the period is not a whole number of samples.
opto.duty_cycle = min(1, opto.PulseDuration / 1000 * opto.Frequency);
if opto.PulseDuration / 1000 * opto.Frequency >= 1 && ~strcmp(opto.mode, 'none')
    warning('PulseDuration >= 1/Frequency: LED will be continuous during stimuli.');
end
if ~strcmp(opto.mode, 'none')
    % Build one sample purely to run the kernel's checks here, at setup, rather
    % than discovering an impossible carrier once the fly is already on the rig.
    % Catches a sub-sample PulseDuration (which used to yield a silently all-zero
    % LED command) and a Frequency above Nyquist.
    pulseTrain(1, opto.amplitude_V, fs, opto.Frequency, opto.duty_cycle);
end
% Randomized stimuli are laid down at TrialLength/(n+1), so a duration longer than
% that spacing gets its tail overwritten by the next stimulus -- silently, while
% stimTable still claims the full duration. Note that "fits between its neighbours"
% and "fits inside the block" are the same condition: the last onset is spacing*n
% and the block ends at spacing*(n+1), so both reduce to duration <= spacing.
if any(strcmp(opto.mode, {'randomized', 'both'})) && ~isempty(opto.stimDurations)
    nStims  = numel(opto.stimDurations);
    spacing = acq.TrialLength / (nStims + 1);
    longest = max(opto.stimDurations) / 1000;
    if longest > spacing
        error('run_session_unified:optoOverlap', ...
              ['%d stimuli in a %g s block are spaced %g s apart, but the longest entry in ' ...
               'opto.stimDurations is %g s -- they would overwrite each other and the last ' ...
               'would run past the end of the block. Lengthen acq.TrialLength to >= %g s, ' ...
               'shorten the stimulus, or use fewer.'], ...
              nStims, acq.TrialLength, spacing, longest, longest * (nStims + 1));
    end
end
if any(strcmp(opto.mode, {'windows', 'both'})) && ~isempty(opto.windows_s)
    W = opto.windows_s;
    assert(size(W, 2) == 2 && all(W(:, 1) >= 0) && all(W(:, 2) <= acq.TrialLength) && all(W(:, 2) > W(:, 1)), ...
        'opto.windows_s rows must satisfy 0 <= onset < offset <= TrialLength');
end

% Phantom derived settings
phantom.mode = lower(phantom.mode);
assert(any(strcmp(phantom.mode, {'framesync', 'fixed_fps'})), 'phantom.mode must be framesync | fixed_fps');
if strcmp(phantom.mode, 'framesync'), phantom.trigger_at = 'end'; end
phantom.trigger_at = lower(phantom.trigger_at);
if strcmp(phantom.trigger_at, 'end'), phantom.trigger_time_s = phantom.window_s(2);
else,                                  phantom.trigger_time_s = phantom.window_s(1); end
phantom.capture_start_s = max(0, phantom.window_s(1) - phantom.arm_lead_s);
if phantom.enable
    assert(phantom.window_s(1) >= 0 && phantom.window_s(2) <= acq.TrialLength && phantom.window_s(2) > phantom.window_s(1), ...
        'phantom.window_s must lie within [0 TrialLength]');
end
phantom.serial     = uint32(phantom.serial);
phantom.saveFolder = fullfile(phantom.saveRoot, nameOf.experiment_name);
phantom.gate_col = [];                                   % column of the Recording signal within acq.ai_channels
if phantom.enable && ~isempty(phantom.gate_ai)
    phantom.gate_col = find(strcmp(acq.ai_names, phantom.gate_ai), 1);
    assert(~isempty(phantom.gate_col), 'phantom.gate_ai "%s" is not in acq.ai_names.', phantom.gate_ai);
end

% File names. The trial glob and the file name must come from the same drop-empties
% logic: interpolating metadata straight into a glob put a double underscore in it
% whenever a field was empty ('*_test__Fly1_Trial*'), so it never matched a real
% file and every run came out as Trial1. Appending a literal 'Trial*' token to the
% parts list makes that impossible -- it degrades to '*_Trial*.mat' at worst.
if ~exist(saveFolder, 'dir'), mkdir(saveFolder); end
trialGlobParts = {nameOf.experiment_name, nameOf.genotype, prefixIfNonEmpty('Fly', nameOf.flyNumber), 'Trial*'};
trialGlobParts = trialGlobParts(~cellfun(@isempty, trialGlobParts));
trialGlob  = ['*_' strjoin(trialGlobParts, '_') '.mat'];
existing   = dir(fullfile(saveFolder, trialGlob));
usedTrials = [];
for iFile = 1:numel(existing)
    tok = regexp(existing(iFile).name, '_Trial(\d+)(?:_|\.)', 'tokens', 'once');
    if ~isempty(tok), usedTrials(end + 1) = str2double(tok{1}); end %#ok<AGROW>
end
if meta.auto_trial_number
    % max + 1, not count + 1: a deleted or renamed trial must not make the next run
    % reuse a number that is still on disk.
    if isempty(usedTrials), meta.trialNum = '1';
    else,                   meta.trialNum = num2str(max(usedTrials) + 1);
    end
    fprintf('Auto trial number: %s (%d file(s) matched %s)\n', meta.trialNum, numel(existing), trialGlob);
elseif ismember(str2double(asText(meta.trialNum)), usedTrials)
    warning('run_session_unified:trialReused', ...
            ['Trial %s already exists for this fly in %s (%d file(s) matched %s). The new file is ' ...
             'time-stamped so nothing is overwritten, but two files will claim the same trial number.'], ...
            asText(meta.trialNum), saveFolder, numel(existing), trialGlob);
end
parts = {nameOf.experiment_name, nameOf.genotype, prefixIfNonEmpty('Fly', nameOf.flyNumber), ...
         prefixIfNonEmpty('Trial', meta.trialNum), nameOf.stimulus_regime, nameOf.stimulus_position, ...
         nameOf.phantom_position, nameOf.visual_stim_type, nameOf.carbon_dioxide};
parts = parts(~cellfun(@isempty, parts));
FlyType      = strjoin(parts, '_');
savedate     = datestr(scriptStart, 'yyyy_mmdd_HHMMSS');
baseFileName = [savedate '_' FlyType];

files = struct();
files.mat        = fullfile(saveFolder, [baseFileName '.mat']);
% Backstop against clobbering earlier data. baseFileName starts with a
% second-resolution timestamp, so this only fires if two runs start within the same
% second -- the duplicate-trial-number case is caught by the warning above instead.
if exist(files.mat, 'file')
    error('run_session_unified:fileExists', ...
          '%s already exists; refusing to overwrite it.', files.mat);
end
files.plot_svg   = fullfile(saveFolder, [baseFileName '_plot.svg']);
files.plot_png   = fullfile(saveFolder, [baseFileName '_plot.png']);
vidExt = '.avi';                                        % the Grayscale AVI container
basler.video_ext = vidExt;
if basler.h264.enable, finalExt = '.mp4'; else, finalExt = vidExt; end
files.top_video  = fullfile(saveFolder, [baseFileName '_' basler.top.label finalExt]);   % final location
files.side_video = fullfile(saveFolder, [baseFileName '_' basler.side.label finalExt]);
% Where the DiskLogger actually writes during the run (see basler.video_scratch_folder),
% and where the ffmpeg pass puts its mp4 before the move.
if isempty(basler.video_scratch_folder), scratchDir = saveFolder; else, scratchDir = basler.video_scratch_folder; end
if ~exist(scratchDir, 'dir'), mkdir(scratchDir); end   % videos and the session log stream here
files.top_video_scratch  = fullfile(scratchDir, [baseFileName '_' basler.top.label vidExt]);
files.side_video_scratch = fullfile(scratchDir, [baseFileName '_' basler.side.label vidExt]);
files.top_video_h264     = fullfile(scratchDir, [baseFileName '_' basler.top.label '.mp4']);
files.side_video_h264    = fullfile(scratchDir, [baseFileName '_' basler.side.label '.mp4']);
if anyCam && basler.h264.enable
    % Fail here, before any hardware is touched, rather than after a whole session.
    compress_video_h264_check(basler.h264.ffmpeg);
end
if strcmpi(phantom.save_format, 'cine')
    files.phantom = fullfile(phantom.saveFolder, [baseFileName '_PhantomCamera.cine']);
else
    files.phantom = fullfile(phantom.saveFolder, [baseFileName '_PhantomCamera']);   % folder of TIFFs
end

% Everything the teardown needs is registered in teardownState (a handle) as it is
% created, and teardownAll is a local, not nested, function that reads only that.
% MATLAB clears this function's variables -- the ones nested functions share --
% before an onCleanup task runs at exit (normal, error and Ctrl+C alike), so a nested
% teardown found hw, mainSession, vids, ... already destroyed and stopped before it
% had zeroed the analog outputs or released anything.
teardownState = containers.Map();
teardownState('simulate') = hw.simulate;
cleanupObj = onCleanup(@() teardownAll(teardownState));   % runs on normal exit, error, or Ctrl+C

% From here on everything printed to the command window also goes to <base>_log.txt:
% in the scratch folder while the session runs (saveFolder may be a slow network
% drive), moved next to the .mat by the teardown when the session ends, however it
% ends. A diary the caller had running is taken over.
files.log         = fullfile(saveFolder, [baseFileName '_log.txt']);
files.log_scratch = fullfile(scratchDir, [baseFileName '_log.txt']);
teardownState('log') = struct('scratch', files.log_scratch, 'final', files.log);
diary(files.log_scratch);

fprintf('\n===== %s =====\n', mfilename);
fprintf('Fly        : %s\n', FlyType);
fprintf('Data file  : %s\n', files.mat);
fprintf('Blocks     : %d x %g s @ %d Hz\n', acq.blocks, acq.TrialLength, fs);
fprintf('Visual     : %s (pattern %d)\n', visual.mode, visual.pattern_id);
fprintf('Opto       : %s, %g Hz, %g ms pulses (duty %.0f %%), %g V\n', opto.mode, opto.Frequency, ...
        opto.PulseDuration, 100 * opto.duty_cycle, opto.amplitude_V);
fprintf('Basler     : top %d, side %d, %g fps, %g us\n', basler.top.enable, basler.side.enable, basler.fps, basler.Exposure_time);
if isempty(phantom.gate_col), gateDesc = 'none'; else, gateDesc = sprintf('AI%d (%s)', acq.ai_channels(phantom.gate_col), phantom.gate_ai); end
fprintf('Phantom    : enable %d, %s, window [%g %g] s, trigger at %g s on %s, Recording gate on %s\n', phantom.enable, ...
        phantom.mode, phantom.window_s(1), phantom.window_s(2), phantom.trigger_time_s, phantom.trigAO, gateDesc);

%% ---------------- shared state (used by nested functions) ---------------
% Stored as single: a 16-bit ADC has ~5 significant digits, far inside single's ~7,
% so nothing is lost, and it halves both the in-memory array and the saved file
% (192 -> 96 MB for a 90 s block). Row 1 carries block-relative time, whose spacing
% must stay resolvable in single -- see the assert below.
Data        = zeros(nAI + 1, N_total + 4 * round(fs * acq.notify_period_s), 'single');   % [t; AI...]
wp          = 0;              % write pointer into Data
samplesThisBlock = 0;
currentBlock = 1;
deviceID    = '';

% plot state
plotLive = false;        % runtime flag: the live figure exists and is usable.
                         % plotting.enable stays the user's setting and is what gets
                         % saved in params; losing the figure only clears plotLive.
hFig = []; hRawAx = []; hEmgAx = []; hXAx = []; hLedAx = []; hSumAx = [];
hRawLines = []; hEmgLine = []; hXLine = []; hYLine = [];
hLED = []; hWBA = []; hWBF = []; hBasler = []; hPhRec = [];
hLegRand = []; hLegWin = []; hLegPh = []; hLegTrig = [];
stimColors  = [1 0.196 0.353; 1 0.6 0.2];   % opto randomized = crimson, opto window = orange
phColor     = [0.3 0.5 1];                  % Phantom capture window
phTrigColor = [0.6 0.7 1];                  % Phantom HW trigger
nBinsMax = ceil(size(Data, 2) / plotting.bin_samples) + 1;
decT = nan(1, nBinsMax); decWBF = nan(1, nBinsMax); decWBA = nan(1, nBinsMax); decLED = nan(1, nBinsMax);
decTrig  = false(1, nBinsMax);           % Basler trigger seen in the bin
decPhRec = false(1, nBinsMax);           % Phantom Recording high in the bin
dp = 0;                                  % decimated write pointer
resid = zeros(0, 6);                     % residual raw samples [t wbf wba led trig phrec] awaiting a full bin

% hardware handles
mainSession = []; lh = [];
vids = struct('top', [], 'side', []);
srcs = struct('top', [], 'side', []);
ph = struct('libsLoaded', false, 'pb', [], 'pr', [], 'camObj', [], 'CN', [], 'aqParams', [], 'bmi', []);
ledSignalCurrent = zeros(N_block, 1);    % used by the simulator
simEnvState = 0;                         % simulator low-pass state

% results
allRandomizedStimOrders = cell(acq.blocks, 1);   % randomized durations per block (read by summarize_*.m)
stimTable = zeros(0, 8);   % [block idx onset_s offset_s duration_ms amp_V onset_global_s source(1=randomized,2=window)]
blockStartIdx  = zeros(1, acq.blocks);
blockStartTime = cell(1, acq.blocks);
blockElapsed_s = nan(1, acq.blocks);
phantom.files              = cell(acq.blocks, 1);
phantom.trigger_sample_idx = nan(acq.blocks, 1);   % block-relative sample of the trigger pulse onset
phantom.arm_called_time_s  = nan(acq.blocks, 1);
phantom.rec_rise_times_s = cell(acq.blocks, 1);
phantom.rec_fall_times_s = cell(acq.blocks, 1);
phantom.rec_on_time_s  = nan(acq.blocks, 1);
phantom.rec_off_time_s = nan(acq.blocks, 1);
phantom.store_wait_s   = nan(acq.blocks, 1);
phantom.save_time_s    = nan(acq.blocks, 1);
phantom.init_ok = false;
baslerInfo = struct();


%% ---------------- arena: closed loop while everything loads ------------
if visual.cl_during_setup, arenaRest(); end

%% ---------------- NI DAQ session ----------------------------------------
aoCol = struct('led', 1, 'phantom', 0);
if ~hw.simulate
    if anyCam
        try                 % close stale previews first; imaqreset then clears the adaptor
            closepreview;
        catch
        end
        imaqreset;
    end
    devices = daq.getDevices;
    assert(~isempty(devices), 'No NI DAQ devices found.');
    if isempty(hw.ni_device), deviceID = devices(1).ID; else, deviceID = hw.ni_device; end
    fprintf('NI device  : %s\n', deviceID);
    teardownState('deviceID') = deviceID;
    teardownState('aoNames')  = {opto.ao};        % outputs the teardown returns to 0 V

    mainSession = daq.createSession('ni');
    teardownState('mainSession') = mainSession;
    aiCh = addAnalogInputChannel(mainSession, deviceID, acq.ai_channels, 'Voltage');
    set(aiCh, 'TerminalConfig', acq.terminal_config);
    fprintf('AI channels: %s, %s\n', mat2str(acq.ai_channels), acq.terminal_config);
    addAnalogOutputChannel(mainSession, deviceID, opto.ao, 'Voltage');            % column 1 = LED
    if phantom.enable
        addAnalogOutputChannel(mainSession, deviceID, phantom.trigAO, 'Voltage'); % column 2 = Phantom trigger
        aoCol.phantom = 2;
        teardownState('aoNames') = {opto.ao, phantom.trigAO};
    end
    if anyCam
        camTrigger = addCounterOutputChannel(mainSession, deviceID, basler.trigger_ctr, 'PulseGeneration');
        camTrigger.Frequency    = basler.fps;
        camTrigger.InitialDelay = basler.trigger_initial_delay_s;
        camTrigger.DutyCycle    = 0.5;
        basler.trigger_terminal = camTrigger.Terminal;
        fprintf('Basler trigger: %s at %g Hz on %s\n', basler.trigger_ctr, basler.fps, basler.trigger_terminal);
    end
    % Set the clock only after every channel exists. The board's aggregate AI limit
    % (250 kS/s on the PCIe-6321) caps the per-channel rate, and a rate set before the
    % channels are added is silently coerced, stretching every queued waveform.
    lim = mainSession.RateLimit;
    if fs > lim(2)
        error('run_session_unified:rate', ...
              ['acq.SampleRate = %g Hz exceeds the maximum of %.1f Hz for %d AI channels on %s. ' ...
               'Lower acq.SampleRate or remove an AI channel.'], fs, lim(2), nAI, deviceID);
    end
    mainSession.Rate = fs;
    assert(abs(mainSession.Rate - fs) < 1e-6 * fs, 'DAQ coerced the sample rate to %.4f Hz.', mainSession.Rate);
    % NotifyWhenDataAvailableExceeds is set per block right after queueOutputData:
    % with analog output channels in the session it cannot be set before data is queued.
    lh = addlistener(mainSession, 'DataAvailable', @onDataAvailable);
    teardownState('lh') = lh;
end

%% ---------------- Basler cameras ----------------------------------------
if anyCam
    wanted = {};
    if basler.top.enable,  wanted{end + 1} = basler.top.serial;  end
    if basler.side.enable, wanted{end + 1} = basler.side.serial; end
    assert(numel(unique(wanted)) == numel(wanted), 'basler.top and basler.side must have different serial numbers.');
    % USB3 cameras can take a moment to re-enumerate after imaqreset: poll until all are visible.
    t0 = tic;
    while true
        camInfo = imaqhwinfo('gentl');
        names = {camInfo.DeviceInfo.DeviceName};
        missing = wanted(~cellfun(@(sn) any(contains(names, ['(' sn ')'])), wanted));
        if isempty(missing) || toc(t0) > basler.discover_timeout_s, break; end
        pause(0.5);
    end
    fprintf('GenTL cameras found:\n');
    for i = 1:numel(camInfo.DeviceInfo)
        fprintf('  [%d] %s (DeviceID %d)\n', i, camInfo.DeviceInfo(i).DeviceName, camInfo.DeviceInfo(i).DeviceID);
    end
    if ~isempty(missing)
        error('run_session_unified:cameraMissing', ...
              ['Basler camera(s) with serial %s not enumerated after %g s. Check the USB connection, ' ...
               'close Pylon Viewer / other GenTL clients, or set basler.<camera>.enable = false.'], ...
              strjoin(missing, ', '), basler.discover_timeout_s);
    end
    if basler.top.enable,  [vids.top,  srcs.top]  = setupBasler('top',  camInfo, files.top_video_scratch);  teardownState('vids') = vids; end
    if basler.side.enable, [vids.side, srcs.side] = setupBasler('side', camInfo, files.side_video_scratch); teardownState('vids') = vids; end
end

%% ---------------- Phantom connect / configure ---------------------------
if phantom.enable
    try
        LoadPhantomLibraries();
        ph.libsLoaded = true;       teardownState('ph') = ph;
        ph.pb = PoolBuilder([]);    teardownState('ph') = ph;
        ph.pb.Register();
        ph.pr = PoolRefresher();    teardownState('ph') = ph; %#ok<NASGU> -- a handle the teardown reads

        t0 = tic; lastN = -1;
        while toc(t0) < phantom.discover_timeout_s
            ph.pr.RefreshCameras();
            pause(0.2);
            n = ph.pr.GetCameraListLength();
            if n ~= lastN
                fprintf('Phantom pool sees %d camera(s)\n', n);
                for ii = 1:n
                    c = ph.pr.GetCameraAt(ii);
                    fprintf('  [%d] %s\n', ii, char(c.ToString()));
                end
                lastN = n;
            end
            for ii = 1:n
                c = ph.pr.GetCameraAt(ii);
                if contains(char(c.ToString()), sprintf('(%d)', phantom.serial))
                    ph.camObj = c;
                    break;
                end
            end
            if ~isempty(ph.camObj), break; end
        end
        assert(~isempty(ph.camObj), 'Phantom camera with serial %d not found.', phantom.serial);

        ph.CN = ph.camObj.GetCameraNumber();
        fprintf('Phantom    : CN=%d serial=%d\n', ph.CN, phantom.serial);

        PhSetPartitions(ph.CN, 1, 1);
        [~, ph.aqParams, ph.bmi] = PhGetCineParams(ph.CN, 1);

        % ACQUIPARAMS field names are fixed by the SDK header (PhConML.h); Exposure is in ns.
        ph.aqParams.Exposure = uint32(phantom.exposure_us * 1000);

        if strcmp(phantom.mode, 'fixed_fps')
            ph.aqParams.SyncImaging = uint32(0);                  % internal clock
            ph.aqParams.dFrameRate  = double(phantom.fps);
            if strcmp(phantom.trigger_at, 'start')
                ptFrames = round(phantom.fps * diff(phantom.window_s));
            else
                ptFrames = phantom.pt_frames;
            end
            ph.aqParams.PTFrames = uint32(ptFrames);
            phantom.pt_frames_set = ptFrames;
            fprintf('Phantom    : fixed %g fps, %d post-trigger frames\n', phantom.fps, ptFrames);
        else
            fprintf('Phantom    : external F-Sync; sync mode, fps, pre-trigger and ROI left to PCC\n');
        end

        PhSetSingleCineParams(ph.CN, ph.aqParams);
        [~, phantom.aqParams_readback] = PhGetCineParams(ph.CN, 1);
        phantom.init_ok = true;
    catch ME
        warning('run_session_unified:phantomInit', 'Phantom init failed: %s. Continuing WITHOUT Phantom.', ME.message);
        phantom.enable = false;
    end
end

if ~exist(phantom.saveFolder, 'dir') && phantom.enable, mkdir(phantom.saveFolder); end

%% ---------------- live figure ------------------------------------------
if plotting.enable, initLivePlot(); plotLive = true; end

%% ---------------- run blocks -------------------------------------------
if anyCam
    fprintf('Starting Basler acquisition...\n');
    if ~isempty(vids.top),  start(vids.top);  end
    if ~isempty(vids.side), start(vids.side); end
end
arenaCmd('stop');

tExperiment = tic;
for block = 1:acq.blocks
    currentBlock = block;
    fprintf('\n--- Block %d of %d ---\n', block, acq.blocks);

    % LED waveform + stimulus bookkeeping
    [ledSignal, rows, order] = buildOptoSignal(opto, N_block, fs, acq.TrialLength);
    allRandomizedStimOrders{block} = order;
    if ~isempty(rows)
        nR = size(rows, 1);
        stimTable = [stimTable; repmat(block, nR, 1), (1:nR)', rows(:, 1:4), ...
                     rows(:, 1) + (block - 1) * acq.TrialLength, rows(:, 5)]; %#ok<AGROW>
        srcNames = {'randomized', 'window'};
        for i = 1:nR
            fprintf('  stim %d (%s): %g-%g s (%g ms, %g V)\n', i, srcNames{rows(i, 5)}, rows(i, 1), rows(i, 2), rows(i, 3), rows(i, 4));
        end
    end
    ledSignalCurrent = ledSignal;

    % Phantom trigger waveform
    phantomSignal = zeros(N_block, 1);
    doPhantomThisBlock = phantom.enable && (phantom.record_each_block || block == phantom.block_to_record);
    if doPhantomThisBlock
        trig_idx0 = round(phantom.trigger_time_s * fs) + 1;
        trig_idx1 = min(N_block, trig_idx0 + max(1, round(phantom.trigPulse_s * fs)) - 1);
        phantomSignal(trig_idx0:trig_idx1) = phantom.trigAmp_V;
        phantom.trigger_sample_idx(block) = trig_idx0;
        fprintf('  Phantom capture from %g s, HW trigger at %.3f s\n', phantom.capture_start_s, phantom.trigger_time_s);
    end

    if aoCol.phantom > 0, aoData = [ledSignal, phantomSignal]; else, aoData = ledSignal; end
    aoData(end, :) = 0;   % never leave the LED / Phantom trigger latched when the block ends
    if ~hw.simulate
        queueOutputData(mainSession, aoData);
        mainSession.NotifyWhenDataAvailableExceeds = round(fs * acq.notify_period_s);
    end

    if plotAlive()
        try
            drawBlockShading(block, rows, phantomPlanned && (phantom.record_each_block || block == phantom.block_to_record));
        catch ME
            plotLive = false;
            warning('run_session_unified:livePlot', ...
                    'Block shading failed (%s); plotting disabled for the rest of the run.', ME.message);
        end
    end

    % arena stimulus for this block
    arenaStartBlock();

    % start acquisition
    blockStartIdx(block)  = wp + 1;
    blockStartTime{block} = datestr(datetime('now', 'TimeZone', 'local'), 'yyyy-mm-dd HH:MM:SS.FFF');
    samplesThisBlock = 0;
    if ~hw.simulate, mainSession.startBackground(); end
    tBlock = tic;

    armed  = false;
    loopPeriod = 0.01;

    simDelivered = 0;
    while true
        tnow = toc(tBlock);

        if hw.simulate
            target = min(N_block, floor(tnow * hw.sim_speed * fs));
            chunk  = round(fs * acq.notify_period_s);
            while simDelivered + chunk <= target
                onDataAvailable([], simulateChunk(simDelivered, chunk));
                simDelivered = simDelivered + chunk;
            end
            if simDelivered >= N_block, break; end
            if simDelivered + chunk > N_block && target >= N_block
                onDataAvailable([], simulateChunk(simDelivered, N_block - simDelivered));
                break;
            end
        else
            if tnow >= acq.TrialLength && (samplesThisBlock >= N_block || ~mainSession.IsRunning), break; end
            if tnow > acq.TrialLength + 5
                warning('Block %d: DAQ did not finish within 5 s of the trial end; stopping it.', block);
                break;
            end
        end

        if doPhantomThisBlock && ~armed && tnow >= phantom.capture_start_s
            phantom.arm_called_time_s(block) = tnow;
            phantomStartCapture();
            armed = true;
        end

        pause(loopPeriod);
    end

    if ~hw.simulate
        mainSession.stop();
    end
    arenaCmd('stop');
    % Close the partial summary bin here, not just at the end of the run: global time
    % jumps by TrialLength at a block boundary, so leftover samples carried across
    % would be averaged into one bin straddling the discontinuity. A no-op whenever
    % the chunk size divides evenly by plotting.bin_samples, which it does by default.
    flushResidual();
    blockElapsed_s(block) = toc(tBlock);
    fprintf('  Block %d done in %.2f s, %d samples\n', block, blockElapsed_s(block), samplesThisBlock);

    % Recording gate edges for this block, from the Phantom "Recording" analog channel
    if doPhantomThisBlock && ~isempty(phantom.gate_col)
        bIdx = blockStartIdx(block):wp;
        g = Data(1 + phantom.gate_col, bIdx) > acq.ttl_threshold_V;
        if phantom.gate_invert, g = ~g; end
        [riseT, fallT, onT, offT] = gateEdges(Data(1, bIdx), g);
        phantom.rec_rise_times_s{block} = riseT; phantom.rec_fall_times_s{block} = fallT;
        phantom.rec_on_time_s(block) = onT;      phantom.rec_off_time_s(block) = offT;
        fprintf('  Recording gate: %d rising, %d falling edges; ON %.3f s, OFF %.3f s\n', numel(riseT), numel(fallT), onT, offT);
        if isempty(riseT) && isempty(fallT)
            if any(g), lvl = 'high'; else, lvl = 'low'; end
            warning('Recording gate showed no edges in block %d (%s stayed %s). Check the cable, the PCC pin function or phantom.gate_invert.', ...
                    block, phantom.gate_ai, lvl);
        end
    end

    % Phantom store + save
    if doPhantomThisBlock
        try
            fprintf('  Waiting for Phantom cine to store...\n');
            tw = tic;
            waitForStore(phantom.store_timeout_s);
            phantom.store_wait_s(block) = toc(tw);
            ts = tic;
            phantom.files{block} = savePhantomCine(block);
            phantom.save_time_s(block) = toc(ts);
            fprintf('  Phantom saved to %s (%.1f s)\n', phantom.files{block}, phantom.save_time_s(block));
        catch ME
            warning('run_session_unified:phantomSave', 'Phantom save failed in block %d: %s', block, ME.message);
        end
    end
end
experimentElapsed_s = toc(tExperiment);

%% ---------------- stop cameras, arena to rest ---------------------------
if ~isempty(vids.top),  stop(vids.top);  end
if ~isempty(vids.side), stop(vids.side); end
arenaRest();
if ~isempty(lh), delete(lh); lh = []; end

%% ---------------- assemble and save (BEFORE the videos) -----------------
% The DAQ data is the irreplaceable part of a session, so it goes to disk before
% anything touches the cameras: an out-of-memory getdata, a full disk or a codec
% failure in writeCameraVideo must not be able to take the whole run with it.
% baslerInfo is saved as a placeholder here and appended for real further down.
Data = Data(:, 1:wp);

params = struct();
params.script          = mfilename;
params.FlyType         = FlyType;
params.baseFileName    = baseFileName;
params.saveFolder      = saveFolder;
params.files           = files;
params.meta            = meta;
params.hw              = hw;
params.acq             = acq;
params.visual          = visual;
params.opto            = opto;
params.basler          = basler;
params.plotting        = plotting;
params.ni_device       = deviceID;
params.data_rows       = [{'time_s'}, acq.ai_names];
params.data_class      = class(Data);   % 'single' since 2026-09; cast on load if needed
params.blockStartIdx   = blockStartIdx;
params.blockStartTime  = blockStartTime;
params.blockElapsed_s  = blockElapsed_s;
params.experimentElapsed_s = experimentElapsed_s;
params.start_time      = datestr(scriptStart, 'yyyy-mm-dd HH:MM:SS');
params.end_time        = datestr(datetime('now', 'TimeZone', 'local'), 'yyyy-mm-dd HH:MM:SS');
params.matlab_version  = version;
params.computer        = getenv('COMPUTERNAME');
% What produced this file: the commit of the code folder (and whether it carried
% uncommitted changes) plus the full text of both source files, so a session can be
% traced even after session_defaults.m has been rewritten by later runs.
[params.git_commit, params.git_dirty] = codeVersion(fileparts(mfilename('fullpath')));
params.script_text   = fileread(which(mfilename));
params.defaults_text = fileread(which('session_defaults'));
params.stimTable_columns = {'block', 'stim_idx', 'onset_s', 'offset_s', 'duration_ms', 'amplitude_V', 'onset_global_s', 'source_1randomized_2window'};

fprintf('\nSaving %s ...\n', files.mat);
saveArgs = {'Data', 'allRandomizedStimOrders', 'stimTable', 'params', 'phantom', 'baslerInfo'};
% The default v7 format gzips the array. On analog noise that buys ~6 % while
% costing ~3 s per 90 s block, and it scales with acq.blocks. Measured on a
% 14 x 1.8e6 array: v7 2.9 s / 181 MB, -v7.3 4.2 s / 179 MB,
% -v7.3 -nocompression 0.1 s / 192 MB. -nocompression is R2017a (9.2) and newer.
% NOTE: v7.3 is HDF5. MATLAB load() is unaffected, but Python readers need h5py --
% scipy.io.loadmat cannot read v7.3 files.
saveArgs{end + 1} = '-v7.3';
if ~verLessThan('matlab', '9.2'), saveArgs{end + 1} = '-nocompression'; end
tSave = tic;
save(files.mat, saveArgs{:});
fprintf('Saved (%.1f s).\n', toc(tSave));

%% ---------------- write Basler videos ----------------------------------
% Each camera is isolated: one failing must not stop the other, the baslerInfo
% append, or the summary plot. The DAQ data is already on disk at this point.
if ~isempty(vids.top)
    try
        baslerInfo.top = writeCameraVideo(vids.top, srcs.top, basler.top, files.top_video_scratch);
    catch ME
        warning('run_session_unified:videoWrite', '%s: video write failed: %s', basler.top.label, ME.message);
    end
end
if ~isempty(vids.side)
    try
        baslerInfo.side = writeCameraVideo(vids.side, srcs.side, basler.side, files.side_video_scratch);
    catch ME
        warning('run_session_unified:videoWrite', '%s: video write failed: %s', basler.side.label, ME.message);
    end
end
if ~isempty(vids.top),  delete(vids.top);  vids.top  = []; end   % closes the DiskLogger file
if ~isempty(vids.side), delete(vids.side); vids.side = []; end

% Compress (ffmpeg, H.264, pending rotation applied) and move the finished videos from
% the local scratch folder into saveFolder. Done only now, with the cameras released
% and the .mat already saved, so a slow encode or Google Drive copy can cost time but
% never data. On any failure the file stays in scratch and baslerInfo.<cam>.file says
% where it is.
if isfield(baslerInfo, 'top')
    [baslerInfo.top, srcFile] = compressVideo(baslerInfo.top, files.top_video_scratch, files.top_video_h264, basler.h264);
    baslerInfo.top = moveVideoToSaveFolder(baslerInfo.top, srcFile, files.top_video);
end
if isfield(baslerInfo, 'side')
    [baslerInfo.side, srcFile] = compressVideo(baslerInfo.side, files.side_video_scratch, files.side_video_h264, basler.h264);
    baslerInfo.side = moveVideoToSaveFolder(baslerInfo.side, srcFile, files.side_video);
end

if anyCam
    try
        save(files.mat, 'baslerInfo', '-append');   % replaces the placeholder saved above
        fprintf('baslerInfo appended to %s\n', files.mat);
    catch ME
        warning('run_session_unified:baslerInfoAppend', ...
                'Could not append baslerInfo to %s: %s', files.mat, ME.message);
    end
end

%% ---------------- final plot -------------------------------------------
% The data is already on disk by this point, so a failure here costs only the
% figure files: never let it skip the return value or the end-of-run sound.
% (sgtitle is R2018b+, so this also covers older rig MATLAB releases.)
if plotAlive()
  try
    flushResidual();
    refreshSummary();
    sgtitle(hFig, FlyType, 'Color', 'w', 'Interpreter', 'none', 'FontSize', 9);
    drawnow;
    if plotting.save_svg, saveas(hFig, files.plot_svg, 'svg'); fprintf('Plot saved: %s\n', files.plot_svg); end
    if plotting.save_png, print(hFig, files.plot_png, '-dpng', '-r150'); fprintf('Plot saved: %s\n', files.plot_png); end
  catch ME
    warning('run_session_unified:finalPlot', ...
            'Final plot failed: %s. The data in %s is unaffected.', ME.message, files.mat);
  end
end

%% ---------------- done ------------------------------------------------
out = struct('Data', Data, 'params', params, 'phantom', phantom, ...
             'stimTable', stimTable, 'allRandomizedStimOrders', {allRandomizedStimOrders}, ...
             'baslerInfo', baslerInfo);

if hw.play_sound_at_end && ~hw.simulate, playEndSound(); end
fprintf('\nAll done (%.1f s).\n', experimentElapsed_s);

% Last, once MATLAB has nothing else to do, so the window is responsive at once.
% Reads the file just written, so it shows exactly what was saved.
if plotting.session_overview
    try
        session_overview(files.mat, plotting.overview_channels);
    catch ME
        warning('run_session_unified:sessionOverview', ...
                'session_overview failed: %s. The data in %s is unaffected.', ME.message, files.mat);
    end
end

%% ======================= NESTED FUNCTIONS ===============================

    function onDataAvailable(~, evt)
        % Store the incoming chunk and update the live plot.
        d = evt.Data; t = evt.TimeStamps(:)';
        n = numel(t);
        if wp + n > size(Data, 2)     % should not happen; grow defensively
            Data(:, end + 1:wp + n + N_block) = 0;
        end
        idx = wp + 1:wp + n;
        Data(1, idx)         = t;
        Data(2:nAI + 1, idx) = d(:, 1:nAI)';
        wp = wp + n;
        samplesThisBlock = samplesThisBlock + n;
        % This runs inside the DataAvailable listener: nothing here may throw, or the
        % error escapes the callback and aborts the whole session. The figure is
        % operator-facing and can vanish at any moment (closed by hand, or a stray
        % close all), and drawnow inside updateLivePlot can process that close
        % mid-call -- hence the try/catch as well as the plotAlive() check.
        if plotAlive()
            try
                updateLivePlot(t, d(:, 1:nAI));
            catch ME
                plotLive = false;
                warning('run_session_unified:livePlot', ...
                        'Live plot failed (%s); plotting disabled for the rest of the run. Acquisition continues.', ...
                        ME.message);
            end
        end
    end

    function ok = plotAlive()
        % True while the live figure exists and can be drawn into. The first time it
        % is found gone, plotting is switched off for the remainder of the run so the
        % experiment keeps going without a figure.
        ok = plotLive && ~isempty(hFig) && isvalid(hFig);
        if plotLive && ~ok
            plotLive = false;
            fprintf('Live figure closed; plotting disabled for the rest of the run (acquisition continues).\n');
        end
    end

    function initLivePlot()
        hFig = figure('Name', ['run_session_unified: ' FlyType], 'NumberTitle', 'off', ...
                      'Color', 'k', 'Position', [40 40 1450 900], 'InvertHardcopy', 'off');
        ch = plotting.ch;
        axW = 0.76;                                   % axes width; legends live in the right-hand column
        if plotting.show_raw
            % top: latest chunk of WBF, WBA, LED driver, right Hutchen
            hRawAx = axes('Parent', hFig, 'Position', [0.06 0.75 axW 0.18]);
            hold(hRawAx, 'on');
            hRawLines = [plot(hRawAx, nan, nan, 'Color', [0 0.5 1], 'LineWidth', 1.2), ...
                         plot(hRawAx, nan, nan, 'g'), ...
                         plot(hRawAx, nan, nan, 'r'), ...
                         plot(hRawAx, nan, nan, 'm')];
            styleAxes(hRawAx);
            ylabel(hRawAx, {'latest chunk', '(V)'}, 'Color', 'w', 'FontSize', 8);
            lg = legend(hRawAx, hRawLines, {'WBF', 'WBA (L+R)/2', 'LED driver', niceName(acq.ai_names{ch.hutchen_right})}, ...
                        'TextColor', 'w', 'Color', 'k', 'FontSize', 8);
            placeLegend(lg, 0.95);
            % middle 1: EMG / Hutchen trigger
            hEmgAx = axes('Parent', hFig, 'Position', [0.06 0.625 axW 0.10]);
            hEmgLine = plot(hEmgAx, nan, nan, 'Color', [0.85 0.85 0.85]);
            styleAxes(hEmgAx);
            ylabel(hEmgAx, {niceName(acq.ai_names{ch.emg}), '(V)'}, 'Color', 'w', 'FontSize', 8);
            % middle 2: arena X and Y position
            hXAx = axes('Parent', hFig, 'Position', [0.06 0.50 axW 0.10]);
            hold(hXAx, 'on');
            hXLine = plot(hXAx, nan, nan, 'Color', [1 0.9 0.2]);
            hYLine = plot(hXAx, nan, nan, 'Color', [0.4 0.8 1]);
            styleAxes(hXAx);
            ylabel(hXAx, {'arena x / y', '(V)'}, 'Color', 'w', 'FontSize', 8);
            lg = legend(hXAx, [hXLine hYLine], {'arena x', 'arena y'}, 'TextColor', 'w', 'Color', 'k', 'FontSize', 8);
            placeLegend(lg, 0.60);
            ledPos = [0.06 0.37 axW 0.095];
            sumPos = [0.06 0.07 axW 0.275];
        else
            ledPos = [0.06 0.80 axW 0.12];
            sumPos = [0.06 0.08 axW 0.68];
        end

        % LED driver on its own 0-10 V axis, time-linked to the summary below
        hLedAx = axes('Parent', hFig, 'Position', ledPos);
        hLED = plot(hLedAx, nan, nan, 'r', 'LineWidth', 1);
        styleAxes(hLedAx);
        set(hLedAx, 'XTickLabel', [], 'YLim', [-0.5 10.5], 'YTick', 0:5:10);
        ylabel(hLedAx, {'LED driver', '(V)'}, 'Color', 'w', 'FontSize', 8);

        % bottom: running summary over the whole experiment
        hSumAx = axes('Parent', hFig, 'Position', sumPos);
        hold(hSumAx, 'on');
        hWBA    = plot(hSumAx, nan, nan, 'g', 'LineWidth', 1);
        hWBF    = plot(hSumAx, nan, nan, 'LineWidth', 2, 'Color', [0 0.5 1]);
        hBasler = patch(hSumAx, nan(4, 1), nan(4, 1), [0 0.9 0.9], 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        hPhRec  = patch(hSumAx, nan(4, 1), nan(4, 1), phColor, 'FaceAlpha', 0.35, 'EdgeColor', 'none');
        % legend proxies for the per-block shading / trigger line drawn in drawBlockShading
        hLegRand = patch(hSumAx, nan(1, 4), nan(1, 4), stimColors(1, :), 'FaceAlpha', 0.25, 'EdgeColor', 'none');
        hLegWin  = patch(hSumAx, nan(1, 4), nan(1, 4), stimColors(2, :), 'FaceAlpha', 0.25, 'EdgeColor', 'none');
        hLegPh   = patch(hSumAx, nan(1, 4), nan(1, 4), phColor, 'FaceAlpha', 0.12, 'EdgeColor', 'none');
        hLegTrig = plot(hSumAx, nan, nan, '-.', 'Color', phTrigColor);
        plot(hSumAx, [0 acq.TrialLength * acq.blocks], [0 0], '--w', 'HandleVisibility', 'off');
        for b = 2:acq.blocks
            plot(hSumAx, (b - 1) * acq.TrialLength * [1 1], plotting.ylim, ':', 'Color', [0.5 0.5 0.5], ...
                 'HandleVisibility', 'off');
        end
        xlim(hSumAx, [0 acq.TrialLength * acq.blocks]);
        ylim(hSumAx, plotting.ylim);
        linkaxes([hLedAx hSumAx], 'x');
        styleAxes(hSumAx);
        set(hSumAx, 'LineWidth', 2, 'FontSize', 9);
        xlabel(hSumAx, 'Time (s)', 'Color', 'w');
        ylabel(hSumAx, sprintf('\\DeltaWBF (Hz)   \\DeltaWBA x%g (V)', plotting.wba_gain), 'Color', 'w');

        hs = [hWBA hWBF];
        names = {sprintf('\\DeltaWBA x%g (V)', plotting.wba_gain), '\DeltaWBF (Hz)'};
        if anyCam || hw.simulate
            hs(end + 1) = hBasler; names{end + 1} = 'Basler recording';
        end
        if any(strcmp(opto.mode, {'randomized', 'both'}))
            hs(end + 1) = hLegRand; names{end + 1} = 'opto randomized';
        end
        if any(strcmp(opto.mode, {'windows', 'both'}))
            hs(end + 1) = hLegWin; names{end + 1} = 'opto window';
        end
        if phantomPlanned
            hs(end + 1) = hLegPh;   names{end + 1} = 'Phantom capture window (planned)';
            hs(end + 1) = hLegTrig; names{end + 1} = 'Phantom HW trigger';
        end
        if ~isempty(phantom.gate_col) || hw.simulate
            hs(end + 1) = hPhRec; names{end + 1} = 'Phantom recording (measured)';
        end
        lg = legend(hSumAx, hs, names, 'TextColor', 'w', 'Color', 'k', 'FontSize', 8);
        placeLegend(lg, sumPos(2) + sumPos(4));
        drawnow;
    end

    function styleAxes(ax)
        set(ax, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'FontSize', 8, 'Box', 'off');
    end

    function placeLegend(lg, topY)
        % Park a legend in the right-hand column, top edge at normalized figure height topY.
        set(lg, 'Units', 'normalized');
        pos = get(lg, 'Position');
        set(lg, 'Position', [0.835, topY - pos(4), pos(3), pos(4)]);
    end

    function drawBlockShading(block, rows, doPh)
        % Opto stimuli (crimson randomized / orange window) and Phantom window for this block.
        off = (block - 1) * acq.TrialLength;
        yl = plotting.ylim;
        for iw = 1:size(rows, 1)
            if rows(iw, 3) <= 0 || rows(iw, 4) == 0, continue; end
            p = patch(hSumAx, off + [rows(iw, 1) rows(iw, 2) rows(iw, 2) rows(iw, 1)], [yl(1) yl(1) yl(2) yl(2)], ...
                      stimColors(rows(iw, 5), :), 'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            uistack(p, 'bottom');
        end
        if doPh
            w = phantom.window_s;
            p = patch(hSumAx, off + [w(1) w(2) w(2) w(1)], [yl(1) yl(1) yl(2) yl(2)], phColor, ...
                      'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            uistack(p, 'bottom');
            plot(hSumAx, off + phantom.trigger_time_s * [1 1], yl, '-.', 'Color', phTrigColor, 'HandleVisibility', 'off');
        end
    end

    function updateLivePlot(t, d)
        ch = plotting.ch;
        wbaRaw = (d(:, ch.wbaL) + d(:, ch.wbaR)) / 2;                  % V
        if plotting.show_raw
            set(hRawLines(1), 'XData', t, 'YData', d(:, ch.wbf)');
            set(hRawLines(2), 'XData', t, 'YData', wbaRaw');
            set(hRawLines(3), 'XData', t, 'YData', d(:, ch.led)');
            set(hRawLines(4), 'XData', t, 'YData', d(:, ch.hutchen_right)');
            set(hEmgLine, 'XData', t, 'YData', d(:, ch.emg)');
            set(hXLine,   'XData', t, 'YData', d(:, ch.arena_x)');
            set(hYLine,   'XData', t, 'YData', d(:, ch.arena_y)');
            if numel(t) > 1          % a 1-sample chunk gives equal limits, which errors
                set([hRawAx hEmgAx hXAx], 'XLim', [t(1) t(end)]);
            end
        end
        tg = t(:) + (currentBlock - 1) * acq.TrialLength;              % global time
        resid = [resid; tg, 100 * d(:, ch.wbf), wbaRaw, d(:, ch.led), d(:, ch.basler_trig), d(:, ch.phantom_rec)];
        nb = floor(size(resid, 1) / plotting.bin_samples);
        if nb > 0
            m   = nb * plotting.bin_samples;
            blk = reshape(resid(1:m, 1:3), plotting.bin_samples, nb, 3);
            mu  = reshape(mean(blk, 1), nb, 3);
            led = max(reshape(resid(1:m, 4), plotting.bin_samples, nb), [], 1);   % bin max: shows the drive voltage, not the duty-cycle mean
            trg = max(reshape(resid(1:m, 5), plotting.bin_samples, nb), [], 1);
            rec = max(reshape(resid(1:m, 6), plotting.bin_samples, nb), [], 1);
            decT(dp + 1:dp + nb)     = mu(:, 1)';
            decWBF(dp + 1:dp + nb)   = mu(:, 2)';
            decWBA(dp + 1:dp + nb)   = mu(:, 3)';
            decLED(dp + 1:dp + nb)   = led;
            decTrig(dp + 1:dp + nb)  = trg > acq.ttl_threshold_V;
            decPhRec(dp + 1:dp + nb) = rec > acq.ttl_threshold_V;
            dp = dp + nb;
            resid = resid(m + 1:end, :);
            refreshSummary();
        end
        drawnow limitrate
    end

    function flushResidual()
        if ~isempty(resid)
            dp = dp + 1;
            decT(dp) = mean(resid(:, 1)); decWBF(dp) = mean(resid(:, 2));
            decWBA(dp) = mean(resid(:, 3)); decLED(dp) = max(resid(:, 4));
            decTrig(dp)  = max(resid(:, 5)) > acq.ttl_threshold_V;
            decPhRec(dp) = max(resid(:, 6)) > acq.ttl_threshold_V;
            resid = zeros(0, 6);
        end
    end

    function refreshSummary()
        if dp == 0, return; end
        bl = decT(1:dp) <= plotting.baseline_s;
        if ~any(bl), bl = 1:dp; end
        set(hWBF, 'XData', decT(1:dp), 'YData', decWBF(1:dp) - mean(decWBF(bl)));
        set(hWBA, 'XData', decT(1:dp), 'YData', plotting.wba_gain * (decWBA(1:dp) - mean(decWBA(bl))));
        set(hLED, 'XData', decT(1:dp), 'YData', decLED(1:dp));
        % Recording bands, one translucent rectangle per contiguous "on" run near the top of the axis:
        % Basler = a trigger pulse within +-1 frame period; Phantom = the camera's Recording output high.
        win = max(1, ceil(2 * fs / basler.fps / plotting.bin_samples));
        yr  = diff(plotting.ylim);
        setRunBand(hBasler, movmax(double(decTrig(1:dp)), win) > 0, plotting.ylim(2) - 0.05 * yr, plotting.ylim(2) - 0.02 * yr);
        setRunBand(hPhRec,  decPhRec(1:dp),                          plotting.ylim(2) - 0.09 * yr, plotting.ylim(2) - 0.06 * yr);
    end

    function setRunBand(h, on, yBot, yTop)
        dOn = diff([false, on(:)', false]);
        i0  = find(dOn == 1);
        i1  = find(dOn == -1) - 1;
        if isempty(i0)
            set(h, 'XData', nan(4, 1), 'YData', nan(4, 1));
        else
            t0 = decT(i0); t1 = decT(i1);
            set(h, 'XData', [t0; t1; t1; t0], 'YData', repmat([yBot; yBot; yTop; yTop], 1, numel(t0)));
        end
    end

    function evt = simulateChunk(n0, n)
        % Synthetic data for hw.simulate: samples n0+1 .. n0+n of the current block.
        t   = ((n0:n0 + n - 1)') / fs;
        led = ledSignalCurrent(n0 + 1:n0 + n);
        alpha = 1 / (0.3 * fs);                                   % ~0.3 s first-order "response" to the LED
        env = filter(alpha, [1, -(1 - alpha)], double(led > 0.5), simEnvState * (1 - alpha));
        simEnvState = env(end);
        wbf  = 2.2 - 0.4 * env + 0.01 * randn(n, 1);
        wbaL = 3 + 0.3 * sin(2 * pi * 0.2 * t) + 0.02 * randn(n, 1);
        wbaR = 3 - 0.3 * sin(2 * pi * 0.2 * t) + 0.02 * randn(n, 1);
        hutL = zeros(n, 1); hutR = zeros(n, 1);
        ax   = 1 + 8 * mod(t / 10, 1);
        ay   = 5 + 2 * sin(2 * pi * 0.05 * t);
        emg  = 0.1 * randn(n, 1);
        trg  = 5 * double(mod(t * basler.fps, 1) < 0.5);
        fsync = 5 * double(mod(t * phantom.fps, 1) < 0.5);
        shutter = trg;                                           % ExposureActive, active high
        phrec = 5 * double(t >= phantom.window_s(1) & t <= phantom.window_s(2));
        d = zeros(n, nAI);                                       % columns by name, as the DAQ delivers them
        ch = plotting.ch;
        d(:, ch.led) = led;   d(:, ch.wbf) = wbf;   d(:, ch.wbaL) = wbaL;   d(:, ch.wbaR) = wbaR;
        d(:, ch.hutchen_left) = hutL;   d(:, ch.hutchen_right) = hutR;
        d(:, ch.arena_x) = ax;   d(:, ch.arena_y) = ay;   d(:, ch.emg) = emg;
        d(:, ch.basler_trig) = trg;   d(:, ch.phantom_fsync) = fsync;
        d(:, ch.basler_shutter) = shutter;   d(:, ch.phantom_rec) = phrec;
        evt = struct('TimeStamps', t, 'Data', d);
    end

    function arenaCmd(cmd, arg)
        if ~arenaActive, return; end
        if nargin < 2, Panel_com(cmd); else, Panel_com(cmd, arg); end
        pause(hw.panel_pause);
    end

    function arenaRest()
        % Closed-loop stripe: used before setup and after the experiment.
        arenaCmd('stop');
        arenaCmd('set_pattern_id', visual.rest.pattern_id);
        arenaCmd('set_mode', [1, 0]);
        arenaCmd('set_position', [visual.rest.x_pos, 1]);
        arenaCmd('send_gain_bias', [visual.rest.CL_X_gain, 0, 0, 0]);
        arenaCmd('start');
    end

    function arenaStartBlock()
        switch lower(visual.mode)
            case 'closed_loop_stripe'
                arenaCmd('set_pattern_id', visual.pattern_id);
                arenaCmd('set_mode', visual.mode_xy);
                arenaCmd('set_position', [visual.x_pos, 1]);
                arenaCmd('send_gain_bias', [visual.CL_X_gain, 0, 0, 0]);
            case 'closed_loop_oscillating'
                arenaCmd('set_pattern_id', visual.pattern_id);
                arenaCmd('set_mode', visual.mode_xy);
                arenaCmd('set_velfunc_id', [2, visual.velfunc_id]);
                arenaCmd('set_funcy_freq', visual.funcy_freq);
                arenaCmd('send_gain_bias', [visual.CL_X_gain, 0, visual.y_gain, visual.y_bias]);
            case 'none'
                return;
            otherwise
                error('Unknown visual.mode "%s"', visual.mode);
        end
        arenaCmd('start');
    end

    function [vid, src] = setupBasler(camKey, camInfo, videoFile)
        cfg   = basler.(camKey);
        names = {camInfo.DeviceInfo.DeviceName};
        idx = find(contains(names, ['(' cfg.serial ')']), 1);
        assert(~isempty(idx), '%s: serial %s not found among GenTL devices.', cfg.label, cfg.serial);
        fprintf('%s -> %s (DeviceID %d)\n', cfg.label, names{idx}, camInfo.DeviceInfo(idx).DeviceID);
        vid = videoinput('gentl', camInfo.DeviceInfo(idx).DeviceID, basler.format);
        triggerconfig(vid, 'hardware');
        vid.LoggingMode      = 'disk';   % frames encode to disk as they arrive; nothing buffers in RAM
        vid.FramesPerTrigger = inf;
        src = getselectedsource(vid);
        if cfg.exposure_active_out                 % Line3 = ExposureActive, active high (read back on AI11)
            src.LineSelector = 'Line3';
            src.LineMode     = 'output';
            src.LineSource   = 'ExposureActive';
            src.LineInverter = 'False';
        end
        src.LineSelector      = 'Line4';
        src.LineMode          = 'input';
        src.LineInverter      = cfg.line_inverter;
        src.TriggerSelector   = 'FrameStart';
        src.TriggerMode       = 'Off';
        src.TriggerSource     = 'Line4';
        src.TriggerActivation = 'RisingEdge';
        src.TriggerDelay      = 0;
        if cfg.binning > 1
            src.BinningHorizontal     = cfg.binning;
            src.BinningVertical       = cfg.binning;
            src.BinningHorizontalMode = 'Sum';
            src.BinningVerticalMode   = 'Sum';
        end
        src.ExposureTime = basler.Exposure_time;
        src.Gain         = cfg.gain;
        src.Gamma        = cfg.gamma;

        % Rotation must be baked in on-camera: with disk logging the frame goes
        % straight from the sensor to the encoder, so MATLAB never sees it. Only
        % 180 deg is expressible in GenICam (ReverseX + ReverseY); 90/270 are left
        % for analysis and recorded in baslerInfo.<cam>.rotate_deg_pending.
        basler.(camKey).rotation_applied   = 'none';
        basler.(camKey).rotate_deg_pending = cfg.rotate_deg;
        if cfg.rotate_deg == 180
            try
                src.ReverseX = 'True';
                src.ReverseY = 'True';
                basler.(camKey).rotation_applied   = 'camera_reverse_xy';
                basler.(camKey).rotate_deg_pending = 0;
                fprintf('  180 deg baked in on-camera (ReverseX + ReverseY)\n');
            catch ME
                warning('run_session_unified:cameraRotate', ...
                        '%s: could not set ReverseX/ReverseY (%s). Video is unrotated; analysis must apply %d deg.', ...
                        cfg.label, ME.message, cfg.rotate_deg);
            end
        elseif cfg.rotate_deg ~= 0
            fprintf('  %d deg NOT applied (no GenICam equivalent); analysis must rotate. See baslerInfo.%s.rotate_deg_pending\n', ...
                    cfg.rotate_deg, camKey);
        end

        % The DiskLogger must exist before start(); the engine opens and closes it.
        vw = VideoWriter(videoFile, basler.video_profile);
        vw.FrameRate = basler.fps;
        vid.DiskLogger = vw;

        src.TriggerMode  = 'On';
        fprintf('  trigger %s on %s, exposure %g us, gain %.3f, gamma %.2f, binning %d\n', ...
                src.TriggerMode, src.TriggerSource, src.ExposureTime, src.Gain, src.Gamma, cfg.binning);
        fprintf('  streaming to %s (%s)\n', videoFile, basler.video_profile);
    end

    function info = writeCameraVideo(vid, src, cfg, filename)
        % Disk logging did the encoding during the run; only the last buffered
        % frames can still be in flight. Wait for the logger to drain, then report.
        info = struct('label', cfg.label, 'file', filename, 'frames', 0, ...
                      'frames_acquired', 0, 'dropped_frames', 0, 'expected_frames', ...
                      acq.blocks * acq.TrialLength * basler.fps, ...
                      'rotate_deg', cfg.rotate_deg, ...
                      'rotation_applied', cfg.rotation_applied, ...
                      'rotate_deg_pending', cfg.rotate_deg_pending, ...
                      'video_profile', basler.video_profile);
        try
            info.source_settings = get(src);
        catch
            info.source_settings = [];
        end
        t0 = tic;
        while vid.FramesAcquired ~= vid.DiskLoggerFrameCount
            if toc(t0) > basler.disk_flush_timeout_s
                warning('run_session_unified:diskFlush', ...
                        '%s: disk logger still %d frame(s) behind after %g s; closing the file anyway.', ...
                        cfg.label, vid.FramesAcquired - vid.DiskLoggerFrameCount, basler.disk_flush_timeout_s);
                break;
            end
            pause(0.05);
        end
        info.frames_acquired = vid.FramesAcquired;
        info.frames          = vid.DiskLoggerFrameCount;
        info.dropped_frames  = info.frames_acquired - info.frames;
        info.flush_wait_s    = toc(t0);
        fprintf('%s: %d frames written to %s (acquired %d, expected ~%d, flush %.2f s)\n', ...
                cfg.label, info.frames, filename, info.frames_acquired, info.expected_frames, info.flush_wait_s);
        if info.frames == 0
            warning('%s: no frames written to %s.', cfg.label, filename);
        elseif info.dropped_frames > 0
            warning('run_session_unified:droppedFrames', '%s: %d frame(s) acquired but never written.', ...
                    cfg.label, info.dropped_frames);
        end
        if info.rotate_deg_pending ~= 0
            fprintf('%s: video is UNROTATED; analysis must apply %d deg clockwise.\n', cfg.label, info.rotate_deg_pending);
        end
    end

    function phantomStartCapture()
        % framesync / fixed 'end': start capture (like PCC "Capture");
        % fixed 'start': arm and wait for the HW trigger. Same SDK calls either way.
        fprintf('  t=%.2f s: starting Phantom capture\n', phantom.arm_called_time_s(currentBlock));
        try
            ph.camObj.SetSelectedCinePartNo(uint32(1));
        catch
        end
        started = false;
        try
            ph.camObj.RecordSpecificCine(uint32(1));
            started = true;
        catch
        end
        if ~started
            try
                ph.camObj.Record();
                started = true;
            catch
            end
        end
        if ~started, PhRecordCine(ph.CN); end
    end

    function waitForStore(timeout_s)
        t0 = tic;
        while toc(t0) < timeout_s
            stored = false;
            try
                st = ph.camObj.GetCinePartitionStatus(uint32(1));
                stored = logical(st.Stored);
            catch
            end
            if ~stored
                try
                    [~, cs] = PhGetCineStatus(ph.CN);
                    for ics = 1:numel(cs)
                        if cs(ics).Stored == 1, stored = true; break; end
                    end
                catch
                end
            end
            if stored, return; end
            pause(0.05);
        end
        error('Timed out after %g s waiting for the Phantom cine to store.', timeout_s);
    end

    function target = savePhantomCine(block)
        if phantom.record_each_block && acq.blocks > 1
            suffix = sprintf('_block%d', block);
        else
            suffix = '';
        end
        [~, CH] = PhNewCineFromCamera(ph.CN, 1);
        PhSetUseCase(CH, PhFileConst.UC_SAVE);
        if strcmpi(phantom.save_format, 'cine')
            target = strrep(files.phantom, '.cine', [suffix '.cine']);
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILENAME, libpointer('cstring', target));
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILETYPE, libpointer('uint32Ptr', PhFileConst.MIFILE_RAWCINE));
        else
            target = [files.phantom suffix];
            if ~exist(target, 'dir'), mkdir(target); end
            [~, seqBase] = fileparts(target);
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILENAME, libpointer('cstring', fullfile(target, seqBase)));
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILETYPE, libpointer('uint32Ptr', PhFileConst.SIFILE_TIF12));
        end
        PhWriteCineFile(CH);
        try
            PhDestroyCine(CH);
        catch
        end
    end

end   % run_session_unified

%% ======================= LOCAL FUNCTIONS ================================

function teardownAll(state)
% Idempotent teardown: safe after a normal run, an error, or Ctrl+C. It reads only
% state (see where teardownState is created): by the time an onCleanup task runs,
% run_session_unified's own variables may already have been cleared.
lh          = entry(state, 'lh');
mainSession = entry(state, 'mainSession');
vids        = entry(state, 'vids');
ph          = entry(state, 'ph');
try
    if ~isempty(lh), delete(lh); end
catch
end
try
    if ~isempty(mainSession), stop(mainSession); end
catch
end
zeroAnalogOutputs(state);     % before release: the fast path needs a live session
try
    if ~isempty(mainSession), release(mainSession); end
catch
end
for camKey = {'top', 'side'}
    try
        v = vids.(camKey{1});
        if ~isempty(v) && isvalid(v), stop(v); delete(v); end
    catch
    end
end
try
    if ~isempty(ph.pr), ph.pr.delete(); end
catch
end
try
    if ~isempty(ph.pb)
        try
            if ph.pb.IsRegistered, ph.pb.Unregister(); end
        catch
        end
        ph.pb.delete();
    end
catch
end
try
    if ph.libsLoaded, UnloadPhantomLibraries(); end
catch
end
closeSessionLog(entry(state, 'log'));   % last, so the lines above are in the log
end

function closeSessionLog(log)
% Stop the diary and move <base>_log.txt from the scratch folder next to the .mat.
% Nothing here may throw: this runs inside the teardown.
if isempty(log), return; end
try
    if strcmp(get(0, 'Diary'), 'on'), diary off; end
catch
end
try
    if exist(log.scratch, 'file') == 2 && ~strcmpi(log.scratch, log.final)
        [ok, msg] = movefile(log.scratch, log.final, 'f');
        if ~ok
            warning('run_session_unified:logMove', 'Could not move the session log %s to %s: %s', ...
                    log.scratch, log.final, msg);
        end
    end
catch
end
end

function [commit, dirty] = codeVersion(folder)
% HEAD commit of the git repository holding folder, and whether tracked files had
% uncommitted changes when the session ran. 'unknown' / NaN when git is not on the
% PATH or the folder is not a repository.
commit = 'unknown'; dirty = NaN;
try
    [st, txt] = system(sprintf('git -C "%s" rev-parse HEAD', folder));
    if st ~= 0, return; end
    commit = strtrim(txt);
    [st, txt] = system(sprintf('git -C "%s" status --porcelain --untracked-files=no', folder));
    if st == 0, dirty = ~isempty(strtrim(txt)); end
catch
end
end

function ch = channelColumns(aiNames)
% Column within acq.ai_names of each signal the code refers to by a short key.
wanted = {'led', 'LED_driver'; 'wbf', 'WBF'; 'wbaL', 'WBA_left'; 'wbaR', 'WBA_right'; ...
          'hutchen_left', 'hutchen_left'; 'hutchen_right', 'hutchen_right'; ...
          'arena_x', 'arena_x'; 'arena_y', 'arena_y'; 'emg', 'EMG'; ...
          'basler_trig', 'basler_trigger'; 'phantom_fsync', 'phantom_fsync'; ...
          'basler_shutter', 'basler_shutter'; 'phantom_rec', 'phantom_recording'};
ch = struct();
for k = 1:size(wanted, 1)
    col = find(strcmpi(aiNames, wanted{k, 2}), 1);
    if isempty(col)
        error('run_session_unified:channelName', ...
              'acq.ai_names has no entry "%s" (the %s signal). Names present: %s', ...
              wanted{k, 2}, wanted{k, 1}, strjoin(aiNames, ', '));
    end
    ch.(wanted{k, 1}) = col;
end
end

function [t, changed] = fileNameParts(meta)
% The metadata fields that build the file name, as text with every character Windows
% refuses in a file name replaced by '-'. A '/' in meta.stimulus_regime ('2/5ms')
% used to turn the base name into a path through a folder that does not exist, and
% the save failed after the whole session had run. params.meta keeps the values as
% entered.
fieldsUsed = {'experiment_name', 'genotype', 'flyNumber', 'trialNum', 'stimulus_regime', ...
              'stimulus_position', 'phantom_position', 'visual_stim_type', 'carbon_dioxide'};
t = struct(); changed = {};
for k = 1:numel(fieldsUsed)
    raw   = asText(meta.(fieldsUsed{k}));
    clean = regexprep(strtrim(raw), '[\\/:*?"<>|\x00-\x1F]', '-');
    if ~strcmp(clean, raw), changed{end + 1} = sprintf('%s ''%s'' -> ''%s''', fieldsUsed{k}, raw, clean); end %#ok<AGROW>
    t.(fieldsUsed{k}) = clean;
end
if ~isempty(changed)
    warning('run_session_unified:fileNameSanitized', ...
            'Changed for the file name (params.meta keeps what was entered): %s', strjoin(changed, '; '));
end
end

function zeroAnalogOutputs(state)
% Drive every analog output back to 0 V. NI-DAQmx holds the last written sample when
% a task is stopped or released, so aborting mid-stimulus would otherwise leave the
% LED driver latched at opto.amplitude_V until MATLAB restarts. Fast path: an
% on-demand scan on the session. If that is rejected (the session also owns the ctr0
% PulseGeneration channel), release it and take the channels with a short-lived
% AO-only session instead.
mainSession = entry(state, 'mainSession');
deviceID    = entry(state, 'deviceID');
aoNames     = entry(state, 'aoNames');
if isequal(entry(state, 'simulate'), true) || isempty(deviceID), return; end
z = zeros(1, numel(aoNames));
try
    outputSingleScan(mainSession, z);
    fprintf('Analog outputs (%s) returned to 0 V.\n', strjoin(aoNames, ', '));
    return;
catch
end
s = [];
try
    try
        if ~isempty(mainSession), release(mainSession); end
    catch
    end
    s = daq.createSession('ni');
    for iAO = 1:numel(aoNames)
        addAnalogOutputChannel(s, deviceID, aoNames{iAO}, 'Voltage');
    end
    outputSingleScan(s, z);
    fprintf('Analog outputs (%s) returned to 0 V.\n', strjoin(aoNames, ', '));
catch ME
    warning('run_session_unified:aoZero', ...
            'Could not return %s to 0 V: %s. CHECK THE LED DRIVER MANUALLY.', ...
            strjoin(aoNames, ', '), ME.message);
end
try
    if ~isempty(s), release(s); end
catch
end
end

function v = entry(state, key)
% state(key), or [] for a resource that was never created.
if isKey(state, key), v = state(key); else, v = []; end
end

function compress_video_h264_check(ffmpegSetting)
% Resolve ffmpeg the same way compress_video_h264 will after the run; errors with
% compress_video_h264:ffmpegNotFound if there is none, before any hardware is touched.
exe = compress_video_h264('which', ffmpegSetting);
fprintf('ffmpeg     : %s\n', exe);
end

function [info, outFile] = compressVideo(info, rawFile, mp4File, h)
% ffmpeg pass for one camera: raw scratch AVI -> H.264 mp4 in the scratch folder,
% applying the rotation the camera could not. Returns the file the move step should
% take: the mp4 on success, the raw AVI when compression is off or failed.
outFile = rawFile;
info.h264 = struct('enabled', h.enable, 'ok', false);
if ~h.enable || ~exist(rawFile, 'file'), return; end
opts = h;
opts.rotate_deg = info.rotate_deg_pending;
fprintf('%s: compressing %s -> H.264 (crf %g, %s, rotate %d deg) ...\n', ...
        info.label, rawFile, h.crf, h.preset, opts.rotate_deg);
try
    r = compress_video_h264(rawFile, mp4File, opts);
catch ME
    warning('run_session_unified:h264', '%s: compression not run (%s). The raw AVI is kept: %s', ...
            info.label, ME.message, rawFile);
    return;
end
info.h264 = r;
info.h264.enabled = true;
if ~r.ok
    warning('run_session_unified:h264', '%s: ffmpeg failed (%.1f s). The raw AVI is kept: %s\n%s', ...
            info.label, r.seconds, rawFile, r.output);
    if exist(mp4File, 'file'), delete(mp4File); end
    return;
end
if isfinite(r.frames) && r.frames ~= info.frames
    warning('run_session_unified:h264Frames', '%s: mp4 has %d frames but %d were logged. The raw AVI is kept: %s', ...
            info.label, r.frames, info.frames, rawFile);
    outFile = mp4File;                               % still deliver the mp4, but do not delete the raw
    info.raw_file_kept = rawFile;
    return;
end
fprintf('%s: H.264 done in %.1f s, %.0f MB -> %.0f MB (%d frames)\n', ...
        info.label, r.seconds, r.bytes_in / 1e6, r.bytes_out / 1e6, r.frames);
info.rotation_applied   = 'ffmpeg';
info.rotate_deg_pending = 0;
outFile = mp4File;
if h.keep_raw
    info.raw_file_kept = rawFile;
else
    delete(rawFile);
end
end

function info = moveVideoToSaveFolder(info, scratchFile, finalFile)
% Move one finished video from the local scratch folder to its final location and
% record the outcome in baslerInfo. A no-op when scratch and final are the same path.
info.scratch_file = scratchFile;
info.file         = scratchFile;
info.moved        = false;
if strcmpi(scratchFile, finalFile)
    info.file  = finalFile;
    info.moved = true;
    return;
end
if ~exist(scratchFile, 'file')
    warning('run_session_unified:videoMove', '%s: nothing to move, %s does not exist.', info.label, scratchFile);
    return;
end
d = dir(scratchFile);
tMove = tic;
[ok, msg] = movefile(scratchFile, finalFile, 'f');
if ok
    info.file   = finalFile;
    info.moved  = true;
    info.move_s = toc(tMove);
    fprintf('%s: moved to %s (%.0f MB, %.1f s)\n', info.label, finalFile, d.bytes / 1e6, info.move_s);
else
    warning('run_session_unified:videoMove', ...
            '%s: could not move %s to %s: %s. The video is still in the scratch folder.', ...
            info.label, scratchFile, finalFile, msg);
end
end

function S = mergeStruct(S, O, path)
% Recursively copy the fields of O onto S, rejecting anything S does not already
% define. Overrides are the documented calling API, so a misspelled field has to
% fail loudly here -- before any hardware is touched -- rather than silently
% leaving the default in force and running a different experiment than the caller
% asked for. ov.hw.simluate = true used to add a dead field and run the rig.
if nargin < 3, path = ''; end
if ~isstruct(O) || ~isstruct(S), S = O; return; end
f     = fieldnames(O);
valid = fieldnames(S);
for i = 1:numel(f)
    name = f{i};
    if isempty(path)
        here = name;              lvl = 'the top level';
    else
        here = [path '.' name];   lvl = path;
    end
    if ~isfield(S, name)
        error('run_session_unified:unknownOverride', ...
              ['Unknown override field "%s".%s\nValid fields at %s: %s\n' ...
               'Add it to session_defaults.m first if it is genuinely new.'], ...
              here, suggestField(name, valid), lvl, strjoin(valid', ', '));
    end
    sIsStruct = isstruct(S.(name));
    oIsStruct = isstruct(O.(name));
    if sIsStruct && oIsStruct
        S.(name) = mergeStruct(S.(name), O.(name), here);
    elseif sIsStruct
        error('run_session_unified:overrideType', ...
              'Override "%s" must be a struct of sub-fields (%s), got a %s.', ...
              here, strjoin(fieldnames(S.(name))', ', '), class(O.(name)));
    elseif oIsStruct
        error('run_session_unified:overrideType', ...
              'Override "%s" must be a %s value like the default, not a struct.', ...
              here, class(S.(name)));
    else
        S.(name) = O.(name);
    end
end
end

function s = suggestField(name, valid)
% Hint for the error above: catches case slips, transpositions and singular/plural.
d   = cellfun(@(v) editDistance(name, v), valid);
tol = max(2, ceil(numel(name) / 4));
keep = d <= tol;
if ~any(keep), s = ''; return; end
hit = valid(keep);
[~, ord] = sort(d(keep));
hit = hit(ord);
s = sprintf(' Did you mean "%s"?', strjoin(hit(1:min(3, numel(hit)))', '" or "'));
end

function d = editDistance(a, b)
% Plain Levenshtein; only ever runs on the error path, so clarity beats speed.
a = lower(a); b = lower(b);
m = numel(a); n = numel(b);
D = zeros(m + 1, n + 1);
D(:, 1) = (0:m)';
D(1, :) = 0:n;
for ii = 1:m
    for jj = 1:n
        D(ii + 1, jj + 1) = min([D(ii, jj + 1) + 1, D(ii + 1, jj) + 1, D(ii, jj) + (a(ii) ~= b(jj))]);
    end
end
d = D(m + 1, n + 1);
end

function s = prefixIfNonEmpty(prefix, value)
t = asText(value);
if isempty(t), s = ''; else, s = [prefix t]; end
end

function s = asText(v)
% Metadata can arrive as a number through overrides (ov.meta.flyNumber = 1), where
% [prefix value] would splice in a character code instead of the digits -- 'Fly'
% followed by char(1) rather than 'Fly1'.
if ischar(v)
    s = v;
elseif isstring(v) || iscellstr(v)
    s = char(v);
elseif isempty(v)
    s = '';
else
    s = num2str(v);
end
end

function s = niceName(name)
s = strrep(name, '_', ' ');
end

function [sig, rows, order] = buildOptoSignal(opto, N, fs, TrialLength)
% Returns the LED command (N x 1) and stimulus rows
% [onset_s offset_s duration_ms amp_V source] with source 1 = randomized, 2 = window,
% plus the randomized duration order for one block (RANDOMIZED stimuli only;
% window stimuli are reported through rows and are excluded from the summarize_* analyses).
sig = zeros(N, 1); rows = zeros(0, 5); order = []; rowsR = zeros(0, 5);
doRand = any(strcmp(opto.mode, {'randomized', 'both'}));
doWin  = any(strcmp(opto.mode, {'windows', 'both'}));
if doRand
    [sig, rowsR, order] = addRandomizedStims(sig, opto, fs, TrialLength);
    rows = [rows; rowsR];
end
if doWin
    [sig, rowsW] = addWindowStims(sig, opto, fs);
    rows = [rows; rowsW];
    for w = 1:size(rowsW, 1)
        overlap = rowsR(:, 3) > 0 & rowsW(w, 1) < rowsR(:, 2) & rowsW(w, 2) > rowsR(:, 1);
        if any(overlap)
            warning('run_session_unified:optoOverlap', ...
                'Opto window %g-%g s overlaps a randomized stimulus; the window overwrites those samples.', ...
                rowsW(w, 1), rowsW(w, 2));
        end
    end
end
end

function [sig, rows, order] = addRandomizedStims(sig, opto, fs, TrialLength)
rows = zeros(0, 5); order = [];
durs = opto.stimDurations(:)';
n = numel(durs);
if n == 0, return; end
if isempty(opto.stimIntensities_V), amps = repmat(opto.amplitude_V, 1, n);
else, amps = opto.stimIntensities_V(:)'; end
assert(numel(amps) == n, 'opto.stimIntensities_V must have one entry per stimDuration.');
if opto.randomize, p = randperm(n); else, p = 1:n; end
order = durs(p); amps = amps(p);
onsets = round((TrialLength / (n + 1)) * (1:n) * fs);      % sample offsets (0-based)
for i = 1:n
    nStim = round(fs * order(i) / 1000);
    [sig, endSamp] = placeTrain(sig, onsets(i), nStim, amps(i), fs, opto.Frequency, opto.duty_cycle);
    rows(i, :) = [onsets(i) / fs, endSamp / fs, order(i), amps(i), 1];   % endSamp = as delivered
end
end

function [sig, rows] = addWindowStims(sig, opto, fs)
rows = zeros(0, 5);
W = opto.windows_s;
n = size(W, 1);
if n == 0, return; end
if isempty(opto.windows_amplitude_V), amps = repmat(opto.amplitude_V, 1, n);
else, amps = opto.windows_amplitude_V(:)'; end
assert(numel(amps) == n, 'opto.windows_amplitude_V must have one entry per window.');
durs_ms = round(diff(W, 1, 2)' * 1000);
for i = 1:n
    on0   = round(W(i, 1) * fs);
    nStim = round((W(i, 2) - W(i, 1)) * fs);
    [sig, endSamp] = placeTrain(sig, on0, nStim, amps(i), fs, opto.Frequency, opto.duty_cycle);
    rows(i, :) = [on0 / fs, endSamp / fs, durs_ms(i), amps(i), 2];   % endSamp = as delivered
end
end

function [sig, endSamp] = placeTrain(sig, onset0, nStim, amp, fs, frequency, dutyCycle)
% Write one gated burst into sig at 0-based sample offset onset0, clipped to the
% end of the block. The carrier comes from the shared pulseTrain kernel, so the
% realised rate stays exact and a sub-sample pulse width raises an error instead
% of silently producing an all-zero burst. Only the clipped length is generated.
%
% endSamp is the last sample the burst actually occupies after clipping, so the
% caller can log what was delivered rather than what was asked for. A sham (0 V,
% or 0 ms) still reports its nominal window: the epoch occupies time even though
% no light comes out, and stimTable has to mark it.
endSamp = min(numel(sig), onset0 + max(0, nStim));
if nStim <= 0 || amp == 0, return; end
i0 = onset0 + 1;
i1 = min(numel(sig), onset0 + nStim);
if i1 < i0, return; end
sig(i0:i1) = pulseTrain(i1 - i0 + 1, amp, fs, frequency, dutyCycle);
end

function [riseTimes, fallTimes, onTime, offTime] = gateEdges(t, gate)
gate = logical(gate(:)); t = t(:);
dv = diff(double(gate));
riseIdx = find(dv > 0.5) + 1;
fallIdx = find(dv < -0.5) + 1;
riseTimes = t(riseIdx); fallTimes = t(fallIdx);
onTime = NaN; offTime = NaN;
if ~isempty(gate) && gate(1)
    onTime = t(1);                       % already high at block start
elseif ~isempty(riseIdx)
    onTime = t(riseIdx(1));
end
if ~isnan(onTime)
    after = fallTimes(fallTimes > onTime);
    if ~isempty(after), offTime = after(1); end
end
end

function playEndSound()
% mi mi mi do / re re re si
for f = [165 165 165], sound(sin(2 * pi * f * (0:0.001:0.4)), 8192); pause(0.2); end
sound(sin(2 * pi * 131 * (0:0.001:4.8)), 8192); pause(1.2);
for f = [147 147 147], sound(sin(2 * pi * f * (0:0.001:0.4)), 8192); pause(0.2); end
sound(sin(2 * pi * 123 * (0:0.001:4.8)), 8192);
end
