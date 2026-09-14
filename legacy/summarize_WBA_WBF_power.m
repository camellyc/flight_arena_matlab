% Author: Yichen Luo 8/2024
% Modified to plot wingbeat frequency (WBF), wingbeat amplitude (WBA), and approximate power
% before, during, and after optogenetic stimulus delivery.
% Approximate power = (WBA*WBF)^3, normalized to baseline as 100%
% WBA is normalized to baseline as 100% (not percentage change from 0%)
% NOTE (2026-09): windowed opto stimuli (run_session_unified.m opto.mode 'windows'
% or 'both'; stimTable source == 2) are EXCLUDED from this analysis via
% exclude_window_stims.m. Only randomized stimuli are analysed for now.
% Data rows are resolved by signal name via data_rows.m (run_session_unified files
% carry the channel names; older files fall back to rows 2/3/4/7).
clear all; close all; clc
 
% === Set Variables Upfront ===
dataFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data\';
saveFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data\plots';
summary_title = 'DNg02_sparse_ChR'; % Title for the final summary plot
 
% Plot settings
x_limits = [-2, 10];    % X-axis limits in seconds (before and after LED ON)
y_limits_wbf = [-80, 20];     % Y-axis limits for WBF plots
y_limits_wba = [25, 175];     % Y-axis limits for WBA percentage plots (centered around 100%)
y_limits_power = [0, 200];    % Y-axis limits for approximate power plots (percentage)
trace_color = [0, 0.5, 1]; % Color of the traces (blue with specified RGB values)
trace_opacity = 0.3;      % Opacity for individual traces
stim_color = [1, 0.196, 0.353]; % Color for the stimulus region [1, 0.196, 0.353] for Chrimson
smooth_window_wbf = 1000;   % Smoothing window size for WBF (in samples)
smooth_window_wba = 1000;  % Smoothing window size for WBA (in samples)
smooth_window_power = 1000; % Smoothing window size for power (in samples)
start_color = [1, 1, 1]; % Start of the gradient (white)
end_color = [0.941, 0.894, 0.259]; % End of the gradient (yellow)
 
% Axis and title settings
x_title = 'Time (s)';
y_title_wbf = '\DeltaWBF (Hz)';
y_title_wba = 'WBA (%)';  % Changed from \DeltaWBA (%) to WBA (%)
y_title_power = 'Approximate Power (%)';
figure_title_prefix = 'Stim Duration: ';
title_color = 'w';
axis_font_size = 12;
title_font_size = 14;
 
% Timing settings
pre_time = abs(x_limits(1)); % Seconds before LED ON
post_time = x_limits(2);     % Seconds after LED ON
 
% Create folders for each analysis type
analysis_types = {'WBF', 'WBA', 'ApproximatePower'};
outputFolders = cell(3, 1);
for i = 1:3
    outputFolders{i} = fullfile(saveFolder, summary_title, analysis_types{i});
    if ~exist(outputFolders{i}, 'dir')
        mkdir(outputFolders{i});
    end
end
 
% === User Selection for Files ===
% Option to select files from multiple folders
all_files = {};
all_folders = {};
folder_count = 0;
 
while true
    % Ask user if they want to select files from another folder
    if folder_count == 0
        choice = questdlg('Select .mat files from folders', 'File Selection', ...
            'Select from first folder', 'Cancel', 'Select from first folder');
    else
        choice = questdlg('Select more files?', 'File Selection', ...
            'Select from another folder', 'Done with selection', 'Done with selection');
    end
    
    if strcmp(choice, 'Cancel') || strcmp(choice, 'Done with selection')
        break;
    end
    
    % Select files from current folder
    if folder_count == 0
        prompt_text = 'Select .mat files from the first folder';
    else
        prompt_text = sprintf('Select .mat files from folder %d', folder_count + 1);
    end
    
    [files, current_folder] = uigetfile('*.mat', prompt_text, dataFolder, 'MultiSelect', 'on');
    
    if isequal(files, 0) % User cancelled
        if folder_count == 0
            return; % Exit if no files selected at all
        else
            break; % Continue with already selected files
        end
    end
    
    % Convert single file selection to cell array
    if ischar(files)
        files = {files};
    end
    
    % Add full paths to the file list
    for i = 1:length(files)
        all_files{end+1} = fullfile(current_folder, files{i});
        all_folders{end+1} = current_folder;
    end
    
    folder_count = folder_count + 1;
    dataFolder = current_folder; % Update default folder for next selection
