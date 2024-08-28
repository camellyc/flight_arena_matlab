% ENL 12/2018
% Runs a flight arena experiment, open loop and closed loop trials,
% "variables" is a structure for parameters to save with the Data
% to do: get rid of input dlg at beginning...
% Stim at each trial
% turn off stim at end
clear all; %close all;

%% Declare variables

% user input variables:
FlyType = 'spMN_VT020126xR20F02_ChR_fly1_legless_3000ms';   % For saving
% Arena variables
CL_spatialFreq = 6; % This is close loop gain. Set to 6Hz
OL_spatialFreq =  8;
L_X_Pos = 60;
R_X_Pos = L_X_Pos;
variables.blocks = 1;
variables.TrialLength = 40;     % seconds
% LED/laser variables
variables.Frequency = 200;%; 100 200];   % Hz
variables.PulseDuration = 2;% 5];  % ms
variables.StimDuration = 3000;   % ms
Stim_spacer = 10;
% variables.latency = 2.5;          % s
% NIdaq variables
variables.SampleRate = 20000; 

% fixed variables:
variables.conditions = 3; %* length(variables.PulseDurations) * length(variables.Frequencies);
panel_pause = .005; % short time to 'space out' commands send to controller
variables.CL_X_gain = 8 * CL_spatialFreq;     % closed loop gain
variables.OL_X_gain = 8 * OL_spatialFreq;     % open loop gain
now = datetime('now','TimeZone','local');
filename = FlyType;
formatOut = 'yyyymmddHHMMSS';
fileroot = 'D:\Yichen\Spiracle_Imaging\240812_R20F02_ChR_flight\';
FILENAME = [fileroot filename '_' datestr(now,formatOut)]; %,'.txt'];
fid1 = fopen(FILENAME,'w');
min_out_voltage = 0.5; % the range of voltages to output as condition indicator is from 0.5 to 10
max_out_voltage = 10;  % reserve 0 as an extra indicator of trial changes
volt_to_code_conversion = 3276.7; % becuase 10 volts is encoded by 2^15 - 1
min_out_code = min_out_voltage*volt_to_code_conversion;
max_out_code = max_out_voltage*volt_to_code_conversion;
analog_output_codes = linspace(min_out_code,max_out_code,variables.conditions);
%% Initialize NIdaq device and stim queue
% AI 0 : WBA left
% AI 1 : WBA right
% AI 2 : WBA frequency
% AI 3 : DAQ0 (arena x position)
% AI 4 : Controller AO (currently empty)
% AI 5 : LED driver input (split ao that goes to LED)
% AI 6 : Orca camera sync trigger output(started by software)
% AI 7 : Basler camera sync trigger output (started by software)

% AO 1 : LED driver trigger

devices = daq.getDevices;
deviceID=devices.ID;

mainSession = daq.createSession('ni');
mainSession.Rate = variables.SampleRate;
mainSession.IsContinuous = 1;
addAnalogInputChannel(mainSession,deviceID,[0 1 2 3 4 5 6 7],'Voltage');
ch = addAnalogInputChannel(mainSession,deviceID,'ai9','Voltage');
addAnalogOutputChannel(mainSession,deviceID,'ao1','Voltage');

% nLatency = variables.SampleRate * variables.latency;
% nStimTime = variables.SampleRate * (variables.StimDuration / 1000);
% nPulseDuration = variables.SampleRate * (variables.PulseDuration / 1000);
% nIPI = (1000 - (variables.PulseDuration * variables.Frequency)) / variables.Frequency;
% outputSignal = zeros((variables.TrialLength * variables.SampleRate),1);
% for o = 1:nPulseDuration
%     outputSignal(nLatency+o:(nPulseDuration+nIPI):(nLatency + nStimTime),1) = 10;
% end
% queueOutputData(mainSession,outputSignal);

nLatency1 = variables.SampleRate * Stim_spacer;  % 1 latency
nLatency2 = variables.SampleRate * 2 * Stim_spacer;  % 2 latency
nLatency3 = variables.SampleRate * 3 * Stim_spacer;  % 3 latency

nStimTime = variables.SampleRate * (variables.StimDuration / 1000);
nPulseDuration = variables.SampleRate * (variables.PulseDuration / 1000);
nIPI = (1000 - (variables.PulseDuration * variables.Frequency)) / variables.Frequency;

% Initialize the output signal
outputSignal = zeros((variables.TrialLength * variables.SampleRate), 1);

