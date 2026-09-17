function tests = test_run_session_unified
%TEST_RUN_SESSION_UNIFIED The settings file and the 'defaults' query, and the session
% teardown, exercised through hardware-free (hw.simulate) sessions written to a
% scratch folder.
tests = functiontests(localfunctions);
end

%% ---- settings file and the 'defaults' query -----------------------------

function testDefaultsQueryReturnsTheSettingsFile(testCase)
% Exactly what session_defaults.m holds. The values run_session_unified derives
% afterwards (duty cycle, trigger time, ...) are not valid overrides, so a GUI built
% from them would send fields the run rejects.
S = run_session_unified('defaults');
verifyEqual(testCase, S, session_defaults(), 'The query must return session_defaults() unchanged.');
verifyClass(testCase, S.saveFolder, 'char');
verifyTrue(testCase, isfield(S.meta, 'flyNumber') && isfield(S.opto, 'mode') && isfield(S.basler.top, 'serial'), ...
    'The settings sections must come back as nested structs.');
verifyFalse(testCase, isfield(S.opto, 'duty_cycle'), 'Derived opto settings must not be returned.');
verifyFalse(testCase, isfield(S.phantom, 'trigger_time_s'), 'Derived Phantom settings must not be returned.');
end

function testDefaultsQueryLeavesOpenFiguresAlone(testCase)
% The query must return before the close all / clc a real session starts with, which
% would take the caller's figures (and the GUI) with it.
f = figure('Visible', 'off');
testCase.addTeardown(@() delete(f(isvalid(f))));
run_session_unified('defaults');
verifyTrue(testCase, isvalid(f), 'A defaults query must not close open figures.');
end

function testSettingsLiveOnlyInTheSettingsFile(testCase)
% run_session_gui rewrites the block between the USER SETTINGS markers of
% session_defaults.m. A second block in the runner would be a second source of truth
% that the window never sees.
marker = '^\s*%%\s*=+\s*USER SETTINGS';
verifyNotEmpty(testCase, regexp(fileread(which('session_defaults')), marker, 'once', 'lineanchors'), ...
    'session_defaults.m must carry the USER SETTINGS marker the GUI looks for.');
verifyEmpty(testCase, regexp(fileread(which('run_session_unified')), marker, 'once', 'lineanchors'), ...
    'run_session_unified.m must not carry a settings block of its own.');
end

%% ---- teardown ----------------------------------------------------------

function testTeardownRunsCleanlyAfterANormalSession(testCase)
% The teardown used to run after MATLAB had already cleared the variables it reads,
% so it failed part-way -- skipping the DAQ, camera and Phantom release -- on every exit.
ov = simulatedSession(testCase);
verifyWarningFree(testCase, @() run_session_unified(ov));
end

function testTeardownRunsCleanlyAfterAFailedSession(testCase)
% The error (and Ctrl+C) path, which is the one that must return the LED to 0 V.
% Decreasing plot limits make the live plot fail after the teardown is armed.
ov = simulatedSession(testCase);
ov.plotting.enable = true;
ov.plotting.ylim   = [50 -100];
testCase.addTeardown(@() close('all'));
lastwarn('', '');
verifyError(testCase, @() run_session_unified(ov), ?MException);
[msg, id] = lastwarn;
verifyEmpty(testCase, msg, sprintf('The session left a warning (%s): %s', id, msg));
end

%% ---- helpers -------------------------------------------------------------

function ov = simulatedSession(testCase)
% Overrides for a 4 s hardware-free session into a scratch folder.
d = tempname;
mkdir(d);
testCase.addTeardown(@() rmdir(d, 's'));
ov = struct('saveFolder', d, 'hw', struct('simulate', true), 'acq', struct('TrialLength', 4), ...
            'opto', struct('mode', 'none'), 'plotting', struct('enable', false));
end
