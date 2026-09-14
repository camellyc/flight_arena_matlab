% Author: Yichen Luo 8/2024
% Modified to use set_velfunc_id for LED display pattern

% Corrected flight arena experiment code to run continuously in closed loop mode
% with x randomized stimuli durations per trial, y trials per experiment, and
% flexible trial lengths with stimuli delivered at 1/x intervals of the trial length.
imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
                    'Spiracle\Flight_Arena_Data\260219_SpINB_WT\'];
                
% Check if the folder exists, and if not, create it
if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end
%% Specify strings for FlyType
experiment_name = 'SpINB_WT';     % Example: spSN_ChR
genotype = 'IS46338_7d_F';             % Example: SS48339_2d_M
flyNumber = '1';                 % Example: Fly1
trialNum = '2';
stimulus_regime = '0ms';   % Example: 0-3000ms
stimulus_position = 'thorax';
phantom_position = 'sp2';
visual_stim_type = 'oscillating_sine_wave_40';
%% Construct FlyType
FlyType = [experiment_name '_' genotype '_Fly' flyNumber '_Trial' trialNum '_' stimulus_regime '_' stimulus_position '_' phantom_position '_' visual_stim_type];

%% Declare variables

% Arena variables
CL_spatialFreq = -5; % Closed loop gain set to 10Hz
L_X_Pos = 48;
R_X_Pos = L_X_Pos;
variables.blocks = 1;             % 3 blocks per experiment
variables.TrialLength = 100;       % seconds per trial

% LED display pattern variables (NEW)
variables.velfunc_id = 5;        % Velocity function ID for LED pattern. ID = 9: 0.05Hz (20s/cycle) oscillating sine wave.
variables.y_gain = 40;            % Y channel gain for LED pattern
variables.y_bias = 0;             % Y channel bias for LED pattern
variables.CL_X_gain = CL_spatialFreq;

% LED/laser variables
variables.Frequency = 200;        % LED stimulation freq
variables.PulseDuration = 3;      % Each LED pulse is 3ms long.
%stimDurations = [0, 100, 300, 1000, 3000];  % Stimulus durations (ms). You can add any numbers of stims, with variable durations.
%stimDurations = [0, 3000, 3000]; %"3000msx3" 
%stimDurations = [20000]; % "10000ms"
stimDurations = [0]; % "0ms"
%stimDurations = [3000, 3000, 3000, 3000, 3000, 3000];
%stimDurations = [0, 1000, 1500, 2000];
%stimDurations = [0, 20000, 0 , 20000];  

% NIdaq and camera variables
variables.SampleRate = 20000;
variables.Basler_fps = 100;   % Desired fps from the Basler cam - CENTRAL SETTING
variables.Exposure_time = 9000;  % Exposure time in microseconds (adjusted to work with Basler_fps)

% Calculate maximum possible exposure time based on frame rate, with 20% margin for readout
max_exposure_time = (1000000 / variables.Basler_fps) * 0.9;
% Ensure exposure time doesn't exceed maximum
if variables.Exposure_time > max_exposure_time
    variables.Exposure_time = max_exposure_time;
    fprintf('Exposure time adjusted to %d us to accommodate %d fps frame rate\n', ...
        variables.Exposure_time, variables.Basler_fps);
end

% Fixed variables:
variables.conditions = 1; % Single condition: closed loop (CL) only
panel_pause = .005;       % Short time to 'space out' commands sent to controller
now = datetime('now','TimeZone','local');
formatOut = 'yyyy_mmdd_HHMMSS';
FILENAME = [saveFolder datestr(now,formatOut) '_' FlyType];
fid1 = fopen(FILENAME,'w');
min_out_voltage = 0.5; 
max_out_voltage = 10;  
volt_to_code_conversion = 3276.7; 
min_out_code = min_out_voltage*volt_to_code_conversion;
max_out_code = max_out_voltage*volt_to_code_conversion;
analog_output_codes = linspace(min_out_code,max_out_code,variables.conditions);

%% Phantom KT810 settings (NEW)
phantom = struct();
phantom.enable = true;
phantom.serial = uint32(34437);

% Record ONE phantom clip per full experiment:
phantom.record_each_block = false;     % set true for one per block
phantom.block_to_record = 1;           % if not each block

