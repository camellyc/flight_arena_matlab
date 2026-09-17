function S = session_defaults()
% SESSION_DEFAULTS  The USER SETTINGS of run_session_unified, as one struct.
%
%   S = session_defaults()
%
% This file is nothing but the settings block: edit a value here, or through
% run_session_gui, whose "Save as file defaults" button rewrites the assignments
% between the USER SETTINGS markers below in place. run_session_unified reads it at
% the start of every session; run_session_unified('defaults') returns the same
% struct. Keep the two marker lines: the GUI locates the block by them, and the
% end-of-line comments become the tooltips of the GUI fields.
%
% Nothing here is derived or validated; that happens in run_session_unified after
% any overrides are merged, so a value that the rig cannot honour fails there,
% before hardware is touched.
%
% See also RUN_SESSION_UNIFIED, RUN_SESSION_GUI.

%% ======================= USER SETTINGS ==================================
saveFolder = 'K:\sanjana\dat\Raw\R71F05';

% --- Fly / experiment metadata (non-empty fields build the file name, in this order) ---
meta.experiment_name   = 'R71F05_ChR';     % e.g. SpINB_ChR
meta.genotype          = 'R71F05';  % e.g. IS46338_ChR_4d_F
meta.flyNumber         = 'ba04';
meta.trialNum          = '4';
meta.stimulus_regime   = '2-5ms';                 % e.g. 0-3000ms, 3000msx3, 10000ms
meta.stimulus_position = 'thorax';
meta.phantom_position  = '';                      % sp1, sp2, wing, ''
meta.visual_stim_type  = 'closed loop stripe';
meta.carbon_dioxide    = 'OFF';
meta.auto_trial_number = false;   % true: trialNum = 1 + #existing .mat files for this fly in saveFolder
meta.notes             = '';

% --- Hardware ---
hw.simulate    = false;   % true: no DAQ / cameras / arena; synthetic data for testing the code
hw.sim_speed   = 10;      % simulated time runs this many times faster than real time
hw.ni_device   = '';      % '' = first NI device found, or e.g. 'Dev1'
hw.panel_pause = 0.005;   % s between Panel_com commands
hw.play_sound_at_end = true;

% --- Acquisition ---
acq.SampleRate      = 10000;   % Hz
acq.TrialLength     = 30;     % s per block
acq.blocks          = 1;
acq.ai_channels     = [0:11 14];
acq.ai_names        = {'LED_driver','WBF','WBA_left','WBA_right','hutchen_left','hutchen_right', ...
                       'arena_x','arena_y','EMG','basler_trigger','phantom_fsync','basler_shutter', ...
                       'phantom_recording'};
acq.terminal_config = 'SingleEnded';   % RSE. AI8-AI14 carry their own signals, so differential pairs are impossible
acq.notify_period_s = 0.1;     % DataAvailable callback period (plot update rate)
acq.ttl_threshold_V = 1.5;     % V; a TTL loop-back (Basler trigger, Phantom Recording) above this reads as high

% --- Visual stimulus (arena) ---
% SD-card patterns: 14 = closed-loop stripe (Pattern_2_stripe_48P_RC),
%   13 = horizontal stripes + smooth vertical bar, 2 = horizontal stripes.
% Velocity functions: 4 = sine 0.025 Hz, 5 = sine 0.05 Hz, 6 = sine 0.2 Hz,
%   8 = sine 1 Hz, 9-14 = square waves (amp1/2/3 at 0.05 / 0.1 Hz).
visual.mode        = 'closed_loop_stripe';      % 'closed_loop_stripe' | 'closed_loop_oscillating' | 'none'
visual.pattern_id  = 14;
visual.CL_X_gain   = -5;
visual.x_pos       = 48;        % start X position (used in stripe mode)
visual.mode_xy     = [1 0];     % Panel_com set_mode: X closed loop, Y open loop
visual.velfunc_id  = 5;         % oscillating mode: Y velocity function id
visual.funcy_freq  = 50;        % oscillating mode: Y function update rate (Hz)
visual.y_gain      = 20;        % oscillating mode: pixels/s
visual.y_bias      = 0;
visual.cl_during_setup = true;  % closed-loop stripe while cameras/Phantom initialise (fly fixates)
visual.rest.pattern_id = 14;    % arena state before setup and after the experiment
visual.rest.x_pos      = 48;
visual.rest.CL_X_gain  = -5;

