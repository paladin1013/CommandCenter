classdef FullChipScanner < Modules.Driver
    properties(SetObservable, GetObservable)
        x_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'set', 'set_x_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        y_pos = Prefs.Integer(0, 'min', -5, 'max', 5, 'steponly', true, 'set', 'set_y_pos', 'help', 'The chiplet coordinate relative to the origin chiplet.');
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        stage = Prefs.ModuleInstance(Drivers.Attocube.ANC350.instance("18.25.29.30"), 'inherits', {'Modules.Driver'});
        x_movement_um = Prefs.DoubleArray([0, 0, 0], 'unit', 'um', 'allow_nan', false, 'min', -50, 'max', 50, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along x axis');
        y_movement_um = Prefs.DoubleArray([0, 0, 0], 'unit', 'um', 'allow_nan', false, 'min', -50, 'max', 50, 'help', 'The approximate distance piezo stage need to move in 3 axis when moving forward along y axis');
        current_position_um = Prefs.DoubleArray([NaN, NaN, NaN], 'unit', 'um', 'readonly', true, 'help', 'Current piezo stage position');
        calibrate_x_movement = Prefs.Button('set', 'set_calibrate_x_position', 'help', 'First move along x axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        calibrate_y_movement = Prefs.Button('set', 'set_calibrate_y_position', 'help', 'First move along y axis to aling the center of the next chiplet with the laser center, then press this button again to confirm.');
        laser_center = Prefs.DoubleArray([NaN, NaN], 'unit', 'pixel', 'help', 'Laser center relative position in the camera image.'); % Regular 
        set_laser_center = Prefs.Button('set', 'set_laser_center_graphical', 'help', 'Set the relative position of laser center on the current snapped image');
    end
    properties(Access=private)
        stage_listener;
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
            % obj.stage_listener = addlistener(hSource, EventName, callback)

        end
    end
    methods
        function success = move(obj, axis_name, forward)
            % success: logical scalar, if true when this movement is successful; false if error occurs
            success = false;
            assert(strcmp(axis_name, 'x') || strcmp(axis_name, 'y'), "axis_name should be one of {'x', 'y'}");
            assert(islogical(forward), "Second argument (forward) should be ether true or false");

        end
        function val = set_x_pos(obj, val, ~)
            prev_val = obj.x_pos;
            assert(abs(val-prev_val) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-prev_val) == 1
                val = val + (prev_val-val)*int8(obj.move('x', val-prev_val == 1));
            end
        end
        function val = set_y_pos(obj, val, ~)
            prev_val = obj.y_pos;
            assert(abs(val-prev_val) <= 1, "The full chip scanner can only move one step each time.");
            if abs(val-prev_val) == 1
                val = val + (prev_val-val)*int8(obj.move('y', val-prev_val == 1));
            end
        end
        function val = set_calibrate_x_position(obj, val, ~)
            persistent calibration_started;
            persistent prev_position;
            if ~exist('calibration_started', 'var')
                calibration_started = false;
                prev_position = obj.stage.get_coordinate_um;
            end
            calibration_started = ~calibration_started; % Change state first
            new_position = obj.stage.get_coordinate_um;
            if calibration_started
                fprintf("x movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                
            else
                fprintf("x movement calibration ended. Final stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                obj.x_movement_um = new_position-prev_position;
                fprintf("Movement: (%d, %d, %d)\n", obj.x_movement_um(1), obj.x_movement_um(2), obj.x_movement_um(3));
            end
            prev_position = new_position;    
        end
        function val = set_calibrate_y_position(obj, val, ~)
            persistent calibration_started;
            persistent prev_position;
            if ~exist('calibration_started', 'var')
                calibration_started = false;
                prev_position = obj.stage.get_coordinate_um;
            end
            calibration_started = ~calibration_started; % Change state first
            new_position = obj.stage.get_coordinate_um;
            if calibration_started
                fprintf("y movement calibration started. Please move the stage until the center of the next chiplet is aligned with the laser center, then press this button again.\n");
                fprintf("Initial stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
            else
                fprintf("y movement calibration ended. Final stage position: (%d, %d, %d)\n", new_position(1), new_position(2), new_position(3));
                obj.y_movement_um = new_position-prev_position;
                fprintf("Movement: (%d, %d, %d)\n", obj.y_movement_um(1), obj.y_movement_um(2), obj.y_movement_um(3));
            end
            prev_position = new_position;    
        end
        function val = set_laser_center_graphical(obj, val, ~)
            img = camera.snapImage;
            fig = figure(53);
            ax = axes('Parent', fig);
            imH = imagesc(ax, img);
            hold(ax, 'on');
            colormap(ax, 'bone');
            y_size = size(img, 1);
            x_size = size(img, 2);
            if any(isnan(obj.laser_center))
                pointH = image.roi.Point(ax, 'Position', round([x_size/2, y_size/2]));
            else
                pointH = image.roi.Point(ax, 'Position', obj.laser_center);
            end
            set(get(ax, 'Title'), 'String', sprintf('Press enter or right click the image to confirm laser center.'));
            imH.ButtonDownFcn = @ROIConfirm;
            fig.KeyPressFcn = @ROIConfirm;
            uiwait(frame_fig);
            imgCorners = round(polyH.Position);
            delete(polyH);
            im = obj.drawCorners(img);
            delete(imH);
            imH = imagesc(ax, im);
            set(get(ax, 'XLabel'), 'String', 'x');
            set(get(ax, 'YLabel'), 'String', 'y');
            colormap(ax, 'bone');
        end
    end
        
end