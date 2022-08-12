classdef ChipletTracker < Modules.Imaging
    % Track the chiplet position with images taken by other imaging modules (eg.EMCCD); 
    %   
    
    properties(SetObservable, GetObservable)
        exposure_ms = Prefs.Double(100, 'unit', 'ms', 'set', 'set_exposure_ms', 'help', 'Will override the exposure time in the camera.')
        initTemplate = Prefs.Button('unit', 'Snap', 'set', 'set_initTemplate', 'help', 'Start to set a template and assign its corners.')
        matchTemplate = Prefs.Boolean(true);
        contrast = Prefs.Double(NaN, 'readonly', true, 'help', 'Difference square contrast. Larger contrast indicates being better focused.');
        contrastOffset = Prefs.Integer(5, 'min', 1, 'max', 10, 'help', 'Move image `offset` pixels then calculate the contrast.');
        brightness = Prefs.Double(NaN, 'readonly', true, 'help', 'Average value off the intensity of the current image.');
        brightnessThreshold = Prefs.Double(5000, 'allow_nan', false, 'help', 'Brightness lower than this value will disable the template matching.');
        maxMovement = Prefs.Double(50, 'min', 10, 'max', 100, 'help', 'Maximum possible movement of both template position and image center position. Single movement larger than this value will be filtered out.');
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        processor = Prefs.ModuleInstance(Drivers.ImageProcessor.instance, 'inherits', {'Modules.Driver'});
        offsetAngle = Prefs.Double(0, 'min', 0, 'max', 1, 'help', 'The offset angle of the image relative to the horizontal position.');
        prefs = {'exposure_ms', 'contrast', 'contrastOffset', 'initTemplate', 'matchTemplate', 'maxMovement', 'offsetAngle'};
    end
    properties
        maxROI
    end
    properties(SetObservable)
        continuous = false;
        resolution = [NaN NaN]; % Set in constructor and set.binning
        ROI              % Region of Interest in pixels [startX startY; stopX stopY]
    end
    properties(Access=private)
        videoTimer       % Handle to video timer object for capturing frames
        hImage          % Handle to the smartimage in ImagingManager. Use snap or startVideo to initialize
        hManagers       % Handle to CommandCenter managers. Will be set when `focus` is called from the ImagingManager.
        template = [];
        frameCnt = 0;           % Frame num counter for updating pattern detection (in video mode). 
        prevTemplatePos = []; % 2*2 matrix to store the coordinates of two rounds.
        templatePos;            % Imaging Coordinates
        prevCenterPos = [];
        centerPos;              % Normal Coordinates
        prevContrast;
        templateCorners;
    end
    
    methods(Access=private)
        function obj = ChipletTracker()
            obj.loadPrefs;
            obj.frameCnt = 0;
            obj.continuous = false;
            obj.camera = Imaging.Hamamatsu.instance;
            obj.processor = Drivers.ImageProcessor.instance;
            obj.ROI = obj.camera.ROI;
            obj.maxROI = obj.camera.maxROI;
            obj.resolution = obj.camera.resolution;
        end
    end
    methods(Static)
        obj = instance()
    end
    methods
        function metric = focus(obj,ax,managers) %#ok<INUSD>
            if ~exist('managers', 'var')
                if isempty(obj.hManagers)
                    error("Please click Auto Focus on the Imaging panel to assign the managers handle");
                else
                    managers = obj.hManagers;
                end
            else
                obj.hManagers = managers;
            end

            ms = managers.MetaStage.active_module;

            Z = ms.get_meta_pref('Z');
            anc = Drivers.Attocube.ANC350.instance('18.25.29.30');
            Zline = anc.lines(3);
            if isempty(Z.reference) || ~strcmp(replace(Z.reference.name, ' ', '_'), 'steps_moved') || ~isequal(Z.reference.parent.line, 3)
                Z.set_reference(Zline.get_meta_pref('steps_moved'));
            end


            Target = ms.get_meta_pref('Target');
            if isempty(Target.reference) || ~strcmp(Target.reference.name, 'contrast')
                Target.set_reference(obj.get_meta_pref('contrast'));
            end
            
            managers.MetaStage.optimize('Z', true);
            metric = Target.read;
        end
        function stop_triggered_acquisition(obj)
            obj.core.stopSequenceAcquisition()
        end
        function delete(obj)
            obj.camera = Imaging.Hamamatsu.empty(1, 0); % Avoid deleting the camera instance
        end

        function dat = snapImage(obj)
            wasRunning = false;
            if obj.continuous == true
                wasRunning = true;
                obj.stopVideo;
            end
            dat = obj.camera.snapImage;
            if wasRunning
                obj.startVideo;
            end
        end
        function startSnapping(obj)
            if obj.core.isSequenceRunning
                obj.core.stopSequenceAcquisition;
            end
            while(obj.core.getRemainingImageCount > 0)
                obj.core.popNextImage;
            end
            obj.core.startContinuousSequenceAcquisition(100);
        end
        function dat = fetchSnapping(obj)
            while(obj.core.getRemainingImageCount == 0)
                pause(0.01);
            end
            dat = obj.core.popNextImage;
            width = obj.core.getImageWidth();
            height = obj.core.getImageHeight();
            obj.core.stopSequenceAcquisition;
            dat = typecast(dat, 'uint16');
            dat = reshape(dat, [width, height]);
            if obj.ImRot90 > 0
                dat = rot90(dat,obj.ImRot90);
            end
            if obj.FlipVer
                dat = flipud(dat);
            end
            if obj.FlipHor
                dat = fliplr(dat);
            end
        end

        function snap(obj,hImage)
            % This function calls snapImage and applies to hImage.
            if ~exist('hImage', 'var')
                if isempty(obj.hImage)
                    error('Please click `snap` in image panel to initialize obj.hImage');
                end
                hImage = obj.hImage;
            else
                obj.hImage = hImage;
            end
            im = obj.snapImage;
            obj.updateContrast(im);
            if obj.matchTemplate
                im = obj.updateMatching(im, true); % Enable forced update
            end
            set(hImage,'cdata',im);
        end
        function startVideo(obj,hImage)
            if ~exist('hImage', 'var')
                if isempty(obj.hImage)
                    error('Please click `snap` in image panel to initialize obj.hImage');
                end
                hImage = obj.hImage;
            else
                obj.hImage = hImage;
            end
            obj.camera.startSnapping;
            obj.videoTimer = timer('tag','Video Timer',...
                                'ExecutionMode','FixedSpacing',...
                                'BusyMode','drop',...
                                'Period', obj.exposure_ms/1e3/2,...
                                'TimerFcn',{@obj.grabFrame,hImage}); % Use exposure time as timer period to detect the frame update
            start(obj.videoTimer)
            obj.continuous = true;
        end
        function grabFrame(obj,~,~,hImage)
            % Timer Callback for frame acquisition
            dat = obj.camera.fetchSnapping(0, true);
            if isempty(dat)
                return
            end
            % obj.camera.startSnapping; % To save time
            obj.updateContrast(dat);

            if obj.matchTemplate 
                if obj.contrast > 0.7*obj.prevContrast
                    % To prevent position shift caused by stage shifting
                    dat = obj.updateMatching(dat); % 0.1s
                end
            end
            set(hImage,'cdata',dat);
            drawnow; % 0.1s
        end
        function stopVideo(obj)
            obj.camera.stopSnapping;
            stop(obj.videoTimer)
            delete(obj.videoTimer)
            obj.continuous = false;
        end
        
        function contrast = updateContrast(obj,frame)
            frame = double(frame);
            xmin = obj.contrastOffset+1;
            xmax = size(frame, 2)-obj.contrastOffset;
            ymin = obj.contrastOffset+1;
            ymax = size(frame, 1)-obj.contrastOffset;
            image = frame(ymin:ymax,xmin:xmax);
            imagex = frame(ymin:ymax,xmin+obj.contrastOffset:xmax+obj.contrastOffset);
            imagey = frame(ymin+obj.contrastOffset:ymax+obj.contrastOffset,xmin:xmax);
            dI = (imagex-image).^2+(imagey-image).^2;
            contrast = mean2(dI);
            obj.prevContrast = obj.contrast;
            obj.contrast = contrast;
            obj.brightness = mean2(frame);
        end
        function snapTemplate(obj, im)
            if ~exist('im', 'var') || isempty(im)
                im = obj.snapImage;
            end
            [template, segments] = obj.processor.processImage(im, struct('pixelThresRatio', 1, 'display', 'Raw')); % When snapping the template, only keep the maximal segment.
            if isempty(segments)
                return;
            end
            obj.template = segments{1}.image;
            frame_fig = figure(41);
            frame_fig.Position = [200, 200, 560, 420];
            frame_ax = axes('Parent', frame_fig);
            imH = imagesc(frame_ax, obj.template);
            colormap(frame_ax, 'bone');
            x_size = size(obj.template, 2);
            y_size = size(obj.template, 1);
            if isempty(obj.templateCorners)
                polyH = drawpolygon(frame_ax, 'Position', [1, x_size, x_size, 1; 1, 1, y_size, y_size]');
            else
                polyH = drawpolygon(frame_ax, 'Position', obj.templateCorners);
            end
            set(get(frame_ax, 'Title'), 'String', sprintf('Press enter or right click the outside image to confirm template corners.'));
            imH.ButtonDownFcn = @ROIConfirm;
            frame_fig.KeyPressFcn = @ROIConfirm;
            uiwait(frame_fig);
            obj.templateCorners = round(polyH.Position);
            delete(polyH);
        end
        function display_im = updateMatching(obj, im, forceUpdate)
            persistent wasBright
            if ~exist('wasBright', 'var')
                wasBright = true;
            end
            if obj.brightness < obj.brightnessThreshold
                if wasBright
                    fprintf("Current brightness %d is lower than its threshold %d. Matching template is temporarily disabled.\n", obj.brightness, obj.brightnessThreshold);
                    wasBright = false;
                    display_im = im;
                    return;
                end
                wasBright = false;
            else
                wasBright = true;
            end


            if ~exist('forceUpdate', 'var')
                forceUpdate = false;
            end
            if isempty(obj.template) || isempty(obj.templateCorners)
                obj.snapTemplate(im);
            end
            [display_im, segments] = obj.processor.processImage(im);
            % [processed_im, segment_images] = frame_detection(im, false, struct('pixel_thres_ratio', obj.pixelThresRatio));
            
            % if obj.showFiltered
            %     im = processed_im*65535;
            % end

            % nSegments = length(segment_images);
            % corrValues = zeros(nSegments, 1);
            % matchingPositions = zeros(nSegments, 2);
            % for k = 1:nSegments
            %     [matchingPositions(k, :), corrValues(k)] = image_matching(processed_im, obj.template);
            % end
            % corrMax = max(corrValues);
            % for k = 1:nSegments
            %     if corrValues(k) > corrMax*obj.pixelThresRatio
            %         im = obj.drawMatching(im, matchingPositions(k, :), obj.template, obj.templateCorners, 65535);
            %     end
            % end

            % MatchingPos is the top right coner of the template image inserted into the target image.
            % switch size(obj.prevTemplatePos, 1)
            % case 0
            %     obj.prevTemplatePos(1, :) = matchingPos;
            %     obj.templatePos = matchingPos;
            % case 1
            %     if forceUpdate || norm(matchingPos-obj.prevTemplatePos) < obj.maxMovement
            %         obj.templatePos = matchingPos;
            %     end
            %     obj.prevTemplatePos(2, :) = matchingPos;
            % case 2
            %     if forceUpdate || norm(matchingPos - obj.prevTemplatePos(1, :)) < obj.maxMovement && norm(matchingPos - obj.prevTemplatePos(2, :)) < obj.maxMovement 
            %         obj.templatePos = matchingPos;
            %     end
            %     obj.prevTemplatePos(1, :) = obj.prevTemplatePos(2, :);
            %     obj.prevTemplatePos(2, :) = matchingPos;
            % otherwise
            %     error(fprintf("size(obj.prevTemplatePos, 1) should be at most 2, but got %d.", size(obj.prevTemplatePos)));
            % end
        end
        function im = drawMatching(obj, im, pos, template, templateCorners, fill_color) % pos is in image coordinate i.e. (y, x)
            y = pos(1);
            x = pos(2);
            template_y = size(template, 1);
            template_x = size(template, 2);

            im_y = size(im, 1);
            im_x = size(im, 2);
            % Draw a white box directly onto the image
            if x <= im_x
                im(max(y-template_y, 1):min(y, im_y), x) = fill_color;
            end
            if x-template_x >= 1
            im(max(y-template_y, 1):min(y, im_y), x-template_x) = fill_color;
            end
            if y <= im_y
                im(y, max(x-template_x, 1):min(x, im_x)) = fill_color;
            end
            if y-template_y >= 1
                im(y-template_y, max(x-template_x, 1):min(x, im_x)) = fill_color;
            end

            offset = pos - size(template);
            % Draw Corners
            if ~exist('radius', 'var')
                radius = 2;
            end
            for k = 1:4
                corner_y = templateCorners(k, 2)+offset(1);
                corner_x = templateCorners(k, 1)+offset(2);
                im(confine(corner_y-radius, 1, im_y):confine(corner_y+radius, 1, im_y), confine(corner_x-radius, 1, im_x):confine(corner_x+radius, 1, im_x)) = fill_color;
            end
            function val = confine(val, lower_bound, upper_bound)
                val = max(min(val, upper_bound), lower_bound);
            end
            obj.centerPos = round(mean(templateCorners));
            im(confine(obj.centerPos(2)+offset(1)-radius, 1, im_y):confine(obj.centerPos(2)+offset(1)+radius, 1, im_y), confine(obj.centerPos(1)+offset(2)-radius, 1, im_x):confine(obj.centerPos(1)+offset(2)+radius, 1, im_x)) = fill_color;
        end
        function val = set_exposure_ms(obj, val, ~)
            if ~isempty(obj.camera) && isvalid(obj.camera)
                obj.camera.exposure = val;
            end
        end
        function val = set_initTemplate(obj, val, ~)
            obj.snapTemplate;
        end
        function set.ROI(obj,val)
            assert(~obj.continuous,'Cannot set while video running.')
            obj.camera.ROI = val;
        end
        function val = get.ROI(obj)
            val = obj.camera.ROI;
        end
    end
end

