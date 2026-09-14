% phantom_opto_experiment.m
%
% Stripped-down acquisition script: Phantom KT810 + optogenetics only.
% No flight arena, no Basler cameras.
%
% Experiment timeline (45 s total):
%   t =  0 s : NI DAQ output starts (LED + Phantom trigger waveforms)
%   t =  1 s : Phantom capture (Record) commanded
%   t = 11-14 s : Optogenetic stimulus 1  (200 Hz, 1 ms pulses)
%   t = 21-24 s : Optogenetic stimulus 2
%   t = 31-34 s : Optogenetic stimulus 3
%   t = 44 s : HW trigger pulse -> Phantom stores cine
%   t = 45 s : Session ends; TIFF12 sequence saved
%
% Phantom is run at fixed 100 fps (internal clock, NOT external F-Sync).
% Post-trigger frames are set to a small buffer; all meaningful frames
% are pre-trigger (circular buffer fills from t=1 to t=44).
%
% Author: Yichen Luo

clear all; close all; clc

%% -------------------------------------------------------------------------
%  USER-EDITABLE SECTION
% --------------------------------------------------------------------------
saveFolder = ['K:\Yichen\spiracle_movies\SpINB_immobilized\'];   

experiment_name    = 'empty_ChR';
genotype           = 'empty_ChR_4d_F';
flyNumber          = '2';
trialNum           = '1';
stimulus_regime    = '3x3000ms';
phantom_position   = 'sp1';

% Phantom camera serial number
phantom_serial = uint32(34437);

% NI DAQ device (auto-detected below; override here if needed)
deviceID_override  = '';   % e.g. 'Dev1'; leave '' for auto

%% -------------------------------------------------------------------------
%  DERIVED NAMING
% --------------------------------------------------------------------------
now_dt       = datetime('now', 'TimeZone', 'local');
savedate     = datestr(now_dt, 'yyyy_mmdd_HHMMSS');
FlyType      = [experiment_name '_' genotype ...
                '_Fly' flyNumber '_Trial' trialNum ...
                '_' stimulus_regime '_' phantom_position];
baseFileName = [savedate '_' FlyType];

if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

fprintf('Base filename: %s\n', baseFileName);

%% -------------------------------------------------------------------------
%  EXPERIMENT PARAMETERS
% --------------------------------------------------------------------------
variables.TrialLength  = 45;        % s
variables.SampleRate   = 20000;     % Hz  (NI DAQ)

% Optogenetic stimulus
variables.Frequency      = 200;     % pulse repetition rate, Hz
variables.PulseDuration  = 4.5;       % single pulse width, ms

% Stimulus windows [onset offset] in seconds -- three epochs
stim_windows = [11 14;
                21 24;
                31 34];
% Phantom
phantom.fps          = 100;         % fixed internal clock fps
phantom.exposure_us  = 150;         % us; set to match your PCC value

phantom.window_s     = [1 44];      % [capture_start  hw_trigger] in s
%   - Phantom Record() called at window_s(1)
%   - HW trigger (store) fired at window_s(2)
%   - Frames captured: (44-1) * 100 = 4300 pre-trigger frames

phantom.pt_frames    = 10;          % small post-trigger buffer (frames)

phantom.trigAmp_V    = 5.0;
phantom.trigPulse_s  = 0.050;       % 50 ms pulse width

phantom.serial       = phantom_serial;
phantom.saveFolder   = saveFolder;

%% -------------------------------------------------------------------------
%  NI DAQ SETUP
% --------------------------------------------------------------------------
devices = daq.getDevices;
assert(~isempty(devices), 'No NI DAQ devices found.');

if isempty(deviceID_override)
    deviceID = devices(1).ID;
else
    deviceID = deviceID_override;
end
fprintf('Using NI device: %s\n', deviceID);

mainSession      = daq.createSession('ni');
mainSession.Rate = variables.SampleRate;

% Two analog inputs for basic monitoring (timestamps the session)
addAnalogInputChannel(mainSession, deviceID, [0 1], 'Voltage');

% AO1 = LED/optogenetics
addAnalogOutputChannel(mainSession, deviceID, 'ao1', 'Voltage');

% AO0 = Phantom hardware trigger (store pulse)
addAnalogOutputChannel(mainSession, deviceID, 'ao0', 'Voltage');

%% -------------------------------------------------------------------------
%  BUILD OUTPUT WAVEFORMS
% --------------------------------------------------------------------------
N = variables.TrialLength * variables.SampleRate;

% -- LED signal (AO1) -------------------------------------------------------
ledSignal    = zeros(N, 1);
pulse_period = round(variables.SampleRate / variables.Frequency);   % samples
pulse_len    = round(variables.SampleRate * variables.PulseDuration / 1000);

for s = 1:size(stim_windows, 1)
    idx_start = round(stim_windows(s,1) * variables.SampleRate) + 1;
    idx_end   = round(stim_windows(s,2) * variables.SampleRate);

    for p = idx_start : pulse_period : idx_end
        p_end = min(p + pulse_len - 1, idx_end);
        ledSignal(p:p_end) = 10;   % 10 V
    end
end

% -- Phantom trigger (AO0): single pulse at window_s(2) --------------------
phantomSignal = zeros(N, 1);
trig_idx0 = round(phantom.window_s(2) * variables.SampleRate) + 1;
trig_len  = round(phantom.trigPulse_s * variables.SampleRate);
trig_idx1 = min(N, trig_idx0 + trig_len - 1);
phantomSignal(trig_idx0:trig_idx1) = phantom.trigAmp_V;

phantom.trigger_sample_idx     = trig_idx0;
phantom.trigger_sample_idx_end = trig_idx1;
phantom.trigger_time_s         = (trig_idx0 - 1) / variables.SampleRate;

fprintf('LED stimulus epochs:\n');
for s = 1:size(stim_windows,1)
    fprintf('  Stim %d : %g - %g s\n', s, stim_windows(s,1), stim_windows(s,2));
end
fprintf('Phantom HW trigger at t = %.3f s (samples %d:%d)\n', ...
    phantom.trigger_time_s, trig_idx0, trig_idx1);

%% -------------------------------------------------------------------------
%  PHANTOM INIT  (fixed fps -- set dFrameRate and PTFrames)
% --------------------------------------------------------------------------
fprintf('\nInitializing Phantom camera...\n');

LoadPhantomLibraries();

pb = PoolBuilder([]);
pb.Register();
pr = PoolRefresher();

camObj = [];
t0 = tic;
while toc(t0) < 15
    pr.RefreshCameras();
    pause(0.2);
    n = pr.GetCameraListLength();
    for ii = 1:n
        c = pr.GetCameraAt(ii);
        if contains(c.ToString(), sprintf('(%d)', phantom.serial))
            camObj = c;
            break;
        end
    end
    if ~isempty(camObj), break; end
end
assert(~isempty(camObj), 'Phantom camera serial %d not found.', phantom.serial);

CN = camObj.GetCameraNumber();
fprintf('Connected: Phantom CN=%d  serial=%d\n', CN, phantom.serial);

PhSetPartitions(CN, 1, 1);
[~, aqParams, bmi] = PhGetCineParams(CN, 1);

% Fixed fps (unlike the external F-sync workflow in the template)
aqParams = setIfFieldExists(aqParams, 'dFrameRate', double(phantom.fps));

% Exposure
exp_ns = uint32(phantom.exposure_us * 1000);
aqParams = setIfFieldExists(aqParams, 'Exposure',   exp_ns);
aqParams = setIfFieldExists(aqParams, 'ExposureNs', exp_ns);
aqParams = setIfFieldExists(aqParams, 'ExposureNS', exp_ns);

% Post-trigger frames: small value; nearly all frames are pre-trigger
aqParams = setIfFieldExists(aqParams, 'PTFrames',           uint32(phantom.pt_frames));
aqParams = setIfFieldExists(aqParams, 'PostTriggerFrames',  uint32(phantom.pt_frames));

% Push parameters to camera
pushed = false;
try
    PhSetSingleCineParams(CN, aqParams, bmi);
    pushed = true;
catch
end
if ~pushed
    PhSetSingleCineParams(CN, aqParams);
end

fprintf('Phantom parameters set: %d fps, %d us exposure, %d post-trigger frames\n', ...
    phantom.fps, phantom.exposure_us, phantom.pt_frames);
fprintf('Expected pre-trigger frames: %d  (%.1f s @ %d fps)\n', ...
    round(diff(phantom.window_s) * phantom.fps), diff(phantom.window_s), phantom.fps);

%% -------------------------------------------------------------------------
%  RUN EXPERIMENT
% --------------------------------------------------------------------------
fprintf('\n--- Starting 45 s trial ---\n');

% DataAvailable listener: plots incoming AI data in real time,
% same pattern as the original template.
figure(1); clf;
lh = addlistener(mainSession, 'DataAvailable', @plotData);

% Queue output data immediately before starting (avoids "data flushed" warning)
queueOutputData(mainSession, [ledSignal, phantomSignal]);

mainSession.startBackground();
tSess0 = tic;

armed        = false;
arm_at       = phantom.window_s(1);   % 1 s
notified_40s = false;

while toc(tSess0) < variables.TrialLength

    tnow = toc(tSess0);

    % Console alert approaching trigger
    if ~notified_40s && tnow >= 40
        fprintf('>>> t = %.2f s : 40 s reached -- HW trigger fires in ~4 s <<<\n', tnow);
        notified_40s = true;
    end

    % Arm Phantom at t = 1 s
    if ~armed && tnow >= arm_at

        fprintf('t = %.2f s : Starting Phantom capture (Record)...\n', tnow);
        phantom.arm_called_time_s = tnow;

        try
            camObj.SetSelectedCinePartNo(uint32(1));
        catch
        end

        didStart = false;
        try
            camObj.RecordSpecificCine(uint32(1));
            didStart = true;
        catch
        end
        if ~didStart
            try
                camObj.Record();
                didStart = true;
            catch
            end
        end
        if ~didStart
            PhRecordCine(CN);   % low-level fallback
        end

        armed = true;
        fprintf('t = %.2f s : Phantom capture running.\n', toc(tSess0));
    end

    pause(0.001);
end

mainSession.stop();
fprintf('t = %.1f s : Trial complete.\n', toc(tSess0));

%% -------------------------------------------------------------------------
%  WAIT FOR CINE STORE, THEN SAVE TIFF12 SEQUENCE
% --------------------------------------------------------------------------
fprintf('\nWaiting for Phantom cine to store...\n');
waitForStoreOrTimeout(CN, camObj, 180);

seqBase   = [baseFileName '_PhantomCamera'];
seqFolder = fullfile(phantom.saveFolder, seqBase);
if ~exist(seqFolder, 'dir')
    mkdir(seqFolder);
end
tifBasePath = fullfile(seqFolder, seqBase);

fprintf('Saving TIFF12 sequence to:\n  %s\n', seqFolder);

[~, CH] = PhNewCineFromCamera(CN, 1);
PhSetUseCase(CH, PhFileConst.UC_SAVE);

pName    = libpointer('cstring', tifBasePath);
PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILENAME, pName);