phantom.fps = 1500;
phantom.exposure_us = 150;             % adjust if needed
phantom.roi = [];                      % leave empty to keep PCC ROI (recommended)

phantom.window_s = [10 90];        % trigger at window_s(1); record post window
phantom.post_s = diff(phantom.window_s);
phantom.arm_lead_s = 0.5;              % arm at (trigger - arm_lead_s)

phantom.trigAO = 'ao0';
phantom.trigAmp_V = 5.0;
phantom.trigPulse_s = 0.010;           % 10 ms

% Record Phantom "Recording" line on NI:
phantom.gate_line = 'Port0/Line7';     % "Recording" -> P0.7
phantom.gate_poll_period_s = 0.001;    % 1 ms polling
phantom.gate_invert = false;           % set true if active-low in practice

% Save folder: K:\Yichen\spiracle_movies\experiment_name
phantom.saveRoot = 'K:\Yichen\spiracle_movies\';
phantom.saveFolder = fullfile(phantom.saveRoot, experiment_name);
if ~exist(phantom.saveFolder, 'dir')
    mkdir(phantom.saveFolder);
end

% Storage
phantom.cineFiles = cell(variables.blocks, 1);
phantom.trigger_sample_idx = nan(variables.blocks, 1);
phantom.trigger_sample_idx_end = nan(variables.blocks, 1);
phantom.trigger_time_s = nan(variables.blocks, 1);
phantom.arm_called_time_s = nan(variables.blocks, 1);

phantom.recGate_t = cell(variables.blocks, 1);
phantom.recGate_raw = cell(variables.blocks, 1);
phantom.recGate = cell(variables.blocks, 1);
phantom.rec_rise_times_s = cell(variables.blocks, 1);
phantom.rec_fall_times_s = cell(variables.blocks, 1);
phantom.rec_on_time_s = nan(variables.blocks, 1);
phantom.rec_off_time_s = nan(variables.blocks, 1);
%% Initialize NIdaq device and stim queue

devices = daq.getDevices;
deviceID=devices.ID;

mainSession = daq.createSession('ni');
mainSession.Rate = variables.SampleRate;

% AI 0/data(2,:) : WBA left
% AI 1/data(3,:) : WBA right
% AI 2/data(4,:) : WB frequency
% AI 3/data(5,:) : DAQ1 (arena x position)
% AI 4/data(6,:) : EMG recording
% AI 5/data(7,:) : LED driver input (split ao that goes to LED)
% AI 6/data(8,:) : Right hutchens
% AI 7/data(9,:) : Basler camera trigger input
% AO 0: Phantom camera trigger output
% AO 1: LED trigger output
addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao0','Voltage');

% Gate session (on-demand digital reads; does NOT change mainSession channel count)
gateSess = [];
if phantom.enable
    try
        gateSess = daq.createSession('ni');
        addDigitalChannel(gateSess, deviceID, phantom.gate_line, 'InputOnly');
        fprintf('Phantom Recording gate will be polled on %s\n', phantom.gate_line);
    catch ME
        warning('Could not create gateSess for %s: %s', phantom.gate_line, ME.message);
        phantom.enable = false;
    end
end

% Trigger the camera - USING CENTRALIZED SETTINGS
camTrigger = addCounterOutputChannel(mainSession, deviceID, 'ctr0', 'PulseGeneration');
camTrigger.Frequency = variables.Basler_fps;  % Uses centralized fps setting
camTrigger.InitialDelay = 0.05; % Ensure we capture the first frame
camTrigger.DutyCycle = 0.5;    % 50% duty cycle for reliable triggering

figure(1); clf;
lh = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));

vidDir = saveFolder; % Specify your video folder here
blankvidFile1 = [vidDir datestr(now,formatOut) '_TopCamera_' FlyType];     % For TOP camera (22703705)
blankvidFile2 = [vidDir datestr(now,formatOut) '_SideCamera_' FlyType];    % For SIDE camera (22843477)

% First, list all available cameras to see their IDs
disp('Available cameras:');
camInfo = imaqhwinfo('gentl');
for i = 1:length(camInfo.DeviceInfo)
    fprintf('Device %d: %s (ID: %s)\n', i, camInfo.DeviceInfo(i).DeviceName, camInfo.DeviceInfo(i).DeviceID);
