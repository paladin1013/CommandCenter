classdef Spectrum < Modules.Experiment
    %Spectrum Experimental wrapper for Drivers.WinSpec
    
    properties(SetObservable,GetObservable)
        ip =        Prefs.String('No Server', 'help', 'IP/hostname of computer with the WinSpec server', 'set', 'set_ip');
        grating = 	Prefs.MultipleChoice('1200 BLZ=  750NM', 'choices', {'1200 BLZ=  750NM', '600 BLZ=  750NM', '300 BLZ=  750NM'}, 'set', 'set_grating'); % Is there a more elegant way to set the valid values? 
        position = 	Prefs.Double(NaN,   'unit', 'nm', 'set', 'set_position');      % Grating position
        exposure =  Prefs.Double(NaN,   'unit', 'sec', 'set', 'set_exposure');     % Exposure time
        LorentzFit = Prefs.Boolean(false, 'help', 'Applying lorentzian fit to the spectrum output.');
        over_exposed_override = Prefs.Boolean(false);       % override over_exposed error from server and return data regardless
    end
    
    properties(Access=private)
        % intensity =     Base.Meas([1 1024], 'unit', 'arb')
        % wavelength =    Base.Meas([1 1024], 'unit', 'nm')
        
        % measurements = [Base.Meas([1 1024], 'field', 'intensity',  'unit', 'arb') ...
        %                 Base.Meas([1 1024], 'field', 'wavelength', 'unit', 'nm')];
    end
    
    properties (Hidden, Constant)
        gratingFormat = @(a)sprintf('%i %s', a.grooves, a.name)
    end
    
    properties(SetObservable,AbortSet)
        data
        
%         prefs = {'over_exposed_override','ip'}; % Not including winspec stuff because it can take a long time!
%         show_prefs = {'exposure','position','grating','over_exposed_override','ip'};
    end
    
    properties(SetAccess=private,Hidden)
        WinSpec
        listeners
    end
    
    methods(Access=private)
        function obj = Spectrum()
            obj.path = 'spectrometer';
            
            try
                obj.loadPrefs; % Load prefs should load WinSpec via set.ip
            catch err % Don't need to raise alert here
                if ~strcmp(err.message,'WinSpec not set')
                    rethrow(err)
                end
            end
            
            obj.measurements = [Base.Meas([1 1024], 'field', 'intensity',  'unit', 'arb') ...
                                Base.Meas([1 1024], 'field', 'wavelength', 'unit', 'nm')];
        end
    end
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Experiments.Spectrum();
                Object.ip = Object.ip;
            end
            obj = Object;
        end
    end
    
    methods
        function run( obj,status,managers,ax )
            assert(~isempty(obj.WinSpec) && isobject(obj.WinSpec)&&isvalid(obj.WinSpec),'WinSpec not configured propertly; check the IP');
            obj.data = [];
            
            if ~isempty(status)
                set(status,'string','Connecting...');
                drawnow;
                obj.data = obj.WinSpec.acquire(@(t)set(status,'string',sprintf('Elapsed Time: %0.2f',t)),obj.over_exposed_override); %user can cause abort error during this call
            else
                obj.data = obj.WinSpec.acquire([],obj.over_exposed_override);
            end
            
            % Get rid of the outlier point (usually the last point)
            obj.data.x = obj.data.x(1:end-1);
            obj.data.y = obj.data.y(1:end-1);
            if obj.LorentzFit
                wavelength = obj.data.x(465:549);
                intensity = obj.data.y(465:549);
                xx = linspace(wavelength(1),wavelength(end),501);
                % guess = struct("amplitudes", 150, "locations", 619, "widths", 0.01, "background", 100);
                [vals,confs,fit_results,gofs,init,stop_condition] = fitpeaks(wavelength,intensity, "FitType", "lorentz");
                % amplitude_fit = params(1)./((xx-params(2)).^2+params(3))+params(4);
                amplitude_fit = fit_results{2}(xx);
                fprintf("  Fit peak: %d\n", val.locations(1));
                obj.data.lorentzFitObj = fit_results{2};
            end
            if ~isempty(obj.data) && ~isempty(ax)
                plot(ax,obj.data.x, obj.data.y)
                if obj.LorentzFit
                    line(xx, amplitude_fit, 'parent', ax, 'Color', 'red')
                end
                xlabel(ax,'Wavelength (nm)')
                ylabel(ax,'Intensity (AU)')
                if ~isempty(status)
                    set(status,'string','Complete!')
                end
            else
                if ~isempty(status)
                    set(status,'string','Unknown error. WinSpec did not return anything.')
                end
            end
            
            if ~isempty(managers)
                obj.data.position = managers.Stages.position;
            end
            
            try
                obj.data.WinSpec_calibration = obj.WinSpec.calibration;
            catch
                obj.data.WinSpec_calibration = [];
            end
        end
        
        function val = set_ip(obj,val, ~)
            delete(obj.listeners);
            obj.WinSpec = []; obj.listeners = [];
            
            obj.ip = val;
            
            err = [];
            
