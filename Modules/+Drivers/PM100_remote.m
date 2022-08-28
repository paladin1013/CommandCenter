classdef PM100_remote < Modules.Driver

    properties (SetObservable, GetObservable)
        power = Prefs.Double(NaN, 'get', 'get_power', 'unit', 'mW');
        matlab_host = Prefs.String('No Server', 'set', 'set_host', 'help', 'IP/hostname of computer with hwserver for PM100');
    end
    properties
        prefs = {'intensity', 'matlab_host'};
        hwserver; % Handle for target hwserver
    end
    properties (Constant)
        noserver = 'No Server';
        hwname = 'Matlab';
    end
    properties (Access = private)
        status % Text object reflecting running
        sliderH
    end

    methods (Access = protected)
        function obj = PM100_remote()
            obj.loadPrefs;
        end
    end
    methods (Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Drivers.PM100_remote();
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
        function delete(obj)
        end
        function val = get_power(obj, ~)

            err = [];
            try
                results = obj.send_commands(["pm = Drivers.PM100.instance;", "pm.get_power;"]);
                val = double(obj.parse_response(results, 2));
            catch err
            end

            if ~isempty(err)
                err = [];
                try
                    results = obj.send_commands(["pm = Drivers.PM100.instance;", "pm.get_power;"]);
                    val = double(obj.parse_response(results, 2));
                catch err
                end
                if ~isempty(err)
                    rethrow(err)
                end
            end
        end

        function val = set_host(obj, val, ~) %this loads the hwserver driver
            try
                obj.hwserver = hwserver(val); %#ok<*MCSUP>
            catch
                obj.hwserver = [];
                val = Drivers.PM100_remote.noserver;
            end
        end

    end
end
