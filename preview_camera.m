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
%   preview_camera('resume', fig)   % restart the previews in that window (after a
%                                   % stoppreview, e.g. once the cameras are started)
%   preview_camera('close')         % close any preview window; a standalone one
%                                   % releases its cameras
%
% Each view is shown as the final video will be: the rotate_deg that is not done
% on-camera (90 deg for the top camera) is applied to the display. Standalone, the
% cameras get the session's exposure, gain, gamma, binning and 180 deg flip but run
% free (TriggerMode Off), so no DAQ is needed. Close the window to release them; a
% session does that too before it takes the cameras.
%
% Standalone, the cameras are found by serial number. After a session (imaqreset) the
% USB3 cameras take a few seconds to re-enumerate, so the search polls for up to
% basler.discover_timeout_s; if one is still missing and nothing else is using the
% adaptor, the adaptor is reset once and the search repeated. Idle videoinputs left
% by an earlier preview are deleted first.
%
% Camera settings outlast the videoinput: the free-run rate limit set here
% (AcquisitionFrameRateEnable at basler.fps) stayed on in the cameras and made the
% hardware-triggered sessions of 2026-10-01..13 drop every other 100 Hz trigger (half
% the frames). run_session_unified now switches it off when it arms the trigger; any
% other property a session relies on must likewise be set there, not assumed.
%
% During a session the window opens while the rest of the session sets up (cameras
% free-running), is paused while the trigger is armed, and resumes on the running
% acquisition, where it updates on every trigger. Every displayed frame is drawn on
% MATLAB's main thread, with the DAQ callbacks and the live plot.
%
% See also RUN_SESSION_UNIFIED, SESSION_DEFAULTS.

TAG        = 'preview_camera';
AXIS_COLOR = [1 0.85 0];      % the X / Y axes over the top view

if nargin >= 1 && (ischar(basler) || isstring(basler))
    switch lower(char(basler))
        case 'close'
            closeWindows(TAG);
        case 'resume'
            assert(nargin >= 2, 'preview_camera: ''resume'' needs the preview window handle.');
            resumePreviews(vids);
        otherwise
            error('preview_camera:command', 'preview_camera: unknown command ''%s''.', char(basler));
    end
    return;
end
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
    % A previous preview window (closed through its close function so it releases
    % its cameras) and every other idle videoinput: a session's own are Running.
    closeWindows(TAG);
    old = imaqfind('Type', 'videoinput');
    for k = 1:numel(old)
        if strcmp(old(k).Running, 'off') && strcmp(old(k).Previewing, 'off'), delete(old(k)); end
    end
    vids = openCameras(basler, cams);
end
cams = cams(cellfun(@(c) ~isempty(vids.(c)) && isvalid(vids.(c)), cams));
assert(~isempty(cams), 'preview_camera: no camera to show (vids.top and vids.side are empty).');

fig = figure('Name', 'Basler preview', 'NumberTitle', 'off', 'Tag', TAG, ...
             'MenuBar', 'none', 'ToolBar', 'none', 'Color', [0.15 0.15 0.15], ...
             'CloseRequestFcn', @(src, ~) onClose(src));
imgs = struct();
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
    imgs.(cam) = img;
    try
        startPreview(vids.(cam), img);
    catch ME
        onClose(fig);
        error('preview_camera:preview', '%s: the preview could not start: %s', cfg.label, ME.message);
    end
end
setappdata(fig, 'vids', vids);      % for 'resume'
setappdata(fig, 'images', imgs);
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

function startPreview(vid, img)
% preview() on a videoinput set up for hardware triggering warns while TriggerMode is
% still Off (a session arms it only at start()); that is the intended free-run view.
ws = warning('off', 'all');
restore = onCleanup(@() warning(ws));
preview(vid, img);
end

function resumePreviews(fig)
% Restart the previews of a window after stoppreview (the session does that to arm the
% trigger): the same image handles, so the view just carries on.
assert(~isempty(fig) && isvalid(fig) && isappdata(fig, 'images'), ...
       'preview_camera: not a preview_camera window.');
