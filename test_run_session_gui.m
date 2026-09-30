function tests = test_run_session_gui
%TEST_RUN_SESSION_GUI Tests for run_session_gui. They drive the real window
% headlessly; every run is hw.simulate into a scratch folder, so no hardware is
% touched. Expected values come from session_defaults.m itself, so editing a default
% does not break a test. The run_session_unified('defaults') query the window is built
% on is tested in test_run_session_unified.
tests = functiontests(localfunctions);
end

%% ---- fixtures ------------------------------------------------------------

function setup(~)
closeGui();   % every test starts without a settings window
end

function teardown(~)
closeGui();
end

%% ---- window: built from the file ---------------------------------------

function testEverySettingHasOneControl(testCase)
% The window is generated from the settings struct: every setting in session_defaults.m
% that is not deliberately hidden must be editable, none dropped or doubled, with no
% GUI edit when one is added. phantom.window_s is the one setting shown as two boxes.
fig = run_session_gui();
hidden = getappdata(fig, 'hiddenSettings');
paths = leafPaths(run_session_unified('defaults'));
for i = 1:numel(paths)
    if isHidden(paths{i}, hidden)
        verifyEmpty(testCase, findall(fig, 'Tag', paths{i}), [paths{i} ' is hidden and must not be shown.']);
    elseif strcmp(paths{i}, 'phantom.window_s')
        verifyNumElements(testCase, findall(fig, 'Tag', 'phantom.window_s:start'), 1);
        verifyNumElements(testCase, findall(fig, 'Tag', 'phantom.window_s:end'), 1);
    else
        verifyNumElements(testCase, findall(fig, 'Tag', paths{i}), 1, paths{i});
    end
end
end

function testFieldsShowTheFileDefaults(testCase)
S = run_session_unified('defaults');
fig = run_session_gui();
verifyEqual(testCase, val(fig, 'saveFolder'), S.saveFolder);
verifyEqual(testCase, val(fig, 'meta.experiment_name'), S.meta.experiment_name);
verifyEqual(testCase, val(fig, 'hw.simulate'), S.hw.simulate);
verifyEqual(testCase, str2num(val(fig, 'opto.stimDurations')), S.opto.stimDurations); %#ok<ST2NM>
verifyEqual(testCase, str2num(val(fig, 'basler.side.gain')), S.basler.side.gain);     %#ok<ST2NM>
verifyEqual(testCase, str2num(val(fig, 'phantom.window_s:start')), S.phantom.window_s(1)); %#ok<ST2NM>
verifyEqual(testCase, str2num(val(fig, 'phantom.window_s:end')), S.phantom.window_s(2));   %#ok<ST2NM>
end

function testControlTypeFollowsTheDefault(testCase)
fig = run_session_gui();
verifyClass(testCase, ctrl(fig, 'hw.simulate'),       'matlab.ui.control.CheckBox');
verifyClass(testCase, ctrl(fig, 'basler.top.enable'), 'matlab.ui.control.CheckBox');
verifyClass(testCase, ctrl(fig, 'acq.TrialLength'),   'matlab.ui.control.EditField');
verifyClass(testCase, ctrl(fig, 'meta.genotype'),     'matlab.ui.control.EditField');
end

function testModeSettingsOfferEveryValidMode(testCase)
% The values run_session_unified accepts; a dropdown missing one makes it unreachable.
S = run_session_unified('defaults');
fig = run_session_gui();
modes = struct('path', {'visual.mode', 'opto.mode', 'phantom.mode', 'phantom.trigger_at', ...
                        'phantom.save_format', 'basler.top.line_inverter'}, ...
               'valid', {{'closed_loop_stripe', 'closed_loop_oscillating', 'none'}, ...
                         {'randomized', 'windows', 'both', 'none'}, {'framesync', 'fixed_fps'}, ...
                         {'end', 'start'}, {'tif12', 'cine'}, {'False', 'True'}});
for m = modes
    dd = ctrl(fig, m.path);
    verifyClass(testCase, dd, 'matlab.ui.control.DropDown', m.path);
    verifyTrue(testCase, all(ismember(m.valid, dd.Items)), [m.path ' is missing a valid value.']);
    verifyEqual(testCase, dd.Value, defaultAt(S, m.path), [m.path ' must start at the file default.']);
end
end

