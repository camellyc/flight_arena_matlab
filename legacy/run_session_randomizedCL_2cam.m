% Author: Yichen Luo 8/2024
% Modified to use set_velfunc_id for LED display pattern
% Modified 2026: Added side camera toggle (useSideCamera)

imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
                    'Spiracle\Flight_Arena_Data\260516_SpMN4_A1ACR\'];
                
% Check if the folder exists, and if not, create it
if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end
%% Specify strings for FlyType
experiment_name = 'SpMN4_A1ACR';     % Example: spSN_ChR
genotype = 'IS76603_A1ACR_4d_F';             % Example: SS48339_2d_M
flyNumber = '7';                 % Example: Fly1
trialNum = '1';
stimulus_regime = '3000msx3';   % Example: 0-3000ms
stimulus_position = 'thorax';
%% Construct FlyType
FlyType = [experiment_name '_' genotype '_Fly' flyNumber '_Trial' trialNum '_' stimulus_regime '_' stimulus_position];

%% Declare variables

% ====== CAMERA TOGGLE ======
useSideCamera = false;  % Set to true to enable side camera acquisition, false to disable
% ===========================

% Arena variables
CL_spatialFreq = -5; % Closed loop gain set to 10Hz
L_X_Pos = 48;
R_X_Pos = L_X_Pos;
variables.blocks = 3;             % 3 blocks per experiment
variables.TrialLength = 90;       % 90 seconds per trial

% LED/laser variables
variables.Frequency = 200;        % LED stimulation freq
variables.PulseDuration = 3;      % Each LED pulse is 3ms long.
%stimDurations = [0, 100, 300, 1000, 3000];  % Stimulus durations (ms). You can add any numbers of stims, with variable durations.
stimDurations = [0, 3000, 3000]; %"3000msx3" 
%stimDurations = [10000]; % "10000ms"
%stimDurations = [0, 300, 300, 300];
%stimDurations = [0, 1000, 1500, 2000];
%stimDurations = [0, 10, 30, 100, 300];  

% NIdaq and camera variables
variables.SampleRate = 20000;
variables.Basler_fps = 100;   % Desired fps from the Basler cam - CENTRAL SETTING
variables.Exposure_time = 9000;  % Exposure time in ?s (adjusted to work with Basler_fps)

% Store side camera flag in variables struct for later reference/analysis
variables.useSideCamera = useSideCamera;

% Calculate maximum possible exposure time based on frame rate, with 20% margin for readout
max_exposure_time = (1000000 / variables.Basler_fps) * 0.9;
% Ensure exposure time doesn't exceed maximum
if variables.Exposure_time > max_exposure_time
    variables.Exposure_time = max_exposure_time;
    fprintf('Exposure time adjusted to %d ?s to accommodate %d fps frame rate\n', ...
        variables.Exposure_time, variables.Basler_fps);
end

% Fixed variables:
variables.conditions = 1; % Single condition: closed loop (CL) only
panel_pause = .005;       % Short time to 'space out' commands sent to controller
variables.CL_X_gain = 1 * CL_spatialFreq;     % Closed loop gain
now = datetime('now','TimeZone','local');
formatOut = 'yyyy_mmdd_HHMMSS';
FILENAME = [saveFolder  datestr(now,formatOut) '_' FlyType];
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
% AI 2/data(4,:) : WB frequency
% AI 3/data(5,:) : DAQ1 (arena x position)
% AI 4/data(6,:) : EMG recording
% AI 5/data(7,:) : LED driver input (split ao that goes to LED)
% AI 6/data(8,:) : Orca camera trigger input 
%(Edited 250318: Now data(8,:)is right hutchens.
% AI 7/data(9,:) : Basler camera trigger input

% AO 0: Orca camera trigger output
% AO 1: LED trigger output
addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');
% addAnalogOutputChannel(mainSession,deviceID,'ao0','Voltage');

% Trigger the camera - USING CENTRALIZED SETTINGS
camTrigger = addCounterOutputChannel(mainSession, deviceID, 'ctr0', 'PulseGeneration');
camTrigger.Frequency = variables.Basler_fps;  % Uses centralized fps setting
camTrigger.InitialDelay = 0.05; % Ensure we capture the first frame
camTrigger.DutyCycle = 0.5;    % 50% duty cycle for reliable triggering

figure(1); clf;
lh = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));

