% Author: Yichen Luo 8/2024
% edit: kyle thieringer 8/2024

% Corrected flight arena experiment code to run continuously in closed loop mode
% with x randomized stimuli durations per trial, y trials per experiment, and
% flexible trial lengths with stimuli delivered at 1/x intervals of the trial length.
imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
                    'Spiracle\Flight_Arena_Data\250613_DNg27_ChR\'];
                
% Check if the folder exists, and if not, create it
if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end
         
%% Specify strings for FlyType
experiment_name = 'DNg27_ChR_desiccated_4hr';     % Example: spSN_ChR
genotype = 'SS01557_4d_F';             % Example: SS48339_2d_M
flyNumber = 'Fly4';                 % Example: Fly1
trialNum = 'Trial1';
stimulus_regime = '3000msx3';   % Example: 0-3000ms
stimulus_position = 'thorax';
%% Construct FlyType
FlyType = [experiment_name '_' genotype '_' flyNumber '_' trialNum '_' stimulus_regime];

%% Declare variables

% Arena variables
CL_spatialFreq = -5; % Closed loop gain set to 10Hz
L_X_Pos = 48;
R_X_Pos = L_X_Pos;
variables.TrialLength = 90;       % seconds per trial

% Update blocks to 4 trials. 1. No bar, 2. Upward bar, 3. No bar, 4. Downward bar.
variables.blocks = 4;

% LED/laser variables
variables.Frequency = 200;        % LED stimulation freq
variables.PulseDuration = 3;      % Each LED pulse is 3ms long.
%stimDurations = [0, 100, 300,1000, 3000];
%stimDurations = [0, 3000, 3000]; %"3000msx3" 
stimDurations = [0]; % "10000ms"
%stimDurations = [3000, 3000, 3000, 3000, 3000, 3000];
%stimDurations = [0, 1000, 1500, 2000];
%stimDurations = [0, 1000];
%stimDurations = [0, 10, 30, 100, 300];   % Stimulus durations (ms). You can add any numbers of stims, with variable durations.

% NIdaq and camera variables
variables.SampleRate = 20000;
variables.Basler_fps = 50;   % Desired fps from the Basler cam - CENTRAL SETTING
variables.Exposure_time = 18000;  % Exposure time in ?s (adjusted to work with Basler_fps)

% Calculate maximum possible exposure time based on frame rate, with 20% margin for readout
max_exposure_time = (1000000 / variables.Basler_fps) * 0.8;
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

%% Initialize camera options - USING CENTRALIZED SETTINGS
vidDir = saveFolder; % Specify your video folder here
blankvidFile = [vidDir FlyType '_' datestr(now,formatOut)];

sideCam = videoinput('gentl', 1, 'Mono8');
triggerconfig(sideCam, 'hardware');
sideCam.LoggingMode = 'memory';
sideCam.FramesPerTrigger = inf;

sideCam_src = getselectedsource(sideCam);

% Configure camera lines and trigger
sideCam_src.LineSelector = 'Line4';
sideCam_src.LineMode = 'input';
sideCam_src.LineInverter = 'True'; 
sideCam_src.TriggerSelector = 'FrameStart';
sideCam_src.TriggerMode = 'Off';  % Will set to 'On' after all settings are configured
sideCam_src.TriggerSource = 'Line4';
sideCam_src.TriggerActivation = 'RisingEdge';

% Enable acquisition frame rate control - USING CENTRALIZED SETTINGS
sideCam_src.AcquisitionFrameRateEnable = 'True';
sideCam_src.AcquisitionFrameRate = variables.Basler_fps;  % Uses centralized fps setting

% Set exposure time - USING CENTRALIZED SETTINGS
sideCam_src.ExposureTime = variables.Exposure_time;

% Optimize bandwidth and performance settings
if isfield(sideCam_src, 'DeviceLinkThroughputLimitMode')
    sideCam_src.DeviceLinkThroughputLimitMode = 'Off';
    disp('Throughput limit mode disabled');
end

if isfield(sideCam_src, 'DeviceLinkThroughputLimit')
    propInfo = propinfo(sideCam_src, 'DeviceLinkThroughputLimit');
    if ~isempty(propInfo) && isfield(propInfo, 'ConstraintValue')
        % Set to maximum possible value
        sideCam_src.DeviceLinkThroughputLimit = propInfo.ConstraintValue(2);
        disp(['Setting max bandwidth to: ', num2str(propInfo.ConstraintValue(2))]);
    end
end

if isfield(sideCam_src, 'BslUSBSpeedMode')
    sideCam_src.BslUSBSpeedMode = 'HighSpeed';
    disp('USB Speed Mode set to HighSpeed');
end

if isfield(sideCam_src, 'SensorReadoutMode')
    sideCam_src.SensorReadoutMode = 'Fast';
    disp('Sensor readout mode set to Fast');
end