function testTooltipIsTheSettingsLineComment(testCase)
% Hovering a field shows the comment written next to it in session_defaults.m.
fig = run_session_gui();
c = ctrl(fig, 'hw.simulate');
tip = char(c.Tooltip);
verifyNotEmpty(testCase, tip);
verifyTrue(testCase, endsWith(strtrim(settingsLine('hw.simulate')), tip), 'The tooltip must be the end-of-line comment.');
verifyFalse(testCase, startsWith(tip, '%') || contains(tip, 'hw.simulate'), 'Only the comment text, not the code.');
end

function testSettingWithoutACommentHasNoTooltip(testCase)
% It must not borrow the comment of a neighbouring line.
assumeFalse(testCase, contains(settingsLine('meta.flyNumber'), '%'), 'meta.flyNumber has gained a comment.');
fig = run_session_gui();
c = ctrl(fig, 'meta.flyNumber');
verifyEmpty(testCase, char(c.Tooltip));
end

function testSecondCallReusesTheOpenWindow(testCase)
% Two windows could start two sessions on one rig; a second call brings back the first.
fig1 = run_session_gui();
fig2 = run_session_gui();
verifySameHandle(testCase, fig2, fig1);
verifyNumElements(testCase, findall(groot, 'Type', 'figure', 'Tag', 'run_session_gui'), 1);
end

function testEveryRowIsVisibleWhenTabsCannotScroll(testCase)
% Before grid layouts could scroll (R2019a, for one), a row below the bottom of its
% tab can never be reached, so there every tab's rows must fit inside the tab.
% Skipped where the tabs scroll; it does its work on the older MATLAB on the rig.
fig = run_session_gui();
% Sizes arrive asynchronously: until the window has been laid out, the tab group still
% reports its creation default (250 x 210 px). Laid out = stretched across the window.
tg = findall(fig, 'Type', 'uitabgroup');
t0 = tic;
while tg.Position(3) < fig.Position(3) / 2 && toc(t0) < 10
    drawnow; pause(0.1);
end
assertGreaterThanOrEqual(testCase, tg.Position(3), fig.Position(3) / 2, 'The window was never laid out.');
avail = tg.SelectedTab.Position(4);   % every tab of the group has the same content area
for t = tg.Children'
    g = t.Children(1);
    assumeFalse(testCase, isprop(g, 'Scrollable') && strcmp(char(g.Scrollable), 'on'), ...
        'The settings tabs scroll on this release.');
    need = sum([g.RowHeight{:}]) + g.RowSpacing * (numel(g.RowHeight) - 1) + g.Padding(2) + g.Padding(4);
    verifyLessThanOrEqual(testCase, need, avail, ...
        sprintf('Tab "%s" needs %g px for its rows but is %g px tall.', t.Title, need, avail));
end
end

function testSettingsUnderAHeadingBelongToIt(testCase)
% A heading (basler.top, basler.h264, ...) must be followed only by that struct's own
% settings: a plain setting listed after it would read as one of them. Every nested
% struct gets exactly one heading, so the check cannot pass by finding none.
fig = run_session_gui();
nHeadings = 0;
for t = findall(fig, 'Type', 'uitab')'
    kids = t.Children(1).Children;
    [~, order] = sort(arrayfun(@(k) k.Layout.Row, kids));
    under = '';   % path of the heading in force; '' above the first one
    for k = kids(order)'
        if startsWith(k.Tag, 'heading:')
            under = extractAfter(k.Tag, 'heading:');
            nHeadings = nHeadings + 1;
        elseif ~contains(k.Tag, ':') && ~isempty(under)
            verifyTrue(testCase, startsWith(k.Tag, [under '.']), ...
                sprintf('%s is listed under the %s heading.', k.Tag, under));
        end
    end
end
verifyEqual(testCase, nHeadings, nestedCount(run_session_unified('defaults'), 0, '', getappdata(fig, 'hiddenSettings')), ...
    'Every nested settings struct that is shown must have exactly one heading.');
end

%% ---- editing: changed and invalid fields -------------------------------

function testEditedSettingsAreMarkedChanged(testCase)
% Every kind of control: text, checkbox, dropdown, number.
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'meta.flyNumber', [S.meta.flyNumber 'x']);
setField(fig, 'hw.simulate', ~S.hw.simulate);
setField(fig, 'opto.mode', otherItem(ctrl(fig, 'opto.mode')));
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
for p = {'meta.flyNumber', 'hw.simulate', 'opto.mode', 'acq.TrialLength'}
    verifyTrue(testCase, isMarkedChanged(fig, p{1}), [p{1} ' must be marked as changed.']);
end
verifyFalse(testCase, isMarkedChanged(fig, 'meta.genotype'), 'An untouched setting must not be marked.');
end