end
 
% Check if any files were selected
if isempty(all_files)
    error('No files selected. Exiting.');
end
 
fprintf('Selected %d files from %d folder(s):\n', length(all_files), folder_count);
for i = 1:length(all_files)
    [~, name, ext] = fileparts(all_files{i});
    fprintf('  %s%s\n', name, ext);
end
 
% Initialize containers for summary data across files
summary_data_wbf = struct();
summary_data_wba = struct();
summary_data_power = struct();
 
% Loop through each selected .mat file
for fileIdx = 1:length(all_files)
    % Display current file being processed
    fprintf('\n=== Processing file %d of %d ===\n', fileIdx, length(all_files));
    [~, current_file_name, ~] = fileparts(all_files{fileIdx});
    fprintf('Current file: %s\n', current_file_name);
    fprintf('Progress: %.1f%% complete\n', (fileIdx-1)/length(all_files)*100);
    
    % Load the .mat file
    dataFile = all_files{fileIdx};
    [file_folder, file_name, ~] = fileparts(dataFile);
    dataDoubleFile = fullfile(file_folder, file_name); % Remove .mat extension for double file

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
 
    % Extract the variables from the struct
    fs = variables.SampleRate; % Sampling rate
    blocks = variables.blocks; % Number of blocks
    pre_samples = pre_time * fs;
    post_samples = post_time * fs;
    pulse_interval = fs / variables.Frequency; % Pulse interval in samples
 
    % Step 1: Identify all potential LED ON events for non-zero stimuli
    led_on_indices = [];
    for k = 1:length(Data(dr.led,:)) - pulse_interval
        if Data(dr.led,k) > 9 && all(Data(dr.led,k-pulse_interval:k-1) < 1) && any(Data(dr.led,k:k+pulse_interval-1) > 9)
            led_on_indices = [led_on_indices, k];
        end
    end

    % Step 1b: Windowed stimuli (run_session_unified.m opto.mode 'windows'/'both',
    % stimTable source == 2) are NOT analysed here. Drop their LED ON events so
    % they cannot be paired with the randomized stimulus list.
    [led_on_indices, nWindowEvents] = exclude_window_stims(led_on_indices, dataFile, fs);
    if nWindowEvents > 0
        fprintf('  Excluded %d LED ON event(s) from windowed stimuli (not analysed).\n', nWindowEvents);
    end
 
    % Step 2: Match LED ON events with corresponding stim durations
    event_index = 1;
    stimulus_indices = cell(blocks, 1);
    stimulus_durations = cell(blocks, 1);
 
    for block = 1:blocks
        randomizedOrder = allRandomizedStimOrders{block};
        num_stims = length(randomizedOrder);
        block_indices = [];
 
        % Estimate block boundaries
        if block == 1
            block_start_idx = 1;
        else
            block_start_idx = round((block-1) * length(Data(dr.led,:)) / blocks) + 1;
        end
 
        if block == blocks
            block_end_idx = length(Data(dr.led,:));
        else
            block_end_idx = round(block * length(Data(dr.led,:)) / blocks);
        end
 
        block_length_samples = block_end_idx - block_start_idx + 1;
 
        % Refine block boundaries by looking at LED activity
        if block < blocks
            for i = block_end_idx-fs*5:min(block_end_idx+fs*5, length(Data(dr.led,:))-fs*5)
                if sum(Data(dr.led,i:i+fs*5) > 1) == 0
                    block_end_idx = i;
                    break;
                end
            end
        end
 
        % Calculate stimulus times
        interval = block_length_samples / (num_stims + 1) / fs;
        expected_stim_times = zeros(1, num_stims);
 
        for i = 1:num_stims
            stim_time_in_block = round(interval * i * fs);
            expected_stim_times(i) = block_start_idx + stim_time_in_block;
        end
 
        % Find LED ON events within this block
        block_led_indices = led_on_indices(led_on_indices >= block_start_idx & led_on_indices <= block_end_idx);
        local_event_index = 1;
 
        for stimIdx = 1:num_stims
            currentStimDuration = randomizedOrder(stimIdx);
 
            if currentStimDuration > 0
                if local_event_index <= length(block_led_indices)
                    block_indices = [block_indices, block_led_indices(local_event_index)];
                    local_event_index = local_event_index + 1;
                else
                    warning('Not enough LED ON events detected for block %d, stimulus %d. Using calculated time.', block, stimIdx);
                    block_indices = [block_indices, expected_stim_times(stimIdx)];
                end
            else
                block_indices = [block_indices, expected_stim_times(stimIdx)];
            end
        end
 
        stimulus_indices{block} = block_indices;
        stimulus_durations{block} = randomizedOrder;
    end
 
    % Step 3: Group events by stimulus duration and process all three metrics
    uniqueStimDurations = unique([stimulus_durations{:}]);
    grouped_wbf_segments = cell(length(uniqueStimDurations), 1);
    grouped_wba_segments = cell(length(uniqueStimDurations), 1);
    grouped_power_segments = cell(length(uniqueStimDurations), 1);
    grouped_block_traces_wbf = cell(length(uniqueStimDurations), blocks);
    grouped_block_traces_wba = cell(length(uniqueStimDurations), blocks);
    grouped_block_traces_power = cell(length(uniqueStimDurations), blocks);
 
    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        
        for block = 1:blocks
            indices_for_duration = stimulus_indices{block}(stimulus_durations{block} == currentStimDuration);
            block_wbf_segments = [];
            block_wba_segments = [];
            block_power_segments = [];
            
            for i = 1:length(indices_for_duration)
                led_on_index = indices_for_duration(i);
                start_idx = led_on_index - pre_samples;
                end_idx = led_on_index + post_samples;
 
                % Ensure indices are within valid range
                if start_idx < 1, start_idx = 1; end
                if end_idx > length(Data(dr.wbf,:)), end_idx = length(Data(dr.wbf,:)); end
 
                % Extract and process WBF data
                wbf_segment = floor(Data(dr.wbf, start_idx:end_idx) * 100);
                smoothed_wbf = smoothdata(wbf_segment, 'movmean', smooth_window_wbf);
                baseline_wbf = mean(smoothed_wbf(1:min(pre_samples, length(smoothed_wbf))));
                adjusted_wbf = smoothed_wbf - baseline_wbf;
 
                % Extract and process WBA data
                wba_segment = (Data(dr.wbaL, start_idx:end_idx) + Data(dr.wbaR, start_idx:end_idx))/2;
                smoothed_wba = smoothdata(wba_segment, 'movmean', smooth_window_wba);
                baseline_wba = mean(smoothed_wba(1:min(pre_samples, length(smoothed_wba))));
                
                % Convert WBA to percentage with baseline as 100%
                if baseline_wba == 0
                    warning('Baseline WBA is zero for file %s, stimulus %d. Setting WBA percentage to 100.', dataFile, i);
                    percentage_wba = ones(size(smoothed_wba)) * 100;
                else
                    percentage_wba = (smoothed_wba / baseline_wba) * 100;
                end
 
                % Calculate approximate power: (WBA * WBF)^3
                % Use completely RAW data first, then smooth the power result
                raw_wbf = floor(Data(dr.wbf, start_idx:end_idx) * 100);  % Raw WBF data
                raw_wba = (Data(dr.wbaL, start_idx:end_idx) + Data(dr.wbaR, start_idx:end_idx))/2;  % Raw WBA data
                
                % Calculate approximate power from raw data
                raw_power = (raw_wba .* raw_wbf).^3;
                
                % Now smooth the power result
                smoothed_power = smoothdata(raw_power, 'movmean', smooth_window_power);
                
                % Normalize to baseline (0.5s before LED ON) as 100%
                baseline_power = mean(smoothed_power(1:min(pre_samples, length(smoothed_power))));
                if baseline_power == 0
                    warning('Baseline power is zero for file %s, stimulus %d. Setting percentage to 100.', dataFile, i);
                    percentage_power = ones(size(smoothed_power)) * 100;
                else
                    percentage_power = (smoothed_power / baseline_power) * 100;
                end
 
                % Pad segments if shorter than expected
                segment_length = post_samples + pre_samples + 1;
                if length(adjusted_wbf) < segment_length
                    adjusted_wbf = [adjusted_wbf, NaN(1, segment_length - length(adjusted_wbf))];
                end
                if length(percentage_wba) < segment_length
                    percentage_wba = [percentage_wba, NaN(1, segment_length - length(percentage_wba))];
                end
                if length(percentage_power) < segment_length
                    percentage_power = [percentage_power, NaN(1, segment_length - length(percentage_power))];
                end
 
                % Store segments
                block_wbf_segments = [block_wbf_segments; adjusted_wbf];
                block_wba_segments = [block_wba_segments; percentage_wba];
                block_power_segments = [block_power_segments; percentage_power];
            end
            
            grouped_block_traces_wbf{j, block} = block_wbf_segments;
            grouped_block_traces_wba{j, block} = block_wba_segments;
            grouped_block_traces_power{j, block} = block_power_segments;
            grouped_wbf_segments{j} = [grouped_wbf_segments{j}; block_wbf_segments];
            grouped_wba_segments{j} = [grouped_wba_segments{j}; block_wba_segments];
            grouped_power_segments{j} = [grouped_power_segments{j}; block_power_segments];
        end
    end
 
    % Step 4: Create individual plots for each analysis type
    fileSummary_wbf = struct();
    fileSummary_wba = struct();
    fileSummary_power = struct();
 
    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        
        % Process WBF data
        all_wbf_segments = grouped_wbf_segments{j};
        if ~isempty(all_wbf_segments)
            mean_wbf = nanmean(all_wbf_segments, 1);
            fileSummary_wbf.(sprintf('stim_%d', currentStimDuration)) = mean_wbf;
            
            % Create WBF plot
            time_axis = linspace(x_limits(1), x_limits(2), length(mean_wbf));
            figure;
            hold on;
            ylim(y_limits_wbf);
            
            % Shade stimulus region
            stim_start_time = 0;
            stim_end_time = stim_start_time + (currentStimDuration / 1000);
            fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
                 [y_limits_wbf(1), y_limits_wbf(1), y_limits_wbf(2), y_limits_wbf(2)], ...
                 stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
            
            yline(0, '--', 'Color', 'w');
            
            % Plot block traces
            for block = 1:blocks
                block_wbf = grouped_block_traces_wbf{j, block};
                if ~isempty(block_wbf)
                    block_mean_wbf = nanmean(block_wbf, 1);
                    plot(time_axis, block_mean_wbf, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]);
                end
            end
            
            plot(time_axis, mean_wbf, 'LineWidth', 2, 'Color', trace_color);
            
            % Set appearance
            set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');
            ylabel(y_title_wbf, 'Color', 'w', 'FontSize', axis_font_size);
            xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
            title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
                'Color', title_color, 'FontSize', title_font_size);
            
            hold off;
            set(gcf, 'InvertHardcopy', 'off');
            
            % Save WBF figure
            [~, base_name, ~] = fileparts(dataFile);
            file_name = [base_name, '_WBF_plot_', num2str(currentStimDuration), 'ms'];
            saveas(gcf, fullfile(outputFolders{1}, file_name), 'png');
            print(fullfile(outputFolders{1}, file_name), '-dpng', '-r300');
            close(gcf);
        end
        
        % Process WBA data
        all_wba_segments = grouped_wba_segments{j};
        if ~isempty(all_wba_segments)
            mean_wba = nanmean(all_wba_segments, 1);
            fileSummary_wba.(sprintf('stim_%d', currentStimDuration)) = mean_wba;
            
            % Create WBA plot
            figure;
            hold on;
            ylim(y_limits_wba);
            
            % Shade stimulus region
            fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
                 [y_limits_wba(1), y_limits_wba(1), y_limits_wba(2), y_limits_wba(2)], ...
                 stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
            
            yline(100, '--', 'Color', 'w'); % 100% baseline for WBA
            
            % Plot block traces
            for block = 1:blocks
                block_wba = grouped_block_traces_wba{j, block};
                if ~isempty(block_wba)
                    block_mean_wba = nanmean(block_wba, 1);
                    plot(time_axis, block_mean_wba, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]);
                end
            end
            
            plot(time_axis, mean_wba, 'LineWidth', 2, 'Color', trace_color);
            
            % Set appearance
            set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');
            ylabel(y_title_wba, 'Color', 'w', 'FontSize', axis_font_size);
            xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
            title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
                'Color', title_color, 'FontSize', title_font_size);
            
            hold off;
            set(gcf, 'InvertHardcopy', 'off');
            
            % Save WBA figure
            file_name = [base_name, '_WBA_plot_', num2str(currentStimDuration), 'ms'];
            saveas(gcf, fullfile(outputFolders{2}, file_name), 'png');
            print(fullfile(outputFolders{2}, file_name), '-dpng', '-r300');
            close(gcf);
        end
        
        % Process Approximate Power data
        all_power_segments = grouped_power_segments{j};
        if ~isempty(all_power_segments)
            mean_power = nanmean(all_power_segments, 1);
            fileSummary_power.(sprintf('stim_%d', currentStimDuration)) = mean_power;
            
            % Create Approximate Power plot
            figure;
            hold on;
            ylim(y_limits_power);
            
            % Shade stimulus region
            fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
                 [y_limits_power(1), y_limits_power(1), y_limits_power(2), y_limits_power(2)], ...
                 stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
            
            yline(100, '--', 'Color', 'w'); % 100% baseline
            
            % Plot block traces
            for block = 1:blocks
                block_power = grouped_block_traces_power{j, block};
                if ~isempty(block_power)
                    block_mean_power = nanmean(block_power, 1);
                    plot(time_axis, block_mean_power, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]);
                end
            end
            
            plot(time_axis, mean_power, 'LineWidth', 2, 'Color', trace_color);
            
            % Set appearance
            set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');
            ylabel(y_title_power, 'Color', 'w', 'FontSize', axis_font_size);
            xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
            title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
                'Color', title_color, 'FontSize', title_font_size);
            
            hold off;
            set(gcf, 'InvertHardcopy', 'off');
            
            % Save Approximate Power figure
            file_name = [base_name, '_ApproximatePower_plot_', num2str(currentStimDuration), 'ms'];
            saveas(gcf, fullfile(outputFolders{3}, file_name), 'png');
            print(fullfile(outputFolders{3}, file_name), '-dpng', '-r300');
            close(gcf);
        end
    end
 
    % Store file summaries
    [~, base_name, ~] = fileparts(dataFile);
    summary_data_wbf(fileIdx).file_name = base_name;
    summary_data_wbf(fileIdx).data = fileSummary_wbf;
    summary_data_wba(fileIdx).file_name = base_name;
    summary_data_wba(fileIdx).data = fileSummary_wba;
    summary_data_power(fileIdx).file_name = base_name;
    summary_data_power(fileIdx).data = fileSummary_power;
