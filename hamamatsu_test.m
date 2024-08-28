% Initialize the video input object
vid = videoinput('hamamatsu', 1, 'MONO8_2048x2048_FastMode');  % DeviceID = 1

% Set the Region of Interest (ROI) to a 256x256 pixel area in the center
roiStartX = (2048 - 256) / 2;  % X-coordinate start position
roiStartY = (2048 - 256) / 2;  % Y-coordinate start position
vid.ROIPosition = [roiStartX roiStartY 256 256];

% Set the FramesPerTrigger to capture 500 frames (1 second at 500 Hz)
vid.FramesPerTrigger = 500;
vid.FrameGrabInterval = 1;

% Set logging mode to disk and specify the save directory and filename
vid.LoggingMode = 'disk';
videoFileName = 'test_video_no_trigger.avi';
savePath = fullfile('C:\Users\Lylah\Desktop\test_hamamatsu', videoFileName);
vid.DiskLogger = VideoWriter(savePath, 'Grayscale AVI');

% Start the acquisition immediately
start(vid);

% Wait for the acquisition to complete
while vid.FramesAvailable < vid.FramesPerTrigger
    pause(0.1);  % Briefly pause to allow acquisition to proceed
end

% Stop the acquisition
stop(vid);

% Clean up
delete(vid);
clear vid;

% Re-enable the warning (optional)
warning('on', 'imaq:hamamatsu:TriggerConnectorAdjusted');

disp(['Video saved to: ', savePath]);