function testSettingEditedBackToItsValueIsUnmarked(testCase)
% "Changed" means "differs from the file", compared as values: 90 retyped as 90.0 is not a change.
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
setField(fig, 'acq.TrialLength', sprintf('%.1f', S.acq.TrialLength));
verifyFalse(testCase, isMarkedChanged(fig, 'acq.TrialLength'));
end

function testUnreadableNumberIsFlagged(testCase)
% 'pi' is valid MATLAB that yields a number: it must still be refused, because an
% entry is only ever read as numeric syntax, never run as code.
fig = run_session_gui();
freeStimDurations(fig);
for bad = {'3000 abc', '[0 3000', 'disp(1)', 'pi'}
    setField(fig, 'opto.stimDurations', bad{1});
    verifyTrue(testCase, isFlagged(fig, 'opto.stimDurations'), sprintf('"%s" must be flagged.', bad{1}));
end
setField(fig, 'opto.stimDurations', '[0 3000]');
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'), 'Fixing the entry must clear the flag.');
end

function testSingleNumberSettingRejectsAListOrNothing(testCase)
% acq.TrialLength is one number in the file; '[4 5]' or an empty box is a typo, not a setting.
fig = run_session_gui();
for bad = {'[4 5]', ''}
    setField(fig, 'acq.TrialLength', bad{1});
    verifyTrue(testCase, isFlagged(fig, 'acq.TrialLength'), sprintf('"%s" must be flagged.', bad{1}));
end
end

function testListSettingMayBeEmptied(testCase)
S = run_session_unified('defaults');
assumeFalse(testCase, isscalar(S.opto.stimDurations), 'opto.stimDurations is no longer a list.');
fig = run_session_gui();
freeStimDurations(fig);
setField(fig, 'opto.stimDurations', '');
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'));
end

function testResetRestoresTheFileDefaults(testCase)
S = run_session_unified('defaults');
fig = run_session_gui();
setField(fig, 'meta.flyNumber', [S.meta.flyNumber 'x']);
freeStimDurations(fig);
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'resetButton');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), S.meta.flyNumber);
verifyEqual(testCase, str2num(val(fig, 'opto.stimDurations')), S.opto.stimDurations); %#ok<ST2NM>
verifyFalse(testCase, isMarkedChanged(fig, 'meta.flyNumber'));
verifyFalse(testCase, isFlagged(fig, 'opto.stimDurations'));
end

%% ---- layout and greying rules --------------------------------------------

function testTabsFollowTheLabOrder(testCase)
% Meta, Opto, Phantom, Basler, Visual, Hardware, Plotting. Acquisition has nothing
% left to show (TrialLength is on Meta, the rest hidden), so it has no tab.
fig = run_session_gui();
tg = findall(fig, 'Type', 'uitabgroup');
titles = regexprep({tg.Children.Title}, ' \d+$', '');   % "Basler 2" where tabs cannot scroll
titles = titles([true, ~strcmp(titles(2:end), titles(1:end - 1))]);
verifyEqual(testCase, titles, {'Meta', 'Opto', 'Phantom', 'Basler', 'Visual', 'Hardware', 'Plotting'});
end

function testTrialLengthIsShownOnTheMetaTab(testCase)
fig = run_session_gui();
tab = ancestor(ctrl(fig, 'acq.TrialLength'), 'uitab');
verifyEqual(testCase, tab.Title, 'Meta');
end

function testHiddenSettingsKeepTheFileValue(testCase)
S = run_session_unified('defaults');
fig = simulatedGui(testCase, 4);
verifyEmpty(testCase, findall(fig, 'Tag', 'acq.ai_names'));
verifyEmpty(testCase, findall(fig, 'Tag', 'visual.rest.pattern_id'));
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.acq.ai_names, S.acq.ai_names);
verifyEqual(testCase, params.visual.rest, S.visual.rest);
end

function testAutoTrialNumberGreysOutTrialNum(testCase)
fig = run_session_gui();
setField(fig, 'meta.auto_trial_number', true);
verifyFalse(testCase, isEnabled(fig, 'meta.trialNum'));
setField(fig, 'meta.auto_trial_number', false);
verifyTrue(testCase, isEnabled(fig, 'meta.trialNum'));
end

