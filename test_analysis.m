% Specify the file path
file_path = 'H:\.shortcut-targets-by-id\10pxdlRXtzFB-abwDGi0jOGOFFNm3pmFK\Tuthill Lab Shared\Yichen\Spiracle\Spiracle Imaging\240827_spSN_ChR\spSN_ChR_SS48339_6d_F_Fly1_Trial1_0-3000ms_2024_0827_110921'; % replace with actual filename

% Open the file
fid = fopen(file_path, 'r');

% Check if the file opened successfully
if fid == -1
    error('Failed to open file.');
end

% Read the data
data = fread(fid, [9, inf], 'double');

% Close the file
fclose(fid);

% Inspect the data
disp(size(data));