end
 
% Step 5: Create summary plots across all files for each analysis type
summary_datasets = {summary_data_wbf, summary_data_wba, summary_data_power};
y_limits_all = {y_limits_wbf, y_limits_wba, y_limits_power};
y_titles_all = {y_title_wbf, y_title_wba, y_title_power};
baseline_lines = {0, 100, 100}; % Baseline reference lines (WBF at 0, WBA and Power at 100%)
 
for analysisType = 1:3
    summary_data_current = summary_datasets{analysisType};
    y_limits_current = y_limits_all{analysisType};
    y_title_current = y_titles_all{analysisType};
    baseline_line = baseline_lines{analysisType};
    
    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        figure;
        hold on;
        time_axis = linspace(x_limits(1), x_limits(2), length(mean_wbf));
       
        % Shade stimulus region
        stim_start_time = 0;
        stim_end_time = stim_start_time + (currentStimDuration / 1000);
        fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
             [y_limits_current(1), y_limits_current(1), y_limits_current(2), y_limits_current(2)], ...
             stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
         
        % Plot individual files' data
        for fileIdx = 1:length(summary_data_current)
            file_data = summary_data_current(fileIdx).data;
            if isfield(file_data, sprintf('stim_%d', currentStimDuration))
                file_trace = file_data.(sprintf('stim_%d', currentStimDuration));
                plot(time_axis, file_trace, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]);
            end
        end
     
        % Calculate and plot grand average
        grand_average = zeros(size(time_axis));
        count = 0;
        for fileIdx = 1:length(summary_data_current)
            file_data = summary_data_current(fileIdx).data;
            if isfield(file_data, sprintf('stim_%d', currentStimDuration))
                grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
                count = count + 1;
            end
        end
        if count > 0
            grand_average = grand_average / count;
            plot(time_axis, grand_average, 'LineWidth', 2, 'Color', trace_color);
        end
     
        ylim(y_limits_current);
        yline(baseline_line, '--', 'Color', 'w');
        
        % Set appearance
        set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
        set(gcf, 'Color', 'k');
        ylabel(y_title_current, 'Color', 'w', 'FontSize', axis_font_size);
        xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
        title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
            'Color', title_color, 'FontSize', title_font_size);
     
        % Display n-number
        x_position = x_limits(1) + 0.02 * (x_limits(2) - x_limits(1));
        y_position = y_limits_current(1) + 0.05 * (y_limits_current(2) - y_limits_current(1));
        text(x_position, y_position, ['n = ', num2str(count)], ...
            'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
            'FontSize', axis_font_size, 'Color', 'w');
     
        hold off;
        set(gcf, 'InvertHardcopy', 'off');
     
        % Save summary figure
        summary_file_name = sprintf('%s_%dms', summary_title, currentStimDuration);
        saveas(gcf, fullfile(outputFolders{analysisType}, summary_file_name), 'png');
        print(fullfile(outputFolders{analysisType}, summary_file_name), '-dpng', '-r300');
        close(gcf);
    end