function testPresetRegimeFixesStimDurations(testCase)
P = session_presets();
fig = run_session_gui();
setField(fig, 'opto.mode', 'randomized');
for k = 1:size(P.stimulus_regime, 1)
    setField(fig, 'meta.stimulus_regime', P.stimulus_regime{k, 1});
    verifyEqual(testCase, str2num(val(fig, 'opto.stimDurations')), P.stimulus_regime{k, 2}, P.stimulus_regime{k, 1}); %#ok<ST2NM>
    verifyFalse(testCase, isEnabled(fig, 'opto.stimDurations'), P.stimulus_regime{k, 1});
    verifyFalse(testCase, isEnabled(fig, 'meta.stimulus_regime:other'), 'The name box is for "user defined" only.');
end
freeStimDurations(fig);
verifyTrue(testCase, isEnabled(fig, 'opto.stimDurations'));
verifyTrue(testCase, isEnabled(fig, 'meta.stimulus_regime:other'));
end

function testUserDefinedRegimeIsNamedAndSent(testCase)
fig = simulatedGui(testCase, 4);
freeStimDurations(fig);
setField(fig, 'meta.stimulus_regime:other', 'myRegime');
setField(fig, 'opto.stimDurations', '[0 500]');
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.meta.stimulus_regime, 'myRegime');
verifyEqual(testCase, params.opto.stimDurations, [0 500]);
verifySubstring(testCase, params.baseFileName, '_myRegime');
end

function testVisualStimTypeFixesModeAndPattern(testCase)
P = session_presets();
fig = run_session_gui();
for k = 1:size(P.visual_stim_type, 1)
    setField(fig, 'meta.visual_stim_type', P.visual_stim_type{k, 1});
    verifyEqual(testCase, val(fig, 'visual.mode'), P.visual_stim_type{k, 2});
    if ~isempty(P.visual_stim_type{k, 3})
        verifyEqual(testCase, str2double(val(fig, 'visual.pattern_id')), P.visual_stim_type{k, 3});
    end
    verifyFalse(testCase, isEnabled(fig, 'visual.mode'));
    verifyFalse(testCase, isEnabled(fig, 'visual.pattern_id'));
end
setField(fig, 'meta.visual_stim_type', 'closed_X');
verifyTrue(testCase, isEnabled(fig, 'visual.x_pos'));
verifyFalse(testCase, isEnabled(fig, 'visual.y_gain'), 'Y gain is for the oscillating mode only.');
setField(fig, 'meta.visual_stim_type', 'closed_X_open_Y');
verifyFalse(testCase, isEnabled(fig, 'visual.x_pos'));
verifyTrue(testCase, isEnabled(fig, 'visual.y_gain'));
end

function testOptoModeGreysOutUnusedFields(testCase)
fig = run_session_gui();
freeStimDurations(fig);
rand = {'opto.stimDurations', 'opto.randomize'};
win  = {'opto.windows_s', 'opto.windows_amplitude_V'};
cases = {'randomized', true, false; 'windows', false, true; 'both', true, true; 'none', false, false};
for k = 1:size(cases, 1)
    setField(fig, 'opto.mode', cases{k, 1});
    for p = rand, verifyEqual(testCase, isEnabled(fig, p{1}), cases{k, 2}, [cases{k, 1} ': ' p{1}]); end
    for p = win,  verifyEqual(testCase, isEnabled(fig, p{1}), cases{k, 3}, [cases{k, 1} ': ' p{1}]); end
end
verifyFalse(testCase, isEnabled(fig, 'opto.amplitude_V'), 'Nothing but the mode is used with opto off.');
verifyTrue(testCase, isEnabled(fig, 'opto.mode'));
end

function testPhantomWindowIsTwoBoxes(testCase)
fig = simulatedGui(testCase, 4);
setField(fig, 'phantom.window_s:start', '1');
setField(fig, 'phantom.window_s:end', '3');
verifyTrue(testCase, isMarkedChanged(fig, 'phantom.window_s:start'));
setField(fig, 'phantom.window_s:end', 'x');
verifyTrue(testCase, isFlagged(fig, 'phantom.window_s:end'));
verifyFalse(testCase, isFlagged(fig, 'phantom.window_s:start'));
setField(fig, 'phantom.window_s:end', '3');
b = ctrl(fig, 'runButton'); %#ok<NASGU> -- used inside the evalc string
txt = evalc('b.ButtonPushedFcn(b, [])');
verifySubstring(testCase, txt, 'phantom.window_s = [1 3]');
verifyEqual(testCase, getfield(savedVar(testCase, 'phantom'), 'window_s'), [1 3]); %#ok<GFLD>
end

