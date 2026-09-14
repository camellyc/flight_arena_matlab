% Author: Yichen Luo 8/2024
% Plot wingbeat frequency data, before, during, and after optogenetic
% stimulus delivery. Summarize all data across flies and plot the mean.
% NOTE (2026-09): windowed opto stimuli (run_session_unified.m opto.mode 'windows'
% or 'both'; stimTable source == 2) are EXCLUDED from this analysis via
% exclude_window_stims.m. Only randomized stimuli are analysed for now.
% Data rows are resolved by signal name via data_rows.m (run_session_unified files
% carry the channel names; older files fall back to rows 2/3/4/7).
clear all; close all; clc

% === Set Variables Upfront ===
dataFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data\';
saveFolder = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Flight_Arena_Data\plots'; % Directory to save the images
summary_title = 'ThSN2_ChR'; % Title for the final summary plot
final_summary_file_name = summary_title;

% Plot settings
x_limits = [-2, 10];    % X-axis limits in seconds (before and after LED ON)
y_limits = [-80, 20];     % Y-axis limits for WBF plots
trace_color = [0, 0.5, 1]; % Color of the WBF traces (blue with specified RGB values)
trace_opacity = 0.3;      % Opacity for individual traces
stim_color = [1, 0.196, 0.353]; % Color for the stimulus region [1, 0.196, 0.353]for Chrimson, [0.404, 1, 0.345] for GtACR 
smooth_window = 100;      % Smoothing window size (in samples)
start_color = [1, 1, 1]; % Start of the gradient (e.g., white)
end_color = [0.941, 0.894, 0.259];   % End of the gradient (e.g., red)
% Blue for DN: [0, 0.447, 0.698] #0072B2
% Yellow for MN: [0.941, 0.894, 0.259] #F0E442
% Magenta for IN: [0.8, 0.475, 0.655] #CC79A7
% Teal for SN: [0, 0.620, 0.451] #009E73
% Orange for AN: [0.835, 0.369, 0] #D55E00
% Grey for control: [0.5, 0.5, 0.5] #808080

% Axis and title settings
x_title = 'Time (s)';         % X-axis label
y_title = '\DeltaWBF (Hz)';   % Y-axis label
figure_title_prefix = 'Stim Duration: '; % Prefix for the figure title
title_color = 'w';            % Color for the figure titles
axis_font_size = 12;          % Font size for axis labels
title_font_size = 14;         % Font size for figure titles

% Timing settings
pre_time = abs(x_limits(1)); % Seconds before LED ON
post_time = x_limits(2);      % Seconds after LED ON