end
 
% Step 6: Create final summary plots with all stimulus durations
final_file_names = {summary_title, [summary_title, '_WBA'], [summary_title, '_ApproximatePower']};
 
for analysisType = 1:3
    summary_data_current = summary_datasets{analysisType};
    y_limits_current = y_limits_all{analysisType};
    y_title_current = y_titles_all{analysisType};
    baseline_line = baseline_lines{analysisType};
    
    figure;
    hold on;
     
    % Generate custom colormap
    n_colors = length(uniqueStimDurations);
    colors = [linspace(start_color(1), end_color(1), n_colors)', ...
              linspace(start_color(2), end_color(2), n_colors)', ...
              linspace(start_color(3), end_color(3), n_colors)'];
     
    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        grand_average = zeros(size(time_axis));
        sem = zeros(size(time_axis));
        count = 0;
     
        % Calculate grand average and SEM
        for fileIdx = 1:length(summary_data_current)
            file_data = summary_data_current(fileIdx).data;
            if isfield(file_data, sprintf('stim_%d', currentStimDuration))
                grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
                sem = sem + (file_data.(sprintf('stim_%d', currentStimDuration))).^2;
                count = count + 1;
            end
        end
        if count > 0
            grand_average = grand_average / count;
            sem = sqrt(sem / count - (grand_average.^2)) / sqrt(count);
            % Plot SEM area
            upper_bound = grand_average + sem;
            lower_bound = grand_average - sem;
            fill([time_axis, fliplr(time_axis)], [upper_bound, fliplr(lower_bound)], ...
                colors(j, :), 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off');
     
            % Plot grand average line
            plot(time_axis, grand_average, 'LineWidth', 2, 'Color', colors(j, :), ...
            'DisplayName', sprintf('%d ms', currentStimDuration));
        end
    end
     
    % Set axis limits and appearance
    xlim(x_limits);
    xticks(0:5:10);
    ylim(y_limits_current);
    
    % Set appropriate y-ticks based on analysis type
    if analysisType == 1 % WBF
        yticks(-80:40:20);
    elseif analysisType == 2 % WBA
        yticks(50:25:150); % Adjusted for 100% baseline
    else % Approximate Power
        yticks(0:50:200);
    end
     
    yline(baseline_line, '--', 'Color', 'w', 'HandleVisibility', 'off');
     
    % Adjust axis position
    ax = gca;
    ax.Position = [0.15, 0.25, 0.7, 0.65];
    ax.XColor = 'w';
    ax.YColor = 'w';
     
    % Set figure appearance
    set(gca, 'Color', 'k');
    set(gcf, 'Color', 'k');
     
    % Add labels and legend
    ylabel(y_title_current, 'Color', 'w', 'FontSize', axis_font_size);
    xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
    legend_handle = legend('show', 'TextColor', 'w', 'Location', 'southeast');
     
    % Display n-number above legend
    legend_position = get(legend_handle, 'Position');
    text(legend_position(1), legend_position(2) + legend_position(4) + 0.02, ['n = ', num2str(count)], ...
        'Units', 'normalized', 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
        'FontSize', axis_font_size, 'Color', 'w');
     
    hold off;
     
    % Ensure rendering preserves colors
    set(gcf, 'InvertHardcopy', 'off');
    set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
    set(gcf, 'Color', 'k');
     
    % Save final summary figure
    saveas(gcf, fullfile(outputFolders{analysisType}, final_file_names{analysisType}), 'png');
    saveas(gcf, fullfile(outputFolders{analysisType}, final_file_names{analysisType}), 'svg');
    print(fullfile(outputFolders{analysisType}, final_file_names{analysisType}), '-dpng', '-r300');
    close(gcf);
end
 
fprintf('Analysis complete! All figures saved in their respective folders:\n');
fprintf('- WBF: %s\n', outputFolders{1});
fprintf('- WBA: %s\n', outputFolders{2});
fprintf('- Approximate Power: %s\n', outputFolders{3});