classdef WhiteLight_remote < Modules.Source
    %WHITELIGHT_remote Is an antiquanted Source for analog LEDs such as:
    % https://www.thorlabs.com/newgrouppage9.cfm?objectgroup_id=2616
    
    properties(SetObservable, GetObservable)
        intensity = Prefs.Double(100, 'set', 'set_intensity'); % Intenisty 0-100 (0-5 V)
        matlab_host =   Prefs.String(Sources.WhiteLight_remote.noserver, 'set', 'set_host', 'help', 'IP/hostname of computer with hwserver for WightLight');
    end
    properties
        prefs = {'intensity', 'matlab_host'};
        hwserver;                   % Handle for target hwserver
    end
    properties(Constant)
        noserver = 'No Server';
        hwname = 'Matlab';
    end
    properties(Access=private)
        status                       % Text object reflecting running
        sliderH
    end
    
    methods(Access=protected)
        function obj = WhiteLight_remote()
            obj.loadPrefs;
        end
    end
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Sources.WhiteLight_remote();
            end
            obj = Object;
            obj.matlab_host = "18.25.29.30";
        end
    end
    methods
        function response = com(obj, func_name, varargin)
            response = obj.hwserver.com(obj.hwname, func_name, varargin{:});
        end
        function response = send_commands(obj, commands)
            response = obj.com('dispatch_commands', commands);
        end
        function result = parse_response(obj, response, idx)
            if iscell(response)
                result = response{idx};
            elseif isvector(response)
                result = response(idx);
            else 
                error("Response type error");
            end
        end
        function task = inactive(obj)
            task = '';
            if obj.source_on
                task = 'Turning off';
                obj.off;
            end
        end
        function delete(obj)
        end
        function val = set_intensity(obj,val, ~)
            err = [];
            try
                if obj.source_on %#ok<*MCSUP>
                    obj.on;  % Reset to this value
                    results = obj.send_commands(["wl = Sources.WhiteLight.instance;", sprintf("wl.intensity = %d;", val), "wl.intensity;"]);
                end
            catch err
            end
            
            
            if ~isempty(err)
                err = [];
                try
                    if obj.source_on.value %#ok<*MCSUP>
                        obj.on;  % Reset to this value
                        results = obj.send_commands(["wl = Sources.WhiteLight.instance;", sprintf("wl.intensity = %d;", val), "wl.intensity;"]);
                    end
                catch err
                end
                if ~isempty(err)
                    rethrow(err)
                end
            end
            val = double(obj.parse_response(results, 3));
        end
        function val = set_source_on(obj, val, ~)
            results = obj.send_commands(["wl = Sources.WhiteLight.instance;", sprintf("wl.set_source_on(%d);", int8(val))]);
            val = logical(obj.parse_response(results, 2));
        end
        
        % % Settings and Callbacks
        % function  settings(obj,panelH,~,~)
        %     spacing = 1.5;
        %     num_lines = 2;
        %     line = 1;
        %     obj.status = uicontrol(panelH,'style','text','string','Power',...
        %         'units','characters','position',[0 spacing*(num_lines-line) 35 1.25]);
        %     line = 2;
        %     obj.sliderH = uicontrol(panelH,'style','slider','min',0,'max',100,'value',max(0,obj.intensity),...
        %         'sliderStep',[0.01 0.1],'units','characters','callback',@obj.changePower,...
        %         'horizontalalignment','left','position',[0 spacing*(num_lines-line) 50 1.5]);
            
        % end
        function changePower(obj,src,varargin)
            val = get(src,'value');
            obj.intensity = val;
        end
        function val = set_host(obj,val,~) %this loads the hwserver driver
            try
                obj.hwserver = hwserver(val); %#ok<*MCSUP>
                results = obj.send_commands(["wl = Sources.WhiteLight.instance;", "wl.source_on;", "wl.intensity;"]);
                obj.set_value_only('source_on', logical(obj.parse_response(results, 2)));
                obj.set_value_only('intensity', double(obj.parse_response(results, 3)));
            catch
                obj.hwserver = [];
                val = Sources.WhiteLight_remote.noserver;
            end
        end
        function val = set_armed(obj, val, ~)
            % Opt out of armed warning.
        end
        
    end
end