% Generate the stimulus at 1s, 2s, and 3s
for o = 1:nPulseDuration
    % First stimulus at 1 second
    outputSignal(nLatency1+o:(nPulseDuration+nIPI):(nLatency1 + nStimTime), 1) = 10;
    % Second stimulus at 2 seconds
    outputSignal(nLatency2+o:(nPulseDuration+nIPI):(nLatency2 + nStimTime), 1) = 10;
    % Third stimulus at 3 seconds
    outputSignal(nLatency3+o:(nPulseDuration+nIPI):(nLatency3 + nStimTime), 1) = 10;
end

outputSignal(end, 1) = 0;

queueOutputData(mainSession, outputSignal);

figure(1);clf;
lh = addlistener(mainSession,'DataAvailable', @plotData);
lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));
lh3 = addlistener(mainSession,'DataRequired',@(src,event)src.queueOutputData(outputSignal));

%% Run Arena Program, acquire data per trial

sessionSchedule = zeros(variables.blocks,variables.conditions);
Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause); % currently not using - see Panel_com.m
mainSession.startBackground();

for block = 1:variables.blocks
    trialSchedule = randperm(variables.conditions);
    sessionSchedule(block,1:3) = trialSchedule;
    for trial = 1:length(trialSchedule)
        currentTrial = trialSchedule(trial);
        Panel_com('set_ao',[4, 0]); pause(panel_pause);
% keyboard
        tic
        if currentTrial == 1 % CL
            Panel_com('set_pattern_id', 14); pause(panel_pause);
            Panel_com('set_mode', [1, 0]); pause(panel_pause); % the mode code for CL on X
            Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause); % randomize at some point?
            Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
            Panel_com('set_ao',[4, analog_output_codes(currentTrial)]); pause(panel_pause);
            Panel_com('start');
            pause(variables.TrialLength); % the pause determines the trial length
            Panel_com('stop'); pause(panel_pause);
            Panel_com('set_ao',[4, 0]); pause(panel_pause);
        elseif currentTrial == 2 % OL left
            Panel_com('set_pattern_id', 14); pause(panel_pause);
            Panel_com('set_mode', [0 0]); pause(panel_pause); % the mode code for OL on X, Y
            Panel_com('set_position', [L_X_Pos 1]); pause(panel_pause);
            Panel_com('send_gain_bias',[-1 * variables.OL_X_gain,0,0,0]); 	% send Gain and Bias values
            Panel_com('set_ao',[4, analog_output_codes(currentTrial)]); pause(panel_pause);
            Panel_com('start');
            pause(variables.TrialLength) % the pause determines the trial length
            Panel_com('stop'); pause(panel_pause);
            Panel_com('set_ao',[4, 0]); pause(panel_pause);
        elseif currentTrial == 3 % OL right
            Panel_com('set_pattern_id', 14); pause(panel_pause);
            Panel_com('set_mode', [0 0]); pause(panel_pause); % the mode code for OL on X, Y
            Panel_com('set_position', [R_X_Pos 1]); pause(panel_pause);
            Panel_com('send_gain_bias',[variables.OL_X_gain,0,0,0]); 	% send Gain and Bias values
            Panel_com('set_ao',[4, analog_output_codes(currentTrial)]); pause(panel_pause);
            Panel_com('start');
            pause(variables.TrialLength) % the pause determines the trial length
            Panel_com('stop'); pause(panel_pause);
            Panel_com('set_ao',[4, 0]); pause(panel_pause);
        end
        toc
        fprintf(['finished trial ', num2str(trial), ' of ', num2str(variables.conditions), '\n']);
    end
    fprintf(['>>>>>>>>>>>>finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
    
end

mainSession.stop();
% hutSession.stop();
delete(lh);
% delete(lh2);
% % % delete(lh2_hut);
% delete(lh3);

outputSignal(end, 1) = 0;     % Turn off LED at the end.

%% Part IV: save data :)
d = dir(fileroot);
fid2 = fopen([fileroot d(length(d)).name]);
[Data,count] = fread(fid2,[10,inf],'double');
fclose(fid2);

% d = dir(filerootHut);
% fid2hut = fopen([filerootHut d(length(d)).name]);
% [DataHut,countHut] = fread(fid2hut,[3,inf],'double');
% fclose(fid2hut);

formatOut = 'yyyy_mmdd_HHMM';
savedate = datestr(now,formatOut);
baseFileName = strcat(FlyType,'_',savedate);
fpath = strcat('D:\Yichen\Spiracle_Imaging\240812_R20F02_ChR_flight\', baseFileName);
save(fpath,'Data','variables','sessionSchedule');