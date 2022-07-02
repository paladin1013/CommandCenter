classdef ANC350 < Modules.Driver

    % Use hwserver as an intermediate controller, instead of controlling by Matlab directly 
    properties(Constant)
        hwname = 'Attocube';
        axisNo = containers.Map({'x', 'y', 'z'}, {0, 1, 2})
        maxSteps = 100;
    end
    properties(SetAccess=private,Hidden)
        connection
    end
    properties(SetAccess=immutable)
        host
        serialNo 
        version
        port
        
    end
    properties
        lines;
    end

    methods(Static)
        function obj = instance(host_ip)
            % error("error")
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.Attocube.ANC350.empty(1,0);
            end
            [~,host_d] = resolvehost(host_ip);
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(host_d, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Drivers.Attocube.ANC350(host_ip);
            obj.singleton_id = obj.serialNo;
            Objects(end+1) = obj;
            obj.spawnLines;
        end
    end
    methods(Access=private)
        function obj = ANC350(host_)
            obj.host = host_;
            try
                obj.connection = hwserver(host_);
                serialNo = obj.connection.com(obj.hwname, 'getSerialNo');
                obj.serialNo = serialNo{1};
            catch err
                warning([   'Could not connect to an instance of hwserver at host "' host_ '". ' ...
                            'Are you sure hwserver is installed there? The hwserver repository is ' ...
                            'located at https://github.mit.edu/mpwalsh/hwserver/.']);
                rethrow(err);
            end
        end
        function spawnLines(obj)
            for ii = 0:6    % Max number of possible lines according to manual
                    % Note that the axis no in hwserver start from 0 (i.e. 0, 1, 2 represent x, y, z respectively)

                try         % Try to make a line; an expected error will occur if the line does not exist.
                    obj.lines = [obj.lines Drivers.Attocube.ANC350.Line.instance(obj, ii)]; 
                catch  err      % Do something error-specfic?
                    % Do nothing.
                    warning("Line %d not found: %s", ii, err.message);
                end
            end
            
            if isempty(obj.lines)
                warning(['Could not find any lines in Drivers.Attocube.ANC350(''' obj.port ''').'])
            end
        end

        function killLines(obj)
            delete(obj.lines);
        end
    end

    methods
        function delete(obj)
            obj.killLines;
            delete(obj.connection);
        end
        function response = com(obj, varargin)              % Communication helper function.
            response = obj.connection.com(obj.hwname, varargin{:});
        end

        function info = getInfo(obj, varargin)
            info = obj.com('getInfo', obj.serialNo, varargin{:});
        end

        function moveTo(obj, axis, target_um)
            obj.com('move', obj.serialNo, obj.axisNo(axis), target_um/1e6);
        end

        function moveTo3D(obj, xTarget_um, yTarget_um, zTarget_um)
            obj.com('move', obj.serialNo, 0, xTarget_um/1e6);
            obj.com('move', obj.serialNo, 1, yTarget_um/1e6);
            obj.com('move', obj.serialNo, 2, zTarget_um/1e6);
        end

        function pos = getPosition_um(obj)
            pos = obj.com('getPosition', obj.serialNo)*1e6;
        end

        function pos = moveSteps(obj, axis, direction, repeat, frequency_Hz)
            
            assert(direction=="forward" || direction== "backward", "direction should be forward or backward");
            for i = 1:repeat
                obj.com('moveSteps', obj.serialNo, obj.axisNo(axis), direction=="forward", 1, frequency_Hz);
            end
            pos = obj.com('getPosition', obj.serialNo)*1e6;
        end

    end
  
end