function testPhantomFieldsGreyOutWhenUnused(testCase)
fig = run_session_gui();
setField(fig, 'phantom.enable', true);
setField(fig, 'phantom.mode', 'framesync');
verifyFalse(testCase, isEnabled(fig, 'phantom.trigger_at'));
verifyTrue(testCase, isEnabled(fig, 'phantom.window_s:start'));
setField(fig, 'phantom.mode', 'fixed_fps');
verifyTrue(testCase, isEnabled(fig, 'phantom.trigger_at'));
setField(fig, 'phantom.enable', false);
verifyFalse(testCase, isEnabled(fig, 'phantom.window_s:end'));
verifyFalse(testCase, isEnabled(fig, 'phantom.mode'));
verifyTrue(testCase, isEnabled(fig, 'phantom.enable'));
end

function testCarbonDioxideIsATickBox(testCase)
fig = simulatedGui(testCase, 4);
verifyClass(testCase, ctrl(fig, 'meta.carbon_dioxide'), 'matlab.ui.control.CheckBox');
setField(fig, 'meta.carbon_dioxide', true);
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.meta.carbon_dioxide, 'ON');
end

function testPositionOtherTakesTheTypedValue(testCase)
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.stimulus_position', 'head');
verifyFalse(testCase, isEnabled(fig, 'meta.stimulus_position:other'));
setField(fig, 'meta.stimulus_position', 'other...');
setField(fig, 'meta.stimulus_position:other', 'leg');
setField(fig, 'meta.phantom_position', 'other...');
setField(fig, 'meta.phantom_position:other', '');
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.meta.stimulus_position, 'leg');
verifyEmpty(testCase, params.meta.phantom_position);
end

function testGreyingIsRestoredAfterARun(testCase)
% The lock during a run switches everything off; afterwards the rules apply again.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.auto_trial_number', true);
click(fig, 'runButton');
verifyFalse(testCase, isEnabled(fig, 'meta.trialNum'));
verifyTrue(testCase, isEnabled(fig, 'meta.flyNumber'));
end

%% ---- Run ---------------------------------------------------------------

function testRunRefusesInvalidSettings(testCase)
fig = simulatedGui(testCase, 4);
freeStimDurations(fig);
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'runButton');
verifyEmpty(testCase, dir(fullfile(testCase.TestData.dir, '*.mat')), 'No session may start.');
verifySubstring(testCase, statusText(fig), 'opto.stimDurations', 'The status must name the bad setting.');
end

function testRunSendsTheEditsToTheSession(testCase)
% Text, number, list, checkbox: each must reach the run with the type of its default.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
freeStimDurations(fig);
setField(fig, 'opto.stimDurations', '[500 1000]');
click(fig, 'runButton');
params = savedParams(testCase);
verifyEqual(testCase, params.meta.flyNumber, '7');
verifyEqual(testCase, params.opto.stimDurations, [500 1000]);
verifyEqual(testCase, params.acq.TrialLength, 4);
verifyEqual(testCase, params.hw.simulate, true);
verifySubstring(testCase, params.baseFileName, 'Fly7');
end

function testRunLogsOnlyTheChangedSettings(testCase)
% The command window records what this session changed from the file, and nothing else.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
b = ctrl(fig, 'runButton'); %#ok<NASGU> -- used inside the evalc string
txt = evalc('b.ButtonPushedFcn(b, [])');
verifySubstring(testCase, txt, 'meta.flyNumber = ''7''');
verifySubstring(testCase, txt, 'acq.TrialLength = 4');
verifyFalse(testCase, contains(txt, 'meta.genotype'), 'An unchanged setting must not be listed.');
end

function testRunResultIsPutInTheBaseWorkspace(testCase)
% The result of *this* run: an out left by an earlier session is cleared first, and
% the one found afterwards must belong to this test's own (unique) save folder.
fig = simulatedGui(testCase, 4);
evalin('base', 'clear out');
testCase.addTeardown(@() evalin('base', 'clear out'));
click(fig, 'runButton');
out = evalin('base', 'out');
verifyEqual(testCase, out.params.saveFolder, testCase.TestData.dir);
end

function testWindowStaysOpenWithTheValuesAfterARun(testCase)
% Ready for the next trial: same values, still marked, Run available again.
fig = simulatedGui(testCase, 4);
setField(fig, 'meta.flyNumber', '7');
click(fig, 'runButton');
verifyTrue(testCase, isvalid(fig), 'The session''s close all must not close the window.');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), '7');
verifyTrue(testCase, isMarkedChanged(fig, 'meta.flyNumber'));
b = ctrl(fig, 'runButton');
verifyEqual(testCase, char(b.Enable), 'on');
end