vids = getappdata(fig, 'vids');
imgs = getappdata(fig, 'images');
for c = fieldnames(imgs)'
    v = vids.(c{1});
    if isempty(v) || ~isvalid(v) || ~isvalid(imgs.(c{1})), continue; end
    startPreview(v, imgs.(c{1}));
end
end

function closeWindows(tag)
% Close every preview window through its close function (a standalone one releases
% its cameras there); a window whose close function fails is deleted anyway.
wins = findall(groot, 'Type', 'figure', 'Tag', tag);
for k = 1:numel(wins)
    try
        close(wins(k));
    catch
    end
    if isvalid(wins(k)), delete(wins(k)); end
end
end

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

function [info, names, missing] = findCameras(wanted, timeout_s)
% Enumerate the GenTL devices until every wanted serial is listed or the time is up
% (USB3 cameras take a moment to come back after imaqreset).
t0 = tic;
while true
    try
        info = imaqhwinfo('gentl');
    catch ME
        error('preview_camera:adaptor', ...
              'The Image Acquisition Toolbox gentl adaptor is not available: %s', ME.message);
    end
    if isstruct(info.DeviceInfo) && ~isempty(info.DeviceInfo)
        names = {info.DeviceInfo.DeviceName};
    else
        names = {};
    end
    missing = wanted(~cellfun(@(sn) any(contains(names, ['(' sn ')'])), wanted));
    if isempty(missing) || toc(t0) > timeout_s, return; end
    pause(0.5);
end
end

function vids = openCameras(basler, cams)
% Free-running videoinputs with the session's imaging settings (the trigger setup of
% run_session_unified's setupBasler is left out). A camera that is not enumerated,
% or cannot be opened, is skipped with a warning.
vids = struct('top', [], 'side', []);
timeout_s = 5;
if isfield(basler, 'discover_timeout_s'), timeout_s = basler.discover_timeout_s; end
wanted = cellfun(@(c) basler.(c).serial, cams, 'UniformOutput', false);
[info, names, missing] = findCameras(wanted, timeout_s);
if ~isempty(missing) && isempty(imaqfind)
    % Nothing else holds a videoinput, so the adaptor can be reset: that re-enumerates
    % a camera a previous session or Pylon Viewer left in a bad state.
    fprintf('preview_camera: serial %s not enumerated after %g s; imaqreset and retry...\n', ...
            strjoin(missing, ', '), timeout_s);
    imaqreset;
    [info, names] = findCameras(wanted, max(timeout_s, 10));
end
exposure = min(basler.Exposure_time, (1e6 / basler.fps) * 0.9);
for c = cams
    cfg = basler.(c{1});
    idx = find(contains(names, ['(' cfg.serial ')']), 1);
    if isempty(idx)
        warning('preview_camera:cameraMissing', ...
                '%s (serial %s) not found. Close Pylon Viewer, check the USB cable.', cfg.label, cfg.serial);
        continue;
    end
    try
        vid = videoinput('gentl', info.DeviceInfo(idx).DeviceID, basler.format);
    catch ME
        warning('preview_camera:cameraBusy', ...
                '%s (serial %s) could not be opened: %s', cfg.label, cfg.serial, ME.message);
        continue;
    end
    try
        configureFreeRun(vid, basler, cfg, exposure);
    catch ME
        delete(vid);
        ME2 = MException('preview_camera:configure', '%s (serial %s): %s', cfg.label, cfg.serial, ME.message);
        throw(addCause(ME2, ME));
    end
    vids.(c{1}) = vid;
end
if isempty(vids.top) && isempty(vids.side)
    if isempty(names), seen = 'none'; else, seen = strjoin(names, ', '); end
    error('preview_camera:noCamera', ...
          'preview_camera: no camera could be opened. GenTL devices enumerated: %s.', seen);
end
end

function configureFreeRun(vid, basler, cfg, exposure)
% The session's imaging settings, free-running at its frame rate. These persist in
% the camera (see the note in the header about the frame-rate limit).
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
end
