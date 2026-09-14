% Data rows are resolved by signal name via data_rows.m (run_session_unified files
% carry the channel names; older files fall back to rows 2/3/4/7).
clear all; close all; clc
 
dataFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data';
 
% === User Selection for Files ===
[files, dataFolder] = uigetfile('*.mat', 'Select the .mat files to include', dataFolder, 'MultiSelect', 'on');
if ischar(files)
    files = {files}; % If only one file is selected, make it a cell array
end
 
saveFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data\plots';
 
for fileIdx = 1:length(files)
    dataFile = fullfile(dataFolder, files{fileIdx});
    dataDoubleFile = strrep(dataFile, '.mat', ''); % Replace '.mat' with '' (or other double file extension)

    % Load the .mat file for variables and allRandomizedStimOrders
    load(dataFile, 'allRandomizedStimOrders', 'variables');
    dr = data_rows(dataFile);   % Data row per signal (by name for run_session_unified files, legacy rows otherwise)

    % Load Data: from the .mat when it is stored there (run_session_unified and
    % later sessions), otherwise fall back to the legacy binary double file
    if ~isempty(whos('-file', dataFile, 'Data'))
        load(dataFile, 'Data');
    elseif isfile(dataDoubleFile)
        fid = fopen(dataDoubleFile, 'r');
        Data = fread(fid, [9, inf], 'double');
        fclose(fid);
    else
        warning('No Data variable in %s and no binary data file next to it. Skipping this file.', dataFile);
        continue;
    end
 
    % Define the sampling rate (Hz)
    fs = 20000; % assuming your data is sampled at 20000 Hz
 
    % Define the smoothing window size (in samples)
    smooth_window = 1000; % Adjust this value as needed
 
    % Extract and smooth the data
    wbf_data = floor(Data(dr.wbf,:) * 100); % Actual WBF data from channel 4
    smoothed_wbf = smoothdata(wbf_data, 'movmean', smooth_window); % Smoothing
    wba_data = Data(dr.wbaL,:);  % WBA data from channel 2
    smoothed_wba = smoothdata(wba_data, 'movmean', smooth_window);  % Smoothing
    
    % Create time axis for plotting (in seconds)
    time_axis = (1:length(smoothed_wbf)) / fs;
 
    % Plot the entire WBF trace
    figure;
    hold on;
 
    % Set the figure background color
    set(gca, 'Color', 'k'); % Set the axis background color to black
    set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2); % Set the axis color to white and thickness
    set(gcf, 'Color', 'k'); % Set the figure background color to black
 
    % Plot the WBF trace (left axis)
    yyaxis left
    plot(time_axis, smoothed_wbf, 'LineWidth', 2, 'Color', [0, 191, 255] / 255); % Electric Blue
    ylabel('Wing Beat Frequency (Hz)', 'Color', 'w');
    ylim([0, 250]);
    yticks(0:50:250);
    set(gca, 'YColor', 'w');
    
    % Plot WBA (right axis)
    yyaxis right
    plot(time_axis, smoothed_wba, 'LineWidth', 2, 'Color', [0, 255, 0] / 255);
    ylabel('WBA', 'Color', 'w');
    ylim([0, 8]);
    yticks(0:2:8);
    set(gca, 'YColor', 'w');
 
    % Remove x-axis labels and ticks
    set(gca, 'XTick', [], 'XColor', 'none');
 
    % Add a scale bar representing 10 seconds, positioned away from the y-axis
    scale_bar_length = 10; % 10 seconds
    y_position = 175; % Position 25 Hz above the y-axis minimum
 
    % Draw the scale bar
    yyaxis left  % Switch to left axis for scale bar
    plot([0, scale_bar_length], [y_position, y_position], 'w', 'LineWidth', 2);
 
    % Label the scale bar
    text(scale_bar_length / 2, y_position - 15, '10 sec', 'Color', 'w', 'HorizontalAlignment', 'center');
 
    % Set the title (without x-axis label)
    title('Wing Beat Frequency', 'Color', 'w');
    
    % Add legend
    legend('WBF', 'WBA', 'TextColor', 'w', 'Color', 'k');
 
    hold off;
 
    % Ensure rendering options preserve the background and axis colors
    set(gcf, 'InvertHardcopy', 'off');
 
    % Save the figure
    save_dir = saveFolder;
    file_name = sprintf('Wing Beat Frequency %d', fileIdx);
    saveas(gcf, fullfile(save_dir, file_name), 'png');
    saveas(gcf, fullfile(save_dir, file_name), 'svg');
    print(fullfile(save_dir, file_name), '-dpng', '-r300');
end