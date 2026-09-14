% Load the .mat file
dataFile = ['H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Spiracle Imaging\', ...
                  '240826_spMN2_ChR\10s\spMN2_ChR_VT029591AD_R20F02DBD_6d_F_Fly1_Trial2_10000ms_2024_0826_134838.mat'];
dataDoubleFile = strrep(dataFile, '.mat', ''); % Replace .mat with .dat (or other double file extension)

% Load the .mat file for variables and allRandomizedStimOrders
load(dataFile, 'allRandomizedStimOrders', 'variables');

% Load the Data from the double file
fid = fopen(dataDoubleFile, 'r');
if fid == -1
    error('Failed to open the double data file.');
end
Data = fread(fid, [9, inf], 'double');
fclose(fid);

% Extract the variables from the struct
fs = variables.SampleRate; % Sampling rate
blocks = variables.blocks; % Number of blocks
pre_time = 1; % 0.8 seconds before LED ON
post_time = 20; % 10 seconds after LED ON
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
            % Let's assume the 0 ms event happens at the expected time in the trial
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

            % Pad the segment with NaNs if it's shorter than expected
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

% Step 4: Plot the data
for j = 1:length(uniqueStimDurations)
    currentStimDuration = uniqueStimDurations(j);
    all_wbf_segments = grouped_wbf_segments{j};

    if ~isempty(all_wbf_segments)
        % Calculate the mean WBF trace across all blocks
        mean_wbf = nanmean(all_wbf_segments, 1); % Use nanmean to handle NaNs

        % Create time axis for plotting
        time_axis = linspace(-pre_time, post_time, length(mean_wbf));

        % Create a new figure for each stim duration
        figure;
        hold on;

        % Set y-axis limits from -40 to +10
        ylim([-150, 10]);
        
        % Set the figure background color
        set(gca, 'Color', 'k');
        set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2);
        set(gcf, 'Color', 'k');

        % Plot traces from each block with thinner lines and lighter shade (30%)
        for block = 1:blocks
            block_wbf = grouped_block_traces{j, block};
            if ~isempty(block_wbf)
                block_mean_wbf = nanmean(block_wbf, 1); % Use nanmean to handle NaNs
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
        file_name = ['WBF_plot_', num2str(currentStimDuration), 'ms']; % Name of the file
        saveas(gcf, fullfile(save_dir, file_name), 'png');
        print(fullfile(save_dir, file_name), '-dpng', '-r300');
        close(gcf); % Close the figure after saving to free memory
    end
end
