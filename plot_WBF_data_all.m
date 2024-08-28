% Author: Yichen Luo 8/2024
% Plot wingbeat frequency data, before, during and after optogenetic
% stimulus delivery. Summarize all data across flies and plot the mean.
clear all; close all; clc

dataFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Spiracle Imaging\'

% Prompt the user to select the .mat files to process
[files, dataFolder] = uigetfile('*.mat', 'Select the .mat files to include', dataFolder, 'MultiSelect', 'on');

if ischar(files)
    files = {files}; % If only one file is selected, make it a cell array
end

% Initialize containers for summary data across files
summary_data = struct();

% Loop through each selected .mat file
for fileIdx = 1:length(files)
    % Load the .mat file
    dataFile = fullfile(dataFolder, files{fileIdx});
    dataDoubleFile = strrep(dataFile, '.mat', ''); % Replace '.mat' with '' (or other double file extension)

    % Check if the data file exists
    if ~isfile(dataDoubleFile)
        warning('The corresponding data file for %s was not found. Skipping this file.', files{fileIdx});
        continue;
    end

    % Load the .mat file for variables and allRandomizedStimOrders
    load(dataFile, 'allRandomizedStimOrders', 'variables');

    % Load the Data from the double file
    fid = fopen(dataDoubleFile, 'r');
    if fid == -1
        warning('Failed to open the double data file: %s. Skipping this file.', dataDoubleFile);
        continue;
    end
    Data = fread(fid, [9, inf], 'double');
    fclose(fid);

    % Extract the variables from the struct
    fs = variables.SampleRate; % Sampling rate
    blocks = variables.blocks; % Number of blocks
    pre_time = 0.8; % 0.8 seconds before LED ON
    post_time = 10; % 10 seconds after LED ON
    pre_samples = pre_time * fs;
    post_samples = post_time * fs;
    pulse_interval = fs / variables.Frequency; % Pulse interval in samples
    smooth_window = 100; % Smoothing window size (in samples)

    % Step 1: Identify all potential LED ON events for non-zero stimuli
    led_on_indices = [];
    for k = 1:length(Data(7,:)) - pulse_interval
        if Data(7,k) > 9 && all(Data(7,k-pulse_interval:k-1) < 1) && any(Data(7,k:k+pulse_interval-1) > 9)
            led_on_indices = [led_on_indices, k];
        end
    end

    % Step 2: Match LED ON events with corresponding stim durations, handle 0 ms separately
    event_index = 1;
    stimulus_indices = cell(blocks, 1);
    stimulus_durations = cell(blocks, 1);

    for block = 1:blocks
        randomizedOrder = allRandomizedStimOrders{block}; % Get the stim durations for this block
        num_stims = length(randomizedOrder); % Number of stimuli in this block
        block_indices = [];
        
        for stimIdx = 1:num_stims
            currentStimDuration = randomizedOrder(stimIdx);
            
            if currentStimDuration > 0
                % Handle non-zero stimuli
                if event_index <= length(led_on_indices)
                    block_indices = [block_indices, led_on_indices(event_index)];
                    event_index = event_index + 1;
                else
                    warning('Not enough LED ON events detected for block %d', block);
                end
            else
                % Handle 0 ms stimuli (no actual LED ON event)
                % Assume the 0 ms event happens at the expected time in the trial
                expected_index = (stimIdx - 1) * (variables.TrialLength / num_stims) * fs + pre_samples + 1;
                block_indices = [block_indices, round(expected_index)];
            end
        end
        
        stimulus_indices{block} = block_indices; % Assign indices to the block
        stimulus_durations{block} = randomizedOrder; % Corresponding stimulus durations
    end

    % Step 3: Group events by stimulus duration across all blocks
    uniqueStimDurations = unique([stimulus_durations{:}]);
    grouped_wbf_segments = cell(length(uniqueStimDurations), 1);
    grouped_block_traces = cell(length(uniqueStimDurations), blocks);

    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        
        for block = 1:blocks
            indices_for_duration = stimulus_indices{block}(stimulus_durations{block} == currentStimDuration);
            block_wbf_segments = [];
            
            for i = 1:length(indices_for_duration)
                led_on_index = indices_for_duration(i);
                start_idx = led_on_index - pre_samples;
                end_idx = led_on_index + post_samples;

                % Ensure indices are within valid range
                if start_idx < 1, start_idx = 1; end
                if end_idx > length(Data(4,:)), end_idx = length(Data(4,:)); end

                % Extract and smooth the WBF data
                wbf_segment = floor(Data(4, start_idx:end_idx) * 100); % WBF
                smoothed_wbf = smoothdata(wbf_segment, 'movmean', smooth_window); % Smoothing

                % Adjust the segment by subtracting the baseline (mean WBF 0.5 sec before LED ON)
                baseline_wbf = mean(smoothed_wbf(1:min(pre_samples, length(smoothed_wbf))));
                adjusted_wbf = smoothed_wbf - baseline_wbf;

                % Pad the segment if it's shorter than expected
                segment_length = post_samples + pre_samples + 1;
                if length(adjusted_wbf) < segment_length
                    adjusted_wbf = [adjusted_wbf, NaN(1, segment_length - length(adjusted_wbf))];
                end

                % Store the adjusted segment in the matrix
                block_wbf_segments = [block_wbf_segments; adjusted_wbf];
            end
            
            grouped_block_traces{j, block} = block_wbf_segments;
            grouped_wbf_segments{j} = [grouped_wbf_segments{j}; block_wbf_segments];
        end
    end

    % Step 4: Plot the individual data
    fileSummary = struct(); % To hold the average WBF for each duration in this file

    for j = 1:length(uniqueStimDurations)
        currentStimDuration = uniqueStimDurations(j);
        all_wbf_segments = grouped_wbf_segments{j};

        if ~isempty(all_wbf_segments)
            % Calculate the mean WBF trace across all blocks
            mean_wbf = nanmean(all_wbf_segments, 1); % Use nanmean to ignore NaNs

            % Store the mean_wbf data for summary plot
            fileSummary.(sprintf('stim_%d', currentStimDuration)) = mean_wbf;

            % Create time axis for plotting
            time_axis = linspace(-pre_time, post_time, length(mean_wbf));

            % Create a new figure for each stim duration
            figure;
            hold on;

            % Set y-axis limits from -40 to +10
            ylim([-80, 10]);
            
            % Set the figure background color
            set(gca, 'Color', 'k');
            set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');

            % Plot traces from each block with thinner lines and lighter shade (30%)
            for block = 1:blocks
                block_wbf = grouped_block_traces{j, block};
                if ~isempty(block_wbf)
                    block_mean_wbf = nanmean(block_wbf, 1); % Use nanmean to ignore NaNs
                    plot(time_axis, block_mean_wbf, 'LineWidth', 1, 'Color', [0, 0.5, 1, 0.3]); % Lighter blue with 30% opacity
                end
            end

            % Plot the mean WBF trace across all blocks with thicker line
            plot(time_axis, mean_wbf, 'LineWidth', 2, 'Color', [0, 0.5, 1]); % Solid blue line

            % Shade the stim_length region in Bright Crimson, spanning the full y-axis range
            stim_start_time = 0; % Start at the LED ON time
            stim_end_time = stim_start_time + (currentStimDuration / 1000); % End after the duration of stim_length
            y_limits = ylim;
            fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
                 [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
                 [1, 0.196, 0.353], 'FaceAlpha', 0.3, 'EdgeColor', 'none');

            % Set labels and title
            ylabel('WBF (Hz)', 'Color', 'w');
            xlabel('Time (s)', 'Color', 'w');
            title(['Stim Duration: ', num2str(currentStimDuration), ' ms'], 'Color', 'w');

            hold off;

            % Ensure rendering options preserve the background and axis colors
            set(gcf, 'InvertHardcopy', 'off');
            set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');

            % Save the individual figure
            save_dir = 'D:\Yichen\Plots'; % Directory to save the images
            file_name = [files{fileIdx}(1:end-4), '_WBF_plot_', num2str(currentStimDuration), 'ms']; % Name of the file
            saveas(gcf, fullfile(save_dir, file_name), 'png');
            print(fullfile(save_dir, file_name), '-dpng', '-r300');
            close(gcf); % Close the figure after saving to free memory
        end
    end

    % Store this file's summary data
    summary_data(fileIdx).file_name = files{fileIdx};
    summary_data(fileIdx).data = fileSummary;
