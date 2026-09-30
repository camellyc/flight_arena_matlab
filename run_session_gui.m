function varargout = run_session_gui()
% RUN_SESSION_GUI  Window for editing the USER SETTINGS of run_session_unified and
% starting a session with them.
%
% USAGE
%   run_session_gui          % open the window (or bring the open one to the front)
%   fig = run_session_gui;   % ... and return its uifigure
%
% The window is generated from run_session_unified('defaults'), so it always opens on
% the values currently in session_defaults.m, and a setting added there shows up here
% with no change to this file. One tab per settings section; hover over a field
% for the comment written next to it in the file. A setting that differs from the
% file has a bold orange label; an entry that cannot be read as a value turns red.
%
%   Run    starts run_session_unified with every setting that differs from the file
%          as an override. The window is locked until the session ends, then keeps
%          your values for the next trial. The session's result is left in `out` in
%          the base workspace, and the changed settings are listed in the command
%          window when it ends. Errors are shown in the window.
%   Reset  re-reads the file, dropping your edits.
%   Save as file defaults
%          writes every setting that differs from the file into the USER SETTINGS
%          block of session_defaults.m (values only: comments, alignment
%          and every other line stay as they are), after a confirmation listing the
%          changes. From then on those values are the defaults that this window,
%          Reset and run_session_unified open on. The rewritten file is read back
%          before the change is accepted; if any value does not come back as written,
%          the original file is restored.
%
% Not every setting is a plain field:
%   - The meta choices in session_presets.m are dropdowns. A preset stimulus_regime
%     fills in opto.stimDurations and greys it out ("user defined..." frees it and
%     takes the regime name from the box next to it); visual_stim_type does the same
%     for visual.mode and visual.pattern_id. Positions offer "other..." with a box.
%   - Settings a choice makes irrelevant are greyed out (trialNum under auto trial
%     number, the opto fields the opto mode does not use, the Phantom fields when it
%     is off or in framesync, the visual fields of the other arena mode).
%   - Some settings are shown on another tab (acq.TrialLength on Meta) or not at all
%     (HIDDEN below); a hidden setting keeps the value in session_defaults.m.
%
% Runs on R2019a and newer. Where grid layouts cannot scroll yet (R2019a, for one),
% the window is a little wider and long sections continue on extra tabs
% ("Basler 2", ...) so that every setting stays on screen.
%
% Author: Kyle Thieringer, 2026-09

GUI_TAG  = 'run_session_gui';
ROW_H    = 22;     % px per settings row
LABEL_W  = 180;
BROWSE_W = 80;
CHANGED_COLOR = [0.85 0.33 0];    % label of a setting that differs from the file
BAD_COLOR     = [1 0.78 0.78];    % background of an entry that cannot be read
ERROR_COLOR   = [0.8 0 0];        % status text after a failure
RUNNING_TEXT  = 'Running...';
% Only where grid layouts cannot scroll:
FALLBACK_SIZE   = [760 760];      % window size, wide enough for the extra tabs
PAGE_ROWS       = 22;             % rows per tab: 22*22 + 21*4 + 20 = 588 px, inside the ~650 px a tab gets
COMPACT_SPACING = 4;              % px between rows
% Only where grid rows and columns cannot be sized to 'fit':
BAR_H   = 26;                     % bottom bar height
SAVE_W  = 150;                    % Save-as-defaults button width
RESET_W = 150;                    % Reset button width
RUN_W   = 60;                     % Run button width
SECTION_TITLES = struct('meta', 'Meta', 'hw', 'Hardware', 'acq', 'Acquisition', 'visual', 'Visual', ...
                        'opto', 'Opto', 'basler', 'Basler', 'phantom', 'Phantom', 'plotting', 'Plotting');
TAB_ORDER = {'meta', 'opto', 'phantom', 'basler', 'visual', 'acq', 'hw', 'plotting'};   % others follow
% Not shown: these keep the value in session_defaults.m. A struct hides all it holds.
HIDDEN = {'acq.SampleRate', 'acq.blocks', 'acq.ai_channels', 'acq.ai_names', 'acq.terminal_config', ...
          'acq.notify_period_s', 'acq.ttl_threshold_V', 'visual.mode_xy', 'visual.funcy_freq', 'visual.rest'};
% Shown away from their place in the file: {setting, tab, after this setting ('' = first)}.
MOVES = {'meta.auto_trial_number', 'meta',    'meta.flyNumber'
         'acq.TrialLength',        'meta',    'meta.trialNum'
         'phantom.window_s',       'phantom', 'phantom.mode'};
