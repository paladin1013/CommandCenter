classdef PM100 < Modules.Driver
    % Interface to Thorlabs PM100 power meter
    
    properties(GetObservable, SetObservable)
        idn         = Prefs.String('', 'readonly', true, 'help_text', 'Identifier for the powermeter.');
        
        wavelength  = Prefs.Double(NaN, 'allow_nan', true, 'unit', 'nm', 'set', 'set_wavelength',               'help_text', 'Calibration wavelength to account for the gain spectrum of the powermeter.');
        freq        = Prefs.Double(NaN, 'allow_nan', true, 'unit', 'Hz', 'set', 'set_measure_frequency',        'help_text', 'Frequency of measurement.');
        averages    = Prefs.Double(NaN, 'allow_nan', true, 'unit', '#',  'set', 'set_average_count',            'help_text', 'Number of measurements to average per returned reading.');
        
        power       = Prefs.Double(NaN, 'allow_nan', true, 'unit', 'mW', 'get', 'get_power', 'readonly', true,  'help_text', 'Last reading.');
        refresh     = Prefs.Button('Poll Powermeter', 'set', 'set_refresh', 'help_text', 'Poll the powermeter for a new reading.');
        window_max  = Prefs.Double(60, 'unit', 's', 'help', 'Max axes width in seconds', 'set', 'set_window_max');
        update_rate = Prefs.Double(0.1, 'unit', 's', 'help', 'Timer function refreshing period.', 'set', 'set_update_rate');  
        start_btn   = Prefs.Button('Start timer update', 'set', 'set_start', 'help_text', 'Start continuous update with period `update_rate`.');
        stop_btn    = Prefs.Button('Stop timer update', 'set', 'set_stop', 'help_text', 'Stop continuous update.');
        running     = Prefs.Boolean(false, 'readonly', true, 'help_text', 'Whether the continuous mode is running.');
    end
    
    properties %(Access=private, Hidden)
        channel;
        id;
        timeout = .1;
        timerH;
        plt;
        ax;
        textH;
        fig;
        display_unit = "uW"; % Options: W, mW, uW, nW; Only impact the display unit in popup window. The unit of `obj.power` is always mW.  
    end
    
    methods(Access=private)
        function out = communicate(obj,msg,output)
            out = '';
            if strcmp(obj.channel.status,'closed')
                fopen(obj.channel);
            end
            fprintf(obj.channel,msg);
            if output
                out = fscanf(obj.channel);
            end
            pause(0.05)
        end
        
        function obj = PM100(varargin)
            obj.id = findInstrument('0x8072'); % model number for the PM100