% --- Optogenetic LED (AO0) ---
opto.mode              = 'both';     % 'randomized' | 'windows' | 'both' | 'none'  ('both' = randomized + windows)
opto.ao                = 'ao0';
opto.Frequency         = 200;           % pulse rate (Hz)
opto.PulseDuration     = 3;             % pulse width (ms); >= 1000/Frequency gives continuous light
opto.amplitude_V       = 5;             % default LED command voltage
% randomized mode: durations (ms), evenly spaced at TrialLength/(n+1); 0 = sham
opto.stimDurations     = [0 2000 5000];
opto.stimIntensities_V = [];            % [] = amplitude_V for all; else one voltage per duration (paired)
opto.randomize         = true;          % shuffle order every block
% windows mode: explicit [onset offset] rows in seconds within the block
opto.windows_s         = [28 28.5];
opto.windows_amplitude_V = [];          % [] = amplitude_V; else one voltage per row

% --- Basler cameras (hardware-triggered by ctr0) ---
basler.fps                     = 100;
basler.Exposure_time           = 9000;  % us; clamped to 90 % of the frame period
basler.trigger_ctr             = 'ctr0';
basler.trigger_initial_delay_s = 0.05;
basler.format                  = 'Mono8';
% Frames stream to disk during acquisition (LoggingMode = 'disk' + DiskLogger), so
% nothing is buffered in RAM. The stream is UNCOMPRESSED Grayscale AVI, not a choice:
% the disk logger hands every frame to a MATLAB VideoWriter on the MATLAB thread, and
% MATLAB's Motion JPEG encoder measured only 109 fps (top, 640x512) / 75 fps (side,
% 800x600) on this PC against the 400 fps two cameras deliver -- the interpreter
% saturated, the live plot and DAQ callbacks stalled and frames were dropped
% (2026-09-15). Grayscale AVI measured 765 / 636 fps and ~160 MB/s total, well inside
% the NVMe. Compression happens after the run with ffmpeg (basler.h264 below).
basler.discover_timeout_s      = 5;     % wait up to this long for the cameras to enumerate after imaqreset
basler.disk_flush_timeout_s    = 30;    % wait up to this long for the disk logger to drain after stop
% The videos stream to this LOCAL folder during the run and are moved into saveFolder
% after the .mat is saved. saveFolder lives on Google Drive File Stream (H:), and
% pushing two Motion JPEG streams through it from the acquisition thread stalled the
% live plot and the whole session (2026-09-15). Keep this on a local NVMe drive;
% '' writes straight into saveFolder.
basler.video_scratch_folder    = 'K:\FlightArena_scratch\';
% After the .mat is saved, each raw AVI in the scratch folder is compressed to H.264
% mp4 with ffmpeg on all cores (~15 s per 18000 frames of 800x600 here), the pending
% rotation is applied in the same pass, the raw file is deleted and the mp4 is moved
% into saveFolder. If ffmpeg fails the raw AVI stays in the scratch folder and
% baslerInfo.<cam>.file points at it.
basler.h264.enable       = true;
basler.h264.ffmpeg       = 'C:\Users\Lylah\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-7.1.1-full_build\bin\ffmpeg.exe';   % '' = the ffmpeg on PATH
basler.h264.crf          = 18;          % libx264 quality: 0 lossless, 18 visually lossless, 23 ffmpeg default
basler.h264.preset       = 'veryfast';  % slower presets give smaller files for a longer encode
basler.h264.pixel_format = 'yuv420p';   % plays everywhere; 'gray' is a little smaller but not every reader opens it
basler.h264.keep_raw     = false;       % true: also leave the uncompressed AVI in video_scratch_folder
% rotate_deg: clockwise rotation the video should end up with (0, 90, 180 or 270).
% Disk logging writes frames straight from the camera, so only 180 deg can be baked in
% on-camera (ReverseX + ReverseY). 90/270 are applied by the ffmpeg pass above; with
% h264.enable = false they stay in baslerInfo.<cam>.rotate_deg_pending for analysis.
basler.top  = struct('enable', true,  'label', 'TopCamera',  'serial', '22703705', ...
                     'gain', 5,  'gamma', 0.5, 'binning', 2, ...
                     'rotate_deg', 90,  'exposure_active_out', false, 'line_inverter', 'False');
