function mapCountersToPFI(devID)
% mapCountersToPFI  Print which NI counter channels map to which PFI terminals
%
% Example:
%   devices = daq.getDevices;
%   devID = devices(1).ID;
%   mapCountersToPFI(devID);

if nargin < 1 || isempty(devID)
    devices = daq.getDevices;
    assert(~isempty(devices), 'No NI DAQ devices found.');
    devID = devices(1).ID;
end

fprintf('--- Counter -> Terminal mapping (Session interface) for device %s ---\n', devID);

s = daq.createSession('ni');

% Try a reasonable range. PCIe-6321 typically has ctr0 and ctr1.
maxTry = 7;

rows = {};  % {ctrName, terminal, status}
for k = 0:maxTry
    ctrName = sprintf('ctr%d', k);

    try
        ch = addCounterInputChannel(s, devID, ctrName, 'EdgeCount');
        % Terminal is read-only but we can read it:
        term = ch.Terminal;
        rows(end+1,:) = {ctrName, term, 'OK'}; %#ok<AGROW>
    catch ME
        rows(end+1,:) = {ctrName, '', ['FAIL: ' ME.message]}; %#ok<AGROW>
    end
end

% Pretty print
fprintf('%-6s %-8s %s\n', 'CTR', 'Terminal', 'Status');
fprintf('%s\n', repmat('-',1,60));
for i = 1:size(rows,1)
    fprintf('%-6s %-8s %s\n', rows{i,1}, rows{i,2}, rows{i,3});
end

% Cleanup
try
    release(s);
catch
end

fprintf('--- Done ---\n');
end
