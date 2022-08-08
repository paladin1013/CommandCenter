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
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        stage = Prefs.ModuleInstance(Drivers.Attocube.ANC350.instance("18.25.29.30"), 'inherits', {'Modules.Driver'});
    end
    properties(Access=private)
        stage_listener;
        prev_x_pos = 0;
        prev_y_pos = 0;
        prev_calibrate_x_movement = false;
        prev_calibrate_y_movement = false;
        position_update_listener;
    end
    methods(Static)
        obj = instance()
    end
    methods(Access = private)
        function obj = FullChipScanner()
            obj.loadPrefs;
            try
                obj.current_position_um = round(obj.stage.get_coordinate_um);
            catch err
                warning(fprintf("Error fetching stage position: %s", err.message));
            end
            try 
                obj.position_update_listener = addlistener(obj.stage, 'update_position', @obj.update_position);
            catch err
                warning(fprinf("Position listener for stage is not set properly. Please add `get_coordinate_um` method to the current stage."));
            end

        end
    end
    methods
        function delete(obj)
            try
                delete(stage_listener);
            catch
                warning(sprintf("Error deleting stage_listener, %s", err.message))
            end
        end
        function success = move(obj, axis_name, forward)
            % success: logical scalar, if true when this movement is successful; false if error occurs
            success = false;
            assert(strcmp(axis_name, 'x') || strcmp(axis_name, 'y'), "axis_name should be one of {'x', 'y'}");
            assert(islogical(forward), "Second argument (forward) should be ether true or false");

        end
        function val = set_x_pos(obj, val, ~)
            assert(abs(val-obj.prev_x_pos) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-obj.prev_x_pos) == 1
                val = val + (obj.prev_x_pos-val)*int8(obj.move('x', val-obj.prev_x_pos == 1));
            end
            obj.prev_x_pos = val;
        end
        function val = set_y_pos(obj, val, ~)
            assert(abs(val-obj.prev_y_pos) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-obj.prev_y_pos) == 1
                val = val + (obj.prev_y_pos-val)*int8(obj.move('y', val-obj.prev_y_pos == 1));
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
            new_position = obj.stage.get_coordinate_um(5);
            if val
                fprintf("x movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                
            else
                fprintf("x movement calibration ended. Final stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                obj.x_movement_um = new_position-prev_position;
                fprintf("Movement: (%d, %d, %d)\n", obj.x_movement_um(1), obj.x_movement_um(2), obj.x_movement_um(3));
            end
            prev_position = new_position;    
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
            new_position = obj.stage.get_coordinate_um(5);
            if val
                fprintf("y movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
            else
                fprintf("y movement calibration ended. Final stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                obj.y_movement_um = new_position-prev_position;
                fprintf("Movement: (%d, %d, %d)\n", obj.y_movement_um(1), obj.y_movement_um(2), obj.y_movement_um(3));
            end
            prev_position = new_position;    
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
    end
        
end