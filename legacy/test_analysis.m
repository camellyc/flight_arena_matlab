% Specify the file path
file_path = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Spiracle Imaging\', ...
             '240822_SS96091_ChR\DNp54_ChR_SS96091_4d_F_Fly2_Trial1_0-3000ms_2024_0822_114636.mat'];

% Load the .mat file
load(file_path);

% Create time vector (20000 samples = 1 second)
time = (1:size(Data,2))/20000;

% Create figure with two y-axes
figure;
yyaxis left  % First y-axis for Data6 and Data7
% Channel 7 - crimson with 30% opacity
plot(time, Data(7,:), 'Color', [0.6350 0 0 0.7], 'LineWidth', 1);
hold on;
% Channel 6 - dark grey
plot(time, Data(6,:), 'Color', [0.3 0.3 0.3], 'LineWidth', 1, 'LineStyle', '-');

ylabel('Amplitude (Volt)');

yyaxis right  % Second y-axis for Data4*100
% Channel 4 - desaturated blue
plot(time, Data(4,:)*100, 'Color', [0.3 0.4 0.8], 'LineWidth', 1);
ylabel('Amplitude (WBF)');

% Add legend and labels
legend('Opto', 'EMG', 'WBF');
xlabel('Time (seconds)');
title('Summary plot');

% Keep the plot
hold off;