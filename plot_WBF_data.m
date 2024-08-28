% Define the sampling rate (Hz)
fs = 20000; % assuming your data is sampled at 20000 Hz

% Convert time to samples
pre_time = 0.8; % 0.8 seconds before LED ON
post_time = 20; % 5 seconds after LED ON
pre_samples = pre_time * fs;
post_samples = post_time * fs;

% Define the pulse interval in samples
pulse_interval = fs / 200; % For 200 Hz frequency

% Define the smoothing window size (in samples)
smooth_window = 100; % Adjust this value as needed

% Define the stimulus length in milliseconds
stim_length = 10000; % 100 ms
stim_length_seconds = stim_length / 1000; % Convert to seconds

% Find the LED ON indices
led_on_indices = [];
for i = pulse_interval+1:length(data(7,:))-pulse_interval
    if data(7,i) > 9 && all(data(7,i-pulse_interval:i-1) < 1) && any(data(7,i:i+pulse_interval-1) > 9)
        led_on_indices = [led_on_indices, i];
    end
end

% Ensure there are valid ON indices
if ~isempty(led_on_indices)
    % Initialize a matrix to store all WBF segments
    all_wbf_segments = [];
    
    % Determine the maximum length of the segments
    max_length = post_samples + pre_samples + 1;
    
    % Loop over each LED ON event
    for i = 1:length(led_on_indices)
        led_on_index = led_on_indices(i);

        start_idx = led_on_index - pre_samples;
        end_idx = led_on_index + post_samples;

        % Ensure indices are within valid range
        if start_idx < 1
            start_idx = 1;
        end
        if end_idx > length(data(4,:))
            end_idx = length(data(4,:));
        end

        % Extract and smooth the WBF data
        wbf_segment = floor(data(4, start_idx:end_idx) * 100); % Actual WBF
        smoothed_wbf = smoothdata(wbf_segment, 'movmean', smooth_window); % Smoothing

        % Adjust the segment by subtracting the baseline (mean WBF 0.5 sec before LED ON)
        baseline_wbf = mean(smoothed_wbf(1:min(pre_samples, length(smoothed_wbf))));
        adjusted_wbf = smoothed_wbf - baseline_wbf;

        % Pad the segment if it's shorter than max_length
        if length(adjusted_wbf) < max_length
            adjusted_wbf = [adjusted_wbf, NaN(1, max_length - length(adjusted_wbf))];
        end

        % Store the adjusted segment in the matrix
        all_wbf_segments = [all_wbf_segments; adjusted_wbf];
    end

    % Calculate the mean and SEM, ignoring NaN values
    mean_wbf = nanmean(all_wbf_segments, 1);
    sem_wbf = nanstd(all_wbf_segments, 0, 1) / sqrt(size(all_wbf_segments, 1));

    % Create time axis for plotting
    time_axis = linspace(-pre_time, post_time, length(mean_wbf));

    % Plot the mean WBF trace
    figure;
    hold on;

    % Set y-axis limits first
    ylim([-200, 10]); % Set the y-axis limits to [-40, 10]
    
    % Set the figure background color
    set(gca, 'Color', 'k'); % Set the axis background color to black
    set(gca, 'XColor', 'w', 'YColor', 'w', 'LineWidth', 2); % Set the axis color to white and thickness
    set(gcf, 'Color', 'k'); % Set the figure background color to black

    % Plot the mean WBF trace
    plot(time_axis, mean_wbf, 'LineWidth', 2, 'Color', [0, 191, 255] / 255); % Electric Blue

    % Plot the SEM shaded area
    fill([time_axis, fliplr(time_axis)], ...
         [mean_wbf + sem_wbf, fliplr(mean_wbf - sem_wbf)], ...
         [0, 191, 255] / 255, 'FaceAlpha', 0.3, 'EdgeColor', 'none'); % Light Blue color

    % Shade the stim_length region in Bright Crimson, spanning the full y-axis range
    stim_start_time = 0; % Start at the LED ON time
    stim_end_time = stim_start_time + stim_length_seconds; % End after the duration of stim_length
    y_limits = ylim; % Get the current y-axis limits
    fill([stim_start_time, stim_end_time, stim_end_time, stim_start_time], ...
         [y_limits(1), y_limits(1), y_limits(2), y_limits(2)], ...
         [1, 0.196, 0.353], 'FaceAlpha', 0.3, 'EdgeColor', 'none'); % Bright Crimson color

    % Set tick intervals
    yticks([-150, -100, -50, 0, 10]); % Set the y-axis to show ticks every 20 units

    % Remove x-axis labels and ticks
    set(gca, 'XTick', [], 'XColor', 'none');

    % Add a scale bar representing 1 second
    scale_bar_length = 1; % 1 second
    y_position = min(ylim) + 2; % Position slightly above the bottom of the y-axis

    % Draw the scale bar
    plot([0, scale_bar_length], [y_position, y_position], 'w', 'LineWidth', 2);

    % Label the scale bar
    text(scale_bar_length / 2, y_position - 3, '1 sec', 'Color', 'w', 'HorizontalAlignment', 'center');

    % Set labels and title (without x-axis label)
    ylabel('Wing Beat Frequency (Hz)', 'Color', 'w'); % Set ylabel color to white
    title('SS48339 > ChrimsonR', 'Color', 'w'); % Set title color to white

    hold off;

    % Ensure rendering options preserve the background and axis colors
    set(gcf, 'InvertHardcopy', 'off'); % Prevent MATLAB from inverting colors when saving

    % Save the figure
    save_dir = 'D:\Yichen\Plots'; % Directory to save the image
    file_name = 'WBF_plot'; % Name of the file without extension
    saveas(gcf, fullfile(save_dir, file_name), 'png'); % Save as PNG file in the specified directory
    print(fullfile(save_dir, file_name), '-dpng', '-r300'); % Save the figure at 300 DPI
end
