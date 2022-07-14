classdef AutomaticLifetime < Modules.Experiment
    %Automatically takes Lifetime at sites
    
    properties
        sites;          % sites data. Assigned after `acquireSites`
        validROIPoly;   % Handle to imrect of validROI
        listeners = {}; % Handle of listeners
        axH;            % Handle to axes (children of figH)
        imH;            % Handle to image (children of axH)
        ax2H;           % Handle to axes (children of figH)
        sitesH;         % Handle to sites scatter plot (children of ax2H)
        msmH;           % Handle to MetaStageManager
        data = []; % subclasses should not set this; it can be manipulated in GetData if necessary
        meta = []; % Store experimental settings
        abort_request = false; % Flag that will be set to true upon abort. Used in run method.
        prefs = {'useSitesMemory', 'importSitesData', 'sitesDataPath', 'method', 'emccdDataPath', 'optimizePos'};
        % prefs = {'useSitesMemory', 'importSitesData', 'sitesDataPath', 'method', 'emccdDataPath', 'optimizePos'};
    end
    properties(SetObservable, GetObservable)
        
        useSitesMemory = Prefs.Boolean(true, 'help', 'Will use previous sites memory if avaliable, without loading sites data / acquiring new sites');
        importSitesData = Prefs.Boolean(true, 'help', 'Will import previously finded sites.');
        method = Prefs.MultipleChoice('Spectrum','choices',{'Spectrum','EMCCD'}, 'help', 'Chose method to get emitter frequency');
        optimizePos = Prefs.Boolean(true, 'help', 'Will optimize sites position using galvo mirror.');

        % Related devices
        imaging_source = Prefs.ModuleInstance(Modules.Source.empty(0),'inherits',{'Modules.Source'});
        imageROI = zeros(2, 2);
        validROI = zeros(4, 2); % Only sites inside this polygon area are valid
        % struct of external imported sites (eg. EMCCD wide field scan)
            % baryPos (N*3): barycentric coordinates of sites position
            % triangleIdx (N*1): site belongs to which triangle in ROI triangulation (Idx = 1 or 2)
            % wavelengths_nm (N*1): (optional) resonant wavelengths_nm of each emitter 
            % freqs_THz (N*1): resonant wavelengths_nm of each emitter 
            % relPos (N*2): (optional, deprecated) relative position based on validROI
            % relSize (N*1): (optional) relative size of each site
        emccdSites = struct('baryPos', [], 'triangleIdx', [], 'relPos', [], 'wavelengths_nm', [], 'freqs_THz', [], 'relSize', []); 
        findedSites = struct('absPos', [], 'relSize', []); % For sites founded by `Peak finder`
        sitesDataPath = Prefs.String("sites_data.mat");
        emccdDataPath = Prefs.String('EMCCD_sites_file.mat','help','Data file to import sites coordinates and frequencies. Should contain field `data.baryPos`, `data.wavelengths_nm`.',...
        'custom_validate','loadEMCCDData');
        figH;           % Handle to figure
        finderH;        % Handle to peak finder results


    end
    methods(Static)
        function obj = instance(varargin)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Experiments.AutomaticLifetime.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(varargin,Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Experiments.AutomaticLifetime(varargin{:});
            obj.singleton_id = varargin;
            obj.imaging_source = Sources.Cobolt_PB.instance;
            Objects(end+1) = obj;
        end
    end
    methods(Access=private)
        function obj = AutomaticLifetime()
            % obj.experiments = Experiments.SlowScan.Open.instance;
            % obj.imaging_source = Sources.Cobolt_PB.instance;
            obj.loadPrefs;
        end
    end
    methods
        
        run(obj,statusH,managers,ax);
        initialize(obj, status, managers, ax);
        acquireSites(obj,managers);

        

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
            if strcmp(obj.method, 'EMCCD')
                obj.updateEMCCDSites;
            elseif strcmp(obj.method, 'Spectrum')
                obj.updateFindedSites;
            end
        end
        function updateEMCCDSites(obj, hObj, eventdata)
            N = size(obj.emccdSites.baryPos, 1);
            assert(size(obj.emccdSites.baryPos, 2) == 3, sprintf("Size of obj.emccdSites.baryPos should be N*3 (N=%d)", N));

            if isempty(obj.emccdSites.freqs_THz) || all(size(obj.emccdSites.freqs_THz) == [N, 1])
                % hold(obj.axH, 'on') 
                P = obj.validROIPoly.Position;
                T = [1, 2, 3; 3, 4, 1];
                TR = triangulation(T, P);
                cartPos = zeros(N, 2);
                for k = 1:N
                    triIdx = obj.emccdSites.triangleInd(k);
                    cartPos(k, :) = barycentricToCartesian(TR, triIdx, obj.emccdSites.baryPos(k, :));
                end
                hold(obj.ax2H, 'on');
%                 triplot(TR);
                obj.sitesH.XData = cartPos(:, 1);
                obj.sitesH.YData = cartPos(:, 2);
                obj.sitesH.SizeData = ones(N, 1)*0.1*min(obj.figH.Position(3), obj.figH.Position(4));
                cbh = obj.ax2H.Colorbar;
                if strcmp(obj.method, 'Spectrum')
                    % Draw scatter plot without frequency
                    cbh.Visible = 'off';
                    obj.sitesH.CData = zeros(N, 1);
                else
                    % Draw scatter plot with frequency
                    wls = obj.emccdSites.wavelengths_nm;
                    freqs = obj.emccdSites.freqs_THz;
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
        function loadEMCCDData(obj,val,~)
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
                obj.emccdSites.baryPos = zeros(N, 3);
                obj.emccdSites.triangleInd = zeros(N, 1);
                obj.emccdSites.wavelengths_nm = zeros(N, 1);
                obj.emccdSites.freqs_THz = zeros(N, 1);
                for k = 1:N
                    siteData = data.sites{k};
                    obj.emccdSites.baryPos(k, :) = siteData.baryPos;
                    obj.emccdSites.triangleInd(k, :) = siteData.triangleInd;
                    obj.emccdSites.wavelengths_nm(k, :) = siteData.wavelength_nm;
                    obj.emccdSites.freqs_THz(k, :) = siteData.frequency_THz;
                end                    
                if isfield(data, 'relSize')
                    obj.emccdSites.relSize = data.relSize;
                end
            end
        end

        function newAbsPos = locateSite(obj, absPos)
            % Find site location with more accuracy
            % msm: MetaStageManager; absPos: 1*2 Double;)
            ms = obj.msmH.active_module; % MetaStage instance
            X = ms.get_meta_pref('X');
            Y = ms.get_meta_pref('Y');
            

            assert(X.writ(absPos(1))&&Y.writ(absPos(2)), "X and Y values are not properly set");
            obj.msmH.optimize('Target', true);
            newAbsPos = [X.read, Y.read];
        end

        function abort(obj)
            % obj.fatal_flag = true;
            obj.abort_request = true;
            obj.msmH.optimize('Target', false); % interrupt the metastage optimization process
            % if ~isempty(obj.current_experiment)
            %     obj.current_experiment.abort;
            % end
            obj.logger.log('Abort requested');
        end
        function dat = GetData(obj,~,~)
            % Callback for saving methods (note, lots more info in the two managers input!)
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
        function UpdateRun(obj,~,~,ax)
        end
    end
end