function testWindowIsLockedWhileRunning(testCase)
% Mid-run, Run must not start a second session and the window must refuse to close.
% A timer looks at the window while the session is running (it fires in the run's pause).
fig = simulatedGui(testCase, 30);   % ~3 s of wall time at hw.sim_speed 10
seen = containers.Map();
t = timer('StartDelay', 1, 'TimerFcn', @(~, ~) probeLock(fig, seen));
testCase.addTeardown(@() delete(t));
start(t);
click(fig, 'runButton');
assertTrue(testCase, isKey(seen, 'openAfterClose'), 'The probe never ran during the session.');
verifyEqual(testCase, seen('runEnabled'), 'off', 'Run must be disabled while a session runs.');
verifyEqual(testCase, seen('fieldEnabled'), 'off', 'Settings must be locked while a session runs.');
verifyTrue(testCase, seen('openAfterClose'), 'Closing the window must be refused while a session runs.');
end

function testRunErrorIsReportedAndTheWindowRecovers(testCase)
% A window past the end of the block is rejected by run_session_unified's own checks.
fig = simulatedGui(testCase, 4);
setField(fig, 'opto.mode', 'windows');
setField(fig, 'opto.windows_s', '[10 11]');
click(fig, 'runButton');
% The message the session itself gives for these settings, obtained without the window.
ov = struct('saveFolder', testCase.TestData.dir, 'hw', struct('simulate', true), ...
            'acq', struct('TrialLength', 4), 'opto', struct('mode', 'windows', 'windows_s', [10 11]));
msg = '';
try
    run_session_unified(ov);
catch ME
    msg = ME.message;
end
assertNotEmpty(testCase, msg, 'These settings no longer make run_session_unified fail.');
verifySubstring(testCase, statusText(fig), msg);
verifyEmpty(testCase, dir(fullfile(testCase.TestData.dir, '*.mat')));
b = ctrl(fig, 'runButton');
verifyEqual(testCase, char(b.Enable), 'on', 'Run must be available again after a failed session.');
end

%% ---- Save as file defaults ---------------------------------------------
% These tests rewrite a private copy of session_defaults.m placed ahead of the real
% one on the path, so the real file is never touched.

function testSaveDefaultsWritesTheValuesIntoTheFile(testCase)
% Every kind of control, plus a setting inside a struct(...) call (basler.side.gain):
% the file re-read gives the new values, the window shows them unmarked, and Reset
% now returns to them.
file = tempSettingsFile(testCase);
S = run_session_unified('defaults');
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
freeStimDurations(fig);
want = {'meta.flyNumber',     [S.meta.flyNumber '7']
        'hw.simulate',        ~S.hw.simulate
        'opto.mode',          otherItem(ctrl(fig, 'opto.mode'))
        'acq.TrialLength',    S.acq.TrialLength + 1
        'opto.stimDurations', [0 500 750]
        'basler.side.gain',   S.basler.side.gain + 1
        'saveFolder',         [S.saveFolder 'newdefault\']};
for k = 1:size(want, 1)
    v = want{k, 2};
    if isnumeric(v), v = mat2str(v); end
    setField(fig, want{k, 1}, v);
end
click(fig, 'saveDefaultsButton');
verifySubstring(testCase, statusText(fig), 'Saved', 'The status must report the save.');
S2 = run_session_unified('defaults');
for k = 1:size(want, 1)
    verifyEqual(testCase, defaultAt(S2, want{k, 1}), want{k, 2}, [want{k, 1} ' must be the new file default.']);
    verifyFalse(testCase, isMarkedChanged(fig, want{k, 1}), [want{k, 1} ' must no longer be marked as changed.']);
end
click(fig, 'resetButton');
verifyEqual(testCase, val(fig, 'meta.flyNumber'), want{1, 2}, 'Reset must return to the new defaults.');
verifySubstring(testCase, fileread(file), ['acq.TrialLength     = ' mat2str(want{4, 2}) ';'], ...
    'The value must be written in place, keeping the alignment of the = sign.');
verifyEqual(testCase, fileread(testCase.TestData.realFile), testCase.TestData.realText, ...
    'The real session_defaults.m must not be touched.');
end

function testSaveDefaultsKeepsTheRestOfTheFile(testCase)
% Only the value changes: the comment next to the setting, its alignment and every
% other line survive, and a struct(...) statement keeps its shape.
file = tempSettingsFile(testCase);
before = splitlines(fileread(file));
S = run_session_unified('defaults');
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
setField(fig, 'acq.TrialLength', num2str(S.acq.TrialLength + 1));
setField(fig, 'basler.side.gain', num2str(S.basler.side.gain + 1));
click(fig, 'saveDefaultsButton');
after = splitlines(fileread(file));
assertEqual(testCase, numel(after), numel(before), 'The number of lines must not change.');
diffLines = find(~strcmp(before, after));
verifyNumElements(testCase, diffLines, 2, 'Exactly the two assignments may differ.');
for i = diffLines'
    verifyEqual(testCase, regexp(after{i}, '%.*$', 'match', 'once'), regexp(before{i}, '%.*$', 'match', 'once'), ...
        sprintf('Line %d must keep its comment.', i));
    verifyEqual(testCase, find(after{i} == '=', 1), find(before{i} == '=', 1), ...
        sprintf('Line %d must keep the column of its = sign.', i));
end
verifyTrue(testCase, any(contains(after(diffLines), 'acq.TrialLength')), 'The acq.TrialLength line must be the one rewritten.');
verifyTrue(testCase, any(contains(after(diffLines), ['''gain'', ' num2str(S.basler.side.gain + 1)])), ...
    'The gain value inside the basler.side struct(...) call must be the one rewritten.');
end

function testSaveDefaultsRefusesInvalidEntries(testCase)
file = tempSettingsFile(testCase);
before = fileread(file);
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
setField(fig, 'meta.flyNumber', '9');
freeStimDurations(fig);
setField(fig, 'opto.stimDurations', 'abc');
click(fig, 'saveDefaultsButton');
verifyEqual(testCase, fileread(file), before, 'Nothing may be written while an entry is invalid.');
verifySubstring(testCase, statusText(fig), 'opto.stimDurations', 'The status must name the bad setting.');
verifyTrue(testCase, isMarkedChanged(fig, 'meta.flyNumber'), 'The pending edit must stay in the window.');
end

function testSaveDefaultsWithNothingChangedLeavesTheFileAlone(testCase)
file = tempSettingsFile(testCase);
before = fileread(file);
fig = run_session_gui();
setappdata(fig, 'skipConfirm', true);
click(fig, 'saveDefaultsButton');
verifyEqual(testCase, fileread(file), before);
verifySubstring(testCase, statusText(fig), 'nothing to save');
end

%% ---- helpers -------------------------------------------------------------

function file = tempSettingsFile(testCase)
% A private copy of session_defaults.m that shadows the real one, so that saving
% defaults rewrites the copy. MATLAB resolves the current folder before the path, so
% the copy is made the current folder (the real code folder, which also holds
% run_session_unified.m, stays reachable on the path). The real file's path and text
% are kept in TestData so a test can check it was left alone.
realFile = which('session_defaults');
realDir  = fileparts(realFile);
testCase.TestData.realFile = realFile;
testCase.TestData.realText = fileread(realFile);
onPath = contains([pathsep path pathsep], [pathsep realDir pathsep]);
if ~onPath, addpath(realDir); end
d = tempname;
mkdir(d);
file = fullfile(d, 'session_defaults.m');
copyfile(realFile, file);
fileattrib(file, '+w');
oldDir = cd(d);
clear('session_defaults');
testCase.addTeardown(@() removeTempSettingsFile(d, oldDir, realDir, ~onPath));
assert(strcmp(which('session_defaults'), file), 'The temporary copy does not shadow the real file.');
end

function removeTempSettingsFile(d, oldDir, realDir, dropPath)
cd(oldDir);
if dropPath, rmpath(realDir); end
clear('session_defaults');
rmdir(d, 's');
end

function fig = simulatedGui(testCase, trialLength)
% The window set up for a fast, hardware-free session into a scratch folder:
% trialLength s of synthetic data at 10x real time, one block, no opto, no live plot.
testCase.TestData.dir = tempname;
mkdir(testCase.TestData.dir);
testCase.addTeardown(@() rmdir(testCase.TestData.dir, 's'));
fig = run_session_gui();
setField(fig, 'saveFolder', testCase.TestData.dir);
setField(fig, 'hw.simulate', true);
setField(fig, 'hw.sim_speed', '10');
setField(fig, 'acq.TrialLength', num2str(trialLength));
setField(fig, 'opto.mode', 'none');
setField(fig, 'plotting.enable', false);
setField(fig, 'meta.auto_trial_number', false);
end

function params = savedParams(testCase)
f = dir(fullfile(testCase.TestData.dir, '*.mat'));
assert(isscalar(f), 'Expected one session file in the scratch folder, found %d.', numel(f));
L = load(fullfile(f.folder, f.name), 'params');
params = L.params;
end

function t = statusText(fig)
s = ctrl(fig, 'statusLabel');
t = char(strjoin(cellstr(s.Text), ' '));
end

function probeLock(fig, seen)
b = findall(fig, 'Tag', 'runButton');
c = findall(fig, 'Tag', 'meta.flyNumber');
seen('runEnabled')   = char(b.Enable);
seen('fieldEnabled') = char(c.Enable);
close(fig);
seen('openAfterClose') = isvalid(fig); %#ok<NASGU> -- seen is a handle (containers.Map)
end

function setField(fig, path, value)
% Enter a value the way a user would: set the control, then fire its callback.
c = ctrl(fig, path);
c.Value = value;
if ~isempty(c.ValueChangedFcn), c.ValueChangedFcn(c, []); end
end

function click(fig, tag)
b = ctrl(fig, tag);
b.ButtonPushedFcn(b, []);
end

function tf = isMarkedChanged(fig, path)
lbl = ctrl(fig, ['label:' path]);
tf = strcmp(char(lbl.FontWeight), 'bold');
end

function tf = isFlagged(fig, path)
% Flagged = coloured differently from a field that is always valid (free text).
c  = ctrl(fig, path);
ok = ctrl(fig, 'meta.genotype');
tf = ~isequal(c.BackgroundColor, ok.BackgroundColor);
end

function v = otherItem(dd)
others = dd.Items(~strcmp(dd.Items, dd.Value));
v = others{1};
end

function n = nestedCount(s, depth, prefix, hidden)
% Structs below the section level (basler.top, basler.h264, ...) that are not hidden:
% the ones that get a heading.
n = 0;
f = fieldnames(s);
for i = 1:numel(f)
    if isempty(prefix), p = f{i}; else, p = [prefix '.' f{i}]; end
    if isstruct(s.(f{i})) && ~isHidden(p, hidden)
        n = n + (depth >= 1) + nestedCount(s.(f{i}), depth + 1, p, hidden);
    end
end
end

function tf = isHidden(path, hidden)
tf = any(strcmp(path, hidden)) || any(startsWith(path, strcat(hidden, '.')));
end

function freeStimDurations(fig)
% A preset stimulus regime fixes opto.stimDurations; "user defined" frees it.
dd = ctrl(fig, 'meta.stimulus_regime');
setField(fig, 'meta.stimulus_regime', dd.Items{end});
end

function tf = isEnabled(fig, path)
c = ctrl(fig, path);
tf = strcmp(char(c.Enable), 'on');
end

function v = savedVar(testCase, name)
f = dir(fullfile(testCase.TestData.dir, '*.mat'));
assert(isscalar(f), 'Expected one session file in the scratch folder, found %d.', numel(f));
L = load(fullfile(f.folder, f.name), name);
v = L.(name);
end

function closeGui()
% delete, not close: close is refused while a session runs.
delete(findall(groot, 'Type', 'figure', 'Tag', 'run_session_gui'));
end

function c = ctrl(fig, path)
c = findall(fig, 'Tag', path);
assert(isscalar(c), 'Expected one control tagged "%s", found %d.', path, numel(c));
end

function v = val(fig, path)
c = ctrl(fig, path);
v = c.Value;
end

function v = defaultAt(S, path)
parts = strsplit(path, '.');
v = getfield(S, parts{:});
end

function p = leafPaths(s, prefix)
% Dotted path of every non-struct setting, e.g. 'basler.top.gain'.
if nargin < 2, prefix = ''; end
p = {};
f = fieldnames(s);
for i = 1:numel(f)
    if isempty(prefix), here = f{i}; else, here = [prefix '.' f{i}]; end
    if isstruct(s.(f{i}))
        p = [p, leafPaths(s.(f{i}), here)]; %#ok<AGROW>
    else
        p{end + 1} = here; %#ok<AGROW>
    end
end
end

function line = settingsLine(path)
% The line of session_defaults.m that assigns this setting.
src = splitlines(fileread(which('session_defaults')));
hit = src(~cellfun(@isempty, regexp(src, ['^\s*' regexptranslate('escape', path) '\s*='], 'once')));
assert(isscalar(hit), 'Expected one line assigning %s, found %d.', path, numel(hit));
line = hit{1};
end