saveType = libpointer('uint32Ptr', PhFileConst.SIFILE_TIF12);
PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILETYPE, saveType);

PhWriteCineFile(CH);
try PhDestroyCine(CH); catch, end

phantom.imageFolders = seqFolder;
fprintf('TIFF12 sequence saved.\n');

%% -------------------------------------------------------------------------
%  SAVE METADATA .mat
% --------------------------------------------------------------------------
matPath = fullfile(saveFolder, baseFileName);
save(matPath, 'variables', 'phantom', 'stim_windows', 'baseFileName');
fprintf('Metadata saved: %s.mat\n', matPath);

%% -------------------------------------------------------------------------
%  CLEANUP
% --------------------------------------------------------------------------
try
    delete(lh);
catch
end
try
    release(mainSession);
catch
end
try
    pr.delete();
catch
end
try
    if pb.IsRegistered
        pb.Unregister();
    end
    pb.delete();
catch
end
try
    UnloadPhantomLibraries();
catch
end

fprintf('\nDone.\n');

%% =========================================================================
%  HELPER FUNCTIONS
%  =========================================================================

function plotData(~, event)
    plot(event.TimeStamps, event.Data);
    xlabel('Time (s)');
    ylabel('Voltage (V)');
    drawnow limitrate;
end

function S = setIfFieldExists(S, fieldName, value)
    if isstruct(S) && isfield(S, fieldName)
        try
            S.(fieldName) = value;
        catch
            warning('Field "%s" exists but could not be set.', fieldName);
        end
    end
end

function waitForStoreOrTimeout(CN, camObj, timeout_s)
    t0 = tic;
    while toc(t0) < timeout_s
        stored = false;
        try
            st = camObj.GetCinePartitionStatus(uint32(1));
            if isfield(st, 'Stored')
                stored = logical(st.Stored);
            end
        catch
        end
        if ~stored
            try
                [~, cs] = PhGetCineStatus(CN);
                if isstruct(cs)
                    for ii = 1:numel(cs)
                        if isfield(cs(ii), 'Stored') && cs(ii).Stored == 1
                            stored = true;
                            break;
                        end
                    end
                end
            catch
            end
        end
        if stored
            fprintf('Cine stored successfully.\n');
            return;
        end
        pause(0.05);
    end
    error('Timed out waiting for Phantom cine to store after %d s.', timeout_s);
end