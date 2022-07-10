classdef Lifetime < Experiments.AutoExperiment.AutoExperiment_invisible
    %Spec automatically takes Lifetime at sites
    
    properties
        prerun_functions = {''};
        patch_functions = {''};
    end
    properties(Access=private)
        validROIRect; % Handle to imrect of validROI
        listeners;   % Listeners to valid ROI
        axH;            % Handle to axes (children of figH)
        imH;            % Handle to image (children of axH)
        ax2H;           % Handle to axes (children of figH)
        sitesH;         % Handle to sites scatter plot (children of ax2H)
    end
    properties(SetObservable, GetObservable)
        enableValidROI = Prefs.Boolean(true);
        imageROI = zeros(2, 2);
        validROI = zeros(2, 2); % Only sites inside this area are valid

        % struct of external input sites (eg. EMCCD wide field scan)
            % relPos (2*N): relative position based on validROI, 
            % wavelengths_nm (1*N): resonant wavelengths_nm of each emitter 
        externalSites = struct('relPos', [], 'wavelengths_nm', []); 
        figH;           % Handle to figure

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
            obj.experiments = Experiments.SlowScan.Open.instance;
            obj.imaging_source = Sources.Cobolt_PB.instance;
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
                source_on = obj.imaging_source.source_on;
                obj.imaging_source.on;
                sites.image = managers.Imaging.snap; %take image snapshot
                if ~source_on
                    obj.imaging_source.off;
                end
            else
                sites.image = managers.Imaging.current_image.info;
            end

            obj.figH = figure;
            obj.axH = axes('parent',obj.figH);
            obj.ax2H = axes('parent',obj.figH); % For sites scatter plot
            obj.sitesH = scatter(obj.ax2H, [], []);
            cbH = colorbar(obj.ax2H);
            cbH.Visible = 'off';
            colormap(obj.ax2H, 'jet');
            obj.ax2H.Visible = 'off';
            axis(obj.ax2H, 'equal');
            linkaxes([obj.axH, obj.ax2H]);
            % set([obj.axH, obj.ax2H], 'Position', [0.1, 0.1, 0.8, 0.8])
            obj.ax2H.Position = obj.axH.Position;
           

            obj.imH = imagesc(sites.image.ROI(1,:),sites.image.ROI(2,:),sites.image.image,'parent',obj.axH);
            colormap(obj.axH,managers.Imaging.set_colormap);
            set(obj.axH,'ydir','normal')
            axis(obj.axH,'image')
            obj.validROI = sites.image.ROI;
            obj.imageROI = sites.image.ROI;
            xmin = obj.validROI(1,1);
            xmax = obj.validROI(1,2);
            ymin = obj.validROI(2,1);
            ymax = obj.validROI(2,2);
            obj.listeners = addlistener(obj, 'validROI', 'PostSet', @obj.updateROI);
            obj.listeners(2) = addlistener(obj, 'externalSites', 'PostSet', @obj.updateExternalSites);
            obj.listeners(3) = addlistener(obj.figH, 'LocationChanged', @obj.adjustMarkerSize);
            obj.validROIRect = imrect(obj.axH,[xmin,ymin,xmax-xmin,ymax-ymin]);
            obj.validROIRect.Deletable = false;
            obj.validROIRect.setColor('b');
            obj.validROIRect.setPositionConstraintFcn(@obj.constrainROI);
            validROIGroup = findall(obj.axH,'tag','imrect');
            for i = 1:length(validROIGroup.Children)
                callback = validROIGroup.Children(i).ButtonDownFcn;
                validROIGroup.Children(i).ButtonDownFcn = @(a,b)obj.prepROI(a,b,callback);
            end
            % Just for debug tests
            obj.externalSites.relPos = [[0.5, 0.25, 0.75, 0.25, 0.75]; [0.5, 0.25, 0.75, 0.75, 0.25]];
            obj.externalSites.wavelengths_nm = [619, 619.2, 619.4, 619.6, 619.8];
            uiwait(obj.figH);

            %         title(sprintf('Click on all positions\nDrag to adjust\nRight click on point to get menu to delete.\n\nRight click on image to finish (DO NOT CLOSE!)'))
            %         obj.imH.UserData.h = [];
            %         obj.imH.ButtonDownFcn = @im_clicked;
            %         uiwait(obj.figH);
            %         sites.positions = NaN(0,2);
            %         for i = 1:length(obj.imH.UserData.h)
            %             if isvalid(obj.imH.UserData.h(i))
            %                 sites.positions(end+1,:) = obj.imH.UserData.h(i).getPosition;
            %             end
            %         end
            sites.positions = [sites.positions, NaN(size(sites.positions,1),1)];
            sites.validROI = obj.validROI;

            close(obj.figH)
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
        function updateExternalSites(obj, hObj, eventdata)
            N = size(obj.externalSites.relPos, 2);
            assert(size(obj.externalSites.relPos, 1) == 2, sprintf("Size of obj.externalSites.resPos should be 2*N (N=%d)", N));

            if isempty(obj.externalSites.wavelengths_nm) || all(size(obj.externalSites.wavelengths_nm) == [1, N])
                % hold(obj.axH, 'on') 
                xrel = obj.externalSites.relPos(1, :);
                yrel = obj.externalSites.relPos(2, :);
                xmin = obj.validROI(1,1);
                xmax = obj.validROI(1,2);
                ymin = obj.validROI(2,1);
                ymax = obj.validROI(2,2);
                xabs = xmin+xrel*(xmax-xmin);
                yabs = ymin+yrel*(ymax-ymin);
                obj.sitesH.XData = xabs;
                obj.sitesH.YData = yabs;
                obj.sitesH.SizeData = ones(1, N)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
                cbh = obj.ax2H.Colorbar;
                if  ~all(size(obj.externalSites.wavelengths_nm) == [1, N])
                    % Draw scatter plot with frequency
                    cbh.Visible = 'off';
                    obj.sitesH.CData = zeros(1, N);
                else
                    % Draw scatter plot without frequency
                    wls = obj.externalSites.wavelengths_nm;
                    cbh.Visible = 'on';
                    obj.sitesH.CData = wls;
                    ylabel(cbh, 'Resonance wavelength (nm)', 'Rotation', 90);
                    cbh.Label.Position(1) = 3;
                    if min(wls)< max(wls)
                        caxis(obj.ax2H, [min(wls), max(wls)]);
                    end
                end
                obj.ax2H.Visible = 'off';
                drawnow;
            end
            
        end

        function adjustMarkerSize(obj, hObj, eventData)
            if ~isempty(obj.sitesH)
                N = size(obj.externalSites.relPos, 2);
                obj.sitesH.SizeData = ones(1, N)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
            end
        end

        function locateSites(obj)
            
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
            obj.updateExternalSites;
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
            f = Base.getParentFigure(obj.axH);
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
    end
end
