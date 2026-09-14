function phantom_test_AO0_P07_recording_gate()
% Phantom KT810 (GigE) + NI PCIe-6321 (BNC-2110)
% Trigger: AO0 pulse
% Gate:    Port0/Line7 (P0.7) sampled clocked with AI
%
% IMPORTANT:
% - In PCC, set the camera output you wired to P0.7 to "Recording"
%   (e.g., PCC -> Camera Signals / Programmable I/O -> set port to "Recording").
%
% WIRING (minimum):
%   AO0  -> Phantom Trigger In
%   AO GND -> Phantom Trigger GND (common ground required)
%   Phantom Recording OUT -> NI P0.7
%   Phantom GND -> NI DGND

%% -------------------------
% User settings
%% -------------------------
saveFolder = 'K:\Yichen\phantom_test\';
if ~exist(saveFolder,'dir'); mkdir(saveFolder); end

phantomSerial = uint32(34437);

record_s = 20;
phantom_fps = 1500;
phantom_exposure_us = 100;
roi_w = 256; roi_h = 256; roi_x = 0; roi_y = 0;
nFrames_post = phantom_fps * record_s;

% NI acquisition
ai_rate  = 20000;     % Hz
ai_chans = 0:7;       % AI0..AI7
gateLine = 'Port0/Line7';   % P0.7

% AO trigger
trigAOChan  = 'ao0';
trigPulse_s = 0.010;  % 10 ms
trigAmp_V   = 5.0;    % try 5V, adjust if needed

% Add padding so you capture ON/OFF edges
pre_s  = 0.50;         % baseline before arming
post_s = 2.00;         % extra after expected record end
acq_s  = record_s + pre_s + post_s;

%% -------------------------
% Filenames
%% -------------------------
nowT = datetime('now','TimeZone','local');
formatOut = 'yyyy_mmdd_HHMMSS';
baseName = sprintf('KT810_%s', datestr(nowT,formatOut));
cineFileName = fullfile(saveFolder, [baseName '.cine']);
matFileName  = fullfile(saveFolder, [baseName '.mat']);

%% -------------------------
% Pick NI device
%% -------------------------
devices = daq.getDevices;
assert(~isempty(devices), 'No NI DAQ devices found.');
idx = find(strcmpi({devices.Model}, 'PCIe-6321'), 1, 'first');
if isempty(idx)
    warning('PCIe-6321 not found; using first device: %s (%s)', devices(1).ID, devices(1).Model);
    devID = devices(1).ID;
else
    devID = devices(idx).ID;
end
fprintf('Using NI device: %s\n', devID);

%% -------------------------
% NI acquisition session: AI + P0.7 (clocked, aligned)
%% -------------------------
acqSess = daq.createSession('ni');
acqSess.Rate = ai_rate;

addAnalogInputChannel(acqSess, devID, ai_chans, 'Voltage');
addDigitalChannel(acqSess, devID, gateLine, 'InputOnly');  % sampled DI

acqSess.DurationInSeconds = acq_s;

dataChunks = {};
tChunks    = {};
chunkCounter = 0;

acqSess.NotifyWhenDataAvailableExceeds = min(2000, acqSess.NumberOfScans);
lh = addlistener(acqSess, 'DataAvailable', @collectData);

%% -------------------------
% NI AO0 trigger (on-demand)
%% -------------------------
aoSess = daq.createSession('ni');
addAnalogOutputChannel(aoSess, devID, trigAOChan, 'Voltage');
outputSingleScan(aoSess, 0); % idle low

%% -------------------------
% Phantom connect + configure + record
%% -------------------------
phLoaded = false;
CH = [];
pb = [];
pr = [];

