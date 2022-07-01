classdef DG645 < Modules.Driver
    % DG645 Connects with hwserver on host machine to control
    % the SRS DG645 via the interpreter program.
    % Call with the IP of the host computer (singleton based on ip)

    properties(Constant)
        hwname = 'DelayGenerator';
    end
    properties(SetAccess=private,Hidden)
        connection
    end
    properties(SetAccess=immutable)
        host
        serialNo 
        
    end

    methods(Static)
        function obj = instance(host_ip)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.DG645.empty(1,0);
            end
            [~,host_d] = resolvehost(host_ip);
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(host_d, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Drivers.DG645(host_ip);
            obj.singleton_id = obj.serialNo;
            Objects(end+1) = obj;
        end
    end
    methods(Access=private)
        function obj = DG645(host_)
            obj.host = host_;
            try
                obj.connection = hwserver(host_);
            catch err
                warning([   'Could not connect to an instance of hwserver at host "' host_ '". ' ...
                            'Are you sure hwserver is installed there? The hwserver repository is ' ...
                            'located at https://github.mit.edu/mpwalsh/hwserver/.']);
                rethrow(err);
            end
        end
    end
    methods
        function delete(obj)
            delete(obj.connection);
        end
        function response = com(obj, varargin)              % Communication helper function.
            response = obj.connection.com(obj.hwname, varargin{:});
        end



        function reset(obj)
            obj.com('reset');
        end
        function calibrate(obj)
            obj.com('calibrate');
        end
        function set_trigger_source(obj, sourceNum)
            % Source Numbers:
            % 0 Internal
            % 1 External rising edges
            % 2 External falling edges
            % 3 Single shot external rising edges
            % 4 Single shot external falling edges
            % 5 Single shot
            % 6 Line 
            obj.com('set_trigger_source', sourceNum);
        end
        function get_trigger_source(obj)
            obj.com('get_trigger_source');
        end
        function set_trigger_rate(obj, rateHz)
            obj.com('set_trigger_rate', rateHz);
        end
        function trigger(obj,N,delay)
            if ~exist('N', 'var')
                N = 1;
            end
            if ~exist('delay', 'var')
                delay = 0;
            end
            obj.com('trigger', N, delay);
        end
        function set_delay(obj,channel,ref,delay)
            obj.com('set_delay', channel, ref, delay);
        end
        function set_burst(obj, channel, pulselength, number, period)
            if ~exist("pulselength", 'var')
                pulselength = 100e-9;
            end
            if ~exist("number", 'var')
                number = 1;
            end
            if ~exist("period", 'var')
                period = 2e-6;
            end
            obj.com('set_burst', channel, pulselength, number, period);
        end
        function set_positive_polarity(obj, output, polarity)
            obj.com('set_positive_polarity', output, polarity);
        end
        function get_polarity(obj, output)
            obj.com('get_polarity', output);
        end
        function check_channel(obj, channel)
            obj.com('check_channel', channel);
        end
        function check_output(obj, output)
            obj.com('check_output', output);
        end
        function set_level(obj, channel, amp)
            assert(amp <= 5 && amp >= 0.5, "Amplitude should be set between 0.5 and 5");
            obj.com('set_level', channel, amp);
        end
        function go_to_local(obj)
            obj.com('go_to_local');
        end
        function go_to_remote(obj)
            obj.com('go_to_remote');
        end

    end
end
