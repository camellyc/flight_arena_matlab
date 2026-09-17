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

%% ---- output files --------------------------------------------------------

function testFileNameReplacesCharactersWindowsRefuses(testCase)
% meta.stimulus_regime = '2/5ms' (seen on the rig, 2026-09-16) made the base name a
% path through a folder that did not exist, and the save failed after the session.
ov = simulatedSession(testCase);
ov.meta = struct('stimulus_regime', '2/5ms', 'genotype', 'a:b');
verifyWarning(testCase, @() run_session_unified(ov), 'run_session_unified:fileNameSanitized');
verifyNumElements(testCase, dir(fullfile(ov.saveFolder, '*_a-b_*_2-5ms_*.mat')), 1, ...
    'The file must be saved with the offending characters replaced.');
m = dir(fullfile(ov.saveFolder, '*.mat'));
S = load(fullfile(ov.saveFolder, m(1).name), 'params');
verifyEqual(testCase, S.params.meta.stimulus_regime, '2/5ms', 'params.meta must keep the value as entered.');
end

function testSessionLogAndCodeVersionAreSaved(testCase)
% Every session leaves <base>_log.txt next to the .mat (streamed to the scratch folder
% during the run) and records in params what code produced it.
ov = simulatedSession(testCase);
ov.basler = struct('video_scratch_folder', fullfile(ov.saveFolder, 'scratch'));
out = run_session_unified(ov);
verifyEqual(testCase, exist(out.params.files.log, 'file'), 2, 'The log must end up in saveFolder.');
verifyEmpty(testCase, dir(fullfile(ov.basler.video_scratch_folder, '*_log.txt')), 'The log must leave the scratch folder.');
txt = fileread(out.params.files.log);
verifySubstring(testCase, txt, 'All done', 'The log must hold the command-window output of the run.');
verifySubstring(testCase, txt, '===== run_session_unified =====', 'The log must start with the banner, before any hardware is touched.');
verifyEqual(testCase, get(0, 'Diary'), 'off', 'The diary must be switched off again.');
verifyClass(testCase, out.params.git_commit, 'char');
verifyNotEmpty(testCase, out.params.git_commit);
verifySubstring(testCase, out.params.script_text, 'function out = run_session_unified');
verifySubstring(testCase, out.params.defaults_text, 'USER SETTINGS');
w = whos('-file', out.params.files.mat);
names = {w.name};
verifyFalse(testCase, ismember('variables', names), 'The legacy variables struct is no longer written.');
verifyTrue(testCase, all(ismember({'Data', 'params', 'stimTable', 'phantom', 'baslerInfo'}, names)));
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