try
    LoadPhantomLibraries();
    phLoaded = true;

    pb = PoolBuilder([]);
    pb.Register();
    pr = PoolRefresher();

    % Poll until camera appears
    camObj = [];
    t0 = tic;
    lastN = -1;

    while toc(t0) < 10.0
        pr.RefreshCameras();
        pause(0.2);

        n = pr.GetCameraListLength();
        if n ~= lastN
            fprintf('PoolRefresher now sees %d camera(s)\n', n);
            for i = 1:n
                c = pr.GetCameraAt(i);
                fprintf('  [%d] %s\n', i, c.ToString());
            end
            lastN = n;
        end

        for i = 1:n
            c = pr.GetCameraAt(i);
            if contains(c.ToString(), sprintf('(%d)', phantomSerial))
                camObj = c;
                break;
            end
        end
        if ~isempty(camObj), break; end
    end

    assert(~isempty(camObj), 'Could not find Phantom camera with serial %d.', phantomSerial);
    CN = camObj.GetCameraNumber();
    fprintf('Using Phantom camera CN=%d (serial=%d)\n', CN, phantomSerial);

    % Single partition
    PhSetPartitions(CN, 1, 1);

    % Configure cine params
    [~, aqParams, bmi] = PhGetCineParams(CN, 1);

    aqParams = setIfFieldExists(aqParams, 'dFrameRate', double(phantom_fps));

    exp_ns = uint32(phantom_exposure_us * 1000); % us -> ns
    aqParams = setIfFieldExists(aqParams, 'Exposure',   exp_ns);
    aqParams = setIfFieldExists(aqParams, 'ExposureNs', exp_ns);
    aqParams = setIfFieldExists(aqParams, 'ExposureNS', exp_ns);

    aqParams = setIfFieldExists(aqParams, 'PTFrames', uint32(nFrames_post));
    aqParams = setIfFieldExists(aqParams, 'PostTrigger', int32(nFrames_post));
    aqParams = setIfFieldExists(aqParams, 'PostTriggerFrames', int32(nFrames_post));

    aqParams = setIfFieldExists(aqParams, 'ImWidth',  uint32(roi_w));
    aqParams = setIfFieldExists(aqParams, 'ImHeight', uint32(roi_h));
    aqParams = setIfFieldExists(aqParams, 'ImX', uint32(roi_x));
    aqParams = setIfFieldExists(aqParams, 'ImY', uint32(roi_y));
    aqParams = setIfFieldExists(aqParams, 'ImLeft', uint32(roi_x));
    aqParams = setIfFieldExists(aqParams, 'ImTop',  uint32(roi_y));

    % Push settings (SDK signatures differ)
    pushed = false;
    try
        PhSetSingleCineParams(CN, aqParams, bmi);
        pushed = true;
    catch
    end
    if ~pushed
        PhSetSingleCineParams(CN, aqParams);
    end

    %% -------------------------
    % START NI FIRST (so you can see gate ON edge)
    %% -------------------------
    disp('Starting NI acquisition (AI0-7 + P0.7 gate)...');
    acqSess.startBackground();

    % baseline
    pause(pre_s);

    % Arm camera (this is when "Recording" typically goes high)
    disp('Arming Phantom (waiting for HW trigger)...');
    PhRecordCine(CN);

    pause(0.05);

    % Trigger via AO0 pulse
    disp('Triggering Phantom via AO0 pulse...');
    outputSingleScan(aoSess, trigAmp_V);
    pause(trigPulse_s);
    outputSingleScan(aoSess, 0);

    % Wait NI done
    acqSess.wait(acq_s + 2);

    % Wait for cine stored (with timeout)
    disp('Waiting for Phantom cine to store...');
    waitForStoreOrTimeout(CN, camObj, record_s + 30);

    % Save cine
    [~, CH] = PhNewCineFromCamera(CN, 1);
    disp(['Saving .cine to: ' cineFileName]);

    PhSetUseCase(CH, PhFileConst.UC_SAVE);
    pName = libpointer('cstring', cineFileName);
    PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILENAME, pName);

    saveType = libpointer('uint32Ptr', PhFileConst.MIFILE_RAWCINE);
    PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILETYPE, saveType);

    PhWriteCineFile(CH);

    %% -------------------------
    % Assemble data + parse gate
    %% -------------------------
    allData = vertcat(dataChunks{:});   % samples x (8 analog + 1 digital)
    allTime = vertcat(tChunks{:});      % samples x 1

    aiData  = allData(:, 1:numel(ai_chans));
    gateRaw = allData(:, end);
    tS      = allTime;

    DataAI  = aiData.';      % 8 x N
    tAI     = tS.';          % 1 x N
    GateP07 = (gateRaw > 0.5).';  % 1 x N logical-ish

    gate = (gateRaw > 0.5);
    dgate = diff(gate);

    gate_on_idx  = find(dgate == 1) + 1;
    gate_off_idx = find(dgate == -1) + 1;

    gate_on_times_s  = tS(gate_on_idx);
    gate_off_times_s = tS(gate_off_idx);

    % First ON/OFF times (robust to starting high)
    if gate(1) == 1
        gate_on_time_s = tS(1);   % already high at acquisition start
    elseif ~isempty(gate_on_times_s)
        gate_on_time_s = gate_on_times_s(1);
    else
        gate_on_time_s = [];
    end

    gate_off_time_s = [];
    if ~isempty(gate_off_times_s)
        if isempty(gate_on_time_s)
            gate_off_time_s = gate_off_times_s(1);
        else
            offAfter = gate_off_times_s(gate_off_times_s > gate_on_time_s);
            if ~isempty(offAfter), gate_off_time_s = offAfter(1); end
        end
    end

    fprintf('Gate sampled on %s\n', gateLine);
    fprintf('  rising edges: %d, falling edges: %d\n', numel(gate_on_idx), numel(gate_off_idx));
    if isempty(gate_on_time_s)
        fprintf('  Gate ON not detected (never rose)\n');
    else
        fprintf('  First Gate ON  at t = %.6f s\n', gate_on_time_s);
    end
    if isempty(gate_off_time_s)
        fprintf('  Gate OFF not detected (never fell within window)\n');
    else
        fprintf('  First Gate OFF at t = %.6f s\n', gate_off_time_s);
    end

    %% -------------------------
    % Save MAT
    %% -------------------------
    variables = struct();
    variables.devID = devID;
    variables.ai_rate = ai_rate;
    variables.ai_channels = ai_chans;
    variables.gateLine = gateLine;
    variables.pre_s = pre_s;
    variables.post_s = post_s;
    variables.acq_s = acq_s;

    variables.phantomSerial = phantomSerial;
    variables.phantom_CN = CN;
    variables.phantom_fps = phantom_fps;
    variables.record_s = record_s;
    variables.nFrames_post = nFrames_post;
    variables.exposure_us = phantom_exposure_us;
    variables.roi = [roi_x roi_y roi_w roi_h];

    variables.trigger = struct('type','AO','channel',trigAOChan,'amp_V',trigAmp_V,'pulse_s',trigPulse_s);

    save(matFileName, ...
        'DataAI','tAI', ...
        'GateP07', ...
        'gate_on_time_s','gate_off_time_s', ...
        'gate_on_times_s','gate_off_times_s', ...
        'gate_on_idx','gate_off_idx', ...
        'variables','cineFileName');

    disp(['Saved MAT : ' matFileName]);
    disp(['Saved CINE: ' cineFileName]);

