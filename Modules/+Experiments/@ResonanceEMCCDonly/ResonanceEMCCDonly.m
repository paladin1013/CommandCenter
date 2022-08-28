classdef ResonanceEMCCDonly < Modules.Experiment
    % Resonance Description of experiment
    % Useful to list any dependencies here too

    properties(GetObservable,SetObservable,AbortSet)
        % These should be preferences you want set in default settings method
        resLaser = Prefs.ModuleInstance(Sources.Msquared.instance, 'inherits', {'Modules.Source'}); % Allow selection of source
        repumpLaser = Prefs.ModuleInstance(Sources.Cobolt_PB.instance, 'inherits', {'Modules.Source'});
        cameraEMCCD = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        whiteLight = Prefs.ModuleInstance(Sources.WhiteLight_remote.instance, 'inherits', {'Modules.Source'});
        EMCCD_binning = Prefs.Integer(1);
        EMCCD_exposure = Prefs.Integer(100, 'unit', 'ms');
        EMCCD_gain = Prefs.Integer(1200);
        ROI_automatic = Prefs.Boolean(true);
        percents = 'linspace(0,100,101)';
        tune_coarse = Prefs.Boolean(false,     'help_text', 'Whether to tune to the coarse value before the scan.');
        set_wavelength = Prefs.Double(619, 'unit', 'nm'); %nm
        scan_points = []; %frequency points, either in THz or in percents
        
        wavemeter_override = Prefs.Boolean(false);
        wavemeter_channel = Prefs.Integer(false);
        wightlight_file = Prefs.File('filter_spec','*.mat','help','Snapped whightlight image.', 'custom_validate','validate_wl_file');
        discard_raw_data = Prefs.Boolean(false, 'help', 'Skip saving raw data to speed up experiment.');
        skip_analysis = Prefs.Boolean(false, 'help', 'Skip the analisys program.');
        keep_entire_image = Prefs.Boolean(true, 'help', 'Will not trim the whitelight and EMCCD image if selected.');
        processor = Prefs.ModuleInstance(Drivers.ImageProcessor.instance, 'inherits', {'Modules.Driver'});
        accelerate = Prefs.Boolean(true, 'help', 'Start snapping data and quiring wavemeter wavelength at the same time to accelerate experiment. May be unstable.');
        use_powermeter = Prefs.Boolean(false, 'help', 'Will acquire laser power for each frame from PM100.');
        powermeter = Prefs.ModuleInstance(Drivers.PM100_remote.instance, 'inherits', {'Modules.Driver'});

    end
    
    properties(Constant)
%         vars = {'scan_points'}; %names of variables to be swept
    end
    
    properties
        prefs = {'percents', 'tune_coarse', 'set_wavelength', 'wavemeter_override','wavemeter_channel','resLaser', 'repumpLaser', 'cameraEMCCD', 'whiteLight',...
            'EMCCD_binning', 'EMCCD_exposure', 'EMCCD_gain', 'ROI_automatic', 'wightlight_file', 'discard_raw_data', 'accelerate'};  % String representation of desired prefs
        %show_prefs = {};   % Use for ordering and/or selecting which prefs to show in GUI
        %readonly_prefs = {}; % CC will leave these as disabled in GUI (if in prefs/show_prefs)
    end
    properties(SetAccess=private,Hidden)
        % Internal properties that should not be accessible by command line
        % Advanced users should feel free to alter these properties (keep in mind methods: abort, GetData)
        data = []; % Useful for saving data from run method
        abort_request = false; % Flag that will be set to true upon abort. Use in run method!
    end
    
    properties
        ax1;
        ax2;
        wl_img = [];
        trimmed_wl_img = [];
        rect_pos = [];
        poly_pos = [];
        wavemeter = [];
        autosave = [];
        processed_data = [];
        segment = [];
    end

    methods(Static)
        % Static instance method is how to call this experiment
        % This is a separate file
        obj = instance()
    end
    methods(Access=private)
        function obj = ResonanceEMCCDonly()
            % Constructor (should not be accessible to command line!)
            obj.loadPrefs; % Load prefs specified as obj.prefs
            ip = Drivers.ImageProcessor.instance;
        end
    end

    methods
        run(obj,status,managers,ax) % Main run method in separate file

        function abort(obj)
            % Callback for when user presses abort in CC
            obj.abort_request = true;
        end

        function dat = GetData(obj,stageManager,imagingManager)
            % Callback for saving methods (note, lots more info in the two managers input!)
            objdata = obj.data; % As to not delete obj.data.meta
            if isfield(obj.data,'meta')
                meta = obj.data.meta;
                objdata = rmfield(obj.data,'meta');
            end
            meta.percents = obj.percents;
            
            if obj.discard_raw_data % Skip uploading image data in order to save time 
                dat.data = [];
            else
                dat.data = objdata;
            end
            dat.meta = meta;
        end
        
        function PreRun(obj,~,managers,ax)
            %prepare frequencies