vidDir = saveFolder; % Specify your video folder here
blankvidFile1 = [vidDir datestr(now,formatOut) '_TopCamera_' FlyType];
if useSideCamera
    blankvidFile2 = [vidDir datestr(now,formatOut) '_SideCamera_' FlyType];
end

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

% CAMERA 2 SETUP - Conditional on useSideCamera flag
if useSideCamera
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
else
    fprintf('\n>>> Side camera acquisition is DISABLED (useSideCamera = false) <<<\n\n');
end

% Configure video writers for both cameras - USING WORKING CODE SETTINGS
TopCamera_Logger = VideoWriter(blankvidFile1, 'MPEG-4');    % TOP camera ? TOP file
TopCamera_Logger.FrameRate = variables.Basler_fps;
TopCamera_Logger.Quality = 100;

if useSideCamera
    SideCamera_Logger = VideoWriter(blankvidFile2, 'MPEG-4');   % SIDE camera ? SIDE file
    SideCamera_Logger.FrameRate = variables.Basler_fps;
    SideCamera_Logger.Quality = 100;
end

% Debug output - check all important camera settings for both cameras
fprintf('\nCamera 1 Setup Summary (Serial: 22703705):\n');
fprintf('  Device Name: %s\n', camInfo.DeviceInfo(1).DeviceName);
fprintf('  Trigger Mode: %s\n', TopCamera_src.TriggerMode);
fprintf('  Frame Rate: %d fps (capture)\n', variables.Basler_fps);
fprintf('  Exposure Time: %d µs\n', TopCamera_src.ExposureTime);
fprintf('  Gain: %.6f\n', TopCamera_src.Gain);
fprintf('  Video Writer Frame Rate: %d fps\n', TopCamera_Logger.FrameRate);

if useSideCamera
    fprintf('\nCamera 2 Setup Summary (Serial:22843477 ):\n');
    fprintf('  Device Name: %s\n', camInfo.DeviceInfo(2).DeviceName);
    fprintf('  Trigger Mode: %s\n', SideCamera_src.TriggerMode);
    fprintf('  Frame Rate: %d fps (capture)\n', variables.Basler_fps);
    fprintf('  Exposure Time: %d µs\n', SideCamera_src.ExposureTime);
    fprintf('  Gain: %.6f\n', SideCamera_src.Gain);
    fprintf('  Video Writer Frame Rate: %d fps\n\n', SideCamera_Logger.FrameRate);
else
    fprintf('\nCamera 2 (Side Camera): SKIPPED (useSideCamera = false)\n\n');
end

%% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks, 1);

%% Run Arena Program, acquire data per trial

Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

% Start the camera before the trials begin
disp('Starting camera...');
if useSideCamera
    start([SideCamera, TopCamera])
else
    start(TopCamera)
end

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

% Stop the camera after all trials are finished
if useSideCamera
    stop([TopCamera, SideCamera])
else
    stop(TopCamera)
end

% Display frame information after stopping cameras
framesAvailable1 = TopCamera.FramesAvailable;
fprintf('Top Camera frames available: %d\n', TopCamera.FramesAvailable);
if useSideCamera
    framesAvailable2 = SideCamera.FramesAvailable;
    fprintf('Side Camera frames available: %d\n', SideCamera.FramesAvailable);
end
fprintf('Expected frames per camera: %d\n', variables.blocks * variables.TrialLength * variables.Basler_fps);
disp('Saving video data...');

% Set arena in closed loop mode after all trials
Panel_com('set_pattern_id', 14); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause); % Set closed loop mode
Panel_com('set_position', [48 1]); pause(panel_pause);
Panel_com('send_gain_bias', [CL_spatialFreq, 0, 0, 0]); pause(panel_pause);
Panel_com('start');

delete(lh);
delete(lh2);

%% Save data and video
%% Modified section for saving data from cameras
disp('Saving video data...');

% Save SIDE Camera data (22843477) - NO rotation
if useSideCamera
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
if useSideCamera
    delete(SideCamera);
end

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
save(fpath,'Data','variables','allRandomizedStimOrders'); % Save all randomized stimulus orders for later analysis

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