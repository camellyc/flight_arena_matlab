% Author: Yichen Luo 10/2024

% Corrected flight arena experiment code to run continuously in mixed mode
% with different gain settings for open and closed loop modes.

imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
                    'Spiracle\Spiracle Imaging\241024_spMN2_GtACR_EMG\'];
                
% Check if the folder exists, and if not, create it
if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end
         
%% Specify strings for FlyType
experiment_name = 'spMN2_GtACR_EMG';     % Example: spSN_ChR
genotype = 'VT029591_R20F02_4d_F';             % Example: SS48339_2d_M
flyNumber = 'Fly2';                 % Example: Fly1
trialNum = 'Trial6';
stimulus_regime = 'horizontal';   % Example: 0-3000ms

%% Construct FlyType
FlyType = [experiment_name '_' genotype '_' flyNumber '_' trialNum '_' stimulus_regime];

%% Declare variables

% Arena variables
OL_spatialFreq = -10; % Open loop gain set to -10 for downward movement
OL_positive_spatialFreq = 10; % Open loop gain set to 10 for upward movement
CL_spatialFreq = -5;  % Closed loop gain set to -5
variables.blocks = 5;             % 5 blocks per experiment
variables.TrialLength = 20;       % seconds per trial

% NIdaq variables
variables.SampleRate = 20000;
variables.Basler_fps = 100;   % Desired fps from the Basler cam
variables.exposureTime = 10000; % Exposure time in us

% Fixed variables:
variables.conditions = 1; % Single condition: closed loop (CL) only
panel_pause = .005;       % Short time to 'space out' commands sent to controller
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

% AI 0/data(2,:) : WBA left
% AI 1/data(3,:) : WBA right
% AI 2/data(4,:) : WBA frequency
% AI 3/data(5,:) : DAQ1 (arena x position)
% AI 4/data(6,:) : EMG recording
% AI 5/data(7,:) : LED driver input (split ao that goes to LED)
% AI 6/data(8,:) : Orca camera trigger input
% AI 7/data(9,:) : Basler camera trigger input

% AO 0: Orca camera trigger output
% AO 1: LED trigger output
addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');
% addAnalogOutputChannel(mainSession,deviceID,'ao0','Voltage');

% Trigger the camera
camTrigger = addCounterOutputChannel(mainSession, deviceID, 'ctr0', 'PulseGeneration');
camTrigger.Frequency = variables.Basler_fps;
camTrigger.InitialDelay = 0.05; % Ensure we capture the first frame

figure(1); clf;
lh = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));

%% Initialize camera options
vidDir = saveFolder; % Specify your video folder here
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

%% Run Arena Program, acquire data per trial

Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

start(sideCam) % Start the camera before the trials begin

% Set gain and mode for each trial
for block = 1:variables.blocks
    fprintf(['Starting block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
    
    if block == 1 || block == 5
        % Closed Loop mode for 1st and 5th trials
        variables.CL_X_gain = CL_spatialFreq;
         % Queue the data for the trial
        outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);
        queueOutputData(mainSession, outputSignal);

        tic
        Panel_com('set_pattern_id', 14); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); 
        Panel_com('set_position', [48 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
        Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);
    
        % Start the session for this trial
        Panel_com('start');
        mainSession.startBackground();
        pause(variables.TrialLength); % Use the set trial length
        mainSession.stop();
        Panel_com('set_pattern_id', 14); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); % Keep arena in closed loop after trial
        Panel_com('set_position', [48 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
        Panel_com('set_ao',[4, 0]); pause(panel_pause);
    elseif block == 3
        % Open Loop mode for 3rd trial with bars moving up (positive gain)
        variables.OL_Y_gain = OL_positive_spatialFreq;
        % Queue the data for the trial
        outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);
        queueOutputData(mainSession, outputSignal);

        tic
        Panel_com('set_pattern_id', 10); pause(panel_pause);
        Panel_com('set_mode', [0, 0]); pause(panel_pause); % Y open loop
        Panel_com('set_position', [1 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[0, 0, variables.OL_Y_gain, 0]); pause(panel_pause);
        Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);
    
        % Start the session for this trial
        Panel_com('start');
        mainSession.startBackground();
        pause(variables.TrialLength); % Use the set trial length
        mainSession.stop();
        Panel_com('stop'); pause(panel_pause);
        Panel_com('set_ao',[4, 0]); pause(panel_pause);
        toc
    else
        % Open Loop mode for 2nd and 4th trials with bars moving down (negative gain)
        variables.OL_Y_gain = OL_spatialFreq;
        % Queue the data for the trial
        outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);
        queueOutputData(mainSession, outputSignal);

        tic
        Panel_com('set_pattern_id', 10); pause(panel_pause);
        Panel_com('set_mode', [0, 0]); pause(panel_pause); % Y open loop
        Panel_com('set_position', [1 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[0, 0, variables.OL_Y_gain, 0]); pause(panel_pause);
        Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);
    
        % Start the session for this trial
        Panel_com('start');
        mainSession.startBackground();
        pause(variables.TrialLength); % Use the set trial length
        mainSession.stop();
        Panel_com('stop'); pause(panel_pause);
        Panel_com('set_ao',[4, 0]); pause(panel_pause);
        toc
    end
    
    fprintf(['Finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
end

stop(sideCam) % Stop the camera after all trials are finished

% Set arena in closed loop mode after all trials
Panel_com('set_pattern_id', 14); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause); % Set closed loop mode
Panel_com('set_position', [48 1]); pause(panel_pause);
Panel_com('send_gain_bias', [CL_spatialFreq, 0, 0, 0]); pause(panel_pause);
Panel_com('start');

delete(lh);
delete(lh2);

%% Save data and video
camData = getdata(sideCam, sideCam.FramesAvailable);
disp(['Total frames captured: ', num2str(size(camData, 4))]); % Display how many frames were captured for debugging.
open(sideCam_Logger)
writeVideo(sideCam_Logger, camData);
close(sideCam_Logger)

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
baseFileName = strcat(FlyType,'_',savedate);
fpath = strcat(saveFolder, baseFileName);
save(fpath,'Data','variables');
