function [outputSignal,stimSchedule,StimParam] = CreateStimuliTrains(variables)

condition_num = 1;
for intensity_ind = 1:length(variables.intensity)
    for freq_ind = 1:length(variables.Frequencies)
        for duration_ind = 1:length(variables.StimDurations)
            StimParam(condition_num,1) = variables.intensity(intensity_ind);
            StimParam(condition_num,2) = variables.Frequencies(freq_ind);
            StimParam(condition_num,3) = variables.StimDurations(duration_ind);
            condition_num = condition_num + 1;
        end
    end
end

stimSchedule = randperm(length(StimParam));
outputSignal = zeros((variables.TrialLength * variables.SampleRate),length(StimParam));
nLatency = variables.SampleRate * variables.latency;

for i = 1:length(stimSchedule)
    thisTrialParams = stimSchedule(i);
    nStimTime = variables.SampleRate * (StimParam(thisTrialParams,3) / 1000);        
    cellsPerCycle = variables.SampleRate / StimParam(thisTrialParams,2);
    for o = nLatency:cellsPerCycle:nLatency + nStimTime
        outputSignal(o:o + (cellsPerCycle/2),i) = (StimParam(thisTrialParams,1));
    end
end