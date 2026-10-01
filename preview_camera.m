function varargout = preview_camera(basler, vids)
% PREVIEW_CAMERA  Live view of the top and side Basler cameras side by side, the
% top view with X and Y axes through the centre of the frame.
%
% USAGE
%   preview_camera                  % open the cameras free-running with the settings
%                                   % in session_defaults.m (for placing the fly)
%   preview_camera(basler)          % ... with this basler settings struct instead
%   fig = preview_camera(basler, vids)
%                                   % show videoinputs someone else owns (what
%                                   % run_session_unified does with basler.preview);
%                                   % closing the window then only stops the preview
%
% Each view is shown as the final video will be: the rotate_deg that is not done
% on-camera (90 deg for the top camera) is applied to the display. Standalone, the
% cameras get the session's exposure, gain, gamma, binning and 180 deg flip but run
% free (TriggerMode Off), so no DAQ is needed. Close the window to release them; a
% session's close all does that too before it takes the cameras.
%
% Every displayed frame is drawn on MATLAB's main thread. Standalone that costs
% nothing; during a session it competes with the DAQ callbacks (see basler.preview).
%
% See also RUN_SESSION_UNIFIED, SESSION_DEFAULTS.

TAG        = 'preview_camera';
AXIS_COLOR = [1 0.85 0];      % the X / Y axes over the top view

if nargin < 1 || isempty(basler)
    S = session_defaults();
    basler = S.basler;
end
owned = nargin < 2;           % we open (and on close, release) the cameras
cams = {};
if basler.top.enable,  cams{end + 1} = 'top';  end
if basler.side.enable, cams{end + 1} = 'side'; end
assert(~isempty(cams), 'preview_camera: basler.top and basler.side are both disabled.');

if owned
    % A previous preview (or one whose window was deleted without its close
    % function) may still hold the cameras: drop its window and every idle videoinput.
    delete(findall(groot, 'Type', 'figure', 'Tag', TAG));
    old = imaqfind('Type', 'videoinput');
    for k = 1:numel(old)
        if strcmp(old(k).Running, 'off'), delete(old(k)); end
    end
    vids = openCameras(basler, cams);
    cams = cams(cellfun(@(c) ~isempty(vids.(c)), cams));
end

fig = figure('Name', 'Basler preview', 'NumberTitle', 'off', 'Tag', TAG, ...
             'MenuBar', 'none', 'ToolBar', 'none', 'Color', [0.15 0.15 0.15], ...
             'CloseRequestFcn', @(src, ~) onClose(src));
for k = 1:numel(cams)
    cam = cams{k};
    cfg = basler.(cam);
    ax  = subplot(1, numel(cams), k, 'Parent', fig);
    img = image(ax, zeros(2, 2, 'uint8'));
    colormap(ax, gray(256));
    axis(ax, 'image', 'off');
    title(ax, sprintf('%s (%s)', cfg.label, cfg.serial), 'Color', 'w', 'Interpreter', 'none');
    if strcmp(cam, 'top')
        axes_ = struct('x', line(ax, nan(1, 2), nan(1, 2), 'Color', AXIS_COLOR, 'LineWidth', 1), ...
                       'y', line(ax, nan(1, 2), nan(1, 2), 'Color', AXIS_COLOR, 'LineWidth', 1), ...
                       'xl', text(ax, nan, nan, 'X', 'Color', AXIS_COLOR, 'FontWeight', 'bold', ...
                                  'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom'), ...
                       'yl', text(ax, nan, nan, 'Y', 'Color', AXIS_COLOR, 'FontWeight', 'bold', ...
                                  'HorizontalAlignment', 'left', 'VerticalAlignment', 'top'));
    else
        axes_ = [];
    end
    k90 = mod(pendingRotation(cfg), 360) / 90;
    setappdata(img, 'UpdatePreviewWindowFcn', @(~, evt, h) showFrame(evt, h, ax, k90, axes_));
    preview(vids.(cam), img);
end
if nargout > 0, varargout{1} = fig; end

    function onClose(win)
        for c = cams
            v = vids.(c{1});
            if isempty(v) || ~isvalid(v), continue; end
            try
                stoppreview(v);
            catch
            end
            if owned, delete(v); end
        end
        delete(win);
    end
end

%% ---------------------------------------------------------------------------

function showFrame(evt, h, ax, k90, axes_)
% One preview frame: rotate as the final video will be, and keep the image, the
% axes limits and the centre axes in step with the frame size.
frame = evt.Data;
if k90 > 0, frame = rot90(frame, -k90); end        % clockwise
[H, W] = size(frame);
if ~isequal(size(h.CData), [H W])
    set(h, 'XData', [1 W], 'YData', [1 H]);
    set(ax, 'XLim', [0.5 W + 0.5], 'YLim', [0.5 H + 0.5]);
    if ~isempty(axes_)
        cx = (W + 1) / 2; cy = (H + 1) / 2;
        set(axes_.x, 'XData', [0.5 W + 0.5], 'YData', [cy cy]);
        set(axes_.y, 'XData', [cx cx], 'YData', [0.5 H + 0.5]);
        set(axes_.xl, 'Position', [W - 2, cy - 2]);
        set(axes_.yl, 'Position', [cx + 3, 3]);
    end
end
h.CData = frame;
end

function k = pendingRotation(cfg)
% Degrees clockwise still to apply to what the camera sends. run_session_unified
% records it in rotate_deg_pending; standalone, 180 is done on-camera (openCameras).
if isfield(cfg, 'rotate_deg_pending'), k = cfg.rotate_deg_pending;
elseif cfg.rotate_deg == 180,          k = 0;
else,                                  k = cfg.rotate_deg;
end
end

function vids = openCameras(basler, cams)
% Free-running videoinputs with the session's imaging settings (the trigger setup of
% run_session_unified's setupBasler is left out). A camera that is not enumerated
% is skipped with a warning.
vids = struct('top', [], 'side', []);
info = imaqhwinfo('gentl');
names = {info.DeviceInfo.DeviceName};
exposure = min(basler.Exposure_time, (1e6 / basler.fps) * 0.9);
for c = cams
    cfg = basler.(c{1});
    idx = find(contains(names, ['(' cfg.serial ')']), 1);
    if isempty(idx)
        warning('preview_camera:cameraMissing', ...
                '%s (serial %s) not found. Close Pylon Viewer, check the USB cable.', cfg.label, cfg.serial);
        continue;
    end
    vid = videoinput('gentl', info.DeviceInfo(idx).DeviceID, basler.format);
    src = getselectedsource(vid);
    src.TriggerSelector = 'FrameStart';
    src.TriggerMode     = 'Off';
    if cfg.binning > 1
        src.BinningHorizontal     = cfg.binning;
        src.BinningVertical       = cfg.binning;
        src.BinningHorizontalMode = 'Sum';
        src.BinningVerticalMode   = 'Sum';
    end
    src.ExposureTime = exposure;
    src.Gain         = cfg.gain;
    src.Gamma        = cfg.gamma;
    flip = 'False';
    if cfg.rotate_deg == 180, flip = 'True'; end
    try
        src.ReverseX = flip;
        src.ReverseY = flip;
    catch
    end
    try                                            % free run at the session's frame rate
        src.AcquisitionFrameRateEnable = 'True';
        src.AcquisitionFrameRate       = basler.fps;
    catch
    end
    vids.(c{1}) = vid;
end
assert(~isempty(vids.top) || ~isempty(vids.side), 'preview_camera: no camera could be opened.');
end