end

% Step 5: Create summary plots across all files
for j = 1:length(uniqueStimDurations)
    currentStimDuration = uniqueStimDurations(j);
    figure;
    hold on;
    time_axis = linspace(-pre_time, post_time, length(mean_wbf)); % Assuming all files have the same time axis length

    % Plot individual files' data as shaded curves
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            file_wbf = file_data.(sprintf('stim_%d', currentStimDuration));
            plot(time_axis, file_wbf, 'LineWidth', 1, 'Color', [0, 0.5, 1, 0.3]); % Individual files with lighter lines
        end
    end

    % Calculate and plot the grand average across all files
    grand_average = zeros(size(time_axis));
    count = 0;
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
            count = count + 1;
        end
    end
    if count > 0
        grand_average = grand_average / count;
        plot(time_axis, grand_average, 'LineWidth', 2, 'Color', [0, 0.5, 1]); % Grand average with thicker line
    end

    % Set y-axis limits from -40 to +10
    ylim([-80, 10]);
    
    % Set the figure background color
    set(gca, 'Color', 'k');
    set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
    set(gcf, 'Color', 'k');

    % Shade the stim_length region in Bright Crimson, spanning the full y-axis range
    stim_start_time = 0; % Start at the LED ON time
    stim_end_time = stim_start_time + (currentStimDuration / 1000); % End after the duration of stim_length
    y_limits = ylim;
    fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
         [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
         [1, 0.196, 0.353], 'FaceAlpha', 0.3, 'EdgeColor', 'none');

    % Set labels and title
    ylabel('WBF (Hz)', 'Color', 'w');
    xlabel('Time (s)', 'Color', 'w');
    title(['Summary: Stim Duration ', num2str(currentStimDuration), ' ms'], 'Color', 'w');

    hold off;

    % Ensure rendering options preserve the background and axis colors
    set(gcf, 'InvertHardcopy', 'off');
    set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
    set(gcf, 'Color', 'k');

    % Save the summary figure
    summary_file_name = sprintf('Summary_WBF_plot_%dms', currentStimDuration);
    saveas(gcf, fullfile(save_dir, summary_file_name), 'png');
    print(fullfile(save_dir, summary_file_name), '-dpng', '-r300');
    close(gcf); % Close the figure after saving to free memory