end

% CAMERA 1 SETUP - Using working code configuration
% Camera 1: acA1300-200um (Serial: 22703705)
TopCamera = videoinput('gentl', 1, 'Mono8');  % Device 1 - Serial: 22703705
triggerconfig(TopCamera, 'hardware');
TopCamera.LoggingMode = 'memory';
TopCamera.FramesPerTrigger = inf;  % Changed to inf like working code

TopCamera_src = getselectedsource(TopCamera);

% Configure camera 1 lines and trigger - USING WORKING CODE SETTINGS
TopCamera_src.LineSelector = 'Line4';
TopCamera_src.LineMode = 'input';
TopCamera_src.LineInverter = 'False';  % Changed to False like working code
TopCamera_src.TriggerSelector = 'FrameStart';
TopCamera_src.TriggerMode = 'Off';  % Will set to 'On' after all settings are configured
TopCamera_src.TriggerSource = 'Line4';
TopCamera_src.TriggerActivation = 'RisingEdge';

% Add these for both cameras after TriggerActivation
TopCamera_src.TriggerDelay = 0;

% Set exposure and gain - USING WORKING CODE VALUES
TopCamera_src.BinningHorizontal = 2;  % X binning size = 2
TopCamera_src.BinningVertical = 2;    % Y binning size = 2
TopCamera_src.BinningHorizontalMode = 'Sum';  % Sum mode for X
TopCamera_src.BinningVerticalMode = 'Sum';    % Sum mode for Y

TopCamera_src.ExposureTime = variables.Exposure_time;  % 9ms exposure
TopCamera_src.Gain = 5;  % From working code
TopCamera_src.Gamma = 0.5;     % From working code

% Enable triggering for Camera 1
TopCamera_src.TriggerMode = 'On';

% CAMERA 2 SETUP - Using working code configuration  
% Camera 2: acA800-510um (Serial: 22843477)
SideCamera = videoinput('gentl', 2, 'Mono8');  % Device 2 - Serial: 22843477
triggerconfig(SideCamera, 'hardware');
SideCamera.LoggingMode = 'memory';
SideCamera.FramesPerTrigger = inf;  % Changed to inf like working code

SideCamera_src = getselectedsource(SideCamera);

% Additional Line3 configuration for Camera 2 (from working code)
SideCamera_src.LineSelector = 'Line3';
SideCamera_src.LineMode = 'output';
SideCamera_src.LineSource = 'ExposureActive';
SideCamera_src.LineInverter = 'True';

% Configure camera 2 lines and trigger - USING WORKING CODE SETTINGS
SideCamera_src.LineSelector = 'Line4';
SideCamera_src.LineMode = 'input';
SideCamera_src.LineInverter = 'False';  % Changed to False like working code
SideCamera_src.TriggerSelector = 'FrameStart';
SideCamera_src.TriggerMode = 'Off';
SideCamera_src.TriggerSource = 'Line4';
SideCamera_src.TriggerActivation = 'RisingEdge';

% Add trigger delay
SideCamera_src.TriggerDelay = 0;

% Set exposure and gain - USING WORKING CODE VALUES
SideCamera_src.ExposureTime = variables.Exposure_time;  % 9ms exposure
SideCamera_src.Gain = 12;  % From working code
SideCamera_src.Gamma = 0.4;     % From working code

% Enable triggering for Camera 2
SideCamera_src.TriggerMode = 'On';

% Configure video writers for both cameras - USING WORKING CODE SETTINGS
TopCamera_Logger = VideoWriter(blankvidFile1, 'MPEG-4');    % TOP camera ? TOP file
TopCamera_Logger.FrameRate = variables.Basler_fps;
TopCamera_Logger.Quality = 100;

SideCamera_Logger = VideoWriter(blankvidFile2, 'MPEG-4');   % SIDE camera ? SIDE file
SideCamera_Logger.FrameRate = variables.Basler_fps;
SideCamera_Logger.Quality = 100;

%% Phantom connect/init (NEW)
phantom.pb = [];
phantom.pr = [];
phantom.camObj = [];
phantom.CN = [];
phantom.bmi = [];
phantom.aqParams = [];
phantom.libsLoaded = false;

