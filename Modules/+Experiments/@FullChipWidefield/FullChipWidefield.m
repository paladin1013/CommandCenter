classdef FullChipWidefield < Modules.Experiment
    %Automatically takes Lifetime at sites
    
    properties
        prefs = {'rangeX', 'rangeY', 'resonatorStart', 'resonatorEnd', 'resonatorPoints', 'resonatorReverse', 'sweepRounds', 'sweepStart', 'sweepEnd', 'useScannerOrigin', 'previewChiplets'};
        current_experiment = [];
        autosave = [];

    end
    properties(SetAccess=private,Hidden)
        abort_request = false;
        data = [];
        meta = [];
    end
    properties(SetObservable, GetObservable)
        experiment = Prefs.ModuleInstance(Experiments.ResonanceEMCCDonly.instance,'n',Inf,'inherits',{'Modules.Experiment'});
        
        scanner = Prefs.ModuleInstance(Drivers.FullChipScanner.instance, 'inherits', {'Modules.Driver'});
        wl = Prefs.ModuleInstance(Sources.WhiteLight_remote.instance, 'inherits', {'Modules.Source'});
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        rangeX = Prefs.Integer(3, 'min', -6, 'max', 6, 'help', 'Chiplet number (minus 1) to be scanned in x axis.');
        rangeY = Prefs.Integer(3, 'min', -6, 'max', 6, 'help', 'Chiplet number (minus 1) to be scanned in y axis.');
        resonatorStart = Prefs.Double(0, 'min', 0, 'max', 100, 'unit', '%', 'help', 'Start value of resonator percents sweep in each widefield scan. (will also run the reverse sequence)');
        resonatorEnd = Prefs.Double(100, 'min', 0, 'max', 100, 'unit', '%', 'help', 'End value of resonator percents sweep in each widefield scan. (will also run the reverse sequence)');
        resonatorPoints = Prefs.Integer(1001, 'help', 'Total points of resonator percents sweep (one-way) in each widefield scan. (will also run the reverse sequence)');
        resonatorReverse = Prefs.Boolean(false, 'help', 'Reverse the resonator percent sequence.')
        sweepRounds = Prefs.Integer(1, 'min', 1, 'help', 'Sweep how many rounds on a single chiplet.');
        sweepStart = Prefs.Integer(1, 'min', 1, 'help', 'Start sweep from this chiplet.')
        sweepEnd = Prefs.Integer(16, 'help', 'Sweep until this chiplet. This value should be no more than (abs(rangeX)+1)*(abs(rangeY)+1)');
        disableAlignment = Prefs.Boolean(false, 'help', 'Will disable the recognizing and alignment step and only keep the measurement');
        useScannerOrigin = Prefs.Boolean(true, 'help', 'Use the origin of FullChipScanner as the (0, 0) of the experiment. If set to false, will use the current scanner position as the origion.');
        previewChiplets = Prefs.Boolean(true, 'help', 'Will go through all chiplets to make sure `FullChipScanner` is functioning well.');
        previewDone = Prefs.Boolean(false, 'help', 'Finished previewing chiplet.')
    end
    methods(Static)
        obj = instance();
    end
    methods(Access=private)
        function obj = FullChipWidefield()
            obj.loadPrefs;
            obj.experiment = Experiments.ResonanceEMCCDonly.instance;
        end
    end
    methods

        function [coordsX, coordsY] = calcChipletCoordinates(obj)
            if obj.useScannerOrigin
                baseX = 0;
                baseY = 0;
            else
                baseX = double(obj.scanner.x_pos);
                baseY = double(obj.scanner.y_pos);
            end
            coordsX = zeros((abs(obj.rangeX)+1)*(abs(obj.rangeY)+1), 1);
            coordsY = zeros((abs(obj.rangeX)+1)*(abs(obj.rangeY)+1), 1);
            % Since moving along Y axis makes more changes to the altitude (piezo Z axis), we prefer to move along X axis first.
            cnt = 1;
            step = sign(obj.rangeY);
            if step == 0
                step = 1;
            end
            for k = 0:step:obj.rangeY
                if mod(k, 2) == 0
                    startX = 0;
                    inc = sign(obj.rangeX);
                    endX = obj.rangeX;
                else
                    startX = obj.rangeX;
                    inc = -sign(obj.rangeX);
                    endX = 0;
                end
                if inc == 0
                    inc = 1;
                end
                for l = startX:inc:endX
                    coordsX(cnt) = l;
                    coordsY(cnt) = k;
                    cnt = cnt + 1;
                end
            end
            coordsX = coordsX + baseX;
            coordsY = coordsY + baseY;


        end
        
        function run(obj,statusH,managers,ax)
            if check_call_stack_func('grabFrame')
                error('Please stop Video then start the experiment.');
            end
            
            if obj.resonatorReverse
                resp = questdlg('Are you sure to reverse resonator percentscanning?');
                if ~strcmp(resp, "Yes")
                    error("Please cancel `resonatorReverse`.")
                end 
            end

            if ~obj.experiment.use_powermeter
                resp = questdlg('Are you sure not to read powermeter data?');
                if ~strcmp(resp, "Yes")
                    error("Please set `use_powermeter` in `ResonanceEMCCDonly` to true.")
                end 
            end

            if obj.experiment.use_powermeter
                obj.experiment.test_powermeter;
            end

            if obj.experiment.wavemeter_override
                try
                    obj.experiment.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu',obj.experiment.wavemeter_channel,true);
                    obj.experiment.wavemeter.SetSwitcherSignalState(1);
                catch err
                    warning(err.message);
                    obj.experiment.wavemeter.delete;
                    obj.experiment.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu',obj.experiment.wavemeter_channel,true);
                end
            end
            handles = managers.handles;
            set(handles.panel_im,'position',[0 0 0.5 handles.AxesPanelsH],'visible','on')
            set(handles.panel_exp,'position',[0.5 0 0.5 handles.AxesPanelsH],'visible','on')
            handles.AxesPanels.enable = 'on';
            handles.AxesPanels.type = 'horizontal';
            if obj.camera.continuous
                obj.camera.stopVideo
            end
            timers = timerfindall;
            for k = 1:length(timers)
                if strcmp(timers(k).tag, 'Video Timer')
                    % There exists other timers generated by `Imaging.startVideo`
                    if strcmp(timers(k).Running, 'on')
                        stop(timers(k)); % Stop all other timers
                    end
                    delete(timers(k));
                end
            end


            obj.abort_request = false;
            obj.autosave = Databases.AutoSave.instance;
            c = fix(clock);
            if strcmp(obj.autosave.exp_dir, "")
                obj.autosave.change_exp_dir;
            end
            [coordsX, coordsY] = obj.calcChipletCoordinates;
            chipletStart = max(1, obj.sweepStart);
            nChiplets = (abs(obj.rangeX)+1)*(abs(obj.rangeY)+1);
            chipletEnd = min(nChiplets, obj.sweepEnd);
            assert(chipletStart <= chipletEnd, "obj.sweepStart should be no more than obj.sweepEnd");
            obj.scanner.disable_movement = false;
            coordX = obj.scanner.x_pos;
            coordY = obj.scanner.y_pos;
            obj.experiment.skip_analysis = true;

            if obj.previewChiplets
                if ~obj.previewDone
                    for k = chipletStart:chipletEnd
                        assert(~obj.abort_request, 'User aborted.');
                        obj.wl.source_on = true;
                        obj.wl.intensity = 100;
                        obj.camera.exposure = 100;
                        nextX = coordsX(k);
                        nextY = coordsY(k);
                        fprintf("Preview: Going to chiplet (%d, %d), %d/%d\n", nextX, nextY, k-chipletStart+1, chipletEnd-chipletStart+1);
                        if nextX ~= coordX % Move one step at a time, until scanner reaches the starting chiplet. 
                            while nextX > obj.scanner.x_pos
                                obj.scanner.x_pos = obj.scanner.x_pos+1;
                            end
                            while nextX < obj.scanner.x_pos
                                obj.scanner.x_pos = obj.scanner.x_pos-1;
                            end
                        elseif nextY ~= coordY
                            while nextY > obj.scanner.y_pos
                                obj.scanner.y_pos = obj.scanner.y_pos + 1;
                            end
                            while nextY < obj.scanner.y_pos
                                obj.scanner.y_pos = obj.scanner.y_pos - 1;
                            end
                        else % Is already at the correct position: still need to align chiplet with laser
                            obj.scanner.x_pos = nextX;
                        end
                        if k ~= chipletStart && obj.scanner.x_pos == coordsX(k-1) && obj.scanner.y_pos == coordsY(k-1) 
                            obj.abort_request = true;
                            error("Chiplet Scanner did not move. Abort.");
                        end


                        coordX = nextX;
                        coordY = nextY;
                        dirName = fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)));
                        if ~exist(dirName, 'dir')
                            mkdir(dirName);
                        end
                        wl_img = obj.camera.snapImage;
                        figH = figure;
                        axH = axes('Parent', figH);
                        imH = imagesc(axH, wl_img);
                        colormap('bone');
                        saveas(axH, fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)),  sprintf("chiplet%d_wl_preview.png", k)));
                    end
                    obj.previewDone = true;
                end 
                for k = chipletEnd:-1:chipletStart
                    assert(~obj.abort_request, 'User aborted.');
                    obj.wl.source_on = true;
                    obj.wl.intensity = 100;
                    obj.camera.exposure = 100; 
                    nextX = coordsX(k);
                    nextY = coordsY(k);
                    fprintf("Widefield Measurement: Going to chiplet (%d, %d), %d/%d\n", nextX, nextY, chipletEnd-k+1, chipletEnd-chipletStart+1);
                    if nextX ~= coordX
                        obj.scanner.x_pos = nextX;
                    else
                        obj.scanner.y_pos = nextY;
                    end
                    if k ~= chipletEnd && obj.scanner.x_pos == coordsX(k+1) && obj.scanner.y_pos == coordsY(k+1) 
                        obj.abort_request = true;
                        error("Chiplet Scanner did not move. Abort.");
                    end
                    mkdir(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3))));
                    wl_img = obj.camera.snapImage;
                    figH = figure;
                    axH = axes('Parent', figH);
                    imH = imagesc(axH, wl_img);
                    colormap('bone');
                    saveas(axH, fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)),  sprintf("chiplet%d_wl.png", k)));
                    save(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)),  sprintf("chiplet%d_wl.mat", k)), 'wl_img');

                    coordX = nextX;
                    coordY = nextY;
                    obj.wl.source_on = false;
                    obj.experiment.set_ROI_automatic(wl_img);
                    widefieldData = cell(1, obj.sweepRounds);
                    for l = 1:obj.sweepRounds
                        if ~obj.resonatorReverse % Begin from the `resonatorStart`
                            obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorStart, obj.resonatorEnd, obj.resonatorPoints);
                        else
                            obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorEnd, obj.resonatorStart, obj.resonatorPoints);
                        end
                        obj.runExperiment(managers, obj.experiment, ax);
                        widefieldData{l} = obj.experiment.processed_data;
                        assert(~obj.abort_request, 'User aborted.');
                        obj.resonatorReverse = ~obj.resonatorReverse;
                    end
                    data = struct('coordX', coordX, 'coordY', coordY, 'widefieldData', widefieldData, 'wl_img', wl_img);
                    wait = msgbox('Please wait, CommandCenter is saving data.');
                    stagePos = obj.scanner.current_position_um;
                    save(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)), sprintf("chiplet%d.mat", k)), 'coordX', 'coordY', 'widefieldData', 'wl_img', 'stagePos');
                    try
                        delete(wait);
                    end
                end
            else
                for k = chipletStart:chipletEnd
                    assert(~obj.abort_request, 'User aborted.');
                    obj.wl.source_on = true;
                    obj.wl.intensity = 100;
                    obj.camera.exposure = 100; 
                    nextX = coordsX(k);
                    nextY = coordsY(k);
                    fprintf("Widefield Measurement: Going to chiplet (%d, %d), %d/%d\n", nextX, nextY, k-chipletStart+1, chipletEnd-chipletStart+1);
                    if nextX ~= coordX
                        obj.scanner.x_pos = nextX;
                    else
                        obj.scanner.y_pos = nextY;
                    end
                    if k ~= chipletStart && obj.scanner.x_pos == coordsX(k-1) && obj.scanner.y_pos == coordsY(k-1) 
                        obj.abort_request = true;
                        error("Chiplet Scanner did not move. Abort.");
                    end
                    assert(~obj.abort_request, 'User aborted.');
                    mkdir(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3))));
                    wl_img = obj.camera.snapImage;
                    figH = figure;
                    axH = axes('Parent', figH);
                    imH = imagesc(axH, wl_img);
                    colormap('bone');
                    saveas(axH, fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)),  sprintf("chiplet%d_wl.png", k)));
                    save(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)),  sprintf("chiplet%d_wl.mat", k)), 'wl_img');

                    coordX = nextX;
                    coordY = nextY;
                    obj.wl.source_on = false;
                    obj.experiment.set_ROI_automatic(wl_img);
                    widefieldData = cell(1, obj.sweepRounds);
                    assert(~obj.abort_request, 'User aborted.');
                    for l = 1:obj.sweepRounds
                        if ~obj.resonatorReverse % Begin from the `resonatorStart`
                            obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorStart, obj.resonatorEnd, obj.resonatorPoints);
                        else
                            obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorEnd, obj.resonatorStart, obj.resonatorPoints);
                        end
                        obj.runExperiment(managers, obj.experiment, ax);
                        widefieldData{l} = obj.experiment.processed_data;
                        assert(~obj.abort_request, 'User aborted.');
                        obj.resonatorReverse = ~obj.resonatorReverse;
                    end
                    data = struct('coordX', coordX, 'coordY', coordY, 'widefieldData', widefieldData, 'wl_img', wl_img);
                    wait = msgbox('Please Wait, CommandCenter is saving data.');
                    stagePos = obj.scanner.current_position_um;
                    save(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)), sprintf("chiplet%d.mat", k)), 'coordX', 'coordY', 'widefieldData', 'wl_img', 'stagePos');
                    try
                        delete(wait);
                    end
                end
            end
            obj.previewDone = false;
        end
        
        function runExperiment(obj,managers,experiment,ax)
            [abortBox,abortH] = ExperimentManager.abortBox(class(experiment),@(~,~)obj.abort);
            try
                drawnow; assert(~obj.abort_request,'User aborted');
                obj.current_experiment = experiment;
                experiment.run(abortBox,managers,ax);
                obj.current_experiment = [];
            catch exp_err
                delete(abortH);
                rethrow(exp_err)
            end
            delete(abortH);
        end

        function PreRun(obj,status,managers,ax)

        end
        
        function PostRun(obj,status,managers,ax)

        end
        

        function abort(obj)
            obj.abort_request = true;
            if ~isempty(obj.experiment)
                obj.experiment.abort;
            end
            obj.logger.log('Abort requested');
        end
        function dat = GetData(obj,~,~)
            % Callback for saving methods (note, lots more info in the two managers input!)
            dat = [];
            for i=1:length(obj.prefs)
                obj.meta = setfield(obj.meta,obj.prefs{i},getfield(obj,obj.prefs{i}));
            end
            
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
        function UpdateRun(obj,~,~,ax)
        end
    end
end