%             obj.data.freqs_measured = NaN(obj.averages,length(obj.scan_points));
            %prepare axes for plotting
            %hold(ax,'on');
            
            subplot(ax);
            obj.ax1 = subplot(2, 1, 1);
            obj.ax2 = subplot(2, 1, 2);
            ax.UserData.plots = plotH;
            %hold(ax,'off');
            
            % center resonant laser range
            if obj.wavemeter_override
                obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu', obj.wavemeter_channel, true);
            end
            % center resonant laser range
            if obj.tune_coarse
                obj.resLaser.TuneCoarse(obj.set_wavelength);
            end

        end
        
        function set.percents(obj,val)
            numeric_vals = str2num(val); %#ok<ST2NM> str2num uses eval but is more robust for numeric input
            assert(~isempty(numeric_vals),'Must have at least one value for percents.');
            assert(min(numeric_vals)>=0&&max(numeric_vals)<=100,'Percents must be between 0 and 100 (inclusive).');
            obj.scan_points = numeric_vals;
            obj.percents = val;
        end

        function validate_wl_file(obj, val, ~)
            % try
                flag = exist(val,'file');
                if flag == 0
                    error('Could not find "%s"!',val)
                end
                if flag ~= 2
                    error('File "%s" must be a mat file!',val)
                end
                wl = load(val);
                assert(isfield(wl, 'image'), sprintf('File %s should have field "image"', val));
                assert(isfield(wl.image, 'image'), sprintf('File %s should have field "image.image"', val));
                if ~all(size(obj.wl_img) == size(wl.image.image), 'all') || ~all(obj.wl_img == wl.image.image, 'all')
                    obj.wl_img = wl.image.image;
                    if obj.ROI_automatic
                        obj.set_ROI_automatic;
                    else
                        obj.set_ROI;
                    end
                end
            % catch err
                % fprintf("Did not take wl image successfully. Taking a new image.\n");
                % obj.whiteLight.source_on = true;
                % obj.wl_img = obj.cameraEMCCD.snapImage;
                % obj.whiteLight.source_on = false;
                % obj.set_ROI;
                % rethrow(err);
            % end
        end
        function set_ROI_automatic(obj, wl_img)
            if ~exist('wl_img', 'var')
                if isempty(obj.wl_img)
                    error("Please first assign wl_img for the experiment.")
                end
                wl_img = obj.wl_img;
            else
                obj.wl_img = wl_img;
            end
            obj.processor.setTemplate(wl_img, false);
            seg = obj.processor.template;
            if obj.keep_entire_image
                obj.rect_pos = [1, 1, size(obj.wl_img, 2)-1, size(obj.wl_img, 1)-1];
                obj.poly_pos = [seg.cornerPos(:, 2), seg.cornerPos(:, 1)]+[seg.xmin-1, seg.ymin-1];
                obj.trimmed_wl_img = obj.wl_img;
            else
                obj.trimmed_wl_img = seg.rawImage;
                obj.rect_pos = [seg.xmin, seg.ymin, size(seg.image, 2)-1, size(seg.image, 1)-1];
                obj.poly_pos = [seg.cornerPos(:, 2), seg.cornerPos(:, 1)];
            end
            try close(41); end
            frame_fig = figure(41);
            frame_fig.Position = [200, 200, 560, 420];
            frame_ax = axes('Parent', frame_fig);
            wlH = imagesc(frame_ax, obj.trimmed_wl_img);
            colormap(frame_ax, 'bone');
            x_size = size(obj.trimmed_wl_img, 2);
            y_size = size(obj.trimmed_wl_img, 1);
            polyH = drawpolygon(frame_ax, 'Position', obj.poly_pos);
            obj.segment = seg;
        end
        function set_ROI(obj)
            
            assert(~isempty(obj.wl_img), 'Please load wightlight image first');
            % Show wl image
            try close(42); catch; end
            roi_fig = figure(42);
            roi_fig.Position = [200, 200, 560, 420];
            roi_ax = axes('Parent', roi_fig);
            im2H = imagesc(roi_ax, obj.wl_img(:, :));
            colormap(roi_ax, 'bone')
            im_size = size(obj.wl_img(:, :));
            if obj.keep_entire_image
                obj.rect_pos = [1, 1, size(obj.wl_img, 2)-1, size(obj.wl_img, 1)-1];
                obj.trimmed_wl_img = obj.wl_img;
            else
                if isempty(obj.rect_pos)
                    rectH = images.roi.Rectangle(roi_ax, 'Position', [1, 1, im_size(1)-1, im_size(2)-1]);
                else
                    rectH = images.roi.Rectangle(roi_ax, 'Position', obj.rect_pos);
                end
                set(get(roi_ax, 'Title'), 'String', sprintf('Please adjust ROI to trim the image and accelarate image processing\nRight click unconvered image to confirm ROI'));
                im2H.ButtonDownFcn = @ROIConfirm;
                uiwait(roi_fig);
                pos = rectH.Position;
                obj.rect_pos = pos;
                rxmin = ceil(pos(1));
                rymin = ceil(pos(2));
                rxmax = floor(pos(1)+pos(3));
                rymax = floor(pos(2)+pos(4));
                delete(roi_fig);
                obj.trimmed_wl_img = obj.wl_img(rymin:rymax, rxmin:rxmax);
            end

            try close(41); catch; end
            frame_fig = figure(41);
            frame_fig.Position = [200, 200, 560, 420];
            frame_ax = axes('Parent', frame_fig);
            wlH = imagesc(frame_ax, obj.trimmed_wl_img);
            colormap(frame_ax, 'bone');
            x_size = size(obj.trimmed_wl_img, 2);
            y_size = size(obj.trimmed_wl_img, 1);
            if isempty(obj.poly_pos)
                polyH = drawpolygon(frame_ax, 'Position', [1, 1, x_size, x_size; 1, y_size, y_size, 1]');
            else
                polyH = drawpolygon(frame_ax, 'Position', obj.poly_pos);
            end
            set(get(frame_ax, 'Title'), 'String', sprintf('Press enter or right click the image to confirm polygon ROI\nOnly emitters inside this region will be shown.'));
            wlH.ButtonDownFcn = @ROIConfirm;
            frame_fig.KeyPressFcn = @ROIConfirm;
            uiwait(frame_fig);
            poly_pos = polyH.Position;
            obj.poly_pos = poly_pos;
            delete(frame_fig);
        end
        
    end
    
end