if phantom.enable
    try
        LoadPhantomLibraries();
        phantom.libsLoaded = true;

        phantom.pb = PoolBuilder([]);
        phantom.pb.Register();
        phantom.pr = PoolRefresher();

        t0 = tic; lastN = -1;
        while toc(t0) < 10.0
            phantom.pr.RefreshCameras();
            pause(0.2);

            n = phantom.pr.GetCameraListLength();
            if n ~= lastN
                fprintf('PoolRefresher now sees %d camera(s)\n', n);
                for ii = 1:n
                    c = phantom.pr.GetCameraAt(ii);
                    fprintf('  [%d] %s\n', ii, c.ToString());
                end
                lastN = n;
            end

            for ii = 1:n
                c = phantom.pr.GetCameraAt(ii);
                if contains(c.ToString(), sprintf('(%d)', phantom.serial))
                    phantom.camObj = c;
                    break;
                end
            end
            if ~isempty(phantom.camObj), break; end
        end

        assert(~isempty(phantom.camObj), 'Phantom camera %d not found.', phantom.serial);

        phantom.CN = phantom.camObj.GetCameraNumber();
        fprintf('Using Phantom camera CN=%d (serial=%d)\n', phantom.CN, phantom.serial);

        PhSetPartitions(phantom.CN, 1, 1);

        [~, phantom.aqParams, phantom.bmi] = PhGetCineParams(phantom.CN, 1);

        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'dFrameRate', double(phantom.fps));

        exp_ns = uint32(phantom.exposure_us * 1000);
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'Exposure',   exp_ns);
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ExposureNs', exp_ns);
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ExposureNS', exp_ns);

        postFrames = uint32(round(phantom.fps * phantom.post_s));
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'PTFrames', postFrames);
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'PostTriggerFrames', int32(postFrames));
        phantom.aqParams = setIfFieldExists(phantom.aqParams, 'PostTrigger', int32(postFrames));

        if ~isempty(phantom.roi) && numel(phantom.roi)==4
            roi_x = uint32(phantom.roi(1)); roi_y = uint32(phantom.roi(2));
            roi_w = uint32(phantom.roi(3)); roi_h = uint32(phantom.roi(4));
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImWidth',  roi_w);
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImHeight', roi_h);
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImX', roi_x);
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImY', roi_y);
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImLeft', roi_x);
            phantom.aqParams = setIfFieldExists(phantom.aqParams, 'ImTop',  roi_y);
        end

        pushed = false;
        try
            PhSetSingleCineParams(phantom.CN, phantom.aqParams, phantom.bmi);
            pushed = true;
        catch
        end
        if ~pushed
            PhSetSingleCineParams(phantom.CN, phantom.aqParams);
        end

    catch ME
        warning('Phantom init failed: %s', ME.message);
        phantom.enable = false;
    end
end

% Debug output - check all important camera settings for both cameras
fprintf('\nCamera 1 Setup Summary (Serial: 22703705):\n');
fprintf('  Device Name: %s\n', camInfo.DeviceInfo(1).DeviceName);
fprintf('  Trigger Mode: %s\n', TopCamera_src.TriggerMode);
fprintf('  Frame Rate: %d fps (capture)\n', variables.Basler_fps);
fprintf('  Exposure Time: %d µs\n', TopCamera_src.ExposureTime);
fprintf('  Gain: %.6f\n', TopCamera_src.Gain);
fprintf('  Video Writer Frame Rate: %d fps\n', TopCamera_Logger.FrameRate);

fprintf('\nCamera 2 Setup Summary (Serial:22843477 ):\n');
fprintf('  Device Name: %s\n', camInfo.DeviceInfo(2).DeviceName);
fprintf('  Trigger Mode: %s\n', SideCamera_src.TriggerMode);
fprintf('  Frame Rate: %d fps (capture)\n', variables.Basler_fps);
fprintf('  Exposure Time: %d µs\n', SideCamera_src.ExposureTime);
fprintf('  Gain: %.6f\n', SideCamera_src.Gain);
fprintf('  Video Writer Frame Rate: %d fps\n\n', SideCamera_Logger.FrameRate);

%% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks, 1);

%% Run Arena Program, acquire data per trial

Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

