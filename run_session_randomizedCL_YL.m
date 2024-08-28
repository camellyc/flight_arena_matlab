% Author: Yichen Luo 8/2024
% edit: kyle thieringer 8/2024

% Corrected flight arena experiment code to run continuously in closed loop mode
% with x randomized stimuli durations per trial, y trials per experiment, and
% flexible trial lengths with stimuli delivered at 1/x intervals of the trial length.
imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = 'D:\Yichen\Spiracle_Imaging\240821_SS81923_ChR\'; % Specify your folder here

%% Specify strings for FlyType
experiment_name = 'DNxn130_ChR';     % Example: spSN_ChR
genotype = 'SS81923_6d_F';             % Example: SS48339_2d_M
flyNumber = 'Fly1';                 % Example: Fly1
trialNum = 'Trial1';
stimulus_regime = '100-3000ms';   % Example: 100-3000ms

%% Construct FlyType
FlyType = [experiment_name '_' genotype '_' flyNumber '_' trialNum '_' stimulus_regime];

%% Declare variables

% Arena variables
CL_spatialFreq = 6; % Closed loop gain set to 6Hz
L_X_Pos = 48;
R_X_Pos = L_X_Pos;
variables.blocks = 3;             % 3 trials per experiment
variables.TrialLength = 5;       % 10s per trial
% LED/laser variables
variables.Frequency = 200;        % LED stimulation freq
variables.PulseDuration = 2;      % Each LED pulse is 2ms long.
stimDurations = [100, 300];   % Stimulus durations (ms). You can add any numbers of stims, with variable durations.
% NIdaq variables
variables.SampleRate = 20000;
variables.Basler_fps = 100;   % Desired fps from the Basler cam
variables.exposureTime = 10000; % Exposure time in us

% Fixed variables:
variables.conditions = 1; % Single condition: closed loop (CL) only
panel_pause = .005;       % Short time to 'space out' commands sent to controller
variables.CL_X_gain = 1 * CL_spatialFreq;     % Closed loop gain
now = datetime('now','TimeZone','local');
formatOut = 'yyyy_mmdd_HHMMSS';
FILENAME = [saveFolder FlyType '_' datestr(now,formatOut)];
fid1 = fopen(FILENAME,'w');
min_out_voltage = 0.5; 
max_out_voltage = 10;  
volt_to_code_conversion = 3276.7; 
min_out_code = min_out_voltage*volt_to_code_conversion;
max_out_code = max_out_voltage*volt_to_code_conversion;
analog_output_codes = linspace(min_out_code,max_out_code,variables.conditions);

%% Initialize NIdaq device and stim queue

devices = daq.getDevices;
deviceID=devices.ID;

mainSession = daq.createSession('ni');
mainSession.Rate = variables.SampleRate;
addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
ch = addAnalogInputChannel(mainSession,deviceID,'ai9','Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');

% Trigger the camera
camTrigger = addCounterOutputChannel(mainSession, deviceID, 'ctr0', 'PulseGeneration');
camTrigger.Frequency = variables.Basler_fps;
camTrigger.InitialDelay = 0.05; % Ensure we capture the first frame

figure(1); clf;
lh = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));

%% Initialize camera options
vidDir = 'D:\Yichen\Spiracle_Imaging\240821_SS81923_ChR\Videos\'; % Specify your video folder here
blankvidFile = [vidDir FlyType '_' datestr(now,formatOut)];

sideCam = videoinput('gentl', 1, 'Mono8');
triggerconfig(sideCam, 'hardware');
sideCam.LoggingMode = 'memory';
sideCam.FramesPerTrigger = inf;

sideCam_src = getselectedsource(sideCam);

sideCam_src.LineSelector = 'Line4';
sideCam_src.LineMode = 'input';
sideCam_src.LineInverter = 'True'; 
sideCam_src.TriggerSelector = 'FrameStart';
sideCam_src.TriggerMode = 'Off';
sideCam_src.TriggerSource = 'Line4';
sideCam_src.TriggerActivation = 'RisingEdge';

sideCam_src.ExposureTime = variables.exposureTime;
sideCam_src.Gain = 5;
sideCam_src.Gamma = 1;
sideCam_src.TriggerMode = 'On';

sideCam_Logger = VideoWriter(blankvidFile, 'MPEG-4');
sideCam_Logger.FrameRate = variables.Basler_fps;

%% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks, 1);

%% Run Arena Program, acquire data per trial

Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

start(sideCam) % Start the camera before the trials begin

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

    % Queue the data for the trial
    queueOutputData(mainSession, outputSignal);

    tic
    Panel_com('set_pattern_id', 14); pause(panel_pause);
    Panel_com('set_mode', [1, 0]); pause(panel_pause); 
    Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
    Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
    Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);
    
    % Start the session for this trial
    Panel_com('start');
    mainSession.startBackground();
    pause(variables.TrialLength); % Use the set trial length
    mainSession.stop();
    Panel_com('stop'); pause(panel_pause);
    Panel_com('set_ao',[4, 0]); pause(panel_pause);
    toc

    fprintf(['Finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
end

stop(sideCam) % Stop the camera after all trials are finished
delete(lh);
delete(lh2);

%% Save data and video
camData = getdata(sideCam, sideCam.FramesAvailable);
open(sideCam_Logger)
writeVideo(sideCam_Logger, camData);
close(sideCam_Logger)

d = dir(saveFolder);

% Filter out directories and keep only files
isFile = ~[d.isdir]; % Logical array where 'true' means it's a file
d = d(isFile); % Keep only the file entries

% Check if any files remain after filtering
if isempty(d)
    error('No files found in the specified directory.');
end

% Find the most recently modified file
[~, idx] = max([d.datenum]);
latestFile = d(idx).name;

% Attempt to open the file
fid2 = fopen([saveFolder latestFile], 'r');
if fid2 == -1
    error('Failed to open the file. Check the file path and permissions.');
end

[Data, count] = fread(fid2, [10, inf], 'double');
fclose(fid2);

formatOut = 'yyyy_mmdd_HHMMSS';
savedate = datestr(now,formatOut);
baseFileName = strcat(FlyType,'_',savedate);
fpath = strcat(saveFolder, baseFileName);
save(fpath,'Data','variables','allRandomizedStimOrders'); % Save all randomized stimulus orders for later analysis