end

% Step 6: Create a final summary plot with all stim duration averages from all files
figure;
hold on;
colors = lines(length(uniqueStimDurations)); % Use MATLAB's 'lines' colormap for distinct colors

for j = 1:length(uniqueStimDurations)
    currentStimDuration = uniqueStimDurations(j);
    grand_average = zeros(size(time_axis));
    count = 0;

    % Calculate the grand average across all files for the current stim duration
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
            count = count + 1;
        end
    end
    if count > 0
        grand_average = grand_average / count;
        plot(time_axis, grand_average, 'LineWidth', 2, 'Color', colors(j, :), ...
            'DisplayName', sprintf('%d ms', currentStimDuration)); % Plot with color and legend entry
    end
end

% Set y-axis limits from -40 to +10
ylim([-80, 10]);

% Set the figure background color
set(gca, 'Color', 'k');
set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
set(gcf, 'Color', 'k');

% Add labels, title, and legend
ylabel('WBF (Hz)', 'Color', 'w');
xlabel('Time (s)', 'Color', 'w');
title('Summary of All Stim Durations', 'Color', 'w');
legend('show', 'TextColor', 'w', 'Location', 'northeast');

hold off;

% Ensure rendering options preserve the background and axis colors
set(gcf, 'InvertHardcopy', 'off');
set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
set(gcf, 'Color', 'k');

% Save the final summary figure
final_summary_file_name = 'Final_Summary_WBF_plot_All_Durations';
saveas(gcf, fullfile(save_dir, final_summary_file_name), 'png');
print(fullfile(save_dir, final_summary_file_name), '-dpng', '-r300');
close(gcf); % Close the figure after saving to free memory
