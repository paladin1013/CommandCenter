classdef AutoExperiment_invisible < Modules.Experiment
    % AutoExperiment_invisible is the superclass for looping through experiments
    % across many emitters.
    %
    % Subclasses need to create the abstract patch_functions property and
    % assign the "experiments" property in the constructor. The
    % AcquireSites abstract method must also be created. Subclasses may
    % find it useful to take advantage of some static helper methods
    % defined here as well.
    
    properties
        prefs = {'run_type','site_selection','tracking_threshold','min_tracking_seconds','max_tracking_seconds','imaging_source','repeat'};
        show_prefs = {'experiments','run_type','site_selection','tracking_threshold','min_tracking_seconds','max_tracking_seconds','imaging_source','repeat'};
        readonly_prefs = {'experiments'};
    end
    properties(Abstract)
        patch_functions %cell array of method names in subclass definition that take input (emitter,prefs)
    end
    properties(SetAccess=protected,Hidden)
        data = [] % Useful for saving data from run method
        meta = [] % Useful to store meta data in run method
        tracker = zeros(1,6); %array of (# experiments)*(# sites) by 6 --> (dx,dy,dz,tracking metric,datenum time,site index)
        abort_request = false; % Flag that will be set to true upon abort
        err_thresh = 10; %if have err_thresh many errors during run, experiment overall will error and quit
    end
    properties(SetObservable, AbortSet)
        experiments = Modules.Experiment.empty(0); %array of experiment handles
        run_type = {Experiments.AutoExperiment.AutoExperiment_invisible.SITES_FIRST,...
                    Experiments.AutoExperiment.AutoExperiment_invisible.EXPERIMENTS_FIRST};
        site_selection = {'Peak finder','Grid','Manual sites'};
        imaging_source = Modules.Source.empty(1,0);
        tracking_threshold = 0.9; %tracking metric will be normalized to 1
        min_tracking_seconds = 0; %in seconds; tracker won't run twice within this amount of time
        max_tracking_seconds = Inf; %in seconds; if tracking_threshold isn't hit, tracker will still run after this amount of time
        current_experiment = []; %this will be a copy of the handle to the current experiment, to be used for passing things like aborts between experiments
        repeat = 1;
    end
    properties(Constant)
        SITES_FIRST = 'All Sites First';
        EXPERIMENTS_FIRST = 'All Experiments First';
    end
    methods(Static)
        function sites = SiteFinder_Confocal(managers,imaging_source,site_selection)
            % Finds positions of peaks in image; if manual input, plots image and allows user input
            % Returns struct sites, with fields:
            %   image = image used in finding sites
            %   positions = [Nx2] array of positions
            %   manual_input = boolean, true if positions were user-supplied
            %   meta = empty if manual_input, else UserData from imfindpeaks
            sites = struct('image',[],'positions',[],'input_method',site_selection,'meta',[]);
            if isempty(managers.Imaging.current_image)
                source_on = imaging_source.source_on;
                imaging_source.on;
                sites.image = managers.Imaging.snap; %take image snapshot
                if ~source_on
                    imaging_source.off;
                end
            else
                sites.image = managers.Imaging.current_image.info;
            end
            
            f = figure;
            ax_temp = axes('parent',f);
            imH = imagesc(sites.image.ROI(1,:),sites.image.ROI(2,:),sites.image.image,'parent',ax_temp);
            colormap(ax_temp,managers.Imaging.set_colormap);
            set(ax_temp,'ydir','normal')
            axis(ax_temp,'image') 
            switch site_selection
                case 'Peak finder'
                    title('Drag red region to set thresholds, then close adjustment window when done.')
                    [scatterH,panelH] = imfindpeaks(imH); %returns array of NV locations
                    uiwait(panelH);
                    sites.positions = [scatterH.XData',scatterH.YData'];
                    sites.meta = scatterH.UserData;
                case 'Grid'
                    sites = obj.select_grid_sites(sites,ax_temp);
                case 'Manual sites'
                    title('Click on all positions, then hit enter when done.')
                    sites.positions = ginput();
            end
            close(f)
            assert(~isempty(sites.positions),'No positions!')
        end
        sites = select_grid_sites(sites,ax_temp)
        varargout = view(varargin);
        function [dx,dy,dz,metric] = Track(Imaging,Stages,thresh)
            %this runs at end of each experiment and should return:
            %   dx = change in x
            %   dy = change in x
            %   dz = change in x
            %   metric = whatever metric used to track (e.g. fluorescence)
            dx = NaN;
            dy = NaN;
            dz = NaN;
            metric = NaN;
        end
    end

    methods
        function obj = AutoExperiment_invisible()
            obj.run_type = obj.SITES_FIRST;
            obj.loadPrefs;
            assert(all(cellfun(@(x)ismethod(obj,x),obj.patch_functions)),'One or more named patch_function do not have corresponding methods.') %make sure all patch funcitons are valid
        end
        run(obj,statusH,managers,ax)
        function delete(obj)
        end
        function abort(obj)
            obj.abort_request = true;
            if ~isempty(obj.current_experiment)
                obj.current_experiment.abort;
            end
            obj.logger.log('Abort requested');
        end
        function pause(obj,~,~)
            obj.pause_request = true;
            obj.logger.log('Pause requested');
        end
        function dat = GetData(obj,~,~)
            % Callback for saving methods
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
        function PreRun(obj,status,managers,ax)
        end
        function PostRun(obj,status,managers,ax)
        end
    end
    methods(Abstract)
        sites = AcquireSites(obj,managers)
    end
end
