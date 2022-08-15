classdef FullChipScanner < Modules.Driver
    properties(SetObservable, GetObservable)
        

        x_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'default_step', 1, 'set', 'set_x_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        y_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'default_step', 1, 'set', 'set_y_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        x_movement_step = Prefs.DoubleArray([0, 0, 0], 'unit', 'step', 'allow_nan', false, 'min', -200, 'max', 200, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along x axis');
        y_movement_step = Prefs.DoubleArray([0, 0, 0], 'unit', 'step', 'allow_nan', false, 'min', -200, 'max', 200, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along y axis');
        current_position_um = Prefs.DoubleArray([NaN, NaN, NaN], 'unit', 'um', 'readonly', true, 'help', 'Current piezo stage position');
        calibrate_x_movement = Prefs.ToggleButton(false, 'set', 'set_calibrate_x_movement', 'help', 'First move along x axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        calibrate_y_movement = Prefs.ToggleButton(false, 'set', 'set_calibrate_y_movement', 'help', 'First move along y axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        laser_center = Prefs.DoubleArray([NaN, NaN], 'unit', 'pixel', 'help', 'Laser center relative position in the camera image.'); % Regular 
        set_laser_center = Prefs.Button('set', 'set_laser_center_callback', 'help', 'Set the relative position of laser center on the current snapped image');
        start_align_laser = Prefs.ToggleButton(false, 'set', 'start_align_laser_callback', 'help', 'Align the center of the current chiplet to the laser center.');
        step_delay_s = Prefs.Double(0.25, 'unit', 's', 'help', 'Delay between each stage steps');
        flip_x_movement = Prefs.Boolean(true, 'help', 'Whether the x direction of stage steps is the same as the movement x direction of the image.');
        flip_y_movement = Prefs.Boolean(false, 'help', 'Whether the x direction of stage steps is the same as the movement x direction of the image.');
        % reverse_step_direction = Prefs.Boolean(true, 'help', 'Check this option if stepping stage forward will result in decreasing of the absolute position.');
        abort

        % stage = Prefs.ModuleInstance(Drivers.Attocube.ANC350.instance("18.25.29.30"), 'inherits', {'Modules.Driver'});
    end
    properties(Access=private)
        stage_listener;
        prev_x_pos = 0;
        prev_y_pos = 0;
        prev_calibrate_x_movement = false;
        prev_calibrate_y_movement = false;
        initialized = false;
        laser_alignment_running = false;
    end
    properties
        prefs = {'x_pos', 'y_pos', 'x_movement_step', 'y_movement_step', 'laser_center', 'flip_x_movement', 'flip_y_movement'};
    end
    properties(SetObservable)
        stage;
        tracker;
    end
    methods(Static)
        obj = instance()
    end
    methods(Access = private)
        function obj = FullChipScanner()
            obj.stage = Drivers.Attocube.ANC350.instance("18.25.29.30");
            obj.tracker = Imaging.ChipletTracker.instance();
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
            obj.stage = Drivers.Attocube.ANC350.empty(1, 0);
            obj.tracker = Imaging.ChipletTracker.empty(1, 0);
            try
                delete(obj.stage_listener);
            catch err
                warning(sprintf("Error deleting stage_listener, %s", err.message))
            end
        end
        function success = step_approximate(obj, axis_name, forward)
            if ~obj.initialized
                % Disable movement if CommandCenter is not fully initialized
                return
            end
            % success: logical scalar, if true when this movement is successful; false if error occurs
            assert(any(strcmp(axis_name, {'x', 'y', 'X', 'Y'})), "axis_name should be one of {'x', 'X', 'y', 'Y'}");
            assert(islogical(forward), "Second argument (forward) should be ether true or false");

            if strcmp(axis_name, 'x')
                stage_steps = obj.x_movement_step;
            else
                stage_steps = obj.y_movement_step;
            end
            
            if forward == false
                stage_steps = -stage_steps;
            end
            success = true;
            prev_steps_moved = obj.stage.get_steps_moved;
            for line = 1:3
                for k = 1:abs(stage_steps(line))
                    obj.stage.lines(line).steps_moved = obj.stage.lines(line).steps_moved + sign(stage_steps(line));
                    pause(obj.step_delay_s);
                end
            end
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
            prev_detect_chiplets = obj.tracker.detectChiplets;
            obj.tracker.detectChiplets = false;
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
            new_steps_moved = obj.stage.get_steps_moved;
            if val
                fprintf("x movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage steps_moved: (%d, %d, %d)\n", new_steps_moved(1), new_steps_moved(2), new_steps_moved(3));
            else
                fprintf("x movement calibration ended. Final stage steps_moved: (%d, %d, %d)\n", new_steps_moved(1), new_steps_moved(2), new_steps_moved(3));
                movement_um = new_position-prev_position;
                steps_moved = obj.stage.get_steps_moved - prev_steps_moved;
                obj.x_movement_step = steps_moved;
                fprintf("Steps moved: (%d, %d, %d)\n", steps_moved(1), steps_moved(2), steps_moved(3))
                fprintf("Movement: (%f, %f, %f)\n", movement_um(1), movement_um(2), movement_um(3));
            end
            prev_position = new_position;
            prev_steps_moved = new_steps_moved;   
            obj.prev_calibrate_x_movement = val;
            obj.tracker.detectChiplets = prev_detect_chiplets;
        end
        function val = set_calibrate_y_movement(obj, val, ~)
            prev_detect_chiplets = obj.tracker.detectChiplets;
            obj.tracker.detectChiplets = false;
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
            new_steps_moved = obj.stage.get_steps_moved;
            if val
                fprintf("y movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage steps_moved: (%d, %d, %d)\n", new_steps_moved(1), new_steps_moved(2), new_steps_moved(3));

            else
                fprintf("y movement calibration ended. Final stage steps_moved: (%d, %d, %d)\n", new_steps_moved(1), new_steps_moved(2), new_steps_moved(3));
                movement_um = new_position-prev_position;
                steps_moved = new_steps_moved - prev_steps_moved;
                obj.y_movement_step = steps_moved;
                fprintf("Steps moved: (%d, %d, %d)\n", steps_moved(1), steps_moved(2), steps_moved(3))
                fprintf("Movement: (%f, %f, %f)\n", movement_um(1), movement_um(2), movement_um(3));
            end
            prev_position = new_position;    
            prev_steps_moved = new_steps_moved;   
            obj.prev_calibrate_y_movement = val;
            obj.tracker.detectChiplets = prev_detect_chiplets;
        end
        function val = set_laser_center_callback(obj, val, ~)
            img = obj.tracker.snapImage;
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
        function align_laser(obj)
            % obj.tracker.focus;
            try
                obj.tracker.stopVideo;
            catch
            end
            distance = norm([obj.tracker.chipletPositionX, obj.tracker.chipletPositionY] - obj.laser_center);
            move_x = true;
            while distance > 10 && obj.laser_alignment_running
                if move_x
                    diff = obj.laser_center(1) - obj.tracker.chipletPositionX;
                    if obj.flip_x_movement
                        step = -sign(diff);
                    else
                        step = sign(diff);
                    end
                    obj.stage.lines(1).steps_moved = obj.stage.lines(1).steps_moved + step;
                    pause(obj.step_delay_s);
                    obj.tracker.snap;
                    diff = [obj.tracker.chipletPositionX, obj.tracker.chipletPositionY] - obj.laser_center;
                    distance = norm(diff);
                    if diff(2) >= 5
                        move_x = false;
                    end

                else
                    diff = obj.laser_center(2) - obj.tracker.chipletPositionY;
                    if obj.flip_y_movement
                        step = -sign(diff);
                    else
                        step = sign(diff);
                    end
                    obj.stage.lines(2).steps_moved = obj.stage.lines(2).steps_moved + step;
                    pause(obj.step_delay_s);
                    obj.tracker.snap;
                    diff = [obj.tracker.chipletPositionX, obj.tracker.chipletPositionY] - obj.laser_center;
                    distance = norm(diff);
                    if diff(1) >= 5
                        move_x = true;
                    end
                end
            end
            obj.laser_alignment_running = false;
            obj.start_align_laser = false;
        end
        function val = start_align_laser_callback(obj, val, ~)
            obj.laser_alignment_running = val;
            if val
                obj.align_laser;
            end
        end
        function update_position(obj, varargin)
            obj.current_position_um = round(obj.stage.get_coordinate_um);
        end
        function reload_stage(obj, varargin)
            obj.stage = Drivers.Attocube.ANC350.instance("18.25.29.30");
        end
    end
        
end