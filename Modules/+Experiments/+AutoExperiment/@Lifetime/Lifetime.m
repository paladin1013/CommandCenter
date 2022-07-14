classdef Lifetime < Experiments.AutoExperiment.AutoExperiment_invisible
    %Spec automatically takes Lifetime at sites
    
    properties
        prerun_functions = {''};
        patch_functions = {''};
        sites;          % sites data. Assigned after 
    end
    properties(Access=private)
        validROIPoly; % Handle to imrect of validROI
        listeners = {}; % Handle of listeners
        axH;            % Handle to axes (children of figH)
        imH;            % Handle to image (children of axH)
        ax2H;           % Handle to axes (children of figH)
        sitesH;         % Handle to sites scatter plot (children of ax2H)
        msmH;           % Handle to MetaStageManager
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
        EMCCDSitesFile = Prefs.File('filter_spec','*.mat','help','Data file to import sites coordinates and frequencies. Should contain field `data.baryPos`, `data.wavelengths_nm`.',...
        'custom_validate','loadSitesData');
        sitesDataPath = Prefs.String("sites_data.mat");
        useSitesMemory = Prefs.Boolean(true, 'help', 'Will use previous sites memory if avaliable, without acquiring new sites');
        optimizeSitesPosition = Prefs.Boolean(true, 'help', 'Will optimize sites position using galvo');

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
    end
    methods(Access=private)
        function obj = Lifetime()
            obj.experiments = Experiments.SlowScan.Open.instance;
            obj.imaging_source = Sources.Cobolt_PB.instance;
            obj.loadPrefs;
        end
    end
    methods
        
        

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
            if isempty(obj.finderH) ||  isempty(obj.finderH.XData)
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

        function [newAbsPos, newFreq] = locateSite(obj, msm, absPos, freq)
            % msm: MetaStageManager; absPos: 1*2 Double; freq: Double, THz; )
            ms = msm.active_module; % MetaStage instance
            X = ms.get_meta_pref('X');
            Y = ms.get_meta_pref('Y');
            
            % Optimize frequency first ?
            newFreq = freq;

            assert(X.writ(absPos(1))&&Y.writ(absPos(2)), "X and Y values are not properly set");
            msm.optimize('Target', true);
            newAbsPos = [X.read, Y.read];
        end

        function abort(obj)
            obj.fatal_flag = true;
            obj.abort_request = true;
            obj.msmH.optimize('Target', false); % interrupt the metastage optimization process
            if ~isempty(obj.current_experiment)
                obj.current_experiment.abort;
            end
            obj.logger.log('Abort requested');
        end

        initialize(obj, status, managers, ax);
        sites = AcquireSites(obj,managers)
    end
end
