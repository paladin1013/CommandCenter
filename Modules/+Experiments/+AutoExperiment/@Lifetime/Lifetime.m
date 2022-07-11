classdef Lifetime < Experiments.AutoExperiment.AutoExperiment_invisible
    %Spec automatically takes Lifetime at sites
    
    properties
        prerun_functions = {''};
        patch_functions = {''};
    end
    properties(Access=private)
        validROIPoly; % Handle to imrect of validROI
        listeners = {}; % Handle of listeners
        axH;            % Handle to axes (children of figH)
        imH;            % Handle to image (children of axH)
        ax2H;           % Handle to axes (children of figH)
        sitesH;         % Handle to sites scatter plot (children of ax2H)
        sites;          % sites data
    end
    properties(SetObservable, GetObservable)
        imageROI = zeros(2, 2);
        validROI = zeros(4, 2); % Only sites inside this polygon area are valid

        % struct of external imported sites (eg. EMCCD wide field scan)
            % baryPos (N*3): barycentric coordinates of sites position
            % triangleIdx (N*1): site belongs to which triangle in ROI triangulation (Idx = 1 or 2)
            % wavelengths_nm (N*1): (optional) resonant wavelengths_nm of each emitter 
            % freqs_THz (N*1): resonant wavelengths_nm of each emitter 
            % relPos (N*2): (optional, deprecated) relative position based on validROI
            % relSize (N*1): (optional) relative size of each site
        importedSites = struct('baryPos', [], 'triangleIdx', [], 'relPos', [], 'wavelengths_nm', [], 'freqs_THz', [], 'relSize', []); 
        findedSites = struct('absPos', [], 'relSize', []); % For sites founded by `Peak finder`
        figH;           % Handle to figure
        finderH;        % Handle to peak finder results
        includeFreq = Prefs.Boolean(false, 'help', 'Whether resonant frequency is considered in each site. Must be set to false to enable manually select');
        sitesFile = Prefs.File('filter_spec','*.mat','help','Data file to import sites coordinates and frequencies. Should contain field `data.relPos`, `data.wavelengths_nm`.',...
        'custom_validate','loadSitesData');
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
            obj.site_selection = 'Load from file';

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
            obj.imageROI = sites.image.ROI;
            xmin = obj.imageROI(1,1);
            xmax = obj.imageROI(1,2);
            ymin = obj.imageROI(2,1);
            ymax = obj.imageROI(2,2);
            obj.validROIPoly = drawpolygon(obj.axH,'Position', [xmin, ymax; xmax, ymax; xmax, ymin; xmin, ymin ], 'Color', 'b');
            obj.validROIPoly.Deletable = false;
            obj.validROIPoly.FaceAlpha = 0.1;
            obj.listeners{1} = addlistener(obj.validROIPoly, 'ROIMoved', @obj.updateROI);
            obj.listeners{2} = addlistener(obj.figH, 'LocationChanged', @obj.adjustMarkerSize);

            if strcmp(obj.site_selection, 'Load from file')
                if isempty(obj.importedSites.baryPos)
                    [file,path] = uigetfile('*.mat','Site Selection',last_path);
                    obj.loadSitesData([path, file]);
                end
                obj.listeners{3} = addlistener(obj, 'importedSites', 'PostSet', @obj.updateImportedSites);
                obj.updateImportedSites;
                set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to fit the imported site region\nMiddle click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
            elseif strcmp(obj.site_selection, 'Peak finder')
                obj.listeners{3} = addlistener(obj, 'findedSites', 'PostSet', @obj.updateFindedSites);
                assert(obj.includeFreq == false, "Peak finder mode does not support frequency mode")
                title('Drag red region to set thresholds, then close adjustment window when done.')
                [obj.finderH,panelH] = imfindpeaks(obj.imH); %returns array of NV locations
                obj.finderH.Visible = 'off'; % Turn off finderH. Use obj.sitesH to display sites location
                obj.findedSites.absPos = [obj.finderH.XData', obj.finderH.YData'];
                obj.listeners{4} = addlistener(obj.finderH, 'YData', 'PostSet', @obj.updateFindedSites);
                set(get(obj.axH, 'Title'), 'String', sprintf('Move the contrast bar to find peaks\nClose the setting panel to confirm\n'));
                uiwait(panelH);
                set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to bound the active region\nMiddle click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
            end
            obj.updateROI;
            obj.imH.ButtonDownFcn = @im_clicked2; % Wait until next click
            uiwait(obj.figH);


            % Convert all scatter points into pointROI
            obj.imH.UserData.h = [];
            xabs = obj.sitesH.XData;
            yabs = obj.sitesH.YData;
            markerSize = obj.sitesH.SizeData;
            obj.sitesH.Visible = false;
            obj.validROIPoly.Visible = 'off';

            if obj.includeFreq
                wls = obj.importedSites.wavelengths_nm;
                wl_max = max(wls);
                wl_min = min(wls);
                cmap = colormap(obj.ax2H, 'jet');
                colors = cmap(floor((wls-wl_min)*255/(wl_max-wl_min)+1), :);
            end

            for k = 1:length(xabs)
                if obj.includeFreq
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
            if ~obj.includeFreq
                title(sprintf('Drag to adjust\nLeft click to add new points\nRight click on point to get menu to delete.\nMiddle click on image to finish (DO NOT CLOSE!)'))
            else
                title(sprintf('Drag to adjust\nRight click on point to get menu to delete.\n\nMiddle click on image to finish (DO NOT CLOSE!)'))
            end
            
            obj.imH.ButtonDownFcn = @im_clicked;
            uiwait(obj.figH);


            % Save data to sites
            sites.positions = NaN(0,2);
            sites.wavelengths_nm = NaN(0, 1);
            sites.freqs_THz = NaN(0, 1);
            for i = 1:length(obj.imH.UserData.h)
                if isvalid(obj.imH.UserData.h(i))
                    sites.positions(end+1,:) = obj.imH.UserData.h(i).Position;
                    if obj.includeFreq
                        sites.freqs_THz(end+1,1) = obj.imH.UserData.h(i).UserData;
                    end
                end
            end
            sites.positions = [sites.positions, NaN(size(sites.positions,1),1)]; % Add z axis
            % sites.validROI = obj.validROI;
            obj.sites = sites;

            close(obj.figH)
            assert(~isempty(sites.positions),'No positions!')
            function im_clicked(hObj,eventdata)
                if eventdata.Button == 2
                    uiresume;
                    return
                end
                if eventdata.Button ~= 1
                    return
                end
                if ~obj.includeFreq
                    h = drawpoint(hObj.Parent, 'Position', eventdata.IntersectionPoint(1:2), 'MarkerSize', 0.01*min(obj.figH.Position(3), obj.figH.Position(4)));
                    if isempty(hObj.UserData.h)
                        hObj.UserData.h = h;
                    else
                        hObj.UserData.h(end+1) = h;
                    end
                else
                    fprintf("Manualy adding sites is prohibited in `includeFreq` mode.\n");
                end
            end
            function im_clicked2(hObj,eventdata)
                if eventdata.Button == 2
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
            % Updates validROI when polynomial location changes
            obj.validROI = obj.validROIPoly.Position;
            if strcmp(obj.site_selection, 'Load from file')
                obj.updateImportedSites;
            elseif strcmp(obj.site_selection, 'Peak finder')
                obj.updateFindedSites;
            end
        end
        function updateImportedSites(obj, hObj, eventdata)
            N = size(obj.importedSites.baryPos, 1);
            assert(size(obj.importedSites.baryPos, 2) == 3, sprintf("Size of obj.importedSites.baryPos should be N*3 (N=%d)", N));

            if isempty(obj.importedSites.freqs_THz) || all(size(obj.importedSites.freqs_THz) == [N, 1])
                % hold(obj.axH, 'on') 
                P = obj.validROIPoly.Position;
                T = [1, 2, 3; 3, 4, 1];
                TR = triangulation(T, P);
                cartPos = zeros(N, 2);
                for k = 1:N
                    triIdx = obj.importedSites.triangleInd(k);
                    cartPos(k, :) = barycentricToCartesian(TR, triIdx, obj.importedSites.baryPos(k, :));
                end
                hold(obj.ax2H, 'on');
