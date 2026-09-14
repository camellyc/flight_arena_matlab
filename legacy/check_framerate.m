% Load the video file
videoFile = ['D:\Yichen\Spiracle_Imaging\240826_spMN2_ChR\spMN2_ChR_VT029591AD_R20F02DBD_6d_F_Fly4_Trial2_10000ms_2024_0826_141019.mp4']; % Adjust the file name as needed
vidObj = VideoReader(videoFile);

% Calculate the number of frames
numFrames = round(vidObj.FrameRate * vidObj.Duration);

% Display the number of frames
disp(['Number of Frames: ', num2str(numFrames)]);

