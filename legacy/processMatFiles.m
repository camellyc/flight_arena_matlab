function processMatFiles()
    % Let user select the parent directory
    parentDir = uigetdir('Select the parent directory containing data folders');
    if parentDir == 0
        fprintf('No directory selected. Operation cancelled.\n');
        return;
    end
    
    % Get all subdirectories
    allDirs = genpath(parentDir);
    folders = textscan(allDirs, '%s', 'Delimiter', pathsep);
    folders = folders{1};
    
    % Process each folder
    totalProcessed = 0;
    for folderIdx = 1:length(folders)
        currentDir = folders{folderIdx};
        if isempty(currentDir)
            continue;
        end
        
        fprintf('\nProcessing folder: %s\n', currentDir);
        
        % Get all files in the directory
        files = dir(currentDir);
        
        % Create a map to store related files
        fileMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
        
        % First pass: organize files by their base names
        for i = 1:length(files)
            if files(i).isdir
                continue;  % Skip directories
            end
            
            [~, baseName, ext] = fileparts(files(i).name);
            
            % Skip .mp4 files as specified
            if strcmpi(ext, '.mp4')
                continue;
            end
            
            % Create or get the file info cell array
            if ~isKey(fileMap, baseName)
                fileMap(baseName) = {'', ''};  % {matFile, binaryFile}
            end
            
            currentFiles = fileMap(baseName);
            
            % Store the file paths based on their extension
            if strcmpi(ext, '.mat')
                currentFiles{1} = fullfile(currentDir, files(i).name);
            elseif isempty(ext)
                currentFiles{2} = fullfile(currentDir, files(i).name);
            end
            
            fileMap(baseName) = currentFiles;
        end
        
        % Process each set of files in current folder
        baseNames = keys(fileMap);
        folderProcessed = 0;
        
        for i = 1:length(baseNames)
            baseName = baseNames{i};
            currentFiles = fileMap(baseName);
            matFile = currentFiles{1};
            binaryFile = currentFiles{2};
            
            % Check if we have both required files
            if ~isempty(matFile) && ~isempty(binaryFile)
                try
                    % Load the .mat file
                    matData = load(matFile);
                    
                    % Verify required variables exist
                    if ~all(isfield(matData, {'allRandomizedStimOrders', 'Data', 'variables'}))
                        warning('Mat file %s missing required variables. Skipping...', matFile);
                        continue;
                    end
                    
                    % Read the binary file
                    fid = fopen(binaryFile, 'rb');
                    if fid == -1
                        warning('Could not open binary file: %s', binaryFile);
                        continue;
                    end
                    
                    % Read as double precision and reshape to 9×n
                    binaryData = fread(fid, 'double');
                    numColumns = length(binaryData) / 9;
                    if mod(length(binaryData), 9) ~= 0
                        warning('Binary data length is not a multiple of 9 for file: %s', binaryFile);
                        fclose(fid);
                        continue;
                    end
                    binaryData = reshape(binaryData, 9, numColumns);
                    fclose(fid);
                    
                    % Create backup of original .mat file
                    backupFile = [matFile '.backup'];
                    if ~exist(backupFile, 'file')
                        copyfile(matFile, backupFile);
                    end
                    
                    % Replace the Data variable
                    matData.Data = binaryData;
                    
                    % Save the modified .mat file
                    save(matFile, '-struct', 'matData');
                    
                    fprintf('Successfully processed files for base name: %s\n', baseName);
                    folderProcessed = folderProcessed + 1;
                    totalProcessed = totalProcessed + 1;
                    
                catch err
                    warning('Error processing files for base name %s: %s', baseName, err.message);
                end
            else
                warning('Missing required files for base name: %s', baseName);
            end
        end
        
        fprintf('Processed %d file pairs in folder: %s\n', folderProcessed, currentDir);
    end
    
    fprintf('\nProcessing complete. Total files processed: %d\n', totalProcessed);
end