function tests = test_acquisition_problems
%TEST_ACQUISITION_PROBLEMS The end-of-trial checks run_session_unified reports.
tests = functiontests(localfunctions);
end

function testCleanTrialHasNoProblems(testCase)
verifyEmpty(testCase, acquisition_problems(cams(6035, 6035), ph(), 0.9));
end

function testCameraUnderTheFractionIsFlagged(testCase)
p = acquisition_problems(cams(3010, 6040), ph(), 0.9);
verifyEqual(testCase, numel(p), 1);
verifySubstring(testCase, p{1}, 'TopCamera: 3010 of ~6000 frames (50 %)');
end

function testCameraJustAboveTheFractionIsNotFlagged(testCase)
verifyEmpty(testCase, acquisition_problems(cams(5450, 5450), ph(), 0.9));
end

function testCameraWithNoFramesIsFlagged(testCase)
p = acquisition_problems(cams(6000, 0), ph(), 0.9);
verifyEqual(testCase, p, {'SideCamera: no frames written'});
end

function testEmptyCameraInfoIsSkipped(testCase)
verifyEmpty(testCase, acquisition_problems(struct(), ph(), 0.9));
verifyEmpty(testCase, acquisition_problems(struct('top', []), ph(), 0.9));
end

function testPhantomInitFailureIsFlagged(testCase)
p = ph(); p.init_error = 'no camera';
r = acquisition_problems(struct(), p, 0.9);
verifyEqual(testCase, r, {'Phantom: not recorded, init failed (no camera)'});
end

function testPhantomNotAttemptedIsNotFlagged(testCase)
p = ph(); p.attempted(1) = false; p.files{1} = '';
verifyEmpty(testCase, acquisition_problems(struct(), p, 0.9));
end

function testPhantomSaveFailureIsFlagged(testCase)
p = ph(); p.files{1} = '';
r = acquisition_problems(struct(), p, 0.9);
verifyEqual(testCase, numel(r), 1);
verifySubstring(testCase, r{1}, 'Phantom: block 1 not saved');
end

function testEmptyPhantomRecordingIsFlagged(testCase)
p = ph(); p.file_count(1) = 0; p.file_bytes(1) = 0;
r = acquisition_problems(struct(), p, 0.9);
verifyEqual(testCase, numel(r), 1);
verifySubstring(testCase, r{1}, 'Phantom: block 1 saved but empty (0 file(s), 0.0 MB)');
p.file_count(1) = 3; p.file_bytes(1) = 2e5;      % a few tiny files is still empty
r = acquisition_problems(struct(), p, 0.9);
verifySubstring(testCase, r{1}, 'saved but empty (3 file(s), 0.2 MB)');
end

function testRecordingGateNeverOnIsFlagged(testCase)
p = ph(); p.rec_on_time_s(1) = nan;
r = acquisition_problems(struct(), p, 0.9);
verifyEqual(testCase, numel(r), 1);
verifySubstring(testCase, r{1}, 'Recording gate never went ON in block 1');
p.gate_col = [];                                  % no gate wired: nothing to judge
verifyEmpty(testCase, acquisition_problems(struct(), p, 0.9));
end

function testEveryProblemIsListed(testCase)
p = ph(); p.files{1} = ''; p.rec_on_time_s(1) = nan;
r = acquisition_problems(cams(1000, 6000), p, 0.9);
verifyEqual(testCase, numel(r), 3);
end

%% ---- helpers -------------------------------------------------------------

function b = cams(topFrames, sideFrames)
b = struct('top',  struct('label', 'TopCamera',  'frames', topFrames,  'expected_frames', 6000), ...
           'side', struct('label', 'SideCamera', 'frames', sideFrames, 'expected_frames', 6000));
end

function p = ph()
% One block, Phantom expected and saved properly, Recording gate seen.
p = struct('init_error', '', 'attempted', true, 'files', {{'C:\x\trial_PhantomCamera'}}, ...
           'file_bytes', 4.2e9, 'file_count', 4000, 'gate_col', 13, 'rec_on_time_s', 19.584);
end
