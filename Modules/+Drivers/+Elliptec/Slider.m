classdef Slider < Modules.Driver

    %SLIDER Connects with a hwserver Elliptec and calls the corresponding module.
    %
    % Call with the 1) hostname of the host computer (singleton based on host), and 2) slider name (eg. `ZPL_PSB_SLIDER`).
    
    properties (Constant)
        hwname = 'Elliptec';
    end
    properties (SetAccess=immutable)
        connection
        name
    end
    properties (GetObservable, SetObservable)
        position = Prefs.Integer(1, 'set', 'set_position', 'help', 'The current position of Thorlab Elliptec slider. Should be 1~N.');
        forward = Prefs.Button('set', 'jog_forward', 'help', 'Slider jog forward');
        backward = Prefs.Button('set', 'jog_backward', 'help', 'Slider jog backward');
    end
    methods(Static)
        function obj = instance(host, name)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.Elliptec.Slider.empty(1,0);
            end
            [~,resolvedIP] = resolvehost(host);
            
            singleton_id = [resolvedIP '_' num2str(name)];
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(singleton_id, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Drivers.Elliptec.Slider(resolvedIP, name);
            obj.singleton_id = singleton_id;
            Objects(end+1) = obj;
        end
        function [arg_names, default_vals] = get_default_args()
            arg_names = {'host', 'name'};
            default_vals = {'"18.25.29.30"', '"ZPL_PSB_SLIDER"'};
        end
    end
    methods(Access=private)
        function obj = Slider(host, name)
            obj.connection = hwserver(host);
            obj.name = name;
        end
        function response = com(obj,funcname,varargin) %keep this
            response = obj.connection.com(obj.hwname, obj.name, funcname,varargin{:});
        end
    end
    methods
        function delete(obj)
            delete(obj.connection)
        end

        function jog(obj, direction)
            assert(strcmp(direction, 'forward') || strcmp(direction, 'backward'), sprintf("Argument direction should be either `forward` or `backward`, bug got %s.", direction));
            obj.position = obj.com('jog', direction);
        end
        function val = set_position(obj, val, ~)
            result = obj.com('set_slot', val);
            assert(result == val, sprintf("Slider position is not properly set: supposed to %d, but got %d", val, result));
            val = result;
        end
        function val = jog_forward(obj, val, ~)
            obj.jog('forward');
        end
        function val = jog_backward(obj, val, ~)
            obj.jog('backward');
        end
    end
end