%             obj.id = findInstrument('0x8076'); % model number for the PM100
            obj.channel = visa('ni', obj.id);
            obj.channel.Timeout = obj.timeout;
            
            obj.command('SENS:POW:UNIT W');     % Make sure that we are measuring power.
            
            obj.idn =           obj.get_idn;
            obj.wavelength =    obj.get_wavelength;
            obj.freq =          obj.get_measure_frequency;
            obj.averages =      obj.get_average_count;
            obj.power =         obj.get_power();
        end
        
    end
    
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Drivers.PM100();
            end
            obj = Object;
        end
    end
    
    methods
        function delete(obj)
            if ~isempty(obj.channel) && isvalid(obj.channel) && strcmp(obj.channel.status,'open')
                fclose(obj.channel);
            end
            obj.set_stop;
            delete(obj.channel)
            obj.close_req;
        end

        function command(obj, msg, varargin)
            obj.communicate(msg,false);
        end
        function out = query(obj, msg)
            out = obj.communicate(msg,true);
        end
        
        function out = get_idn(obj, ~)
            out = strtrim(obj.query('*IDN?'));
        end
        
        function wavelength = set_wavelength(obj, wavelength, ~)
            obj.command(sprintf('CORR:WAV %f',wavelength))
            wavelength = obj.get_wavelength();
        end
        function out = get_wavelength(obj, ~)
            out = obj.query('CORR:WAV?');
            out = str2double(out);
        end
        
        function freq = set_measure_frequency(obj, freq, ~)
            obj.command(sprintf('FREQ:RANGE %f',freq));
            freq = obj.get_measure_frequency();
        end
        function out = get_measure_frequency(obj, ~)
            out = obj.query('FREQ:RANGE?');
            out = str2double(out);
        end
        
        function count = set_average_count(obj, count, ~)
            obj.command(sprintf('AVER:COUN %i',count));
            count = obj.get_average_count();
        end
        function out = get_average_count(obj, ~)
            out = obj.query('AVER:COUN?');
            out = str2double(out);
        end
        
        function out = get_power(obj, ~)
            out = obj.query('MEAS:POW?');
            out = str2double(out) * 1e3;   % Convert from watts to milliwatts.
        end

        function update_power(obj, varargin)
            obj.power = obj.get_power;
            if ~isempty(obj.fig)
                obj.update_view;
            end
        end
        
        function val = set_refresh(obj, val, ~)
            obj.power = obj.get_power();
        end

        function val = set_start(obj, val, ~)
            if obj.running
                obj.set_stop;
            end
            if isempty(obj.fig)
                obj.view;
            else
                figure(obj.fig);  % Bring to foreground
            end
            obj.timerH = timer('ExecutionMode','fixedRate','name','PowerMeter',...
                'period',obj.update_rate,'timerfcn',@obj.update_power);
            start(obj.timerH);
            obj.running = true;
        end

        function val = set_stop(obj, val, ~)
            try
                if ~isempty(obj.timerH) && isvalid(obj.timerH)
                    stop(obj.timerH);
                    delete(obj.timerH);
                end
                obj.timerH = [];
                obj.running = false;
            catch err
                warning(sprintf("Error stopping PM100 timer:\n%s", err.message));
            end
        end

        view(obj);

        function update_view(obj)
            % Default GUI callback
            assert(~isempty(find(strcmp(obj.display_unit, {'W', 'mW', 'uW', 'nW'}))), "obj.display_unit should be one of {'W', 'mW', 'uW', 'nW'}");
            unit_ratio_to_mW = 10^(3*find(strcmp(obj.display_unit, {'W', 'mW', 'uW', 'nW'}))) / 1e6; % W: 1e-3; mW: 1; uW: 1e3; nW: 1e6
            display_power = obj.power * unit_ratio_to_mW;
            title(obj.ax,sprintf('Power %.3f (%s) (%i Samples Averaged)', display_power, obj.display_unit, obj.averages));
            xmax = round(obj.window_max/obj.update_rate);
            x = obj.fig.UserData.x;
            y = obj.fig.UserData.y;
            if numel(x) > xmax
                delta = numel(x)-xmax;
                obj.fig.UserData.y = [y(1+delta:end) obj.power];
                obj.fig.UserData.x = [x(1+delta:end) x(end)+obj.update_rate];
            else
                obj.fig.UserData.y(end+1) = obj.power;
                obj.fig.UserData.x(end+1) = x(end)+obj.update_rate;
            end
            x = obj.fig.UserData.x;
            y = obj.fig.UserData.y;
            set(obj.plt,'xdata',x,'ydata',y*unit_ratio_to_mW);
            xlim = [x(1) x(end)+(x(end)-x(1))*0.1];
            set(obj.ax,'xlim',xlim)
            set(obj.textH,'string',sprintf('%.3f %s',display_power, obj.display_unit))
            ylabel(obj.ax, sprintf('Power (%s)', obj.display_unit))
            ylim(obj.ax, 'auto');
            drawnow limitrate;
        end

        % Callbacks from GUI
        function close_req(obj,varargin)
            if ~isempty(obj.fig)&&isvalid(obj.fig)
                obj.set_stop;
                delete(obj.fig)
                obj.fig = [];
            end
        end
        function val = set_update_rate(obj,val, ~)
            if ~isempty(obj.timerH) && isvalid(obj.timerH)
                stop(obj.timerH)
                obj.timerH.Period = val;
                start(obj.timerH)
            end
        end
        function val = set_window_max(obj,val, ~)

        end
        function update_rate_callback(obj,hObj,varargin)
            val = str2double(get(hObj,'string'));
            obj.update_rate = val;
        end
        function window_max_callback(obj,hObj,varargin)
            val = str2double(get(hObj,'string'));
            obj.window_max = val;
        end
        function update_unit_callback(obj, hObj, varargin)
            str = hObj.String;
            val = hObj.Value;
            obj.display_unit = str{val};
        end
    end    
end

