function P = session_presets()
% SESSION_PRESETS  The fixed choices of the meta settings and what each one sets.
%
%   P = session_presets()
%
% One table for run_session_gui (which offers these as dropdown choices and greys
% out the settings they fix) and run_session_unified (which applies them after the
% overrides are merged, so a session started without the window behaves the same).
%
%   P.stimulus_regime   {name, opto.stimDurations (ms)}. Any other name is a
%                       user-defined regime: opto.stimDurations is used as written.
%   P.visual_stim_type  {name, visual.mode, visual.pattern_id}; [] leaves pattern_id
%                       as written. Any other name leaves visual.* as written.
%   P.stimulus_position, P.phantom_position
%                       the listed choices; anything else can be typed in the GUI.
%
% See also RUN_SESSION_UNIFIED, RUN_SESSION_GUI, SESSION_DEFAULTS.

P.stimulus_regime = {'3000msx3', [0 3000 3000]
                     '10000ms',  10000
                     '0-3000ms', [0 100 300 1000 3000]
                     '0-300ms',  [0 10 30 100 300]};
% Arena SD card: 14 = closed-loop stripe, 13 = horizontal stripes + smooth vertical bar.
P.visual_stim_type = {'closed_X',        'closed_loop_stripe',      14
                      'closed_X_open_Y', 'closed_loop_oscillating', 13
                      'none',            'none',                    []};
P.stimulus_position = {'thorax', 'head'};
P.phantom_position  = {'sp1', 'sp2'};
end