%                 triplot(TR);
                obj.sitesH.XData = cartPos(:, 1);
                obj.sitesH.YData = cartPos(:, 2);
                obj.sitesH.SizeData = ones(N, 1)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
                cbh = obj.ax2H.Colorbar;
                if  ~obj.includeFreq
                    % Draw scatter plot without frequency
                    cbh.Visible = 'off';
                    obj.sitesH.CData = zeros(N, 1);
                else
                    % Draw scatter plot with frequency
                    wls = obj.importedSites.wavelengths_nm;
                    freqs = obj.importedSites.freqs_THz;
                    cbh.Visible = 'on';
                    obj.sitesH.CData = freqs;
                    ylabel(cbh, 'Resonant frequency (THz)', 'Rotation', 90);
                    cbh.Label.Position(1) = 3;
                    if min(freqs)< max(freqs)
                        caxis(obj.ax2H, [min(freqs), max(freqs)]);
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
            pos = NaN(N, 2);
            n = 0;
            absPos = obj.findedSites.absPos;
            for k = 1:N
                if  inpolygon(absPos(k, 1), absPos(k, 2), obj.validROI(:, 1), obj.validROI(:, 2))
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
        function loadSitesData(obj,val,~)
            % Validate input data: data.sites{k} should contain fields baryPos, triangleInd, frequency_THz, wavelength_nm
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
                assert(isfield(data, 'sites'), "Imported site data file should contain field `sites`\n");
                N = length(data.sites);
                obj.importedSites.baryPos = zeros(N, 3);
                obj.importedSites.triangleInd = zeros(N, 1);
                obj.importedSites.wavelengths_nm = zeros(N, 1);
                obj.importedSites.freqs_THz = zeros(N, 1);
                for k = 1:N
                    siteData = data.sites{k};
                    obj.importedSites.baryPos(k, :) = siteData.baryPos;
                    obj.importedSites.triangleInd(k, :) = siteData.triangleInd;
                    obj.importedSites.wavelengths_nm(k, :) = siteData.wavelength_nm;
                    obj.importedSites.freqs_THz(k, :) = siteData.frequency_THz;
                end                    
                if isfield(data, 'relSize')
                    obj.importedSites.relSize = data.relSize;
                end
            end
        end
    end
end