catch ME
    fprintf(2, '\nERROR: %s\n', ME.message);
    for k = 1:numel(ME.stack)
        fprintf(2, '  %s (line %d)\n', ME.stack(k).name, ME.stack(k).line);
    end
end

%% Cleanup
try delete(lh); catch, end
try release(acqSess); catch, end
try release(aoSess); catch, end

if ~isempty(CH)
    try PhDestroyCine(CH); catch, end
end

try
    if ~isempty(pr), pr.delete(); end
catch
end
try
    if ~isempty(pb)
        try
            if pb.IsRegistered, pb.Unregister(); end
        catch
        end
        pb.delete();
    end
catch
end

if phLoaded
    try UnloadPhantomLibraries(); catch, end
end

disp('Done.');

%% Listener
    function collectData(~, evt)
        chunkCounter = chunkCounter + 1;
        dataChunks{chunkCounter,1} = evt.Data;
        tChunks{chunkCounter,1}    = evt.TimeStamps;
    end
end

function S = setIfFieldExists(S, fieldName, value)
    if isstruct(S) && isfield(S, fieldName)
        try
            S.(fieldName) = value;
        catch
            warning('Field "%s" exists but could not be set (type mismatch).', fieldName);
        end
    end
end

function waitForStoreOrTimeout(CN, camObj, timeout_s)
t0 = tic;
while toc(t0) < timeout_s
    stored = false;

    % Prefer camera object if available
    try
        st = camObj.GetCinePartitionStatus(uint32(1));
        if isfield(st,'Stored'), stored = logical(st.Stored); end
    catch
    end

    % Fallback: scan PhGetCineStatus
    if ~stored
        try
            [~, cs] = PhGetCineStatus(CN);
            if isstruct(cs)
                for ii = 1:numel(cs)
                    if isfield(cs(ii),'Stored') && cs(ii).Stored == 1
                        stored = true;
                        break;
                    end
                end
            end
        catch
        end
    end

    if stored, return; end
    pause(0.05);
end
error('Timed out waiting for cine to store.');
end
