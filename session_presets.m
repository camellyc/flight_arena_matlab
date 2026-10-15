function P = session_presets()
% SESSION_PRESETS  The fixed choices of the meta settings and what each one sets.
%
%   P = session_presets()
%
% One table for run_session_gui (which offers these as dropdown choices and greys
% out the settings they fix) and run_session_unified (which applies them after the
% overrides are merged, so a session started without the window behaves the same).
%
%   P.stimulus_regime   {name, opto.stimDurations (ms), opto.mode}; [] leaves
%                       stimDurations as written, '' leaves opto.mode as written
%                       ('none' = no opto at all). Any other name is a user-defined
%                       regime: opto.* is used as written.
%   P.visual_stim_type  {name, visual.mode, visual.pattern_id}; [] leaves pattern_id
%                       as written. Any other name leaves visual.* as written.
%   P.stimulus_position, P.phantom_position
%                       the listed choices; anything else can be typed in the GUI.
%   P.quick             {button label, {setting path, value; ...}}: one button each
%                       in run_session_gui. Pressing it types the listed values into
%                       the window (the rules above then apply, so a regime of 'none'
%                       sets opto.mode to 'none'); everything stays editable and
%                       nothing is written to session_defaults.m.
%
% See also RUN_SESSION_UNIFIED, RUN_SESSION_GUI, SESSION_DEFAULTS.

P.stimulus_regime = {'3000msx3', [0 3000 3000],         ''
                     '10000ms',  10000,                 ''
                     '0-3000ms', [0 100 300 1000 3000], ''
                     '0-300ms',  [0 10 30 100 300],     ''
                     'none',     [],                    'none'};
% Arena SD card: 14 = closed-loop stripe, 13 = horizontal stripes + smooth vertical bar.
P.visual_stim_type = {'closed_X',        'closed_loop_stripe',      14
                      'closed_X_open_Y', 'closed_loop_oscillating', 13
                      'none',            'none',                    []};
P.stimulus_position = {'thorax', 'head'};
P.phantom_position  = {'sp1', 'sp2'};
P.quick = {'opto_standard',        {'acq.TrialLength',      60
                                    'meta.stimulus_regime',  '10000ms'
                                    'meta.visual_stim_type', 'closed_X'
                                    'opto.mode',             'windows'
                                    'opto.windows_s',        [25 35]
                                    'phantom.enable',        true
                                    'phantom.window_s',      [15 45]}
           'oscillating_standard', {'acq.TrialLength',      62
                                    'meta.stimulus_regime',  'none'
                                    'meta.visual_stim_type', 'closed_X_open_Y'
                                    'phantom.enable',        true
                                    'phantom.window_s',      [20 60]}};
end
