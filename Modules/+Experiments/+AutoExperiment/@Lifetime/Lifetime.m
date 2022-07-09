classdef Lifetime < Experiments.AutoExperiment.AutoExperiment_invisible
    %Spec automatically takes Lifetime at sites
    
    properties
        prerun_functions = {'preLifetime'};
        patch_functions = {''};
    end
    properties(Access=private)
        validROIRect; % Handle to imrect of validROI
        listeners;   % Listeners to valid ROI
        ax;
    end
    properties(SetObservable, GetObservable)
        enable_validROI = Prefs.Boolean(true);
        imageROI = zeros(2, 2);
        validROI = zeros(2, 2); % Only sites inside this area are valid
    end
    methods(Static)
        function obj = instance(varargin)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Experiments.AutoExperiment.Lifetime.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(varargin,Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Experiments.AutoExperiment.Lifetime(varargin{:});
            obj.singleton_id = varargin;
            Objects(end+1) = obj;
        end
        function [dx,dy,dz,metric] = Track(Imaging,Stage,track_thresh) 
            % Imaging = handle to active imaging module
            % Stage = handle to active stage module
            % track_thresh = true --> force track
            %                false --> return metric, but don't track
            %                numeric --> if metric <= track_thresh, track
            
            % tracker = Drivers.Tracker.instance(Stage,Stage.galvoDriver);
            dx = NaN;
            dy = NaN;
            dz = NaN;
            metric = NaN;
            try
                counter = Drivers.Counter.instance('APD1','APDgate');
                try
                    metric = counter.singleShot(tracker.dwell);
                catch err
                    counter.delete
                    rethrow(err)
                end
                counter.delete
                if (islogical(track_thresh) && track_thresh) || (~islogical(track_thresh) && metric < track_thresh)
                    currPosition = Stage.position;
                    % tracker.Track(false);
                    newPosition = Stage.position;
                    delta = newPosition-currPosition;
                    dx = delta(1);
                    dy = delta(2);
                    dz = delta(3);
                end
            catch err
                % tracker.delete;
                rethrow(err)
            end
            % tracker.delete;
        end
    end
    methods(Access=private)
        function obj = Lifetime()
            obj.experiments = Experiments.PulseSequenceSweep.LifetimeMeasurement.instance;
            obj.loadPrefs;
        end
    end
    methods
        function sites = AcquireSites(obj,managers)
            % sites = Experiments.AutoExperiment.AutoExperiment_invisible.SiteFinder_Confocal(managers,obj.imaging_source,obj.site_selection);
            % function sites = SiteFinder_Confocal(managers,imaging_source,site_selection)
                % Finds positions of peaks in image; if manual input, plots image and allows user input
                % Returns struct sites, with fields:
                %   image = image used in finding sites
                %   positions = [Nx2] array of positions
                %   manual_input = boolean, true if positions were user-supplied
                %   meta = empty if manual_input, else UserData from imfindpeaks
            persistent last_path
            if isempty(last_path)
                last_path = '';
            end
            sites = struct('image',[],'positions',[],'input_method',obj.site_selection,'meta',[]);

            if strcmp(obj.site_selection,'Load from file')
                [file,path] = uigetfile('*.mat','Site Selection',last_path);
                    if isequal(file,0)
                        error('Site selection aborted')
                    else
                        last_path = path;
                        temp = load(fullfile(path,file));
                        f = fieldnames(temp);
                        assert(numel(f)==1,...
                            sprintf('The mat file containing sites should only contain a single variable, found:\n\n%s',...
                            strjoin(f,', ')))
                        sites.positions = temp.(f{1});
                        sites.meta.path = fullfile(path,file);
                        recvd = num2str(size(sites.positions),'%i, ');
                        assert(size(sites.positions,2)==2,...
                            sprintf('Only supports loading x, y coordinates (expected Nx2 array, received [%s]).',recvd(1:end-1)));
                    end
                sites.positions = [sites.positions, NaN(size(sites.positions,1),1)];
                return
            end

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
            obj.ax = ax_temp;
             if obj.enable_validROI
                obj.validROI = sites.image.ROI;
                obj.imageROI = sites.image.ROI;
                xmin = obj.validROI(1,1);
                xmax = obj.validROI(1,2);
                ymin = obj.validROI(2,1);
                ymax = obj.validROI(2,2);
                obj.listeners = addlistener(obj, 'validROI', 'PostSet', @obj.updateROI);
                obj.validROIRect = imrect(ax_temp,[xmin,ymin,xmax-xmin,ymax-ymin]);
                obj.validROIRect.Deletable = false;
                obj.validROIRect.setColor('b');
                obj.validROIRect.setPositionConstraintFcn(@obj.constrainROI);
                validROIGroup = findall(ax_temp,'tag','imrect');
                for i = 1:length(validROIGroup.Children)
                    callback = validROIGroup.Children(i).ButtonDownFcn;
                    validROIGroup.Children(i).ButtonDownFcn = @(a,b)obj.prepROI(a,b,callback);
                end
            end
            switch obj.site_selection
                case 'Peak finder'
                    title('Drag red region to set thresholds, then close adjustment window when done.')
                    [scatterH,panelH] = imfindpeaks(imH); %returns array of NV locations
                    uiwait(panelH);
                    sites.positions = [scatterH.XData',scatterH.YData'];
                    sites.meta = scatterH.UserData;
                case 'Grid'
                    sites = Experiments.AutoExperiment.AutoExperiment_invisible.select_grid_sites(sites,ax_temp);
                case 'Manual sites'
                    title(sprintf('Click on all positions\nDrag to adjust\nRight click on point to get menu to delete.\n\nRight click on image to finish (DO NOT CLOSE!)'))
                    imH.UserData.h = [];
                    imH.ButtonDownFcn = @im_clicked;
                    uiwait(f);
                    sites.positions = NaN(0,2);
                    for i = 1:length(imH.UserData.h)
                        if isvalid(imH.UserData.h(i))
                            sites.positions(end+1,:) = imH.UserData.h(i).getPosition;
                        end
                    end
            end
            % Add in column of NaNs for Z (this will prevent setting Z when
            % moving to emitter position; Track can still modify global Z
            % if desired.
            sites.positions = [sites.positions, NaN(size(sites.positions,1),1)];
            sites.validROI = obj.validROI;

            close(f)
            assert(~isempty(sites.positions),'No positions!')
            function im_clicked(hObj,eventdata)
                if eventdata.Button ~= 1
                    uiresume;
                    return
                end
                h = impoint(hObj.Parent,eventdata.IntersectionPoint(1:2));
                if isempty(hObj.UserData.h)
                    hObj.UserData.h = h;
                else
                    hObj.UserData.h(end+1) = h;
                end
            end
        end
        
        function updateROI(obj,varargin)
            % Updates imrect from imager ROI change
            roi = obj.validROI;
            xmin = roi(1,1);
            xmax = roi(1,2);
            ymin = roi(2,1);
            ymax = roi(2,2);
            pos = [xmin,ymin,xmax-xmin,ymax-ymin];
            obj.validROIRect.setPosition(pos);
        end
        function pos = constrainROI(obj,pos,varargin)
            maxROI = obj.imageROI;
            roi(1,1) = min(max(maxROI(1,1),pos(1)),maxROI(1,2));
            roi(1,2) = max(min(maxROI(1,2),pos(1)+pos(3)),maxROI(1,1));
            roi(2,1) = min(max(maxROI(2,1),pos(2)),maxROI(2,2));
            roi(2,2) = max(min(maxROI(2,2),pos(2)+pos(4)),maxROI(2,1));
            pos(1) = roi(1,1);
            pos(2) = roi(2,1);
            pos(3) = roi(1,2)-roi(1,1);
            pos(4) = roi(2,2)-roi(2,1);
        end
        function prepROI(obj,hObj,eventdata,callback)
            f = Base.getParentFigure(obj.ax);
            callback(hObj,eventdata);  % This assigns its own WindowButtonUpFcn
            ButtonUp = f.WindowButtonUpFcn;
            f.WindowButtonUpFcn = @(a,b)obj.newROI(a,b,ButtonUp);
        end
        function newROI(obj,hObj,eventdata,callback)
            % Should be called on WindowButtonUpFcn
            % Updates imager's ROI from imrect change
            m_type = get(hObj,'selectionType');
            hObj.WindowButtonUpFcn = '';
            if strcmp(m_type,'normal')
                callback(hObj,eventdata);
                pos = obj.validROIRect.getPosition;
                xmin = pos(1);
                xmax = pos(1)+pos(3);
                ymin = pos(2);
                ymax = pos(2)+pos(4);
                obj.validROI = [xmin,xmax;ymin,ymax]; % This should call obj.updateROI from listener
            end
        end
        function PreRun(obj,status,managers,ax)
            %turn laser on before running
            obj.imaging_source.on;
            managers.Path.select_path('APD1'); %this may be unnecessary
        end
        function PostRun(obj,status,managers,ax)
            %turn laser off after running
            obj.imaging_source.off;
        end
        function preLifetime(obj,exp)
            obj.imaging_source.on;
        end
    end
end
