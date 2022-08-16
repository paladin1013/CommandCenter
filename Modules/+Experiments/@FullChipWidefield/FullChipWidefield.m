classdef FullChipWidefield < Modules.Experiment
    %Automatically takes Lifetime at sites
    
    properties
        prefs = {'rangeX', 'rangeY'};
        current_experiment = [];
        autosave = [];

    end
    properties(SetAccess=private,Hidden)
        abort_request = false;
        data = [];
    end
    properties(SetObservable, GetObservable)
        experiment = Prefs.ModuleInstance(Experiments.ResonanceEMCCDonly.instance,'n',Inf,'inherits',{'Modules.Experiment'});
        
        scanner = Prefs.ModuleInstance(Drivers.FullChipScanner.instance, 'inherits', {'Modules.Driver'});
        wl = Prefs.ModuleInstance(Sources.WhiteLight_remote.instance, 'inherits', {'Modules.Source'});
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        rangeX = Prefs.Integer(1, 'min', -6, 'max', 6, 'help', 'Chiplet number (minus 1) to be scanned in x axis.');
        rangeY = Prefs.Integer(1, 'min', -6, 'max', 6, 'help', 'Chiplet number (minus 1) to be scanned in y axis.');
        resonatorStart = Prefs.Double(0, 'min', 0, 'max', 100, 'unit', '%', 'help', 'Start value of resonator percents sweep in each widefield scan. (will also run the reverse sequence)');
        resonatorEnd = Prefs.Double(10, 'min', 0, 'max', 100, 'unit', '%', 'help', 'End value of resonator percents sweep in each widefield scan. (will also run the reverse sequence)');
        resonatorPoints = Prefs.Integer(11, 'help', 'Total points of resonator percents sweep (one-way) in each widefield scan. (will also run the reverse sequence)');
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
            baseX = double(obj.scanner.x_pos);
            baseY = double(obj.scanner.y_pos);
            coordsX = zeros((abs(obj.rangeX)+1)*(abs(obj.rangeY)+1), 1);
            coordsY = zeros((abs(obj.rangeX)+1)*(abs(obj.rangeY)+1), 1);
            % Since moving along Y axis makes more changes to the altitude (piezo Z axis), we prefer to move along X axis first.
            cnt = 1;
            for k = 0:sign(obj.rangeY):obj.rangeY
                if mod(k, 2) == 0
                    startX = 0;
                    inc = sign(obj.rangeX);
                    endX = obj.rangeX;
                else
                    startX = obj.rangeX;
                    inc = -sign(obj.rangeX);
                    endX = 0;
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
            obj.autosave = Databases.AutoSave.instance;
            c = fix(clock);
            if strcmp(obj.autosave.exp_dir, "")
                obj.autosave.change_exp_dir;
            end
            [coordsX, coordsY] = obj.calcChipletCoordinates;
            nChiplets = (abs(obj.rangeX)+1)*(abs(obj.rangeY)+1);
            currentX = obj.scanner.x_pos;
            currentY = obj.scanner.y_pos;
            obj.data = cell(1, nChiplets);
            obj.experiment.skip_analysis = true;
            for k = 1:nChiplets
                assert(~obj.abort_request, 'User aborted.');
                try
                    obj.camera.stopVideo;
                end
                obj.wl.source_on = true;
                obj.wl.intensity = 100;
                obj.camera.exposure = 100;
                nextX = coordsX(k);
                nextY = coordsY(k);
                fprintf("Going to chiplet (%d, %d), %d/%d\n", nextX, nextY, k, nChiplets);
                if nextX ~= currentX
                    obj.scanner.x_pos = nextX;
                elseif nextY ~= currentY
                    obj.scanner.y_pos = nextY;
                end
                wl_img = obj.camera.snapImage;
                assert(~obj.abort_request, 'User aborted.');
                currentX = nextX;
                currentY = nextY;
                obj.wl.source_on = false;
                obj.camera.exposure = 500;
                obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorStart, obj.resonatorEnd, obj.resonatorPoints);
                obj.experiment.set_ROI_automatic(wl_img);
                obj.runExperiment(managers, obj.experiment, ax);
                data1 = obj.experiment.processed_data;
                assert(~obj.abort_request, 'User aborted.');
                obj.experiment.percents = sprintf("linspace(%d, %d, %d)", obj.resonatorEnd, obj.resonatorStart, obj.resonatorPoints);
                obj.runExperiment(managers, obj.experiment, ax);
                data2 = obj.experiment.processed_data;
                data = struct('coordX', currentX, 'coordY', currentY, 'data1', data1, 'data2', data2, 'wl', wl_img);
                obj.data{k} = data;
                mkdir(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3))));
                save(fullfile(obj.autosave.exp_dir, sprintf("Full_chip_widefield_data_%d_%d", c(2), c(3)), sprintf("Chiplet_%d.mat", k)), 'data');

            end
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
            dat.data = obj.data;
        end
        function UpdateRun(obj,~,~,ax)
        end
    end
end
