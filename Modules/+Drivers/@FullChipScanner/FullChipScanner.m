classdef FullChipScanner < Modules.Driver
    properties(SetObservable, GetObservable)
        

        x_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'set', 'set_x_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        y_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'set', 'set_y_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        x_movement_um = Prefs.DoubleArray([0, 0, 0], 'unit', 'um', 'allow_nan', false, 'min', -50, 'max', 50, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along x axis');
        y_movement_um = Prefs.DoubleArray([0, 0, 0], 'unit', 'um', 'allow_nan', false, 'min', -50, 'max', 50, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along y axis');
        current_position_um = Prefs.DoubleArray([NaN, NaN, NaN], 'unit', 'um', 'readonly', true, 'help', 'Current piezo stage position');
        calibrate_x_movement = Prefs.ToggleButton(false, 'set', 'set_calibrate_x_movement', 'help', 'First move along x axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        calibrate_y_movement = Prefs.ToggleButton(false, 'set', 'set_calibrate_y_movement', 'help', 'First move along y axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        laser_center = Prefs.DoubleArray([NaN, NaN], 'unit', 'pixel', 'help', 'Laser center relative position in the camera image.'); % Regular 
        set_laser_center = Prefs.Button('set', 'set_laser_center_graphical', 'help', 'Set the relative position of laser center on the current snapped image');
        reverse_step_direction = Prefs.Boolean(true, 'help', 'Check this option if stepping stage forward will result in decreasing of the absolute position.');

        % camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        % stage = Prefs.ModuleInstance(Drivers.Attocube.ANC350.instance("18.25.29.30"), 'inherits', {'Modules.Driver'});
    end
    properties(Access=private)
        stage_listener;
        prev_x_pos = 0;
        prev_y_pos = 0;
        prev_calibrate_x_movement = false;
        prev_calibrate_y_movement = false;
        initialized = false;
    end
    properties
        prefs = {'x_pos', 'y_pos', 'x_movement_um', 'y_movement_um', 'laser_center', 'reverse_step_direction'};
    end
    properties(SetObservable)
        camera;
        stage;
    end
    methods(Static)
        obj = instance()
    end
    methods(Access = private)
        function obj = FullChipScanner()
            obj.camera = Imaging.Hamamatsu.instance;
            obj.stage = Drivers.Attocube.ANC350.instance("18.25.29.30");
            obj.loadPrefs;
            try
                obj.current_position_um = round(obj.stage.get_coordinate_um);
            catch err
                warning(sprintf("Error fetching stage position: %s", err.message));
            end
            try 
                obj.stage_listener = addlistener(obj.stage, 'update_position', @obj.update_position);
            catch err
                warning(sprintf("Position listener for stage is not set properly. Please add `get_coordinate_um` method to the current stage."));
            end

        end
    end
    methods
        function delete(obj)
            obj.camera = Imaging.Hamamatsu.empty(1, 0); % Only set the handles to empty and avoid deleting the drivers. 
            obj.stage = Drivers.Attocube.ANC350.empty(1, 0);
            try
                delete(obj.stage_listener);
            catch err
                warning(sprintf("Error deleting stage_listener, %s", err.message))
            end
        end
        function success = step_approximate(obj, axis_name, forward, max_steps, max_wrong_cnt, step_delay_s)
            if ~obj.initialized
                % Disable movement if CommandCenter is not fully initialized
                return
            end
            % Use absolute position to approximately move the stage (x_movement_um)
            % success: logical scalar, if true when this movement is successful; false if error occurs
            assert(any(strcmp(axis_name, {'x', 'y', 'X', 'Y'})), "axis_name should be one of {'x', 'X', 'y', 'Y'}");
            assert(islogical(forward), "Second argument (forward) should be ether true or false");
            success = false;
            initial_position_um = obj.stage.get_coordinate_um(5);
            obj.current_position_um = round(initial_position_um);
            fprintf("Start moving along %s axis\n", axis_name);
            fprintf("  initial position: (%.2f, %.2f, %.2f)\n", initial_position_um(1), initial_position_um(2), initial_position_um(3));
            target_position_um = initial_position_um + obj.x_movement_um;
            fprintf("  target position: (%.2f, %.2f, %.2f)\n", target_position_um(1), target_position_um(2) , target_position_um(3));
            if ~exist('max_steps', 'var')
                max_steps = 50;
            end
            if ~exist('max_wrong_cnt', 'var')
                % reverse the stepping direction after 3 wrong moves.
                max_wrong_cnt = 3;
            end
            if ~exist('step_delay_s', 'var')
                % Time interval between each moving steps
                step_delay_s = 0.2;
            end
            for checkpoint = [0.5, 1]  % Finish the whole process in how many subroutines (using checkpoint)
                for axis_num = 1:3
                    if strcmp(axis_name, 'x') || strcmp(axis_name, 'X')
                        target_movement = obj.x_movement_um(axis_num)*checkpoint;
                    else
                        target_movement = obj.y_movement_um(axis_num)*checkpoint;
                    end
                    if ~forward
                        target_movement = ~target_movement;
                    end
                    wrong_cnt = 0;
                    reverse_direction = obj.reverse_step_direction;

                    current_movement = obj.current_position_um(axis_num) - initial_position_um(axis_num);
                    for k = 1:ceil(max_steps*checkpoint)
                        obj.stage.lines(axis_num).steps_moved = obj.stage.lines(axis_num).steps_moved + xor(sign(target_movement), reverse_direction);
                        current_position_um = obj.stage.get_coordinate_um(5);
                        obj.current_position_um = round(current_position_um);
                        step_movement = current_position_um(axis_num) - initial_position_um(axis_num)-current_movement; % Position increament of this single step
                        current_movement = current_position_um(axis_num) - initial_position_um(axis_num);
                        if step_movement*target_movement < 0 || abs(step_movement) < 0.5 % moving toward a wrong direction or the stage is not moving (less than 0.5um)
                            wrong_cnt = wrong_cnt + 1;
                            if wrong_cnt >= max_wrong_cnt
                                reverse_direction = ~reverse_direction;
                                if reverse_direction == obj.reverse_step_direction % Tried both directions: failed to go to the correct place
                                    success = false;
                                    warning("Stepping failed. Please check the stage output.")
                                    return;
                                end
                                wrong_cnt = 0;
                            end
                        else % moving toward a correct direction
                            wrong_cnt = 0;
                            if abs(current_movement) > abs(target_movement)
                                break;
                            end
                        end
                        pause(step_delay_s);
                    end
                end
            end
            success = true;
        end
        function val = set_x_pos(obj, val, ~)
            if ~obj.initialized
                % Disable movement if CommandCenter is not fully initialized
                return
            end
            assert(abs(val-obj.prev_x_pos) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-obj.prev_x_pos) == 1
                val = obj.prev_x_pos + (val - obj.prev_x_pos)*int8(obj.step_approximate('x', val-obj.prev_x_pos == 1));
            end
            obj.prev_x_pos = val;
        end
        function val = set_y_pos(obj, val, ~)
            if ~obj.initialized
                % Disable movement if CommandCenter is not fully initialized
                return
            end
            assert(abs(val-obj.prev_y_pos) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-obj.prev_y_pos) == 1
                val = obj.prev_y_pos + (val - obj.prev_y_pos)*int8(obj.step_approximate('y', val-obj.prev_y_pos == 1));
            end
            obj.prev_y_pos = val;
        end
        function val = set_calibrate_x_movement(obj, val, ~)
            if val == obj.prev_calibrate_x_movement % Otherwise this function will be executed 2 times for unknown reason.
                return;
            end
            persistent prev_position;
            if ~exist('prev_position', 'var') || isempty(prev_position)
                prev_position = obj.stage.get_coordinate_um(5);
            end
            persistent prev_steps_moved;
            if ~exist('prev_steps_moved', 'var') || isempty(prev_steps_moved)
                prev_steps_moved = obj.stage.get_steps_moved;
            end
            new_position = obj.stage.get_coordinate_um(5);
            if val
                fprintf("x movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%f, %f, %f)\n", new_position(1), new_position(2), new_position(3));
                
            else
                fprintf("x movement calibration ended. Final stage position: (%f, %f, %f)\n", new_position(1), new_position(2), new_position(3));
                obj.x_movement_um = new_position-prev_position;
                steps_moved = obj.stage.get_steps_moved - prev_steps_moved;
                movement = obj.x_movement_um;
                movement(abs(movement) < 1) = 0;
                if all(double(steps_moved).*movement >= 0)
                    % If steps have the same direction as absolute movements.
                    obj.reverse_step_direction = false;
                elseif all(double(steps_moved).*movement <= 0)
                    % If steps have the opposite direction as absolute movements.
                    obj.reverse_step_direction = true;
                end
                fprintf("Movement: (%f, %f, %f)\n", obj.x_movement_um(1), obj.x_movement_um(2), obj.x_movement_um(3));
                fprintf("Steps moved: (%d, %d, %d)\n", steps_moved(1), steps_moved(2), steps_moved(3))
            end
            prev_position = new_position;
            prev_steps_moved = obj.stage.get_steps_moved;   

            obj.prev_calibrate_x_movement = val;
        end
        function val = set_calibrate_y_movement(obj, val, ~)
            
            if val == obj.prev_calibrate_y_movement
                return;
            end
            persistent prev_position;
            if ~exist('prev_position', 'var') || isempty(prev_position)
                prev_position = obj.stage.get_coordinate_um(5);
            end
            persistent prev_steps_moved;
            if ~exist('prev_steps_moved', 'var') || isempty(prev_steps_moved)
                prev_steps_moved = obj.stage.get_steps_moved;
            end
            new_position = obj.stage.get_coordinate_um(5);
            if val
                fprintf("y movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%f, %f, %f)\n", new_position(1), new_position(2), new_position(3));
            else
                fprintf("y movement calibration ended. Final stage position: (%f, %f, %f)\n", new_position(1), new_position(2), new_position(3));
                obj.y_movement_um = new_position-prev_position;
                steps_moved = obj.stage.get_steps_moved - prev_steps_moved;
                movement = obj.y_movement_um;
                movement(abs(movement) < 1) = 0;
                if all(double(steps_moved).*movement >= 0)
                    % If steps have the same direction as absolute movements.
                    obj.reverse_step_direction = false;
                elseif all(double(steps_moved).*movement <= 0)
                    % If steps have the opposite direction as absolute movements.
                    obj.reverse_step_direction = true;
                end
                fprintf("Movement: (%f, %f, %f)\n", obj.y_movement_um(1), obj.y_movement_um(2), obj.y_movement_um(3));
                fprintf("Steps moved: (%d, %d, %d)\n", steps_moved(1), steps_moved(2), steps_moved(3))
            end
            prev_position = new_position;    
            prev_steps_moved = obj.stage.get_steps_moved;   
            obj.prev_calibrate_y_movement = val;
        end
        function val = set_laser_center_graphical(obj, val, ~)
            img = obj.camera.snapImage;
            fig = figure(53);
            ax = axes('Parent', fig);
            imH = imagesc(ax, img);
            hold(ax, 'on');
            colormap(ax, 'bone');
            y_size = size(img, 1);
            x_size = size(img, 2);
            if any(isnan(obj.laser_center))
                pointH = images.roi.Point(ax, 'Deletable', false, 'Position', round([x_size/2, y_size/2]));
            else
                pointH = images.roi.Point(ax, 'Deletable', false, 'Position', obj.laser_center);
            end
            set(get(ax, 'Title'), 'String', sprintf('Please drag the point to set laser center.\nPress enter or right click the image to confirm.'));
            imH.ButtonDownFcn = @ROIConfirm;
            fig.KeyPressFcn = @ROIConfirm;
            uiwait(fig);
            obj.laser_center = round(pointH.Position);
            delete(fig);
        end
        function update_position(obj, varargin)
            obj.current_position_um = round(obj.stage.get_coordinate_um);
        end
        function reload_stage(obj, varargin)
            obj.stage = Drivers.Attocube.ANC350.instance("18.25.29.30");
        end
    end
        
end