% Create a folder named after summary_title under saveFolder
outputFolder = fullfile(saveFolder, summary_title);
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% === User Selection for Files ===
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

    % Step 2: Match LED ON events with corresponding stim durations, handle 0 ms separately
    event_index = 1;
    stimulus_indices = cell(blocks, 1);
    stimulus_durations = cell(blocks, 1);

    for block = 1:blocks
        randomizedOrder = allRandomizedStimOrders{block}; % Get the stim durations for this block
        num_stims = length(randomizedOrder); % Number of stimuli in this block
        block_indices = [];

        % Estimate block length by finding the range of timestamps in the current block
        % First, find approximate block boundaries (if not already known)
        if block == 1
            block_start_idx = 1;
        else
            % Estimate based on proportion of data length
            block_start_idx = round((block-1) * length(Data(dr.led,:)) / blocks) + 1;
        end

        if block == blocks
            block_end_idx = length(Data(dr.led,:));
        else
            block_end_idx = round(block * length(Data(dr.led,:)) / blocks);
        end

        % Calculate block length based on this range (in samples)
        block_length_samples = block_end_idx - block_start_idx + 1;

        % Refine block boundaries by looking at LED activity if possible
        % This helps find the actual block starts/ends if they're not perfectly evenly spaced
        if block < blocks
            % Look for a gap in LED activity that marks the end of this block
            for i = block_end_idx-fs*5:min(block_end_idx+fs*5, length(Data(dr.led,:))-fs*5)
                if sum(Data(dr.led,i:i+fs*5) > 1) == 0  % If there's a 5-second period with no LED activity
                    block_end_idx = i;
                    break;
                end
            end
        end

        % Calculate stimulus times based on the detected block length
        interval = block_length_samples / (num_stims + 1) / fs;  % interval in seconds
        expected_stim_times = zeros(1, num_stims);

        for i = 1:num_stims
            % Calculate exact stimulus time in samples, relative to block start
            stim_time_in_block = round(interval * i * fs);
            expected_stim_times(i) = block_start_idx + stim_time_in_block;
        end

        % Find LED ON events that fall within this block's bounds
        block_led_indices = led_on_indices(led_on_indices >= block_start_idx & led_on_indices <= block_end_idx);
        local_event_index = 1;  % Index for LED events within this block

        for stimIdx = 1:num_stims
            currentStimDuration = randomizedOrder(stimIdx);

            if currentStimDuration > 0
                % Handle non-zero stimuli by using detected LED ON events within this block
                if local_event_index <= length(block_led_indices)
                    block_indices = [block_indices, block_led_indices(local_event_index)];
                    local_event_index = local_event_index + 1;
                else
                    warning('Not enough LED ON events detected for block %d, stimulus %d. Using calculated time.', block, stimIdx);
                    % Fall back to the calculated time point
                    block_indices = [block_indices, expected_stim_times(stimIdx)];
                end
            else
                % Handle 0 ms stimuli by using the calculated time point
                block_indices = [block_indices, expected_stim_times(stimIdx)];
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
                if end_idx > length(Data(dr.wbf,:)), end_idx = length(Data(dr.wbf,:)); end

                % Extract and smooth the WBF data
                wbf_segment = floor(Data(dr.wbf, start_idx:end_idx) * 100); % WBF
                smoothed_wbf = smoothdata(wbf_segment, 'movmean', smooth_window); % Smoothing

                % Adjust the segment by subtracting the baseline (mean WBF 2 sec before LED ON)
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
            time_axis = linspace(x_limits(1), x_limits(2), length(mean_wbf));

            % Create a new figure for each stim duration
            figure;
            hold on;

            % Set y-axis limits
            ylim(y_limits);
            
            % Shade the stim_length region, spanning the full y-axis range
            stim_start_time = 0; % Start at the LED ON time
            stim_end_time = stim_start_time + (currentStimDuration / 1000); % End after the duration of stim_length
            fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
                 [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
                 stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
            
            % Add a dashed line at y = 0
            yline(0, '--', 'Color', 'w');

            % Plot traces from each block with thinner lines and lighter shade
            for block = 1:blocks
                block_wbf = grouped_block_traces{j, block};
                if ~isempty(block_wbf)
                    block_mean_wbf = nanmean(block_wbf, 1); % Use nanmean to ignore NaNs
                    plot(time_axis, block_mean_wbf, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]);
                end
            end

            % Plot the mean WBF trace across all blocks with thicker line
            plot(time_axis, mean_wbf, 'LineWidth', 2, 'Color', trace_color); % Solid blue line

            % Set the figure background color
            set(gca, 'Color', 'k');
            set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');
            
            % Set labels and title
            ylabel(y_title, 'Color', 'w', 'FontSize', axis_font_size);
            xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
            title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
                'Color', title_color, 'FontSize', title_font_size);

            hold off;

            % Ensure rendering options preserve the background and axis colors
            set(gcf, 'InvertHardcopy', 'off');
            set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
            set(gcf, 'Color', 'k');

            % Save the individual figure
            file_name = [files{fileIdx}(1:end-4), '_WBF_plot_', num2str(currentStimDuration), 'ms'];
            saveas(gcf, fullfile(outputFolder, file_name), 'png');
            print(fullfile(outputFolder, file_name), '-dpng', '-r300');
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
    time_axis = linspace(x_limits(1), x_limits(2), length(mean_wbf)); % Assuming all files have the same time axis length
   
    % Shade the stim_length region, spanning the full y-axis range
    stim_start_time = 0; % Start at the LED ON time
    stim_end_time = stim_start_time + (currentStimDuration / 1000); % End after the duration of stim_length
    fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
         [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
         stim_color, 'FaceAlpha', 0.3, 'EdgeColor', 'none');
     
    % Plot individual files' data as shaded curves
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            file_wbf = file_data.(sprintf('stim_%d', currentStimDuration));
            plot(time_axis, file_wbf, 'LineWidth', 1, 'Color', [trace_color, trace_opacity]); % Individual files with lighter lines
        end
    end

    % Calculate and plot the grand average across all files
    grand_average = zeros(size(time_axis));
    sem = zeros(size(time_axis));
    count = 0;
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
            sem = sem + (file_data.(sprintf('stim_%d', currentStimDuration))).^2;
            count = count + 1;
        end
    end
    if count > 0
        grand_average = grand_average / count;
        plot(time_axis, grand_average, 'LineWidth', 2, 'Color', trace_color); % Grand average with thicker line
    end

    % Set y-axis limits
    ylim(y_limits);
    
    % Add a dashed line at y = 0
    yline(0, '--', 'Color', 'w');
    
    % Set the figure background color
    set(gca, 'Color', 'k');
    set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
    set(gcf, 'Color', 'k');

    % Set labels and title
    ylabel(y_title, 'Color', 'w', 'FontSize', axis_font_size);
    xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
    title([figure_title_prefix, num2str(currentStimDuration), ' ms'], ...
        'Color', title_color, 'FontSize', title_font_size);

    % Display n-number (number of files)
    % Slightly offset from the y-axis and place near the bottom
    x_position = x_limits(1) + 0.02 * (x_limits(2) - x_limits(1)); % Small offset from y-axis
    y_position = y_limits(1) + 0.05 * (y_limits(2) - y_limits(1)); % Near the bottom

    text(x_position, y_position, ['n = ', num2str(count)], ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
    'FontSize', axis_font_size, 'Color', 'w');

    hold off;

    % Ensure rendering options preserve the background and axis colors
    set(gcf, 'InvertHardcopy', 'off');
    set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
    set(gcf, 'Color', 'k');

    % Save the summary figure
    summary_file_name = sprintf('%s_%dms', summary_title, currentStimDuration);
    saveas(gcf, fullfile(outputFolder, summary_file_name), 'png');
    print(fullfile(outputFolder, summary_file_name), '-dpng', '-r300');
    close(gcf); % Close the figure after saving to free memory