% Additional camera settings
sideCam_src.Gain = 12; % maximum value = 12
sideCam_src.Gamma = 1;
sideCam_src.AutoTargetBrightness = 0.8;

% Now enable triggering
sideCam_src.TriggerMode = 'On';

% Configure video writer - USING CENTRALIZED SETTINGS
sideCam_Logger = VideoWriter(blankvidFile, 'MPEG-4');
sideCam_Logger.FrameRate = variables.Basler_fps;  % Uses centralized fps setting
sideCam_Logger.Quality = 95; % Higher quality to ensure we don't lose frames due to compression

% Debug output - check all important camera settings
fprintf('\nCamera Setup Summary:\n');
fprintf('  Trigger Mode: %s\n', sideCam_src.TriggerMode);
fprintf('  Trigger Source: %s\n', sideCam_src.TriggerSource);
fprintf('  Frame Rate Enabled: %s\n', sideCam_src.AcquisitionFrameRateEnable);
fprintf('  Requested Frame Rate: %d fps\n', sideCam_src.AcquisitionFrameRate);
fprintf('  Resulting Frame Rate: %.2f fps\n', sideCam_src.ResultingFrameRate);
fprintf('  Exposure Time: %d ?s\n', sideCam_src.ExposureTime);
fprintf('  Video Writer Frame Rate: %d fps\n\n', sideCam_Logger.FrameRate);

%% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks, 1);

%% Run Arena Program, acquire data per trial

Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

% Start the camera before the trials begin
disp('Starting camera...');
start(sideCam)

% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks, 1);

%% Randomize trial order
% Define the 4 trial types: 1, 3=no movement, 2=upward, 4=downward  
trialTypes = [1, 2, 3, 4]; % 1, 3=no movement, 2=upward, 4=downward
randomizedTrialOrder = trialTypes(randperm(length(trialTypes)));
fprintf('Randomized trial order: ');
disp(randomizedTrialOrder);

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

    % Different pattern behavior for each block (trial)
    if randomizedTrialOrder(block) == 1
        % Second trial: No moving horizontal bars with closed-loop vertical bar
        fprintf('Type 1: No moving horizontal bars with closed-loop vertical bar\n');
        Panel_com('set_pattern_id', 13); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); 
        Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain, 0, 0, 0]); pause(panel_pause);
        
    elseif randomizedTrialOrder(block) == 2
        % First trial: Upward moving horizontal bars with closed-loop vertical bar
        fprintf('Type 2: Upward moving horizontal bars with closed-loop vertical bar\n');
        Panel_com('set_pattern_id', 13); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); 
        Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain, 0, 10, 0]); pause(panel_pause);
  
    elseif randomizedTrialOrder(block) == 3
        % Fourth trial: Another stationary horizontal bars trial with closed-loop vertical bar
        fprintf('Type 3: No moving horizontal bars with closed-loop vertical bar (repeat)\n');
        Panel_com('set_pattern_id', 13); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); 
        Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain, 0, 0, 0]); pause(panel_pause);
        
    else randomizedTrialOrder(block) == 4
        % Third trial: Downward moving horizontal bars with closed-loop vertical bar
        fprintf('Type 4: Downward moving horizontal bars with closed-loop vertical bar\n');
        Panel_com('set_pattern_id', 13); pause(panel_pause);
        Panel_com('set_mode', [1, 0]); pause(panel_pause); 
        Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
        Panel_com('send_gain_bias',[variables.CL_X_gain, 0, -10, 0]); pause(panel_pause);
        
    end
    
    Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);
    
    % Start the pattern and data acquisition
    tic  % Original position for tic
    Panel_com('start');
    mainSession.startBackground();
    
    % Let the trial run for the specified trial length
    pause(variables.TrialLength);
    
    mainSession.stop();
    Panel_com('stop'); pause(panel_pause);
    Panel_com('set_ao',[4, 0]); pause(panel_pause);
    toc  % Original position for toc

    fprintf(['Finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
end

% Display frame information before stopping camera
framesAvailable = sideCam.FramesAvailable;
fprintf('Camera frames available before stopping: %d\n', framesAvailable);
fprintf('Expected frames: %d\n', variables.blocks * variables.TrialLength * variables.Basler_fps);

% Stop the camera after all trials are finished
stop(sideCam)

% Set arena in closed loop mode after all trials
Panel_com('set_pattern_id', 13); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause); % Set closed loop mode
Panel_com('set_position', [48 1]); pause(panel_pause);
Panel_com('send_gain_bias', [CL_spatialFreq, 0, 0, 0]); pause(panel_pause);
Panel_com('start');

delete(lh);
delete(lh2);
%% Save data and video
disp('Saving video data...');
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
save(fpath,'Data','variables','allRandomizedStimOrders', 'randomizedTrialOrder'); % Save all randomized stimulus orders for later analysis

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