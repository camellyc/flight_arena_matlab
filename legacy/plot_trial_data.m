figure;
hold on;

% Plot row 4
plot(data(4, :), 'LineWidth', 2, 'DisplayName', 'Row 4');

% Plot row 7
% plot(data(9, :), 'LineWidth', 2, 'DisplayName', 'Row 7');

hold off;
xlabel('X-axis Label');
ylabel('Y-axis Label');
title('Plot of Row 4 and Row 7');
legend show; % Show the legend
