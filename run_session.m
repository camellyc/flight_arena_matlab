% ENL 12/2018
% Runs a flight arena experiment, closed loop trials to test effects of
% laser intensity
% Don't forgot to change the serial port settings in init_serial - as of
% now it's hard coded as COM5.
clear all; close all;

%% Declare variables

% user input variables:
FlyType = 'spMN1';
CL_Gain = 6; % Hz
X_Pos = 72; % 72 is center
variables.blocks = 1;
variables.repeats = 1; 
variables.TrialLength = 4.5;     % seconds
% LED/laser variables
variables.Frequencies = 200;   % Hz
variables.DutyCycle = 50; % percent not changable in the code yet
variables.StimDurations = [100 300 1000];   % ms
variables.latency = 1.5;          % s
variables.intensity = [0];
% NIdaq variables
variables.SampleRate = 20000;

% fixed variables:
CLStripe = 14; % 14 is full vertical stripe on display
variables.conditions = 1; %* length(variables.PulseDurations) * length(variables.Frequencies);
panel_pause = .005; % short time to 'space out' commands send to controller
variables.CL_X_gain = CL_Gain;     % closed loop gain
now = datetime('now','TimeZone','local');
filename = 'test_';
formatOut = 'yyyymmddHHMMSS';
fileroot = 'D:\Yichen\Temp\';
FILENAME = [fileroot filename datestr(now,formatOut)]; %,'.txt'];
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
% ch = addAnalogInputChannel(mainSession,deviceID,'ai9','Voltage');

outputSession = daq.createSession('ni');
outputSession.Rate = variables.SampleRate;
outputSession.IsContinuous = 0.5;
addAnalogOutputChannel(outputSession,deviceID,'ao1','Voltage');

[outputSignal,stimSchedule, StimParam] = CreateStimuliTrains(variables);
variables.stimSchedule = stimSchedule;
variables.StimParam = StimParam;

lh2 = addlistener(mainSession,'DataAvailable',@(src,event)logData(src,event,fid1));

%% Run Arena Program, acquire data per trial

sessionSchedule = zeros(variables.blocks,variables.conditions);
Panel_com('stop'); pause(panel_pause);
Panel_com('set_ao',[4, 0]); pause(panel_pause);
mainSession.startBackground();

for repeat = 1:variables.repeats
for stimType = 1:length(stimSchedule)
    thisTrialParams = stimSchedule(stimType);
    for block = 1:variables.blocks
        trialSchedule = randperm(variables.conditions); 
        sessionSchedule(block,1:3) = trialSchedule;
        for trial = 1:length(trialSchedule)
            currentTrial = trialSchedule(trial);
            queueOutputData(outputSession,outputSignal(:,thisTrialParams));
            Panel_com('set_ao',[4, 0]); pause(panel_pause);
            % keyboard
            tic
            Panel_com('set_pattern_id', CLStripe); pause(panel_pause);
            Panel_com('set_mode', [1, 0]); pause(panel_pause); % the mode code for CL on X
            Panel_com('set_position', [X_Pos 1]); pause(panel_pause); % randomize at some point?
            Panel_com('send_gain_bias',[variables.CL_X_gain,0,0,0]); pause(panel_pause);
            Panel_com('set_ao',[4, analog_output_codes(currentTrial)]); pause(panel_pause);
            Panel_com('start');
            outputSession.startBackground()
            pause(variables.TrialLength); % the pause determines the trial length
            Panel_com('stop'); pause(panel_pause);
            Panel_com('set_ao',[4, 0]); pause(panel_pause);
            outputSession.stop();
            toc
            fprintf(['finished trial ', num2str(trial), ' of ', num2str(variables.conditions), '\n']);
        end
%         fprintf(['>>>>>>>>>>>>finished block ', num2str(block), ' of ', num2str(variables.blocks), '\n']);
        
    end
    
    fprintf(['>>>>>>>>>>>>finished stimulation ', num2str(stimType), ' of ', num2str(length(stimSchedule)), '\n']);        
end
    fprintf(['>>>>>>>>>>>>finished block ', num2str(repeat), ' of ', num2str(variables.repeats), '\n']);

end

mainSession.stop();
delete(lh2);

%% Part IV: save data
d = dir(fileroot);
fid2 = fopen([fileroot d(length(d)).name]);
[Data,count] = fread(fid2,[10,inf],'double');
fclose(fid2);

for i = 1:7
    downSampData(i,:) = downsample(Data(i,:),20);
end
wbData = Data(8:9,:);

formatOut = 'yyyy_mmdd_HHMM';
savedate = datestr(now,formatOut);
baseFileName = strcat(FlyType,'_',savedate);
fpath = strcat('D:\Yichen\Temp\', baseFileName);

save(fpath,'wbData','downSampData','variables'); 