basler.side = struct('enable', true,  'label', 'SideCamera', 'serial', '22843477', ...
                     'gain', 12, 'gamma', 0.4, 'binning', 1, ...
                     'rotate_deg', 180, 'exposure_active_out', true,  'line_inverter', 'False');

% --- Phantom KT810 ---
phantom.enable        = false;
phantom.mode          = 'framesync';  % 'framesync' | 'fixed_fps' - need to also set Phantom PCC to "external"
phantom.serial        = 34437;
phantom.fps           = 100;         % framesync: metadata only (external clock); fixed_fps: set on camera
phantom.exposure_us   = 150;
phantom.window_s      = [5 15];      % [capture start, trigger] for framesync / fixed 'end'; [trigger, end] for fixed 'start'
phantom.trigger_at    = 'end';        % fixed_fps only: 'end' (pre-trigger buffer) | 'start' (post-trigger frames)
phantom.pt_frames     = 10;           % fixed_fps + 'end': small post-trigger buffer
phantom.arm_lead_s    = 0.5;          % start capture / arm this long before window_s(1)
phantom.trigAO        = 'ao1';         % -> Phantom "1 Trigger" input
phantom.trigAmp_V     = 5.0;
phantom.trigPulse_s   = 0.050;
phantom.gate_ai       = 'phantom_recording';  % acq.ai_names entry carrying the Phantom "Recording" output ('' = none)
phantom.gate_invert   = false;
phantom.record_each_block = false;
phantom.block_to_record   = 1;
phantom.save_format   = 'tif12';       % 'tif12' (TIFF sequence folder) | 'cine'
phantom.saveRoot      = 'K:\Yichen\spiracle_movies\';   % sequence goes to <saveRoot>\<experiment_name>\
phantom.store_timeout_s    = 180;
phantom.discover_timeout_s = 10;

% --- Plotting ---
plotting.enable      = true;
plotting.show_raw    = true;   % raw panels of the latest chunk: WBF/WBA/LED/Hutchen, EMG, arena X/Y
plotting.wba_gain    = 20;     % delta WBA (V) is multiplied by this to share the delta WBF (Hz) axis
plotting.bin_samples = 100;    % summary traces = block means of this many samples 
plotting.baseline_s  = 5;      % baseline window for delta WBF / WBA (first seconds of the experiment)
plotting.ylim        = [-100 50];
plotting.save_svg    = true;
plotting.save_png    = true;
% When the run is over, open session_overview on the saved .mat: every channel in its
% own panel, linked zoom/pan in time, opto and Phantom windows overlaid. Nothing is
% saved; it is for checking the trial. Dense pulse trains (Basler trigger, F-Sync)
% look like a solid band until you zoom in.
plotting.session_overview = true;
plotting.overview_channels = 'all';   % 'all', or a list like {'WBF', {'WBA_left', 'WBA_right'}, 'basler_trigger'}
%% ===================== END USER SETTINGS ================================

S = struct('saveFolder', saveFolder, 'meta', meta, 'hw', hw, 'acq', acq, 'visual', visual, ...
           'opto', opto, 'basler', basler, 'phantom', phantom, 'plotting', plotting);
end
