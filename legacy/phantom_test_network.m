function phantom_path_and_poll_debug()
    fprintf('\n--- PATH RESOLUTION ---\n');
    disp('LoadPhantomLibraries:'); disp(which('-all','LoadPhantomLibraries'));
    disp('PoolBuilder:');         disp(which('-all','PoolBuilder'));
    disp('PoolRefresher:');       disp(which('-all','PoolRefresher'));
    disp('PhDemoMatlab:');        disp(which('-all','PhDemoMatlab'));

    % Force same folder as demo (if present)
    demoFile = which('PhDemoMatlab');
    if ~isempty(demoFile)
        sdkRoot = fileparts(demoFile);
        addpath(genpath(sdkRoot));
        rehash; clear classes;
        fprintf('\nForced addpath(genpath(%s))\n', sdkRoot);
    end

    fprintf('\n--- CAMERA POLL (5s) ---\n');
    LoadPhantomLibraries();
    pb = PoolBuilder([]); pb.Register();
    pr = PoolRefresher();

    t0 = tic;
    while toc(t0) < 5
        pr.RefreshCameras();
        n = pr.GetCameraListLength();
        fprintf('n=%d\n', n);
        for i = 1:n
            c = pr.GetCameraAt(i);
            fprintf('  [%d] %s\n', i, c.ToString());
        end
        pause(0.5);
    end

    try, if pb.IsRegistered, pb.Unregister(); end, catch, end
    try, pr.delete(); catch, end
    try, pb.delete(); catch, end
    UnloadPhantomLibraries();
end