%             obj.setMeasurementVars(1024);
            
            if ~strcmp(val, 'No Server')
                h = msgbox(sprintf('Connecting to %s...',val), mfilename, 'help', 'modal');
                delete(findall(h,'tag','OKButton')); drawnow;
                try
                    obj.WinSpec = Drivers.WinSpec.instance(val);
                    
                    obj.setGratingStrings();
                    obj.get_grating();
                    
                    obj.position = obj.WinSpec.position;
                    obj.exposure = obj.WinSpec.exposure;
                    
%                     obj.setMeasurementVars(1024);
                    
                    delete(h)
                    return;
                catch err
                    delete(h)
                end
            end
            
            
            obj.WinSpec = [];
            
            obj.grating = {};
            obj.position = NaN;
            obj.exposure = NaN;
            
            obj.ip = 'No Server';
            
            val = obj.ip;
            
            if ~isempty(err)
                rethrow(err)
            end
        end
%         function setMeasurementVars(obj, N)
%             obj.sizes = struct('wavelength', [1 N],   'intensity', [1 N]);
%             obj.units = struct('wavelength', 'nm',      'intensity', 'arb');
%             % Scans and dims default to 1:N (pixels), which is fine.
%         end
        function delete(obj)
            delete(obj.listeners)
            delete(obj.WinSpec)
        end
        function abort(obj)
            obj.WinSpec.abort;
        end
        
        function data = measure(obj)
            N = 1024;
            
            ii = randi(N);
            
            data.intensity.dat = rand(1, N) + (5+5*rand())*exp(-(((1:N) - ii)/10).^2);
            data.intensity.std = sqrt(data.intensity.dat);
            data.wavelength = linspace(600, 640, N);
        end
        function dat = GetData(obj,~,~)
            dat = [];
            if ~isempty(obj.data)
                dat.diamondbase.data_name = 'Spectrum';
                dat.diamondbase.data_type = 'local';
                dat.wavelength = obj.data.x;
                dat.intensity = obj.data.y;
                if obj.LorentzFit
                    dat.LorentzianParams = obj.data.lorentzFitObj;
                end
                dat.meta = rmfield(obj.data,{'x','y'});
            end
        end
        
        function strs = getGratingStrings(obj)
            if ~isempty(obj.WinSpec)
                strs = arrayfun(obj.gratingFormat, obj.WinSpec.gratings_avail, 'uniformoutput', false);
            else
                strs = {};
            end
        end
        function setGratingStrings(obj)
            g = obj.get_meta_pref('grating');

            g.choices = obj.getGratingStrings();

            obj.set_meta_pref('grating', g);
        end
        function val = get_grating(obj, ~)
            val = '';
            if ~isempty(obj.WinSpec)
                grating_info = obj.WinSpec.gratings_avail(obj.WinSpec.grating);
                obj.grating = obj.gratingFormat(grating_info);
                val = obj.grating;
            end
        end
        
        % Experimental Set methods
        function val = set_grating(obj, val, ~)
            % obj.grating = val;
            if strcmp(val, "")
                return;
            end

            if isempty(obj.WinSpec); return; end
            d = dbstack;
            if ismember([mfilename '.' mfilename],{d.name}); return; end % Redundant, just to avoid msgbox popup
            idx = find(strcmp(obj.getGratingStrings,val)); % Grab index corresponding to option
            assert(~isempty(idx),sprintf('Could not find "%s" grating in WinSpec.gratings_avail',idx));
            h = msgbox(sprintf(['Moving grating from %i to %i',newline,...
                'This may take time.'],obj.WinSpec.grating,idx),[mfilename ' grating'],'help','modal');
            delete(findall(h,'tag','OKButton')); drawnow;
            err = [];
            try
            obj.setWrapper('Grating', idx, []);
            catch err
            end
            delete(h)
            if ~isempty(err)
                rethrow(err)
            end
        end
        function setWrapper(obj,param,varargin)
            if isempty(obj.WinSpec); return; end
            % Don't set in constructor.
            d = dbstack;
            if ismember([mfilename '.' mfilename],{d.name}); return; end
            obj.WinSpec.(sprintf('set%s',param))(varargin{:});
        end
        function val = set_position(obj, val, ~)
            obj.position = val;
            obj.setWrapper('Grating', [], val);
        end
        function val = set_exposure(obj, val, ~)
            obj.exposure = val;
            obj.setWrapper('Exposure', val);
        end
    end
    
end

