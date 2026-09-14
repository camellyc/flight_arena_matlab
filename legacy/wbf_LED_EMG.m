% Extracting the specific traces
data4 = smoothdata(Data(4, :),'movmean', 100); % WBF
data6 = Data(6, :); % EMG
data7 = Data(7, :); % LED
data8 = Data(8, :); % Hutchens
data2_3 = smoothdata(((Data(2,:) + Data(3,:))/2)/5, 'movmean', 1000); % WBA

% Normalizing data4 and data6 to the range [0, 1]
data4_normalized = (data4 - 2) / (2.5 - 2); % Normalizing data4 from 200-250 to 0-1
data6_normalized = (data6 + 10) / (20);     % Normalizing data6 from -10-10 to 0-1
% Normalizing data8 (assuming it needs normalization - adjust the range as needed)
data8_normalized = (data8 - min(data8)) / (max(data8) - min(data8)); % Normalizing data8 to 0-1

% Creating the figure with black background
figure('Color', 'k');
hold on;

% Plot LED stim in crimson with 50% opacity
plot(data7, 'Color', [0.86, 0.08, 0.24, 0.2], 'LineWidth', 1.5); % Crimson color with 50% opacity

% Plot Hutchens in cyan
%plot(data8_normalized, 'Color', [0, 1, 1], 'LineWidth', 1.5); % Cyan color

% Plot WBF in blue
plot(data4_normalized, 'Color', [0, 0, 1], 'LineWidth', 1.5); % Blue color

% Plot EMG in gray
plot(data6_normalized, 'Color', [1, 1, 1], 'LineWidth', 1.5); % Gray color

% Plot WBA in gray
plot(data2_3, 'Color', [0, 1, 0], 'LineWidth', 1.5); % Gray color


% Adding labels and title
xlabel('Time');
ylabel('Normalized Amplitude');
title('Normalized Data Plots');
legend('Data 7 (Crimson)', 'Data 4 (Blue)', 'Data 6 (Gray)', 'Data 8 (Cyan)');

% Setting black background for the axes
set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w');
hold off;