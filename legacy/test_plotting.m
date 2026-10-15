% Data: 9 x 1800000 double, one variable per row
[nVar, nSamp] = size(Data);

%% ---- Plot: one subplot per row, downsampled for display ----
step = max(1, floor(nSamp / 20000));   % ~20k points per trace; set to 1 for raw
x    = 1:step:nSamp;

figure('Name', 'All variables', 'Color', 'w');
ax = gobjects(nVar, 1);
for k = 1:nVar
    ax(k) = subplot(nVar, 1, k);
    plot(x, Data(k, x));
    ylabel(sprintf('Var %d', k));
    axis tight
    grid on
    if k < nVar
        set(ax(k), 'XTickLabel', []);
    end
end
xlabel('Sample');
linkaxes(ax, 'x');

%% ---- Export rows 6 and 8 to CSV on the Desktop ----
answer = inputdlg('File name (without .csv):', 'Save CSV', 1, {'session'});
if isempty(answer) || isempty(strtrim(answer{1}))
    disp('Save cancelled.');
    return
end
fname = regexprep(strtrim(answer{1}), '[\\/:*?"<>|]', '_');   % strip illegal chars

desktop = fullfile(getenv('USERPROFILE'), 'Desktop');           % Windows
if ~isfolder(desktop)
    desktop = fullfile(char(java.lang.System.getProperty('user.home')), 'Desktop');
end
outPath = fullfile(desktop, [fname '.csv']);

T = table(Data(6, :)', Data(8, :)', ...
          'VariableNames', {'wingbeat_trigger', 'hutchen_signal'});
writetable(T, outPath);
fprintf('Saved %d rows to %s\n', height(T), outPath);