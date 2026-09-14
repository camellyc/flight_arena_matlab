% Author: Yichen Luo
% Corrected flight arena experiment code to run continuously in closed loop mode
% CAMERA ACQUISITION + VIDEO SAVING REMOVED

imaqreset
closepreview
clear all; close all; clc

%% Specify folder to save data
saveFolder = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\', ...
                    'Spiracle\Flight_Arena_Data\260114_SpMN4_ChR_EMG\'];

if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

%% Specify strings for FlyType
experiment_name = 'SpMN4_ChR_EMG';
genotype = 'IS76603_ChR_5d_F';
flyNumber = '2';
trialNum = '2';
stimulus_regime = '0ms';
stimulus_position = 'thorax';

FlyType = [experiment_name '_' genotype '_Fly' flyNumber ...
           '_Trial' trialNum '_' stimulus_regime '_' stimulus_position];

%% Declare variables
CL_spatialFreq = -5;
L_X_Pos = 48;
R_X_Pos = L_X_Pos;
variables.blocks = 1;
variables.TrialLength = 1800;

variables.Frequency = 200;
variables.PulseDuration = 3;
stimDurations = [0];

variables.SampleRate = 20000;

variables.conditions = 1;
panel_pause = .005;
variables.CL_X_gain = CL_spatialFreq;

now = datetime('now','TimeZone','local');
formatOut = 'yyyy_mmdd_HHMMSS';
FILENAME = [saveFolder FlyType '_' datestr(now,formatOut)];
fid1 = fopen(FILENAME,'w');

min_out_voltage = 0.5;
max_out_voltage = 10;
volt_to_code_conversion = 3276.7;
analog_output_codes = linspace(min_out_voltage*volt_to_code_conversion, ...
                               max_out_voltage*volt_to_code_conversion, ...
                               variables.conditions);

%% Initialize NIdaq device
devices = daq.getDevices;
deviceID = devices.ID;

mainSession = daq.createSession('ni');
mainSession.Rate = variables.SampleRate;

addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');

figure(1); clf;
lh  = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable', @(src,event)logData(src,event,fid1));

%% Initialize storage for randomized stimulus orders
allRandomizedStimOrders = cell(variables.blocks,1);

%% Run Arena Program
Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);

for block = 1:variables.blocks
    fprintf('Starting block %d of %d\n', block, variables.blocks);

    randomizedStimOrder = stimDurations(randperm(length(stimDurations)));
    allRandomizedStimOrders{block} = randomizedStimOrder;

    outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);
    stimTimes = round((variables.TrialLength / (length(stimDurations)+1)) ...
                      * (1:length(stimDurations)) * variables.SampleRate);

    for i = 1:length(randomizedStimOrder)
        currentStimDuration = randomizedStimOrder(i);
        nStimTime = variables.SampleRate * (currentStimDuration / 1000);
        nPulseDuration = variables.SampleRate * (variables.PulseDuration / 1000);
        nIPI = (1000 - (variables.PulseDuration * variables.Frequency)) / variables.Frequency;

        for o = 1:nPulseDuration
            outputSignal(stimTimes(i)+o:(nPulseDuration+nIPI):(stimTimes(i)+nStimTime)) = 10;
        end
    end

    queueOutputData(mainSession, outputSignal);

    tic
    Panel_com('set_pattern_id', 14); pause(panel_pause);
    Panel_com('set_mode', [1, 0]); pause(panel_pause);
    Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
    Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
    Panel_com('set_ao',[4, analog_output_codes(1)]); pause(panel_pause);

    Panel_com('start');
    mainSession.startBackground();
    pause(variables.TrialLength);
    mainSession.stop();

    Panel_com('stop'); pause(panel_pause);
    Panel_com('set_ao',[4, 0]); pause(panel_pause);
    toc

    fprintf('Finished block %d of %d\n', block, variables.blocks);
end

Panel_com('set_pattern_id', 14); pause(panel_pause);
Panel_com('set_mode', [1, 0]); pause(panel_pause);
Panel_com('set_position', [48 1]); pause(panel_pause);
Panel_com('send_gain_bias', [CL_spatialFreq, 0, 0, 0]); pause(panel_pause);
Panel_com('start');

delete(lh);
delete(lh2);

%% Load & save data
d = dir(saveFolder);
d = d(~[d.isdir]);
noExt = d(arrayfun(@(x) isempty(regexp(x.name,'\.[^.]*$','once')), d));
[~, idx] = max([noExt.datenum]);
latestFile = noExt(idx).name;

fid2 = fopen([saveFolder latestFile], 'r');
[Data, ~] = fread(fid2, [9, inf], 'double');
fclose(fid2);

savedate = datestr(now,formatOut);
baseFileName = strcat(FlyType,'_',savedate);
fpath = strcat(saveFolder, baseFileName);
save(fpath,'Data','variables','allRandomizedStimOrders','-v7.3');

%% Plot Basic Wingbeat Frequency
wbf_data = floor(Data(4,:) * 100);
wba_data = floor((Data(2,:) + Data(3,:))*20)/2;
data7 = Data(7,:);

smooth_window = 100;
smoothed_wbf = smoothdata(wbf_data,'movmean',smooth_window);
smoothed_wba = smoothdata(wba_data,'movmean',smooth_window);

time_axis = linspace(0, variables.TrialLength * variables.blocks, length(smoothed_wbf));

baseline_samples = min(5 * variables.SampleRate, length(smoothed_wbf));
adjusted_wbf = smoothed_wbf - mean(smoothed_wbf(1:baseline_samples));
adjusted_wba = smoothed_wba - mean(smoothed_wba(1:baseline_samples));

figure('Position',[100 100 1200 600]);
plot(time_axis, data7,'r'); hold on
plot(time_axis, adjusted_wba,'g');
plot(time_axis, adjusted_wbf,'LineWidth',2);

yline(0,'--','Color','w');
xlim([0 variables.TrialLength * variables.blocks]);
ylim([-100 50]);

set(gca,'Color','k','XColor','w','YColor','w','LineWidth',2);
set(gcf,'Color','k','InvertHardcopy','off');

xlabel('Time (s)','Color','w');
ylabel('\DeltaWBF (Hz)','Color','w');

svg_filename = [fpath '_plot.svg'];
saveas(gcf, svg_filename,'svg');

%% End sound
sound(sin(2*pi*165*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*165*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*165*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*131*(0:0.001:4.8)),8192); pause(1.2)

sound(sin(2*pi*147*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*147*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*147*(0:0.001:0.4)),8192); pause(0.2)
sound(sin(2*pi*123*(0:0.001:4.8)),8192);
