function problems = acquisition_problems(baslerInfo, phantom, minFraction)
% ACQUISITION_PROBLEMS  What a user must know about before the next trial.
%
%   problems = acquisition_problems(baslerInfo, phantom, minFraction)
%
% One line per problem, {} when all is well. run_session_unified calls it at the end
% of every run and prints, pops up and beeps the result (hw.alert_on_problems); it is
% also in out.problems and the GUI status line.
%
%   baslerInfo   struct with one field per camera (top, side), each as
%                run_session_unified's writeCameraVideo returns it: label, frames,
%                expected_frames. A camera field that is not such a struct is skipped.
%   phantom      run_session_unified's phantom struct: init_error, attempted (per
%                block), files (per block), file_bytes, file_count, gate_col,
%                rec_on_time_s.
%   minFraction  a camera video with fewer frames than this fraction of expected is
%                flagged (0.9 in run_session_unified).
%
% Flagged:
%   - a camera video with no frames, or under minFraction of the expected frames
%   - Phantom init failed (phantom.init_error) although a recording was configured
%   - a block in which a Phantom recording was expected (phantom.attempted) but the
%     save failed (empty phantom.files{block}), or what was saved is empty (no files,
%     or under 1 MB), or the Recording gate never went ON (PCC did not record)
%
% See also RUN_SESSION_UNIFIED.

MIN_PHANTOM_BYTES = 1e6;

problems = {};
for cam = fieldnames(baslerInfo)'
    info = baslerInfo.(cam{1});
    if ~isstruct(info) || ~isfield(info, 'frames'), continue; end
    if info.frames == 0
        problems{end + 1} = sprintf('%s: no frames written', info.label); %#ok<AGROW>
    elseif info.expected_frames > 0 && info.frames < minFraction * info.expected_frames
        problems{end + 1} = sprintf('%s: %d of ~%d frames (%.0f %%)', info.label, info.frames, ...
                                    info.expected_frames, 100 * info.frames / info.expected_frames); %#ok<AGROW>
    end
end

if isfield(phantom, 'init_error') && ~isempty(phantom.init_error)
    problems{end + 1} = sprintf('Phantom: not recorded, init failed (%s)', phantom.init_error);
end
if ~isfield(phantom, 'attempted'), return; end
for block = find(phantom.attempted(:))'
    if isempty(phantom.files{block})
        problems{end + 1} = sprintf('Phantom: block %d not saved (see the warning above)', block); %#ok<AGROW>
    elseif phantom.file_count(block) == 0 || phantom.file_bytes(block) < MIN_PHANTOM_BYTES
        problems{end + 1} = sprintf('Phantom: block %d saved but empty (%d file(s), %.1f MB) in %s', block, ...
                                    phantom.file_count(block), phantom.file_bytes(block) / 1e6, phantom.files{block}); %#ok<AGROW>
    end
    if isfield(phantom, 'gate_col') && ~isempty(phantom.gate_col) && isnan(phantom.rec_on_time_s(block))
        problems{end + 1} = sprintf('Phantom: Recording gate never went ON in block %d (did PCC record?)', block); %#ok<AGROW>
    end
end
end