% Start the camera before the trials begin
disp('Starting camera...');
start([TopCamera, SideCamera])

for block = 1:variables.blocks
    fprintf(['Starting block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
    % Randomize the order of stimulus durations for each trial
    randomizedStimOrder = stimDurations(randperm(length(stimDurations)));
    
    % Store the randomized stimulus order
    allRandomizedStimOrders{block} = randomizedStimOrder;
    
    % Prepare the output signal for the trial
    outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);
    
    % Calculate stimulus times.
    stimTimes = round((variables.TrialLength / ((length(stimDurations)+1))) * (1:(length(stimDurations))) * variables.SampleRate); % Use round to ensure integer indices

    for i = 1:length(randomizedStimOrder)
        currentStimDuration = randomizedStimOrder(i);
        nStimTime = variables.SampleRate * (currentStimDuration / 1000);
        nPulseDuration = variables.SampleRate * (variables.PulseDuration / 1000);
        nIPI = (1000 - (variables.PulseDuration * variables.Frequency)) / variables.Frequency;

        % Generate the stimulus at the calculated times
        for o = 1:nPulseDuration
            outputSignal(stimTimes(i)+o:(nPulseDuration+nIPI):(stimTimes(i) + nStimTime), 1) = 10;
        end
    end

    % -------------------------
    % Build Phantom trigger waveform on AO0 (NEW)
    % -------------------------
    N = numel(outputSignal);
    phantomSignal = zeros(N, 1);

    doPhantomThisBlock = phantom.enable && (phantom.record_each_block || block == phantom.block_to_record);

    if doPhantomThisBlock
        trig_idx0 = round(phantom.window_s(1) * variables.SampleRate) + 1;
        trig_len  = max(1, round(phantom.trigPulse_s * variables.SampleRate));
        trig_idx1 = min(N, trig_idx0 + trig_len - 1);

        phantomSignal(trig_idx0:trig_idx1) = phantom.trigAmp_V;

        phantom.trigger_sample_idx(block) = trig_idx0;
        phantom.trigger_sample_idx_end(block) = trig_idx1;
        phantom.trigger_time_s(block) = (trig_idx0 - 1) / variables.SampleRate;
    end

    % Queue two AO channels: [AO1 LED, AO0 Phantom]
    queueOutputData(mainSession, [outputSignal, phantomSignal]);

    tic
    Panel_com('set_pattern_id', 13); pause(panel_pause);
    Panel_com('set_mode', [1, 0]); pause(panel_pause);

    Panel_com('set_velfunc_id', [2, variables.velfunc_id]); pause(panel_pause);
    Panel_com('set_funcy_freq', 50); pause(panel_pause);
    Panel_com('send_gain_bias',[variables.CL_X_gain, 0, variables.y_gain, variables.y_bias]); pause(panel_pause);

    Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);

    Panel_com('start');
    mainSession.startBackground();

    % -------------------------
    % NEW: arm Phantom + poll Recording gate during trial
    % -------------------------
    tSess0 = tic;
    armed = false;
    arm_at = max(0, phantom.window_s(1) - phantom.arm_lead_s);

    gate_t = [];
    gate_raw = [];
    k = 0;

    if doPhantomThisBlock && ~isempty(gateSess)
        gate_t = zeros(ceil(variables.TrialLength / phantom.gate_poll_period_s) + 5, 1);
        gate_raw = false(size(gate_t));
    end

    while toc(tSess0) < variables.TrialLength
        tnow = toc(tSess0);

        % Arm Phantom shortly before trigger time
        if doPhantomThisBlock && ~armed && tnow >= arm_at
            disp('Arming Phantom (waiting for HW trigger)...');
            phantom.arm_called_time_s(block) = tnow;
            PhRecordCine(phantom.CN);
            armed = true;
        end

        % Poll Recording line
        if doPhantomThisBlock && ~isempty(gateSess)
            k = k + 1;
            gate_t(k) = tnow;
            try
                v = inputSingleScan(gateSess);
                gate_raw(k) = logical(v(1));
            catch
                gate_raw(k) = false;
            end
        end

        pause(phantom.gate_poll_period_s);
    end

    mainSession.stop();
    Panel_com('stop'); pause(panel_pause);
    Panel_com('set_ao',[4, 0]); pause(panel_pause);
    toc

    % -------------------------
    % NEW: Save gate trace + derive ON/OFF times
    % -------------------------
    if doPhantomThisBlock && ~isempty(gateSess) && ~isempty(gate_t)
        gate_t = gate_t(1:k);
        gate_raw = gate_raw(1:k);

        gate = gate_raw;
        if phantom.gate_invert
            gate = ~gate;
        end

        [riseTimes, fallTimes, onTime, offTime] = gateEdges(gate_t, gate);

        phantom.recGate_t{block} = gate_t;
        phantom.recGate_raw{block} = gate_raw;
        phantom.recGate{block} = gate;
        phantom.rec_rise_times_s{block} = riseTimes;
        phantom.rec_fall_times_s{block} = fallTimes;
        phantom.rec_on_time_s(block) = onTime;
        phantom.rec_off_time_s(block) = offTime;

        fprintf('Gate sampled on %s\n', phantom.gate_line);
        fprintf('  rising edges: %d, falling edges: %d\n', numel(riseTimes), numel(fallTimes));
        if ~isnan(onTime),  fprintf('  Recording ON  at: %.6f s\n', onTime);  else, disp('  Recording ON not detected');  end
        if ~isnan(offTime), fprintf('  Recording OFF at: %.6f s\n', offTime); else, disp('  Recording OFF not detected'); end
    end

    % -------------------------
    % NEW: Save Phantom cine for this block
    % -------------------------
    if doPhantomThisBlock
        try
            disp('Waiting for Phantom cine to store...');
            waitForStoreOrTimeout(phantom.CN, phantom.camObj, 60);

            now2 = datetime('now','TimeZone','local');
            fmt2 = 'yyyy_mmdd_HHMMSS';
            cineBase = sprintf('%s_%s_Fly%s_Trial%s_%s_%s_%s_%s_%s', ...
                experiment_name, genotype, flyNumber, trialNum, stimulus_regime, stimulus_position, phantom_position, visual_stim_type, datestr(now2, fmt2));
            cinePath = fullfile(phantom.saveFolder, [cineBase '.cine']);
            
            [~, CH] = PhNewCineFromCamera(phantom.CN, 1);
            PhSetUseCase(CH, PhFileConst.UC_SAVE);

            pName = libpointer('cstring', cinePath);
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILENAME, pName);

            saveType = libpointer('uint32Ptr', PhFileConst.MIFILE_RAWCINE);
            PhSetCineInfo(CH, PhFileConst.GCI_SAVEFILETYPE, saveType);

            PhWriteCineFile(CH);
            try PhDestroyCine(CH); catch, end

            phantom.cineFiles{block} = cinePath;
            fprintf('Saved Phantom CINE: %s\n', cinePath);

        catch ME
            warning('Phantom save failed in block %d: %s', block, ME.message);
        end
    end

    
    
    
    Panel_com('stop'); pause(panel_pause);
    Panel_com('set_ao',[4, 0]); pause(panel_pause);
    toc

    fprintf(['Finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
end

% Stop the camera after all trials are finished
stop([TopCamera, SideCamera])

% Display frame information after stopping cameras
framesAvailable1 = TopCamera.FramesAvailable;
framesAvailable2 = SideCamera.FramesAvailable;
fprintf('Top Camera frames available: %d\n', TopCamera.FramesAvailable);
fprintf('Side Camera frames available: %d\n', SideCamera.FramesAvailable);
fprintf('Expected frames per camera: %d\n', variables.blocks * variables.TrialLength * variables.Basler_fps);
disp('Saving video data from both cameras...');

% Set arena in closed loop mode after all trials
Panel_com('set_pattern_id', 13); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause); % Set closed loop mode
Panel_com('set_position', [48 1]); pause(panel_pause);
Panel_com('send_gain_bias', [CL_spatialFreq, 0, 0, 0]); pause(panel_pause);
Panel_com('start');

delete(lh);
delete(lh2);
%% Save data and video
%% Modified section for saving data from both cameras
disp('Saving video data from both cameras...');

% Save SIDE Camera data (22843477) - NO rotation
if SideCamera.FramesAvailable > 0
    fprintf('%d frames available from Side Camera (22843477)\n', SideCamera.FramesAvailable);
    sideCamData = getdata(SideCamera, SideCamera.FramesAvailable);
    open(SideCamera_Logger)
    writeVideo(SideCamera_Logger, sideCamData);
    close(SideCamera_Logger)
    disp('Side Camera video saved successfully (no rotation)');
else
    disp('Warning: No frames available from Side Camera');
end

% Save TOP Camera data (22703705) - WITH 90° rotation
if TopCamera.FramesAvailable > 0
    fprintf('%d frames available from Top Camera (22703705)\n', TopCamera.FramesAvailable);
    topCamData = getdata(TopCamera, TopCamera.FramesAvailable);
    
    % Rotate each frame 90 degrees clockwise
    fprintf('Rotating top camera frames 90 degrees clockwise...\n');
    
    % Check if this is grayscale (2D) or color (3D) data
    if ndims(topCamData) == 3
        % Grayscale: [height, width, numFrames]
        [height, width, numFrames] = size(topCamData);
        rotatedData = zeros(width, height, numFrames, 'like', topCamData);
        
        for i = 1:numFrames
            rotatedData(:,:,i) = rot90(topCamData(:,:,i), -1);  % -1 = 90° clockwise
        end
    else
        % Color: [height, width, channels, numFrames]
        [height, width, channels, numFrames] = size(topCamData);
        rotatedData = zeros(width, height, channels, numFrames, 'like', topCamData);
        
        for i = 1:numFrames
            rotatedData(:,:,:,i) = rot90(topCamData(:,:,:,i), -1);  % -1 = 90° clockwise
        end
    end
    
    open(TopCamera_Logger)  % FIXED: Use TopCamera_Logger for TopCamera data
    writeVideo(TopCamera_Logger, rotatedData);
    close(TopCamera_Logger)
    disp('Top Camera video saved successfully (rotated 90° clockwise)');
else
    disp('Warning: No frames available from Top Camera');
end

% Clean up camera objects
delete(TopCamera);
delete(SideCamera);

d = dir(saveFolder);

% Filter out directories and keep only files
isFile = ~[d.isdir]; % Logical array where 'true' means it's a file
d = d(isFile); % Keep only the file entries

% Filter out files with extensions (those containing a '.')
noExtensionFiles = d(arrayfun(@(x) isempty(regexp(x.name, '\.[^.]*$', 'once')), d));

% Check if any files remain after filtering
if isempty(noExtensionFiles)
    error('No files found in the specified directory without an extension.');
end

% Find the most recently modified file among the files without extensions
[~, idx] = max([noExtensionFiles.datenum]);
latestFile = noExtensionFiles(idx).name;

disp(['Latest file without an extension: ', latestFile]);

% Attempt to open the file
fid2 = fopen([saveFolder latestFile], 'r');
if fid2 == -1
    error('Failed to open the file. Check the file path and permissions.');
end

[Data, count] = fread(fid2, [9, inf], 'double');
fclose(fid2);

formatOut = 'yyyy_mmdd_HHMMSS';
savedate = datestr(now,formatOut);
baseFileName = strcat(savedate,'_',FlyType);
fpath = strcat(saveFolder, baseFileName);
save(fpath,'Data','variables','allRandomizedStimOrders', 'phantom'); % Save all randomized stimulus orders for later analysis

%% Plot Basic Wingbeat Frequency
% Simple plot of WBF data

% Extract WBF and WBA data (channel 4 and channel 2/3)
wbf_data = floor(Data(4, :) * 100); % WBF data
wba_data = floor((Data(2,:) + Data(3,:))*20)/2; % WBA data

% Extract Data(7,:) and optionally scale if needed
data7 = Data(7, :); % Raw data from channel 7

% Smooth the WBF data
smooth_window = 100;
smoothed_wbf = smoothdata(wbf_data, 'movmean', smooth_window);
smoothed_wba = smoothdata(wba_data, 'movmean', smooth_window);

% Calculate time axis in seconds
time_axis = linspace(0, variables.TrialLength * variables.blocks, length(smoothed_wbf));

% Calculate baseline WBF (first 5 seconds)
baseline_samples = min(5 * variables.SampleRate, length(smoothed_wbf));
baseline_wbf = mean(smoothed_wbf(1:baseline_samples));

% Adjust WBF by subtracting the baseline
adjusted_wbf = smoothed_wbf - baseline_wbf;

% Calculate baseline WBF (first 5 seconds)
baseline_wba_samples = min(5 * variables.SampleRate, length(smoothed_wba));
baseline_wba = mean(smoothed_wba(1:baseline_samples));

% Adjust WBF by subtracting the baseline
adjusted_wba = (smoothed_wba - baseline_wba);

% Create a figure to display the WBF data
figure('Position', [100, 100, 1200, 600]);

% Plot Data(7,:) in red, BEHIND smoothed WBF
plot(time_axis, data7, 'r', 'LineWidth', 1); 
hold on;

% Plot Data(7,:) in red, BEHIND smoothed WBF
plot(time_axis, adjusted_wba, 'g', 'LineWidth', 1); 
hold on;

% Plot the adjusted smoothed WBF data
plot(time_axis, adjusted_wbf, 'LineWidth', 2, 'Color', [0, 0.5, 1]);

% Add a dashed line at y = 0
yline(0, '--', 'Color', 'w');

% Set the axis limits
xlim([0, variables.TrialLength * variables.blocks]);
ylim([-100, 50]);

% Set the figure background and text colors
set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
set(gcf, 'Color', 'k', 'InvertHardcopy', 'off');

% Add simple labels
xlabel('Time (s)', 'Color', 'w');
ylabel('\DeltaWBF (Hz)', 'Color', 'w');

% Create svg filename using the same base filename
svg_filename = [fpath, '_plot.svg'];

% Save the figure as SVG
saveas(gcf, svg_filename, 'svg');

% Display confirmation message
fprintf('Plot saved as: %s\n', svg_filename);

% First phrase: mi mi mi do (E-E-E-C) - lowered by octave
sound(sin(2*pi*165*(0:0.001:0.4)), 8192); pause(0.2);  % mi (E3)
sound(sin(2*pi*165*(0:0.001:0.4)), 8192); pause(0.2);  % mi (E3)
sound(sin(2*pi*165*(0:0.001:0.4)), 8192); pause(0.2);  % mi (E3)
sound(sin(2*pi*131*(0:0.001:4.8)), 8192); pause(1.2);  % do (C3)

% Second phrase: re re re si (D-D-D-B) - lowered by octave
sound(sin(2*pi*147*(0:0.001:0.4)), 8192); pause(0.2);  % re (D3)
sound(sin(2*pi*147*(0:0.001:0.4)), 8192); pause(0.2);  % re (D3)
sound(sin(2*pi*147*(0:0.001:0.4)), 8192); pause(0.2);  % re (D3)
sound(sin(2*pi*123*(0:0.001:4.8)), 8192);              % si (B2)

%% Phantom cleanup (NEW)
try
    if exist('gateSess','var') && ~isempty(gateSess), release(gateSess); end
catch
end

try
    if isfield(phantom,'pr') && ~isempty(phantom.pr)
        phantom.pr.delete();
    end
catch
end
try
    if isfield(phantom,'pb') && ~isempty(phantom.pb)
        try
            if phantom.pb.IsRegistered
                phantom.pb.Unregister();
            end
        catch
        end
        phantom.pb.delete();
    end
catch
end
try
    if isfield(phantom,'libsLoaded') && phantom.libsLoaded
        UnloadPhantomLibraries();
    end
catch
end

%% ===== helper functions (NEW) =====
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
            if isfield(st,'Stored')
                stored = logical(st.Stored);
            end
        catch
        end

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

        if stored
            return;
        end
        pause(0.05);
    end
    error('Timed out waiting for cine to store.');
end

function [riseTimes, fallTimes, onTime, offTime] = gateEdges(t, gate)
    gate = logical(gate(:));
    t = t(:);

    dv = diff(double(gate));
    riseIdx = find(dv > 0.5) + 1;
    fallIdx = find(dv < -0.5) + 1;

    riseTimes = t(riseIdx);
    fallTimes = t(fallIdx);

    onTime = NaN;
    offTime = NaN;

    if ~isempty(riseIdx)
        onTime = t(riseIdx(1));
        after = fallIdx(fallIdx > riseIdx(1));
        if ~isempty(after)
            offTime = t(after(1));
        end
    end
end