LABELS = {'acq.TrialLength', 'trial length (s)'};   % label other than the field name
PAIRS  = {'phantom.window_s', {'window start (s)', 'window end (s)'}};   % [a b] as two boxes
PAIR_TAGS = {'start', 'end'};                       % control tags <path>:start, <path>:end
ONOFF  = {'meta.carbon_dioxide'};                   % 'ON' / 'OFF' as a tick box
PRESETS = session_presets();
OTHER        = 'other...';
USER_DEFINED = 'user defined...';
% A dropdown whose last item frees a text box (tag <path>:other) for any other value.
CHOICE_OTHER = {'meta.stimulus_regime',   [PRESETS.stimulus_regime(:, 1)', {USER_DEFINED}]
                'meta.stimulus_position', [PRESETS.stimulus_position, {OTHER}]
                'meta.phantom_position',  [PRESETS.phantom_position, {OTHER}]};
% Settings with a fixed set of values, as validated by run_session_unified.
CHOICES = {'meta.visual_stim_type',     PRESETS.visual_stim_type(:, 1)'
           'visual.mode',               {'closed_loop_stripe', 'closed_loop_oscillating', 'none'}
           'opto.mode',                 {'randomized', 'windows', 'both', 'none'}
           'phantom.mode',              {'framesync', 'fixed_fps'}
           'phantom.trigger_at',        {'end', 'start'}
           'phantom.save_format',       {'tif12', 'cine'}
           'basler.top.line_inverter',  {'False', 'True'}
           'basler.side.line_inverter', {'False', 'True'}};
FOLDERS = {'saveFolder', 'phantom.saveRoot', 'basler.video_scratch_folder'};   % get a Browse button

% One window per MATLAB: two could start two sessions on the same rig.
existing = findall(groot, 'Type', 'figure', 'Tag', GUI_TAG);
if ~isempty(existing)
    fig = existing(1);
    figure(fig);
    if nargout > 0, varargout{1} = fig; end
    return;
end

% HandleVisibility 'off' keeps the window out of the close all a session starts with.
fig = uifigure('Name', 'Flight arena session', 'Tag', GUI_TAG, 'HandleVisibility', 'off', ...
               'Position', [100 100 640 760], 'CloseRequestFcn', @(~, ~) onClose());
root = uigridlayout(fig, [3 1]);
% Layout features newer than R2019a are used only where this MATLAB has them: 'fit'
% grid sizes (R2019b), label WordWrap (R2020b) and scrollable grid layouts (present by
% R2021a). Without scrolling, long sections continue on extra tabs instead.
canFit    = acceptsFit(root);
canScroll = isprop(root, 'Scrollable');
if canFit, root.RowHeight = {'fit', '1x', 'fit'}; else, root.RowHeight = {ROW_H, '1x', BAR_H}; end
if ~canScroll, fig.Position(3:4) = FALLBACK_SIZE; end
topGrid = uigridlayout(root, [1 3], 'Padding', [0 0 0 0]);
topGrid.ColumnWidth = {LABEL_W, '1x', BROWSE_W};
tabs = uitabgroup(root);
bottom = uigridlayout(root, [1 4], 'Padding', [0 0 0 0]);
if canFit, bottom.ColumnWidth = {'1x', 'fit', 'fit', 'fit'}; else, bottom.ColumnWidth = {'1x', SAVE_W, RESET_W, RUN_W}; end
statusLabel = uilabel(bottom, 'Text', '', 'Tag', 'statusLabel');
if canFit && isprop(statusLabel, 'WordWrap'), statusLabel.WordWrap = 'on'; end   % grows the 'fit' row
statusFg = statusLabel.FontColor;
uibutton(bottom, 'Text', 'Save as file defaults', 'Tag', 'saveDefaultsButton', ...
         'Tooltip', 'Write the changed settings into the USER SETTINGS block of session_defaults.m', ...
         'ButtonPushedFcn', @(~, ~) onSaveDefaults());
uibutton(bottom, 'Text', 'Reset to file defaults', 'Tag', 'resetButton', ...
         'Tooltip', 'Re-read the USER SETTINGS block of session_defaults.m', ...
         'ButtonPushedFcn', @(~, ~) onReset());
uibutton(bottom, 'Text', 'Run', 'Tag', 'runButton', 'FontWeight', 'bold', ...
         'Tooltip', 'Start run_session_unified with these settings', ...
         'ButtonPushedFcn', @(~, ~) onRun());
running = false;   % a session started from this window is in progress

% One entry per editable setting. fg / bg / labelFg are the colours the controls were
% created with, restored when a flag or mark is cleared (so a dark theme survives).
% ctrl2 / label2: the second box of a pair, or the "other" text box of a dropdown.
fields = struct('path', {}, 'kind', {}, 'default', {}, 'ctrl', {}, 'label', {}, ...
                'fg', {}, 'bg', {}, 'labelFg', {}, 'ctrl2', {}, 'label2', {});
setappdata(fig, 'hiddenSettings', HIDDEN);   % for the tests
buildForm(run_session_unified('defaults'));

if nargout > 0, varargout{1} = fig; end

%% ======================= NESTED FUNCTIONS ===============================

    function buildForm(S)
        % (Re)create every control from the settings struct S: top-level plain
        % settings (saveFolder) above the tabs, one tab per settings section in
        % TAB_ORDER, with HIDDEN left out and MOVES applied.
        tips = settingComments();
        delete(topGrid.Children);
        delete(tabs.Children);
        fields = fields([]);
        names = fieldnames(S);
        isSection = cellfun(@(n) isstruct(S.(n)), names);
        top = names(~isSection);
        topGrid.RowHeight = repmat({ROW_H}, 1, numel(top));
        if ~canFit   % what 'fit' would have made of this row
            root.RowHeight{1} = numel(top) * ROW_H + max(0, numel(top) - 1) * topGrid.RowSpacing;
        end
        for i = 1:numel(top)
            addSetting(topGrid, i, top{i}, top{i}, S.(top{i}), tips, 0);
        end
        secs = names(isSection)';
        secs = [TAB_ORDER(ismember(TAB_ORDER, secs)), secs(~ismember(secs, TAB_ORDER))];
        rows = struct();
        for i = 1:numel(secs)
            rows.(secs{i}) = shownItems(S.(secs{i}), secs{i}, HIDDEN, PAIRS);
        end
        for m = 1:size(MOVES, 1)
            rows = moveItem(rows, MOVES{m, :});
        end
        for i = 1:numel(secs)
            items = rows.(secs{i});
            if isempty(items), continue; end   % everything in it hidden or moved
            if canScroll, pages = {items}; else, pages = pageItems(items, PAGE_ROWS); end
            for p = 1:numel(pages)
                tabTitle = sectionTitle(secs{i});
                if p > 1, tabTitle = sprintf('%s %d', tabTitle, p); end
                addTab(tabTitle, pages{p}, tips);
            end
        end
        applyRules();
    end

    function addTab(tabTitle, items, tips)
        tab = uitab(tabs, 'Title', tabTitle);
        g = uigridlayout(tab, [max(1, numel(items)) 3]);
        g.RowHeight   = repmat({ROW_H}, 1, numel(items));
        g.ColumnWidth = {LABEL_W, '1x', BROWSE_W};
        if canScroll, g.Scrollable = 'on'; else, g.RowSpacing = COMPACT_SPACING; end
        for r = 1:numel(items)
            if items(r).heading
                h = uilabel(g, 'Text', items(r).name, 'FontWeight', 'bold', 'Tag', ['heading:' items(r).path]);
                h.Layout.Row = r; h.Layout.Column = [1 3];
            else
                addSetting(g, r, items(r).name, items(r).path, items(r).value, tips, items(r).part);
            end
        end
    end

    function addSetting(g, r, name, path, value, tips, part)
        % part: 0 for a whole setting; 1 or 2 for the two boxes of a PAIRS setting.
        lbl = uilabel(g, 'Text', name, 'Tag', ['label:' path]);
        lbl.Layout.Row = r; lbl.Layout.Column = 1;
        hit = strcmp(LABELS(:, 1), path);
        if any(hit) && part == 0, lbl.Text = LABELS{hit, 2}; end
        c2 = [];
        if part > 0
            kind = 'pair';
            tag  = [path ':' PAIR_TAGS{part}];
            lbl.Tag = ['label:' tag];
            if numel(value) >= part, txt = toText('numeric', value(part)); else, txt = ''; end
            c = uieditfield(g, 'text', 'Value', txt, 'Tag', tag);
            c.Layout.Row = r; c.Layout.Column = 2;
        else
            [kind, items] = kindOf(path, value);
            switch kind
                case 'logical', c = uicheckbox(g, 'Text', '', 'Value', value);
                case 'onoff',   c = uicheckbox(g, 'Text', '', 'Value', strcmpi(value, 'ON'));
                case 'choice',  c = uidropdown(g, 'Items', items, 'Value', value);
                case 'choiceOther'
                    sub = uigridlayout(g, [1 2], 'Padding', [0 0 0 0]);
                    sub.Layout.Row = r; sub.Layout.Column = [2 3];
                    if any(strcmp(items(1:end - 1), value)), dv = value; tv = '';
                    else,                                    dv = items{end}; tv = value;
                    end
                    c  = uidropdown(sub, 'Items', items, 'Value', dv);
                    c2 = uieditfield(sub, 'text', 'Value', tv, 'Tag', [path ':other']);
                    c2.ValueChangedFcn = @(~, ~) onEdit(path);
                otherwise,      c = uieditfield(g, 'text', 'Value', toText(kind, value));
            end
            if strcmp(kind, 'fixed'), c.Editable = 'off'; end
            c.Tag = path;
            if ~strcmp(kind, 'choiceOther'), c.Layout.Row = r; c.Layout.Column = 2; end
        end
        c.ValueChangedFcn = @(~, ~) onEdit(path);
        if isKey(tips, path)
            c.Tooltip = tips(path); lbl.Tooltip = tips(path);
            if ~isempty(c2), c2.Tooltip = tips(path); end
        end
        if any(strcmp(path, FOLDERS))
            b = uibutton(g, 'Text', 'Browse...', 'Tag', ['browse:' path], ...
                         'ButtonPushedFcn', @(~, ~) browse(c, path));
            b.Layout.Row = r; b.Layout.Column = 3;
        end
        if part == 2   % the second box joins the entry the first one made
            k = find(strcmp({fields.path}, path), 1);
            fields(k).ctrl2 = c; fields(k).label2 = lbl;
            return;
        end
        fg = []; bg = [];
        if isprop(c, 'FontColor'),       fg = c.FontColor;       end
        if isprop(c, 'BackgroundColor'), bg = c.BackgroundColor; end
        fields(end + 1) = struct('path', path, 'kind', kind, 'default', {value}, 'ctrl', c, 'label', lbl, ...
                                 'fg', fg, 'bg', bg, 'labelFg', lbl.FontColor, 'ctrl2', c2, 'label2', []);
    end

    function [kind, items] = kindOf(path, value)
        items = {};
        hit  = strcmp(CHOICES(:, 1), path);
        hitO = strcmp(CHOICE_OTHER(:, 1), path);
        if any(hitO) && ischar(value)
            kind  = 'choiceOther';
            items = CHOICE_OTHER{hitO, 2};
        elseif any(strcmp(ONOFF, path)) && ischar(value)
            kind = 'onoff';
        elseif any(hit) && ischar(value)
            kind  = 'choice';
            items = CHOICES{hit, 2};
            if ~any(strcmp(items, value)), items = [{value}, items]; end   % keep an unlisted file value
        elseif islogical(value) && isscalar(value)
            kind = 'logical';
        elseif ischar(value) && (isrow(value) || isempty(value))
            kind = 'char';
        elseif isnumeric(value) && isreal(value) && ismatrix(value)
            kind = 'numeric';
        elseif iscellstr(value) && (isvector(value) || isempty(value))
            kind = 'cellstr';
        else
            kind = 'fixed';   % shown read-only and never sent; edit it in the file
        end
    end

    function onEdit(path)
        refreshField(path);
        applyRules();
    end

    function refreshField(path)
        % Mark a setting that differs from the file; flag an entry that cannot be read.
        f = fields(strcmp({fields.path}, path));
        [v, ok] = readField(f);
        lbls = [f.label, f.label2];
        if ok && ~sameValue(v, f.default)
            set(lbls, 'FontWeight', 'bold', 'FontColor', CHANGED_COLOR);
        else
            set(lbls, 'FontWeight', 'normal', 'FontColor', f.labelFg);
        end
        switch f.kind
            case 'numeric'
                flagBox(f, f.ctrl, ok);
            case 'pair'
                [~, ok1] = readPart(f.ctrl,  f.default);
                [~, ok2] = readPart(f.ctrl2, f.default);
                flagBox(f, f.ctrl, ok1);
                flagBox(f, f.ctrl2, ok2);
        end
    end

    function flagBox(f, c, ok)
        if ok, c.BackgroundColor = f.bg;        c.FontColor = f.fg;
        else,  c.BackgroundColor = BAD_COLOR;   c.FontColor = [0 0 0];
        end
    end

    function applyRules()
        % Grey out the settings the current choices make irrelevant, and fill in the
        % ones a preset fixes (the same values run_session_unified applies).
        if running || isempty(fields) || ~isvalid(fig), return; end
        paths = {fields.path};
        en = true(1, numel(fields));
        if isequal(valueOf('meta.auto_trial_number'), true), off('meta.trialNum'); end

        hit = strcmp(PRESETS.stimulus_regime(:, 1), valueOf('meta.stimulus_regime'));
        if any(hit)
            show('opto.stimDurations', PRESETS.stimulus_regime{hit, 2});
            off('opto.stimDurations');
        end

        hit = strcmp(PRESETS.visual_stim_type(:, 1), valueOf('meta.visual_stim_type'));
        if any(hit)
            show('visual.mode', PRESETS.visual_stim_type{hit, 2});
            if ~isempty(PRESETS.visual_stim_type{hit, 3})
                show('visual.pattern_id', PRESETS.visual_stim_type{hit, 3});
            end
            off('visual.mode'); off('visual.pattern_id');
        end
        switch char(valueOf('visual.mode'))
            case 'closed_loop_stripe',      off('visual.velfunc_id'); off('visual.y_gain'); off('visual.y_bias');
            case 'closed_loop_oscillating', off('visual.x_pos');
            case 'none',                    offUnder('visual', '');
        end

        om = valueOf('opto.mode');
        if ~any(strcmp(om, {'randomized', 'both'}))
            off('opto.stimDurations'); off('opto.stimIntensities_V'); off('opto.randomize');
        end
        if ~any(strcmp(om, {'windows', 'both'}))
            off('opto.windows_s'); off('opto.windows_amplitude_V');
        end
        if strcmp(om, 'none'), offUnder('opto', 'opto.mode'); end

        if isequal(valueOf('phantom.enable'), false), offUnder('phantom', 'phantom.enable'); end
        if strcmp(valueOf('phantom.mode'), 'framesync')          % triggers at the window end
            off('phantom.trigger_at'); off('phantom.pt_frames');
        elseif strcmp(valueOf('phantom.trigger_at'), 'start')    % pt_frames is the 'end' buffer
            off('phantom.pt_frames');
        end

        for k = 1:numel(fields), setEnabled(fields(k), en(k)); end

        function off(path)
            en(strcmp(paths, path)) = false;
        end
        function offUnder(section, except)
            en(startsWith(paths, [section '.']) & ~strcmp(paths, except)) = false;
        end
    end

    function v = valueOf(path)
        % The value a setting has in the window now ([] if the file has no such setting).
        k = find(strcmp({fields.path}, path), 1);
        if isempty(k), v = []; else, v = readField(fields(k)); end
    end

    function show(path, v)
        % Put the value a preset fixes into its control.
        k = find(strcmp({fields.path}, path), 1);
        if isempty(k), return; end
        c = fields(k).ctrl;
        switch fields(k).kind
            case 'numeric', txt = toText('numeric', v);
            case 'choice',  txt = v; if ~any(strcmp(c.Items, v)), return; end
            otherwise,      return;
        end
        if ~strcmp(c.Value, txt), c.Value = txt; refreshField(path); end
    end

    function setEnabled(f, tf)
        if tf, e = 'on'; else, e = 'off'; end
        f.ctrl.Enable = e;
        if isempty(f.ctrl2), return; end
        if strcmp(f.kind, 'choiceOther') && tf && ~strcmp(f.ctrl.Value, f.ctrl.Items{end}), e = 'off'; end
        f.ctrl2.Enable = e;
    end

    function [ov, changed, bad] = collectOverrides()
        % The settings that differ from the file, as the nested override struct
        % run_session_unified takes. changed = {path, value} rows for the log;
        % bad = paths of entries that cannot be read.
        ov = struct(); changed = cell(0, 2); bad = {};
        for k = 1:numel(fields)
            f = fields(k);
            refreshField(f.path);            % so the marks match exactly what is sent
            [v, ok] = readField(f);
            if ~ok, bad{end + 1} = f.path; continue; end %#ok<AGROW>
            if sameValue(v, f.default), continue; end
            parts = strsplit(f.path, '.');
            ov = setfield(ov, parts{:}, v);
            changed(end + 1, :) = {f.path, v}; %#ok<AGROW>
        end
    end

    function onRun()
        if running, return; end
        [ov, changed, bad] = collectOverrides();
        if ~isempty(bad)
            setStatus(['Not started. Fix the red entries: ' strjoin(bad, ', ')], true);
            uialert(fig, sprintf('These entries cannot be read as values:\n\n%s', strjoin(bad, newline)), ...
                    'Invalid settings');
            return;
        end
        setRunning(true);
        setStatus(RUNNING_TEXT, false);
        drawnow;
        finish = onCleanup(@() finishRun(changed));   % runs on success, error or Ctrl+C
        try
            out = run_session_unified(ov);
            assignin('base', 'out', out);
            setStatus(['Saved ' out.params.files.mat], false);
        catch ME
            fprintf(2, 'run_session_gui: the session failed.\n%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            setStatus(['Failed: ' ME.message], true);
            if isvalid(fig), uialert(fig, ME.message, 'Session failed'); end
        end
    end

    function finishRun(changed)
        setRunning(false);
        logChanges(changed);
        if isvalid(fig) && strcmp(statusLabel.Text, RUNNING_TEXT)   % interrupted with Ctrl+C
            setStatus('Stopped before the session finished; see the command window.', true);
        end
    end

    function setRunning(tf)
        % Lock every control (Run and Reset included) while a session runs; afterwards
        % the greying rules decide again what is enabled.
        running = tf;
        if ~isvalid(fig), return; end
        if tf, e = 'off'; else, e = 'on'; end
        for k = 1:numel(fields), setEnabled(fields(k), ~tf); end
        set(findall(fig, 'Type', 'uibutton'), 'Enable', e);
        applyRules();
    end

    function setStatus(text, isError)
        if ~isvalid(fig), return; end
        statusLabel.Text = text;
        if isError, statusLabel.FontColor = ERROR_COLOR; else, statusLabel.FontColor = statusFg; end
    end

    function onClose()
        % The session is still using the window (and the Run callback is its caller).
        if running
            uialert(fig, ['A session is running. Wait for it to finish, or stop it with Ctrl+C ' ...
                          'in the MATLAB command window, then close this window.'], 'Session running');
            return;
        end
        delete(fig);
    end

    function onReset()
        % Re-read the file (picking up edits made since the window opened), keeping the tab.
        sel = '';
        if ~isempty(tabs.SelectedTab), sel = tabs.SelectedTab.Title; end
        buildForm(run_session_unified('defaults'));
        kids = tabs.Children;
        hit  = kids(strcmp({kids.Title}, sel));
        if ~isempty(hit), tabs.SelectedTab = hit(1); end
    end

    function onSaveDefaults()
        % Write the settings that differ from the file into the file itself, so they
        % are the defaults this window, Reset and run_session_unified open on.
        if running, return; end
        [~, changed, bad] = collectOverrides();
        if ~isempty(bad)
            setStatus(['Nothing saved. Fix the red entries: ' strjoin(bad, ', ')], true);
            uialert(fig, sprintf('These entries cannot be read as values:\n\n%s', strjoin(bad, newline)), ...
                    'Invalid settings');
            return;
        end
        if isempty(changed)
            setStatus('No setting differs from the file; nothing to save.', false);
            return;
        end
        file  = which('session_defaults');
        lines = cellfun(@(p, v) sprintf('%s = %s', p, valueText(v)), changed(:, 1), changed(:, 2), ...
                        'UniformOutput', false);
        % The tests set skipConfirm on the figure; a person is always asked first.
        if ~isequal(getappdata(fig, 'skipConfirm'), true)
            choice = uiconfirm(fig, sprintf('Write these %d setting(s) into the USER SETTINGS block of\n%s ?\n\n%s', ...
                                            numel(lines), file, strjoin(lines, newline)), ...
                               'Save as file defaults', 'Options', {'Save', 'Cancel'}, ...
                               'DefaultOption', 1, 'CancelOption', 2);
            if ~strcmp(choice, 'Save'), setStatus('Not saved.', false); return; end
        end
        try
            writeSettingsFile(file, changed);
        catch ME
            setStatus(['Nothing saved: ' ME.message], true);
            uialert(fig, ME.message, 'Save failed');
            return;
        end
        fprintf('run_session_gui: wrote %d setting(s) into %s:\n', numel(lines), file);
        fprintf('  %s\n', lines{:});
        onReset();   % re-read the file: the marks clear because the values now match it
        setStatus(sprintf('Saved %d setting(s) as the defaults in %s', numel(lines), file), false);
    end

    function t = sectionTitle(name)
        if isfield(SECTION_TITLES, name), t = SECTION_TITLES.(name); else, t = name; end
    end

    function browse(c, path)
        start = c.Value;
        if ~isfolder(start), start = pwd; end
        d = uigetdir(start, 'Choose folder');
        figure(fig);                        % the dialog can leave the window behind others
        if ischar(d), c.Value = d; refreshField(path); end
    end

end   % run_session_gui

%% ======================= LOCAL FUNCTIONS ================================

function tf = acceptsFit(g)
% True when this MATLAB takes 'fit' as a grid row height (R2019b on); R2019a rejects it.
old = g.RowHeight;
try
    g.RowHeight = repmat({'fit'}, size(old));
    tf = true;
catch
    tf = false;
end
g.RowHeight = old;
end

function pages = pageItems(items, maxRows)
% Split one section's rows over tabs of at most maxRows, for releases whose grid
% layouts cannot scroll. A nested struct's heading stays on the same tab as its
% settings; only a group longer than a whole tab is cut, into equal parts.
if isempty(items), pages = {items}; return; end
starts = unique([1, find([items.heading])]);
ends   = [starts(2:end) - 1, numel(items)];
pages  = {};
cur    = items([]);
for k = 1:numel(starts)
    grp = items(starts(k):ends(k));
    if ~isempty(cur) && numel(cur) + numel(grp) > maxRows
        pages{end + 1} = cur; %#ok<AGROW>
        cur = items([]);
    end
    while numel(grp) > maxRows
        n = ceil(numel(grp) / ceil(numel(grp) / maxRows));
        pages{end + 1} = grp(1:n); %#ok<AGROW>
        grp = grp(n + 1:end);
    end
    cur = [cur, grp]; %#ok<AGROW>
end
if ~isempty(cur), pages{end + 1} = cur; end
end

function [v, ok] = readField(f)
% The setting's value as entered, converted back to the type of its file default.
ok = true;
switch f.kind
    case 'numeric', [v, ok] = parseNumber(f.ctrl.Value, f.default);
    case 'cellstr', v = parseList(f.ctrl.Value, f.default);
    case 'fixed',   v = f.default;
    case 'onoff'
        if f.ctrl.Value, v = 'ON'; else, v = 'OFF'; end
        if strcmpi(v, f.default), v = f.default; end       % 'off' in the file is not a change
    case 'choiceOther'                                     % the last item frees the text box
        if strcmp(f.ctrl.Value, f.ctrl.Items{end}), v = strtrim(f.ctrl2.Value); else, v = f.ctrl.Value; end
    case 'pair'
        [a, ok1] = readPart(f.ctrl,  f.default);
        [b, ok2] = readPart(f.ctrl2, f.default);
        ok = ok1 && ok2;
        if ok, v = [a b]; else, v = []; end
    otherwise,      v = f.ctrl.Value;
end
end

function [v, ok] = readPart(c, default)
% One box of a pair: a single number of the class of the pair's file default.
[v, ok] = parseNumber(c.Value, cast(0, class(default)));
end

function [v, ok] = parseNumber(txt, default)
% Numbers as MATLAB writes them: 90, [0 3000 3000], [88 88.5; 90 91], [0:11 14].
% Only digits and array punctuation get as far as str2num, so nothing typed here
% can run as code. A setting that is a single number in the file must stay one.
v = []; ok = false;
txt = strtrim(txt);
if isempty(txt)                       % before the regexp, which never matches ''
    ok = ~isscalar(default);          % clearing a list is fine; a single number cannot be blank
    return;
end
if isempty(regexp(txt, '^[-+\d\s.,;:\[\]eE]*$', 'once')), return; end
[v, ok] = str2num(txt);               % input already restricted to numeric syntax
if ok && isscalar(default) && ~isscalar(v), ok = false; end
if ok, v = cast(v, class(default)); end
end

function v = parseList(txt, default)
% 'a, b, c' -> {'a', 'b', 'c'}, oriented like the default.
v = strtrim(strsplit(txt, ','));
v = v(~cellfun(@isempty, v));
if size(default, 1) > 1, v = v(:); end
end

function tf = sameValue(a, b)
% Values, not text: 90 and 90.0 match. Any two empties match ('' vs 1x0 char, [] vs zeros(0, 2)).
tf = isequal(a, b) || (isempty(a) && isempty(b));
end

function logChanges(changed)
% What this session changed from the file. Printed when the session ends, because
% run_session_unified clears the command window as it starts.
if isempty(changed)
    fprintf('\nrun_session_gui: this session used the settings in session_defaults.m unchanged.\n');
    return;
end
fprintf('\nrun_session_gui: this session changed %d setting(s) from session_defaults.m:\n', size(changed, 1));
for k = 1:size(changed, 1)
    fprintf('  %s = %s\n', changed{k, 1}, valueText(changed{k, 2}));
end
end

function t = valueText(v)
% A value as it would be typed in MATLAB: 'text', 4, [0 3000], true, {'a', 'b'}.
% Also what "Save as file defaults" writes, so every branch must be valid source.
if ischar(v)
    t = ['''' strrep(v, '''', '''''') ''''];
elseif islogical(v) && isscalar(v)
    if v, t = 'true'; else, t = 'false'; end
elseif iscellstr(v)
    t = ['{' strjoin(cellfun(@valueText, v, 'UniformOutput', false), ', ') '}'];
elseif isnumeric(v) && isempty(v)
    t = '[]';                      % mat2str([]) is 'zeros(0,0)'
else
    t = mat2str(v);
end
end

%% ---- Save as file defaults: rewriting the USER SETTINGS block --------------

function writeSettingsFile(file, changed)
% Replace the values of the settings in changed ({path, value} rows) inside the
% USER SETTINGS block of file, leaving every other character alone. All or nothing:
% the new text is built in full first, then written, then read back through
% run_session_unified('defaults'). If any value does not come back as written, the
% original text is put back and an error raised.
old = fileread(file);
if contains(old, sprintf('\r\n')), nl = sprintf('\r\n'); else, nl = newline; end
src = splitlines(old);
missing = {};
for k = 1:size(changed, 1)
    [b0, b1] = settingsBlock(src, file);          % re-found each time: a multi-line statement may collapse
    [src, ok] = replaceSetting(src, b0, b1, changed{k, 1}, changed{k, 2});
    if ~ok, missing{end + 1} = changed{k, 1}; end %#ok<AGROW>
end
if ~isempty(missing)
    error('run_session_gui:settingNotFound', ...
          'No assignment of %s in the USER SETTINGS block of %s. Nothing was written.', ...
          strjoin(missing, ', '), file);
end
writeText(file, strjoin(src, nl));
clear('session_defaults');                     % make sure the next call parses the new file
try
    S = run_session_unified('defaults');
    for k = 1:size(changed, 1)
        parts = strsplit(changed{k, 1}, '.');
        got   = getfield(S, parts{:});
        assert(sameValue(got, changed{k, 2}), '%s reads back as %s, not %s', ...
               changed{k, 1}, valueText(got), valueText(changed{k, 2}));
    end
catch ME
    writeText(file, old);
    clear('session_defaults');
    error('run_session_gui:writeFailed', ...
          'The rewritten file did not read back correctly (%s). The original file was restored.', ME.message);
end
end

function [b0, b1] = settingsBlock(src, file)
% First and last line index inside the USER SETTINGS block.
s = find(~cellfun(@isempty, regexp(src, '^\s*%%\s*=+\s*USER SETTINGS', 'once')), 1);
e = find(~cellfun(@isempty, regexp(src, '^\s*%%\s*=+\s*END USER SETTINGS', 'once')), 1);
if isempty(s) || isempty(e) || e <= s
    error('run_session_gui:noSettingsBlock', 'No USER SETTINGS ... END USER SETTINGS block in %s.', file);
end
b0 = s + 1; b1 = e - 1;
end

function [src, ok] = replaceSetting(src, b0, b1, path, v)
% Give the setting at path the value v in the lines src (a cellstr of the file).
% Either the setting has its own assignment line (possibly continued with ...), which
% is collapsed to one line that keeps its end-of-line comment and alignment; or it is
% a field of a struct(...) call, e.g. basler.top.gain inside
% "basler.top = struct(..., 'gain', 5, ...)", where only the value token changes.
ok = false;
k = findAssignment(src, b0, b1, path);
if ~isempty(k)
    kEnd = statementEnd(src, k);
    ln   = src{k};
    eq   = find(ln == '=', 1);                     % the path itself never contains one
    [~, comment, col] = splitComment(ln);
    code = [ln(1:eq) ' ' valueText(v) ';'];
    if isempty(comment)
        src{k} = code;
    else
        src{k} = [code, repmat(' ', 1, max(2, col - 1 - numel(code))), '% ', comment];
    end
    src(k + 1:kEnd) = [];
    ok = true;
    return;
end
dot = find(path == '.', 1, 'last');
if isempty(dot), return; end
parent = path(1:dot - 1);
leaf   = path(dot + 1:end);
k = findAssignment(src, b0, b1, parent);
if isempty(k), return; end
kEnd = statementEnd(src, k);
stmt = strjoin(src(k:kEnd), newline);              % kept multi-line: only the value token changes
% 'leaf', <value>  -- the value may sit on the next line after a ... continuation
key = ['''' regexptranslate('escape', leaf) '''\s*,\s*(?:\.\.\.[^\n]*\n\s*)?'];
i = regexp(stmt, key, 'end', 'once') + 1;
if isempty(i) || i > numel(stmt), return; end
e = valueTokenEnd(stmt, i);
stmt = [stmt(1:i - 1) valueText(v) stmt(e + 1:end)];
src(k:kEnd) = splitlines(stmt);                    % same number of lines as before
ok = true;
end

function k = findAssignment(src, b0, b1, path)
% Line index (into src) of "path = ..." inside the block, [] when there is none.
pat = ['^\s*' regexptranslate('escape', path) '\s*=(?!=)'];
hit = find(~cellfun(@isempty, regexp(src(b0:b1), pat, 'once')), 1);
if isempty(hit), k = []; else, k = b0 + hit - 1; end
end

function kEnd = statementEnd(src, k)
% Last line of the statement starting on line k: lines whose code ends in ... continue.
kEnd = k;
while kEnd < numel(src)
    code = splitComment(src{kEnd});
    if isempty(regexp(strtrim(code), '\.\.\.$', 'once')), break; end
    kEnd = kEnd + 1;
end
end

function e = valueTokenEnd(s, i)
% Index of the last character of the value that starts at s(i): a quoted string, a
% bracketed [...] / {...} / (...) expression, or a bare token up to the next , or ).
if s(i) == ''''
    j = i + 1;
    while j <= numel(s)
        if s(j) == ''''
            if j < numel(s) && s(j + 1) == '''', j = j + 2; continue; end   % doubled quote
            e = j; return;
        end
        j = j + 1;
    end
    error('run_session_gui:unterminatedString', 'Unterminated string in the settings statement.');
end
depth = 0;
e = numel(s);
for j = i:numel(s)
    switch s(j)
        case {'[', '{', '('}
            depth = depth + 1;
        case {']', '}', ')'}
            if depth == 0, e = j - 1; break; end
            depth = depth - 1;
        case ','
            if depth == 0, e = j - 1; break; end
    end
end
while e > i && isspace(s(e)), e = e - 1; end        % drop the whitespace before the , or )
end

function writeText(file, txt)
fid = fopen(file, 'w');                             % binary: line endings written as given
assert(fid > 0, 'run_session_gui:cannotWrite', 'Cannot open %s for writing.', file);
c = onCleanup(@() fclose(fid));
fprintf(fid, '%s', txt);
end

function items = shownItems(s, prefix, hidden, pairs)
% The rows of one settings section as the window shows them: HIDDEN settings (and
% everything inside a hidden struct) left out, and a PAIRS setting as two rows.
items = flatten(s, prefix);
keep = true(1, numel(items));
for k = 1:numel(items)
    keep(k) = ~any(strcmp(items(k).path, hidden) | startsWith(items(k).path, strcat(hidden, '.')));
end
items = items(keep);
for k = numel(items):-1:1
    hit = strcmp(pairs(:, 1), items(k).path);
    if ~any(hit) || items(k).heading, continue; end
    two = [items(k), items(k)];
    two(1).name = pairs{hit, 2}{1}; two(1).part = 1;
    two(2).name = pairs{hit, 2}{2}; two(2).part = 2;
    items = [items(1:k - 1), two, items(k + 1:end)];
end
end

function rows = moveItem(rows, path, toSec, after)
% Move the row(s) of setting path from its section to section toSec, after the row
% of setting after ('' = first). Nothing happens if either is not shown.
fromSec = strtok(path, '.');
if ~isfield(rows, fromSec) || ~isfield(rows, toSec), return; end
take = strcmp({rows.(fromSec).path}, path);
if ~any(take), return; end
moved = rows.(fromSec)(take);
rows.(fromSec) = rows.(fromSec)(~take);
dest = rows.(toSec);
if isempty(after)
    at = 0;
else
    at = find(strcmp({dest.path}, after), 1, 'last');
    if isempty(at), at = numel(dest); end
end
rows.(toSec) = [dest(1:at), moved, dest(at + 1:end)];
end

function items = flatten(s, prefix)
% Rows for one settings section: its plain settings in file order, then a heading for
% each nested struct (basler.top, basler.h264, ...) followed by that struct's rows.
% Nested structs go last so that no plain setting is ever listed under a heading
% should one sit mid-section in the file with plain settings after it.
items  = struct('heading', {}, 'name', {}, 'path', {}, 'value', {}, 'part', {});
nested = items;
f = fieldnames(s);
for k = 1:numel(f)
    p = [prefix '.' f{k}];
    v = s.(f{k});
    if isstruct(v) && isscalar(v)
        nested(end + 1) = struct('heading', true, 'name', p(find(p == '.', 1) + 1:end), 'path', p, 'value', [], 'part', 0); %#ok<AGROW>
        nested = [nested, flatten(v, p)]; %#ok<AGROW>
    else
        items(end + 1) = struct('heading', false, 'name', f{k}, 'path', p, 'value', {v}, 'part', 0); %#ok<AGROW>
    end
end
items = [items, nested];
end

function t = toText(kind, v)
switch kind
    case 'char'
        t = v;
    case 'numeric'
        if isempty(v), t = '[]'; else, t = mat2str(double(v)); end
    case 'cellstr'
        t = strjoin(v, ', ');
    otherwise
        t = sprintf('(%s %s: edit in session_defaults.m)', mat2str(size(v)), class(v));
end
end

function tips = settingComments()
% End-of-line comment of every assignment in the USER SETTINGS block, by setting path.
tips = containers.Map('KeyType', 'char', 'ValueType', 'char');
src = splitlines(fileread(which('session_defaults')));
inBlock = false;
for k = 1:numel(src)
    ln = src{k};
    if ~inBlock
        inBlock = ~isempty(regexp(ln, '^\s*%%\s*=+\s*USER SETTINGS', 'once'));
        continue;
    end
    if ~isempty(regexp(ln, '^\s*%%\s*=+\s*END USER SETTINGS', 'once')), break; end
    tok = regexp(ln, '^\s*([A-Za-z]\w*(?:\.\w+)*)\s*=', 'tokens', 'once');
    if isempty(tok), continue; end
    c = commentOf(ln);
    if ~isempty(c), tips(tok{1}) = c; end
end
end

function c = commentOf(ln)
% Text after the first % outside a quoted string ('' when the line has none), so a
% value such as '50% power' is not mistaken for the start of the comment.
[~, c] = splitComment(ln);
end

function [code, comment, col] = splitComment(ln)
% The code part of a line, the trimmed comment after its first % outside a quoted
% string ('' when there is none), and the column of that % (0 when there is none).
code = ln; comment = ''; col = 0;
nameEnd = ['A':'Z' 'a':'z' '0':'9' '_.)]}'''];   % a ' straight after one of these is a transpose
q = '';   % quote character of the string being scanned, '' when outside one
j = 1;
while j <= numel(ln)
    ch = ln(j);
    if ~isempty(q)
        if ch == q
            if j < numel(ln) && ln(j + 1) == q, j = j + 1;   % doubled quote inside the string
            else, q = ''; end
        end
    elseif ch == '%'
        code    = ln(1:j - 1);
        comment = strtrim(ln(j + 1:end));
        col     = j;
        return;
    elseif ch == '"' || (ch == '''' && (j == 1 || ~any(ln(j - 1) == nameEnd)))
        q = ch;
    end
    j = j + 1;
end
end
