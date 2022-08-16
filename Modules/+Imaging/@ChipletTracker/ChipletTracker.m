classdef ChipletTracker < Modules.Imaging
    % Track the chiplet position with images taken by other imaging modules (eg.EMCCD); 
    %   
    
    properties(SetObservable, GetObservable)
        exposure_ms = Prefs.Double(100, 'unit', 'ms', 'set', 'set_exposure_ms', 'help', 'Will override the exposure time in the camera.')
        initTemplate = Prefs.Button('unit', 'Snap', 'set', 'set_initTemplate', 'help', 'Start to set a template and assign its corners.')
        detectChiplets = Prefs.Boolean(true, 'help', 'Cancel this option will reset the tracking movements.');
        contrast = Prefs.Double(NaN, 'readonly', true, 'help', 'Difference square contrast. Larger contrast indicates being better focused.');
        contrastOffset = Prefs.Integer(5, 'min', 1, 'max', 10, 'help', 'Move image `offset` pixels then calculate the contrast.');
        brightness = Prefs.Double(NaN, 'readonly', true, 'help', 'Average value off the intensity of the current image.');
        brightnessThreshold = Prefs.Double(5000, 'allow_nan', false, 'help', 'Brightness lower than this value will disable the template matching.');
        maxMovement = Prefs.Double(150, 'min', 10, 'max', 200, 'help', 'Maximum possible movement of both template position and image center position. Single movement larger than this value will be filtered out.');
        camera = Prefs.ModuleInstance(Imaging.Hamamatsu.instance, 'inherits', {'Modules.Imaging'});
        processor = Prefs.ModuleInstance(Drivers.ImageProcessor.instance, 'inherits', {'Modules.Driver'});
        wl = Prefs.ModuleInstance(Sources.WhiteLight_remote.instance, 'inherits', {'Modules.Source'});
        movementX_pixel = Prefs.Integer(0, 'unit', 'pixel', 'readonly', true, 'help', 'Overall x movement of the camera image since detectChiplets started.')
        movementY_pixel = Prefs.Integer(0, 'unit', 'pixel', 'readonly', true, 'help', 'Overall y movement of the camera image since detectChiplets started.')
        chipletHorDistanceX_pixel = Prefs.Double(400, 'unit', 'pixel', 'help', 'Distance between two X-adjacent chiplets in pixel. Set by pressing calibrateDistanceX.');
        chipletHorDistanceY_pixel = Prefs.Double(-10, 'unit', 'pixel', 'help', 'Distance between two X-adjacent chiplets in pixel. Set by pressing calibrateDistanceX.');
        chipletVerDistanceX_pixel = Prefs.Double(20, 'unit', 'pixel', 'help', 'Distance between two Y-adjacent chiplets in pixel. Set by pressing calibrateDistanceY.');
        chipletVerDistanceY_pixel = Prefs.Double(300, 'unit', 'pixel', 'help', 'Distance between two Y-adjacent chiplets in pixel. Set by pressing calibrateDistanceY.');
        calibrateDistanceX = Prefs.ToggleButton(false, 'unit', 'start', 'set', 'set_calibrateDistanceX', 'help', 'First move along x axis (horizontal) to aling the center of the next chiplet with the laser center, then press this button again to confirm.')
        calibrateDistanceY = Prefs.ToggleButton(false, 'unit', 'start', 'set', 'set_calibrateDistanceY', 'help', 'First move along y axis (vertical) to aling the center of the next chiplet with the laser center, then press this button again to confirm.')
        chipletCoordinateX = Prefs.Integer(NaN, 'allow_nan', true, 'readonly', true, 'help', 'The chiplet-wise X coordinate of the chiplet that is closest to the imaging center.');
        chipletCoordinateY = Prefs.Integer(NaN, 'allow_nan', true, 'readonly', true, 'help', 'The chiplet-wise Y coordinate of the chiplet that is closest to the imaging center.');
        chipletPositionX = Prefs.Integer(NaN, 'allow_nan', true, 'readonly', true, 'help', 'X pisition (in image axes) of the chiplet that is closest to the imaging center.')
        chipletPositionY = Prefs.Integer(NaN, 'allow_nan', true, 'readonly', true, 'help', 'Y pisition (in image axes) of the chiplet that is closest to the imaging center.')
        resetOrigin = Prefs.Button('unit', 'Reset', 'set', 'set_resetOrigin', 'help', 'Reset chiplet coordinates and movements.')
        tolerance = Prefs.Double(0.2, 'help', 'How much difference is tolerable relative to the calibrated distance.')
        correlationThres = Prefs.Double(100000, 'min', 0, 'max', 32767^2, 'help', 'A valid movement should let the cross correlation be larger than this threshold.')
        prefs = {'exposure_ms', 'contrast', 'contrastOffset', 'initTemplate', 'detectChiplets', 'maxMovement', 'movementX_pixel', 'movementY_pixel', 'chipletCoordinateX', 'chipletCoordinateY', 'chipletPositionX', 'chipletPositionY', 'chipletHorDistanceX_pixel', 'chipletHorDistanceY_pixel', 'chipletVerDistanceX_pixel', 'chipletVerDistanceY_pixel'};
    end
    properties
        maxROI
        im = []; % Previous raw image 
        chiplets = []; % containers.Map, key: global chiplet coordinate "chipletX_chipletY"; value: struct (x, y, ...) image relative coordinate(imagePosX, imagePosY); The (x, y) order is different from the imaging coordinate (y, x) !!!!!
        managerInitialized = false;
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
        frameCnt = 0;           % Frame num counter for updating pattern detection (in video mode). 
        prevTemplatePos = []; % 2*2 matrix to store the coordinates of two rounds.
        templatePos;            % Imaging Coordinates
        prevCenterPos = [];
        centerPos;              % Normal Coordinates
        prevContrast;
        initialized = false;
        prevCalibrateDistanceX = false;
        prevCalibrateDistanceY = false;
        prevChipletPos = []; % (x, y)
        prevMovement = []; % (x, y)
    end
    
    methods(Access=private)
        function obj = ChipletTracker()
            obj.loadPrefs;
            obj.frameCnt = 0;
            obj.continuous = false;
            obj.camera = Imaging.Hamamatsu.instance;
            obj.processor = Drivers.ImageProcessor.instance;
            obj.wl = Sources.WhiteLight_remote.instance;
            obj.ROI = obj.camera.ROI;
            obj.maxROI = obj.camera.maxROI;
            obj.resolution = obj.camera.resolution;
            obj.initialized = true;
            obj.managerInitialized = false;
            obj.chiplets = obj.fetchPrefData('chiplets');
            obj.im = obj.fetchPrefData('im');  
        end
    end
    methods(Static)
        obj = instance()
    end
    methods
        function savePrefData(obj, name, data)
            if ~exist('data', 'var')
                data = obj.(name);
            end
            setpref(obj.namespace, name, data);
        end
        function data = fetchPrefData(obj, name)
            try
                data = getpref(obj.namespace, name);
            catch
                data = [];
                warning(sprintf("obj.%s is not properly saved in matlab prefs."), name);
            end
        end
        function metric = focus(obj,ax,managers) %#ok<INUSD>
            if ~exist('managers', 'var')
                if isempty(obj.hManagers)
                    error("Please click Auto Focus on the Imaging panel to assign the managers handle");
                else
                    managers = obj.hManagers;
                end
            else
                obj.hManagers = managers;
                obj.managerInitialized = true;
            end
            prevExposure_ms = obj.exposure_ms;
            obj.exposure_ms = 100;
            prevDetectChiplets = obj.detectChiplets;
            obj.detectChiplets = false;
            prevIntensity = obj.wl.intensity;
            obj.wl.intensity = 100;
            prevContinuous = obj.continuous;
            ms = managers.MetaStage.active_module;

            prev_sample_num = ms.sample_num;
            ms.sample_num = 1;

            Z = ms.get_meta_pref('Z');
            anc = Drivers.Attocube.ANC350.instance('18.25.29.30');
            Zline = anc.lines(3);
            if isempty(Z.reference) || ~strcmp(replace(Z.reference.name, ' ', '_'), 'steps_moved') || ~isequal(Z.reference.parent.line, 3)
                Z.set_reference(Zline.get_meta_pref('steps_moved'));
            end
            ms.key_step_z = 1;


            Target = ms.get_meta_pref('Target');
            if isempty(Target.reference) || ~strcmp(Target.reference.name, 'contrast')
                Target.set_reference(obj.get_meta_pref('contrast'));
            end
            
            managers.MetaStage.optimize('Z', true);
            metric = obj.contrast;
            obj.detectChiplets = prevDetectChiplets;
            obj.exposure_ms = prevExposure_ms;
            obj.camera.exposure = prevExposure_ms;
            obj.wl.intensity = prevIntensity;
            ms.sample_num = prev_sample_num;
            if prevContinuous
                obj.startVideo;
            end
        end
        function stop_triggered_acquisition(obj)
            obj.core.stopSequenceAcquisition()
        end
        function delete(obj)
            obj.camera = Imaging.Hamamatsu.empty(1, 0); % Avoid deleting the camera instance
            try
                stop(obj.videoTimer);
                delete(obj.videoTimer);
            end
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
            if ~exist('hImage', 'var') || ~isvalid(hImage)
                if isempty(obj.hImage) || ~isvalid(obj.hImage)
                    error('Please click `snap` in image panel to initialize obj.hImage');
                end
                hImage = obj.hImage;
            else
                obj.hImage = hImage;
            end
            im = obj.snapImage;
            obj.updateContrast(im);
            if obj.detectChiplets
                [displayIm, segments] = obj.updateDetection(im, true); % Enable forced update
                [movementX, movementY, movementMask] = obj.updateTracking(im, segments);
                displayIm = displayIm.*uint16(~movementMask);
            else
                displayIm = im;
            end



            set(hImage,'cdata',displayIm);
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
            obj.savePrefData('im');
            obj.savePrefData('chiplets');
        end
        function grabFrame(obj,~,~,hImage)
            % Timer Callback for frame acquisition
            im = obj.camera.fetchSnapping(0, true); % 0.005s
            if isempty(im)
                return
            end
            % obj.camera.startSnapping; % To save time
            obj.updateContrast(im); % 0.013s

            if obj.detectChiplets 
                if obj.contrast > 0.7*obj.prevContrast
                    % To prevent position shift caused by stage shifting
                    [displayIm, segments] = obj.updateDetection(im); % 0.15s
                    [movementX, movementY, movementMask] = obj.updateTracking(im, segments); % 0.1s
                    displayIm = displayIm.*uint16(~movementMask);
                else
                    displayIm = im;
                end
            else
                displayIm = im;
            end

            if isempty(hImage) || ~isvalid(hImage)
                obj.stopVideo;
                return;
            end

            set(hImage,'cdata',displayIm); % 0.001s
            drawnow; % 0.1s

        end
        function stopVideo(obj)
            obj.camera.stopSnapping;
            try
                stop(obj.videoTimer)
                delete(obj.videoTimer)
            end
            obj.continuous = false;
            obj.savePrefData('im');
            obj.savePrefData('chiplets');
        end
        
        function contrast = updateContrast(obj,frame, disableUpdateContrast)
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
            if ~exist('disableUpdateContrast', 'var') || ~disableUpdateContrast
                obj.contrast = contrast;
            end
            obj.brightness = mean2(frame);
        end
        function snapTemplate(obj, im)
            if ~obj.initialized
                return;
            end
            if ~exist('im', 'var') || isempty(im)
                im = obj.snapImage;
            end
            obj.processor.setTemplate(im);
            
        end
        function [displayIm, segments] = updateDetection(obj, im, forceUpdate)
            persistent wasBright
            if ~exist('wasBright', 'var')
                wasBright = true;
            end
            if obj.brightness < obj.brightnessThreshold
                if wasBright
                    fprintf("Current brightness %d is lower than its threshold %d. Matching template is temporarily disabled.\n", obj.brightness, obj.brightnessThreshold);
                    wasBright = false;
                    displayIm = im;
                    return;
                end
                wasBright = false;
            else
                wasBright = true;
            end


            if ~exist('forceUpdate', 'var')
                forceUpdate = false;
            end
            [displayIm, segments] = obj.processor.processImage(im);
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

        function [movementX, movementY, movementMask] = updateTracking(obj, im, segments)
            movementX = NaN;
            movementY = NaN;
            movementMask = zeros(size(im));
            nSegments = length(segments);
            imSizeX = size(im, 2);
            imSizeY = size(im, 1);
            if nSegments == 0
                fprintf("No segments found. Skip updateTracking.\n");
            end

            if isempty(obj.chiplets)
                for k = 1:nSegments
                    if isfield(segments{k}, 'absCenterX') && isfield(segments{k}, 'absCenterY') && ~isnan(segments{k}.absCenterX) && ~isnan(segments{k}.absCenterY)
                        
                        if isempty(obj.chiplets) % Usually the first valid segment is the closest to the image center
                            obj.chiplets = containers.Map;
                            obj.chiplets("0_0") = struct('x', segments{k}.absCenterX, 'y', segments{k}.absCenterY);
                        else
                            % First determine what is the direction relative to the first chiplet
                            chiplet = obj.chiplets("0_0");
                            diff = [segments{k}.absCenterX, segments{k}.absCenterY] - [chiplet.x, chiplet.y];

                            % Decompose diff onto Horizontal/Vertical distance vecotrs
                            baseMatrix = [obj.chipletHorDistanceX_pixel, obj.chipletVerDistanceX_pixel; obj.chipletHorDistanceY_pixel, obj.chipletVerDistanceY_pixel];
                            decomposeVector = baseMatrix^(-1)*diff';
                            xCoord = roundWithTolerance(decomposeVector(1), obj.tolerance);
                            yCoord = roundWithTolerance(decomposeVector(1), obj.tolerance);
                            if ~isnan(xCoord) && ~isnan(yCoord)
                                obj.chiplets(sprintf("%d_%d", xCoord, yCoord)) = struct('x', segments{k}.absCenterX, 'y', segments{k}.absCenterY);
                            end
                        end
                    end
                end
                obj.chipletCoordinateX = 0;
                obj.chipletCoordinateY = 0;
                obj.movementX_pixel = 0;
                obj.movementY_pixel = 0;
                chiplet = obj.chiplets("0_0");
                obj.chipletPositionX = chiplet.x;
                obj.chipletPositionY = chiplet.y;
                obj.im = im;
                return;
            end

            % There already are some recorded chiplet positions:
            matched = zeros(nSegments, 1);
            matchedCoord = cell(nSegments, 1);
            movements = nan(nSegments, 2); % (x, y) for each segment
            corrVals = nan(nSegments, 1);
            valid = ones(nSegments, 1);
            for k = 1:nSegments
                if isnan(segments{k}.absCenterX) || isnan(segments{k}.absCenterY)
                    valid(k) = false;
                    continue;
                end
                pos = [segments{k}.absCenterX, segments{k}.absCenterY];
                prevCoord = obj.chiplets.keys;
                for l = 1:length(prevCoord)
                    testCoord = prevCoord{l};
                    chiplet = obj.chiplets(testCoord);
                    testPos = [chiplet.x, chiplet.y];
                    if norm(testPos-pos) < obj.maxMovement
                        % Match successfully
                        matched(k) = true;
                        matchedCoord{k} = testCoord;
                        movements(k, :) = pos - testPos;
                        break;
                    end
                end 
            end
            
            if sum(matched) == 0
                fprintf("Matched center not found. Please move the stage slowly back to its previous position.\n");
                return;
            end
            % Estimate movement according to matched chiplets
            % estimatedMovement = mean(movements(find(matched), :), 1); % (x, y)
            % standardDeviation = [std(movements(find(matched), 1)), std(movements(find(matched), 2))];

            % Find out the best movement according to the movement of each chiplet centers
            if isempty(obj.im) || ~isequal(size(im), size(obj.im))
                fprintf("obj.im is empty or size is not compatible. Update obj.im. Abort update.\n");
                obj.im = im;
                return
            else % Verify movement by taking image correlation
                for k = 1:nSegments
                    if isnan(movements(k, 1)) || isnan(movements(k, 2))
                        continue;
                    end
                    movementX = round(movements(k, 1));
                    movementY = round(movements(k, 2));
                    prevImOverlap = double(obj.im(max(movementY+1, 1):min(imSizeY, imSizeY+movementY), max(movementX+1, 1):min(imSizeX, imSizeX+movementX)));
                    newImOverlap = double(im(max(1-movementY, 1):min(imSizeY, imSizeY-movementY), max(1-movementX, 1):min(imSizeX, imSizeX-movementX)));
                    prevImOverlap = prevImOverlap - mean2(prevImOverlap);
                    newImOverlap = newImOverlap - mean2(newImOverlap);
                    corrVals(k) = mean2(prevImOverlap.*newImOverlap);
                end
                [maxCorr, maxIdx] = max(corrVals);
                if maxCorr < obj.correlationThres
                    fprintf("Correlation (%f) of the shifted image does not meet obj.correlationThres (%f). Abort update.\n", maxCorr, obj.correlationThres);
                    return;
                end
                movementX = round(movements(maxIdx, 1));
                movementY = round(movements(maxIdx, 2));
            end
            

            % Update old chiplet positions and add new chiplet positions based on new movement information.
            chipletCoords = obj.chiplets.keys;
            for k = 1:length(chipletCoords)
                chiplet = obj.chiplets(chipletCoords{k});
                chiplet.x = chiplet.x + movementX;
                chiplet.y = chiplet.y + movementY;
                obj.chiplets(chipletCoords{k}) = chiplet;
            end

            % Overwrite matched chiplet positions for existing chiplets
            for k = 1:nSegments
                if matched(k)
                    chiplet = struct('x', segments{k}.absCenterX, 'y', segments{k}.absCenterY);
                    obj.chiplets(matchedCoord{k}) = chiplet;
                end
            end

            % There should be at least one matched chiplet, which can be a reference
            matchedIdx = find(matched, 1);
            matchedChiplet = obj.chiplets(matchedCoord{matchedIdx});
            coord = int16(str2double(split(matchedCoord{matchedIdx}, "_")));
            matchedX = coord(1);
            matchedY = coord(2);

            % Add new chiplets
            for k = 1:nSegments
                if valid(k) && ~matched(k)
                    
                    diff = [segments{k}.absCenterX, segments{k}.absCenterY] - [matchedChiplet.x, matchedChiplet.y];

                    % Decompose diff onto Horizontal/Vertical distance vecotrs
                    baseMatrix = [obj.chipletHorDistanceX_pixel, obj.chipletVerDistanceX_pixel; obj.chipletHorDistanceY_pixel, obj.chipletVerDistanceY_pixel];
                    decomposeVector = baseMatrix^(-1)*diff';
                    
                    xCoord = roundWithTolerance(decomposeVector(1), obj.tolerance)+matchedX;
                    yCoord = roundWithTolerance(decomposeVector(2), obj.tolerance)+matchedY;
                    if ~isnan(xCoord) && ~isnan(yCoord)
                        matchedCoord{k} = sprintf("%d_%d", xCoord, yCoord);
                        obj.chiplets(matchedCoord{k}) = struct('x', segments{k}.absCenterX, 'y', segments{k}.absCenterY);
                    end
                end
            end             


            % Update cloest chiplet; if enableTemplateMatching in Image processor, will only consider the ones that best matches the template 
            centerDistance = nan(nSegments, 1);
            corrVals = nan(nSegments, 1);
            for k = 1:nSegments
                if valid(k) && ~isempty(matchedCoord{k})
                    if obj.processor.enableTemplateMatching
                        if isfield(segments{k}, 'corrVal')
                            corrVals(k) = segments{k}.corrVal;
                        end
                    else
                        centerDistance(k) = norm([segments{k}.absCenterX-imSizeX/2, segments{k}.absCenterY-imSizeY/2]);
                    end
                    if abs(movementX) > abs(movementY) && movementX ~= 0
                        if movementX < 0
                            interval = 1;
                        else
                            interval = -1;
                        end
                        maskCoordsX = segments{k}.absCenterX:interval:segments{k}.absCenterX-movementX;
                        maskCoordsY = round(segments{k}.absCenterY+(maskCoordsX-segments{k}.absCenterX)*movementY/movementX);
                        inds = sub2ind(size(im), maskCoordsY, maskCoordsX);
                        movementMask(inds) = 1;
                    elseif  abs(movementY) > abs(movementX) && movementY ~= 0
                        if movementY < 0
                            interval = 1;
                        else
                            interval = -1;
                        end
                        maskCoordsY = segments{k}.absCenterY:interval:segments{k}.absCenterY-movementY;
                        maskCoordsX = round(segments{k}.absCenterX+(maskCoordsY-segments{k}.absCenterY)*movementX/movementY);
                        inds = sub2ind(size(im), maskCoordsY, maskCoordsX);
                        movementMask(inds) = 1;
                    end
                end
            end
            if obj.processor.enableTemplateMatching
                [maxCorr, idx] = max(corrVals);
            else
                [minDist, idx] = min(centerDistance);
            end
            minCoord = int16(str2double(split(matchedCoord{idx}, "_")));
            obj.chipletCoordinateX = minCoord(1);
            obj.chipletCoordinateY = minCoord(2);
            chiplet = obj.chiplets(matchedCoord{idx});
            obj.chipletPositionX = chiplet.x;
            obj.chipletPositionY = chiplet.y;
            obj.movementX_pixel = obj.movementX_pixel + movementX;
            obj.movementY_pixel = obj.movementY_pixel + movementY;
            obj.im = im;
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
            if ~obj.initialized
                return;
            end
            obj.snapTemplate;
        end
        function val = set_resetOrigin(obj, val, ~)
            obj.movementX_pixel = 0;
            obj.movementY_pixel = 0;
            obj.im = [];
            obj.chiplets = [];
            obj.chipletCoordinateX = NaN;
            obj.chipletCoordinateY = NaN;
            obj.chipletPositionX = NaN;
            obj.chipletPositionY = NaN;
        end
        function set.ROI(obj,val)
            assert(~obj.continuous,'Cannot set while video running.')
            obj.camera.ROI = val;
        end
        function val = get.ROI(obj)
            val = obj.camera.ROI;
        end
        function val = set_calibrateDistanceX(obj, val, ~)
            if val == obj.prevCalibrateDistanceX
                return;
            end            
            if obj.prevCalibrateDistanceY
                fprintf("Please disable Y distance calibration before starting X calibration.\n");
            end
            if val
                movement = [obj.movementX_pixel, obj.movementY_pixel];
                chiplet = obj.chiplets(sprintf("%d_%d", obj.chipletCoordinateX, obj.chipletCoordinateY));
                chipletPos = [chiplet.x, chiplet.y];
                fprintf("X distance calibration started. Please move the stage until the chiplet on the right is the closest to the image center, then press this button again.\n")
                fprintf("Current chiplet coordinate: X %d, Y %d; chipletPos: X %d, Y %d; movement: X %d, y %d\n", obj.chipletCoordinateX, obj.chipletCoordinateY, chiplet.x, chiplet.y, obj.movementX_pixel, obj.movementY_pixel);
            else
                fprintf("X distance calibration ended.\n")
                chiplet = obj.chiplets(sprintf("%d_%d", obj.chipletCoordinateX, obj.chipletCoordinateY));
                chipletPos = [chiplet.x, chiplet.y];
                movement = [obj.movementX_pixel, obj.movementY_pixel];
                fprintf("Current chiplet coordinate: X %d, Y %d; chipletPos: X %d, Y %d; movement: X %d, y %d\n", obj.chipletCoordinateX, obj.chipletCoordinateY, chipletPos(1), chipletPos(2), obj.movementX_pixel, obj.movementY_pixel);
                diff = chipletPos-obj.prevChipletPos-movement+obj.prevMovement;
                obj.chipletHorDistanceX_pixel = diff(1);
                obj.chipletHorDistanceY_pixel = diff(2);
                fprintf("Horizontal distance (x, y) = (%d, %d)\n", obj.chipletHorDistanceX_pixel, obj.chipletHorDistanceY_pixel);
            end
            obj.prevChipletPos = chipletPos;
            obj.prevMovement = movement;
            obj.prevCalibrateDistanceX = val;
        end
        function val = set_calibrateDistanceY(obj, val, ~)
            if  val == obj.prevCalibrateDistanceY
                return;
            end            
            if obj.prevCalibrateDistanceX
                fprintf("Please disable X distance calibration before starting Y calibration.\n");
            end
            if val
                movement = [obj.movementX_pixel, obj.movementY_pixel];
                chiplet = obj.chiplets(sprintf("%d_%d", obj.chipletCoordinateX, obj.chipletCoordinateY));
                chipletPos = [chiplet.x, chiplet.y];
                fprintf("Y distance calibration started. Please move the stage until the chiplet on the right is the closest to the image center, then press this button again.\n")
                fprintf("Current chiplet coordinate: X %d, Y %d; chipletPos: X %d, Y %d; movement: X %d, Y %d\n", obj.chipletCoordinateX, obj.chipletCoordinateY, chiplet.x, chiplet.y, obj.movementX_pixel, obj.movementY_pixel);
            else
                fprintf("X distance calibration ended.\n")
                chiplet = obj.chiplets(sprintf("%d_%d", obj.chipletCoordinateX, obj.chipletCoordinateY));
                chipletPos = [chiplet.x, chiplet.y];
                movement = [obj.movementX_pixel, obj.movementY_pixel];
                fprintf("Current chiplet coordinate: X %d, Y %d; chipletPos: X %d, Y %d; movement: X %d, Y %d\n", obj.chipletCoordinateX, obj.chipletCoordinateY, chipletPos(1), chipletPos(2), obj.movementX_pixel, obj.movementY_pixel);
                diff = chipletPos-obj.prevChipletPos-movement+obj.prevMovement;
                obj.chipletVerDistanceX_pixel = diff(1);
                obj.chipletVerDistanceY_pixel = diff(2);
                fprintf("Vertical distance (x, y) = (%d, %d)\n", obj.chipletVerDistanceX_pixel, obj.chipletVerDistanceY_pixel);
            end
            obj.prevChipletPos = chipletPos;
            obj.prevMovement = movement;
            obj.prevCalibrateDistanceY = val;
        end
    end
end


function output = roundWithTolerance(input, tolerance)
    output = round(input);
    if abs(output-input) > tolerance
        output = NaN;
    end
end