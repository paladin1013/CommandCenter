classdef Lifetime < Experiments.AutoExperiment.AutoExperiment_invisible
    %Spec automatically takes Lifetime at sites
    
    properties
        prerun_functions = {''};
        patch_functions = {''};
    end
    properties(Access=private)
        validROIRect; % Handle to imrect of validROI
        listeners = {}; % Handle of listeners
        axH;            % Handle to axes (children of figH)
        imH;            % Handle to image (children of axH)
        ax2H;           % Handle to axes (children of figH)
        sitesH;         % Handle to sites scatter plot (children of ax2H)
        sites;          % sites data
    end
    properties(SetObservable, GetObservable)
        imageROI = zeros(2, 2);
        validROI = zeros(2, 2); % Only sites inside this area are valid

        % struct of external input sites (eg. EMCCD wide field scan)
            % relPos (N*2): relative position based on validROI, 
            % wavelengths_nm (N*1): resonant wavelengths_nm of each emitter 
        importedSites = struct('relPos', [], 'wavelengths_nm', [], 'relSize', []); 
        findedSites = struct('absPos', [], 'relSize', []); % For sites founded by `Peak finder`
        figH;           % Handle to figure
        finderH;        % Handle to peak finder results
        includeWavelength = Prefs.Boolean(false, 'help', 'Whether wavelength is considered in each site. Must be set to false to enable manually select');
        sitesFile = Prefs.File('filter_spec','*.mat','help','Data file to import sites coordinates and frequencies. Should contain field `data.relPos`, `data.wavelengths_nm`.',...
        'custom_validate','validate_sites_data');
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
            obj.site_selection = 'Peak finder';

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
                %   wavelengths_nm = [N]
                %   manual_input = boolean, true if positions were user-supplied
                %   meta = empty if manual_input, else UserData from imfindpeaks
            persistent last_path
            if isempty(last_path)
                last_path = '';
            end
            sites = struct('image',[],'positions',[],'input_method',obj.site_selection,'meta',[]);



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

            obj.figH = figure('Position', [500,  100, 1000, 1000]);
            obj.axH = axes('parent',obj.figH);
            obj.ax2H = axes('parent',obj.figH); % For sites scatter plot
            obj.sitesH = scatter(obj.ax2H, [], []);
            cbH = colorbar(obj.ax2H);
            cbH.Visible = 'off';
            colormap(obj.ax2H, 'jet');
            obj.ax2H.Visible = 'off';
            axis(obj.ax2H, 'equal');
            linkaxes([obj.axH, obj.ax2H]);
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
            obj.validROIRect = drawrectangle(obj.axH,'Position', [xmin,ymin,xmax-xmin,ymax-ymin], 'Color', 'b');
            obj.validROIRect.Deletable = false;
            obj.validROIRect.FaceAlpha = 0.1;
            obj.updateROI;
            obj.listeners{1} = addlistener(obj.validROIRect, 'ROIMoved', @obj.updateROI);
            obj.listeners{2} = addlistener(obj.figH, 'LocationChanged', @obj.adjustMarkerSize);

            if strcmp(obj.site_selection, 'Load from file')
                if isempty(obj.importedSites.relPos)
                    [file,path] = uigetfile('*.mat','Site Selection',last_path);
                    if isequal(file,0)
                        error('Site selection aborted')
                    else
                        last_path = path;
                        temp = load(fullfile(path,file));
                        data = temp.data;
                        assert(isfield(data, 'relPos'), "Imported site data file should contain field `relPos`\n");
                        assert(isfield(data, 'wavelengths_nm'), "Imported site data file should contain field `wavelengths_nm`\n");
                        obj.importedSites.relPos = data.relPos;
                        obj.importedSites.wavelengths_nm = data.wavelengths_nm;
                        if isfield(data, 'relSize')
                            obj.importedSites.relSize = data.relSize;
                        end
                    end
                end
                obj.listeners{3} = addlistener(obj, 'importedSites', 'PostSet', @obj.updateImportedSites);
                set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to fit the imported site region\nRight click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
            elseif strcmp(obj.site_selection, 'Peak finder')
                obj.listeners{3} = addlistener(obj, 'findedSites', 'PostSet', @obj.updateFindedSites);
                assert(obj.includeWavelength == false, "Peak finder mode does not support wavelength mode")
                title('Drag red region to set thresholds, then close adjustment window when done.')
                [obj.finderH,panelH] = imfindpeaks(obj.imH); %returns array of NV locations
                obj.finderH.Visible = 'off'; % Turn off finderH. Use obj.sitesH to display sites location
                obj.findedSites.absPos = [obj.finderH.XData', obj.finderH.YData'];
                obj.listeners{4} = addlistener(obj.finderH, 'YData', 'PostSet', @obj.updateFindedSites);
                set(get(obj.axH, 'Title'), 'String', sprintf('Move the contrast bar to find peaks\nClose the setting panel to confirm\n'));
                uiwait(panelH);
                set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to bound the active region\nRight click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
            end
            obj.imH.ButtonDownFcn = @im_clicked2; % Wait until next click
            uiwait(obj.figH);


            % Convert all scatter points into pointROI
            obj.imH.UserData.h = [];
            xabs = obj.sitesH.XData;
            yabs = obj.sitesH.YData;
            markerSize = obj.sitesH.SizeData;
            obj.sitesH.Visible = false;
            obj.validROIRect.Visible = 'off';

            if obj.includeWavelength
                wls = obj.importedSites.wavelengths_nm;
                wl_max = max(wls);
                wl_min = min(wls);
                cmap = colormap(obj.ax2H, 'jet');
                colors = cmap(floor((wls-wl_min)*255/(wl_max-wl_min)+1), :);
            end

            for k = 1:length(xabs)
                if obj.includeWavelength
                    h = drawpoint(obj.axH, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)/10, 'Color', colors(k, :));
                    h.UserData = wls(k);
                else
                    h = drawpoint(obj.axH, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)/10);
                end
                if isempty(obj.imH.UserData.h)
                    obj.imH.UserData.h = h;
                else
                    obj.imH.UserData.h(end+1) = h;
                end
            end
            if ~obj.includeWavelength
                title(sprintf('Drag to adjust\nLeft click to add new points\nRight click on point to get menu to delete.\nRight click on image to finish (DO NOT CLOSE!)'))
            else
                title(sprintf('Drag to adjust\nRight click on point to get menu to delete.\n\nRight click on image to finish (DO NOT CLOSE!)'))
            end
            
            obj.imH.ButtonDownFcn = @im_clicked;
            uiwait(obj.figH);


            % Save data to sites
            sites.positions = NaN(0,2);
            sites.wavelengths_nm = NaN(0, 1);
            for i = 1:length(obj.imH.UserData.h)
                if isvalid(obj.imH.UserData.h(i))
                    sites.positions(end+1,:) = obj.imH.UserData.h(i).Position;
                    if obj.includeWavelength
                        sites.wavelengths_nm(end+1,1) = obj.imH.UserData.h(i).UserData;
                    end
                end
            end
            sites.positions = [sites.positions, NaN(size(sites.positions,1),1)]; % Add z axis
            sites.validROI = obj.validROI;
            obj.sites = sites;

            close(obj.figH)
            assert(~isempty(sites.positions),'No positions!')
            function im_clicked(hObj,eventdata)
                if eventdata.Button ~= 1
                    uiresume;
                    return
                end
                if ~obj.includeWavelength
                    h = drawpoint(hObj.Parent, 'Position', eventdata.IntersectionPoint(1:2), 'MarkerSize', 0.01*min(obj.figH.Position(3), obj.figH.Position(4)));
                    if isempty(hObj.UserData.h)
                        hObj.UserData.h = h;
                    else
                        hObj.UserData.h(end+1) = h;
                    end
                else
                    fprintf("Manualy adding sites is prohibited in `includeWavelength` mode.\n");
                end
            end
            function im_clicked2(hObj,eventdata)
                if eventdata.Button ~= 1
                    uiresume;
                    return
                end
            end
        end
        

        function adjustMarkerSize(obj, hObj, eventData)
            if ~isempty(obj.sitesH)
                N = length(obj.sitesH.XData);
                obj.sitesH.SizeData = ones(N, 1)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
            end
            if ~isempty(obj.imH.UserData.h)
                for k = 1:length(obj.imH.UserData.h)
                    obj.imH.UserData.h(k).MarkerSize = 0.01*min(obj.figH.Position(3), obj.figH.Position(4));
                end
            end
        end

        function updateROI(obj,varargin)
            % Updates imrect from imager ROI change
            pos = obj.validROIRect.Position;
            xmin = pos(1);
            xmax = pos(1)+pos(3);
            ymin = pos(2);
            ymax = pos(2)+pos(4);
            obj.validROI = [xmin,xmax;ymin,ymax]; % This should call obj.updateROI from listener
            if strcmp(obj.site_selection, 'Load from file')
                obj.updateImportedSites;
            elseif strcmp(obj.site_selection, 'Peak finder')
                obj.updateFindedSites;
            end
        end
        function updateImportedSites(obj, hObj, eventdata)
            N = size(obj.importedSites.relPos, 1);
            assert(size(obj.importedSites.relPos, 2) == 2, sprintf("Size of obj.importedSites.relPos should be N*2 (N=%d)", N));

            if isempty(obj.importedSites.wavelengths_nm) || all(size(obj.importedSites.wavelengths_nm) == [1, N])
                % hold(obj.axH, 'on') 
                xrel = obj.importedSites.relPos(:, 1);
                yrel = obj.importedSites.relPos(:, 2);
                xmin = obj.validROI(1,1);
                xmax = obj.validROI(1,2);
                ymin = obj.validROI(2,1);
                ymax = obj.validROI(2,2);
                xabs = xmin+xrel*(xmax-xmin);
                yabs = ymin+yrel*(ymax-ymin);
                obj.sitesH.XData = xabs;
                obj.sitesH.YData = yabs;
                obj.sitesH.SizeData = ones(N, 1)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
                cbh = obj.ax2H.Colorbar;
                if  ~obj.includeWavelength
                    % Draw scatter plot without frequency
                    cbh.Visible = 'off';
                    obj.sitesH.CData = zeros(N, 1);
                else
                    % Draw scatter plot with frequency
                    wls = obj.importedSites.wavelengths_nm;
                    cbh.Visible = 'on';
                    obj.sitesH.CData = wls;
                    ylabel(cbh, 'Resonant wavelength (nm)', 'Rotation', 90);
                    cbh.Label.Position(1) = 3;
                    if min(wls)< max(wls)
                        caxis(obj.ax2H, [min(wls), max(wls)]);
                    end
                end
                obj.ax2H.Visible = 'off';
            end 
        end

        function updateFindedSites(obj, hObj, eventdata)
            if isempty(obj.finderH) || ~isprop(obj.finderH, 'XData') || isempty(obj.finderH.XData)
                return;
            end
            obj.findedSites.absPos = [obj.finderH.XData', obj.finderH.YData'];
            N = size(obj.findedSites.absPos, 1);
            assert(size(obj.findedSites.absPos, 2) == 2, sprintf("Size of obj.findedSites.absPos should be 2*N (N=%d)", N));
            xmin = obj.validROI(1,1);
            xmax = obj.validROI(1,2);
            ymin = obj.validROI(2,1);
            ymax = obj.validROI(2,2);
            pos = NaN(N, 2);
            n = 0;
            absPos = obj.findedSites.absPos;
            for k = 1:N
                if  absPos (k, 1)>= xmin && absPos(k, 1) <= xmax && absPos(k, 2) >= ymin && absPos(k, 2) <= ymax
                    % Only display sites within the rectangle ROI
                    n = n + 1;
                    pos(n, :) = absPos(k, :);
                end
            end
            obj.sitesH.XData = pos(1:n, 1);
            obj.sitesH.YData = pos(1:n, 2);
            
            obj.sitesH.MarkerEdgeColor = 'r';
            obj.sitesH.SizeData = ones(n, 1)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
            obj.ax2H.Visible = 'off';
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
        function validate_sites_data(obj,val,~)
            % We will validate and set the analysis prop here
            if ~isempty(val)
                flag = exist(val,'file');
                if flag == 0
                    error('Could not find "%s"!',val)
                end
                if flag ~= 2
                    error('File "%s" must be a mat file!',val)
                end
                data = load(val);
                if isfield(data, 'data')
                    data = data.data;
                end
                assert(isfield(data, 'relPos'), "Imported site data file should contain field `relPos`\n");
                assert(isfield(data, 'wavelengths_nm'), "Imported site data file should contain field `wavelengths_nm`\n");
                obj.importedSites.relPos = data.relPos;
                obj.importedSites.wavelengths_nm = data.wavelengths_nm;
                if isfield(data, 'relSize')
                    obj.importedSites.relSize = data.relSize;
                end
            end
        end
    end
end
