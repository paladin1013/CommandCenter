classdef ANC350 < Modules.Driver

    % Use hwserver as an intermediate controller, instead of controlling by Matlab directly 
    properties(Constant)
        hwname = 'Attocube';
        axisNo = containers.Map({'x', 'y', 'z'}, {1, 2, 3})
                    % Note that the axis no in hwserver start from 0 (i.e. 0, 1, 2 represent x, y, z respectively)
                    % This conversion is done in Line.com()
        maxSteps = 200;
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
    events
        update_position
    end
    properties(SetObservable, GetObservable)
        x_output = Prefs.Boolean(true, 'help', 'Enable output on X axis', 'set', 'set_x_output');
        y_output = Prefs.Boolean(true, 'help', 'Enable output on Y axis', 'set', 'set_y_output');
        z_output = Prefs.Boolean(true, 'help', 'Enable output on Z axis', 'set', 'set_z_output');
        multistep_ratio = Prefs.Integer(10, 'min', 0, 'max', 50, 'unit', '#', 'help', 'Do move steps `multistep_ratio` more times when `key_step`/`joy_step` is set to larger than 1.')
        x_position_um = Prefs.Double(0, 'unit', 'um', 'readonly', true, 'help', 'Absolute position (unstable)');
        y_position_um = Prefs.Double(0, 'unit', 'um', 'readonly', true, 'help', 'Absolute position (unstable)');
        z_position_um = Prefs.Double(0, 'unit', 'um', 'readonly', true, 'help', 'Absolute position (unstable)');
        x_amplitude = Prefs.Double(60, 'unit', 'V', 'help', 'Single step pulse amplitude', 'set', 'set_x_amplitude');
        y_amplitude = Prefs.Double(60, 'unit', 'V', 'help', 'Single step pulse amplitude', 'set', 'set_y_amplitude');
        z_amplitude = Prefs.Double(30, 'unit', 'V', 'help', 'Single step pulse amplitude', 'set', 'set_z_amplitude');
        x_frequency = Prefs.Double(200, 'unit', 'Hz', 'help', 'Continuous steps pulse frequency', 'set', 'set_x_frequency');
        y_frequency = Prefs.Double(200, 'unit', 'Hz', 'help', 'Continuous steps pulse frequency', 'set', 'set_y_frequency');
        z_frequency = Prefs.Double(100, 'unit', 'Hz', 'help', 'Continuous steps pulse frequency', 'set', 'set_z_frequency');
        new_origin = Prefs.Button('set', 'set_new_origin', 'help', 'Set the curren place as new origin (to avoid maxSteps constraint).');
    end

    properties
        lines;

        prefs = {'x_output', 'y_output', 'z_output', 'multistep_ratio', 'x_position_um', 'y_position_um', 'z_position_um', 'x_amplitude', 'y_amplitude', 'z_amplitude', 'x_frequency', 'y_frequency', 'z_frequency'};
    end

    methods(Static)
        function obj = instance(host_ip)
            % error("error")
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.Attocube.ANC350.empty(1,0);
            end
            serials = Drivers.Attocube.ANC350.get_serialNo(host_ip);
            singleton_id = serials{1};
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(singleton_id, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Drivers.Attocube.ANC350(host_ip);
            obj.singleton_id = singleton_id;
            Objects(end+1) = obj;
            obj.spawnLines;
        end
        function [arg_names, default_vals] = get_default_args()
            arg_names = {'host_ip'};
            default_vals = {'"18.25.29.30"'};
        end
        function serialNo = get_serialNo(host_ip)
            connection = hwserver(host_ip);
            serialNo = connection.com('Attocube', 'getSerialNo');
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
            for ii = 1:3    % Max number of possible lines according to manual

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
            % obj.lines = Drivers.Attocube.ANC350.Line.empty(1, 0); % No need to kill lines?
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

        function pos = moveSteps(obj, axis, direction, repeat)
            assert(direction=="forward" || direction== "backward", "direction should be forward or backward");
            if repeat > 1
            obj.com('moveSteps', obj.serialNo, obj.axisNo(axis), direction=="forward", repeat*obj.multistep_ratio);
            elseif repeat == 1
                obj.com('moveSteps', obj.serialNo, obj.axisNo(axis), direction=="forward", 1);
            end
            pos = obj.com('getPosition', obj.serialNo)*1e6;
        end
        function val = set_x_output(obj, val, ~)
            obj.lines(1).output = val;
        end
        function val = set_y_output(obj, val, ~)
            obj.lines(2).output = val;
        end
        function val = set_z_output(obj, val, ~)
            obj.lines(3).output = val;
        end
        function val = set_x_amplitude(obj, val, ~)
            obj.lines(1).amplitude = val;
        end
        function val = set_y_amplitude(obj, val, ~)
            obj.lines(2).amplitude = val;
        end
        function val = set_z_amplitude(obj, val, ~)
            obj.lines(3).amplitude = val;
        end
        function val = set_x_frequency(obj, val, ~)
            obj.lines(1).frequency = val;
        end
        function val = set_y_frequency(obj, val, ~)
            obj.lines(2).frequency = val;
        end
        function val = set_z_frequency(obj, val, ~)
            obj.lines(3).frequency = val;
        end
        function val = set_new_origin(obj, val, ~)
            prev_x_output = obj.x_output;
            prev_y_output = obj.y_output;
            prev_z_output = obj.z_output;
            obj.x_output = false;
            obj.y_output = false;
            obj.z_output = false;
            for k = 1:3
                line = obj.lines(k);
                mp = line.get_meta_pref('steps_moved');
                line.steps_moved_prev = 0;
                mp.writ(0);
            end
            obj.x_output = prev_x_output;
            obj.y_output = prev_y_output;
            obj.z_output = prev_z_output;
        end
        function coordinate_um =  get_coordinate_um(obj, sample_num, sample_interval_s)
            % Export current coordinate to other modules
            if ~exist('sample_num', 'var')
                sample_num = 0;
            end

            if sample_num == 0
                coordinate_um = [obj.x_position_um, obj.y_position_um, obj.z_position_um];
                return
            end
            if ~exist('sample_interval_s', 'var')
                sample_interval_s = 0.05;
            end
            positions = NaN(sample_num, 3);
            for k = 1:sample_num
                positions(k, :) = obj.getPosition_um;
                pause(sample_interval_s);
            end
            coordinate_um = mean([positions]);
            obj.x_position_um = coordinate_um(1);
            obj.y_position_um = coordinate_um(2);
            obj.z_position_um = coordinate_um(3);
        end
        function steps = get_steps_moved(obj)
            steps = zeros(1, 3);
            for k = 1:3
                line = obj.lines(k);
                steps(k) = line.steps_moved;
            end
        end
    end
  
end