end

% Step 6: Create a final summary plot with all stim duration averages from all files
figure;
hold on;

% Generate a custom colormap from start_color to end_color
n_colors = length(uniqueStimDurations); % Number of unique stimulus durations
colors = [linspace(start_color(1), end_color(1), n_colors)', ...
          linspace(start_color(2), end_color(2), n_colors)', ...
          linspace(start_color(3), end_color(3), n_colors)'];

for j = 1:length(uniqueStimDurations)
    currentStimDuration = uniqueStimDurations(j);
    grand_average = zeros(size(time_axis));
    sem = zeros(size(time_axis));
    count = 0;

    % Calculate the grand average and SEM across all files for the current stim duration
    for fileIdx = 1:length(summary_data)
        file_data = summary_data(fileIdx).data;
        if isfield(file_data, sprintf('stim_%d', currentStimDuration))
            grand_average = grand_average + file_data.(sprintf('stim_%d', currentStimDuration));
            sem = sem + (file_data.(sprintf('stim_%d', currentStimDuration))).^2;
            count = count + 1;
        end
    end
    if count > 0
        grand_average = grand_average / count;
        sem = sqrt(sem / count - (grand_average.^2)) / sqrt(count);

        % Smooth the grand average and SEM
        grand_average_smooth = smoothdata(grand_average, 'movmean', smooth_window);
        sem_smooth = smoothdata(sem, 'movmean', smooth_window);

        % Shaded SEM area, excluded from the legend
        upper_bound = grand_average_smooth + sem_smooth;
        lower_bound = grand_average_smooth - sem_smooth;
        fill([time_axis, fliplr(time_axis)], [upper_bound, fliplr(lower_bound)], ...
            colors(j, :), 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'HandleVisibility', 'off'); % Exclude from legend

        % Plot the smoothed grand average line, included in the legend
        plot(time_axis, grand_average_smooth, 'LineWidth', 2, 'Color', colors(j, :), ...
        'DisplayName', sprintf('%d ms', currentStimDuration)); % Set DisplayName for the legend
    end

end

% Set x-axis limits from -2 to 10 seconds
xlim(x_limits);
xticks(0:5:10); % Set x-ticks every 5 seconds

% Set y-axis limits from -80 to 20 Hz
ylim(y_limits);
yticks(-80:40:20); % Set y-ticks every 40 Hz

% Add a dashed line at y = 0
yline(0, '--', 'Color', 'w', 'HandleVisibility', 'off');

% Offset the axis intersection (shift the axes away from the origin)
ax = gca;
ax.Position = [0.15, 0.25, 0.7, 0.65]; % Adjust position to offset axes
ax.XColor = 'w'; % Set x-axis color
ax.YColor = 'w'; % Set y-axis color

% Set the figure background color
set(gca, 'Color', 'k');
set(gcf, 'Color', 'k');

% Add labels, title, and legend
ylabel(y_title, 'Color', 'w', 'FontSize', axis_font_size);
xlabel(x_title, 'Color', 'w', 'FontSize', axis_font_size);
legend_handle = legend('show', 'TextColor', 'w', 'Location', 'southeast'); % Move legend to the lower right corner

% Display n-number (number of files) above the legend
legend_position = get(legend_handle, 'Position'); % Get the current legend position
text(legend_position(1), legend_position(2) + legend_position(4) + 0.02, ['n = ', num2str(count)], ...
    'Units', 'normalized', 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
    'FontSize', axis_font_size, 'Color', 'w');

hold off;

% Ensure rendering options preserve the background and axis colors
set(gcf, 'InvertHardcopy', 'off');
set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
set(gcf, 'Color', 'k');

% Save the final summary figure as PNG and SVG in the created folder
saveas(gcf, fullfile(outputFolder, final_summary_file_name), 'png');
saveas(gcf, fullfile(outputFolder, final_summary_file_name), 'svg');
print(fullfile(outputFolder, final_summary_file_name), '-dpng', '-r300');
