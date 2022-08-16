classdef ImageProcessor < Modules.Driver
    % ImageProcessor for chiplet recognition: take the raw image & template as input, and give processed image with matched positions as output. 
    properties(SetObservable, GetObservable)
        binarizeThresRatio = Prefs.Double(0.1, 'min', 0, 'max', 1, 'help', 'Binarize filters: pixels with value lower than this ratio threshold will be discarded.');
        cutoffLow = Prefs.Double(10, 'min', 0, 'max', 100, 'help', 'Filter lowerbound in the Fourier plane.');
        cutoffHigh = Prefs.Double(80, 'min', 50, 'max', 150, 'help', 'Filter upperbound in the Fourier plane.');
        minPixel = Prefs.Integer(300, 'min', 0, 'max', 1000, 'help', 'Islands with connected pixel number less than this value will be discarded (when applying imopen).');
        diskRadius = Prefs.Integer(3, 'min', 0, 'max', 5, 'help', 'Disk radius when applying imclose. Gaps thinner than this value will be filled.');
        pixelThresRatio = Prefs.Double(0.15, 'min', 0, 'max', 1, 'help', 'When filtering the image, only components with pixel number larger than this ratio (against the largest component) will be kept. 1 if the largest is kept.');
        display = Prefs.MultipleChoice('Raw', 'allow_empty', false, 'choices', Drivers.ImageProcessor.displayTypes);
        plotAllIntermediate = Prefs.Boolean(false, 'help', 'Whether to display the intermediate filtered results.')
        waveguideWidth_pixel = Prefs.Integer(5, 'unit', 'pixel', 'min', 1, 'max', 20, 'help', 'Width of the waveguide in each chiplet. Used for angle detection.')
        cornerLengthRatio = Prefs.Integer(15, 'min', 1, 'max', 20, 'help', 'When doing corner detection, the ratio between edge length and width.')
        showCorners = Prefs.Boolean(true, 'help', 'Whether to run corner detection and show all corners on the plot')
        angle_deg = Prefs.Double(NaN, 'allow_nan', true, 'readonly', true, 'unit', 'degree', 'min', -90, 'max', 90, 'help', 'The offset angle of the image relative to the horizontal position. Can be set by calling `setTemplate`');
        cornerHorDist = Prefs.Double(NaN, 'min', 0, 'readonly', true, 'unit', 'pixel', 'help', 'Horizontal distance between two corners (angle is considered)');
        cornerVerDist = Prefs.Double(NaN, 'min', 0, 'readonly', true, 'unit', 'pixel', 'help', 'Vertical distance between two corners (angle is considered');
        cornerValidThres = Prefs.Double(0.6, 'min', 0, 'max', 1, 'help', 'When detecting corners, a corner position will be valid if its correlation is at least this value relative to the correlation of the best matched corner.');
        enableTemplateMatching = Prefs.Boolean(true, 'help', 'Use template to match segments whose size is as large as the template.');
        tolerance = Prefs.Double(0.3, 'min', 0, 'max', 1, 'help', 'To what extent the snapped image can be different from the template parameters when it is still valid.')
    end
    properties
        prefs = {'binarizeThresRatio','cutoffLow','cutoffHigh','minPixel','diskRadius','pixelThresRatio','display','plotAllIntermediate', 'waveguideWidth_pixel', 'enableTemplateMatching'};
        angleCalibrated = false;
        template; % Follows the same structure as a segment: has fields 'image', 'corners', 'center', 
    end
    properties(Constant)
        displayTypes = {'Raw', 'Binarized 1', 'Bandpass filtered', 'Binarized 2', 'Removed small components', 'Connected', 'Chiplets selected'};
    end
    methods(Static)
        obj = instance()
    end
    methods(Access = private)
        function obj = ImageProcessor()
            obj.loadPrefs;
            obj.angleCalibrated = false;
            obj.template = obj.fetchPrefData('template');  
        end
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
        function setTemplate(obj, inputImage, waitUI)
            prevMatchTemplate = obj.enableTemplateMatching;
            obj.enableTemplateMatching = false;
            [displayImage, segments] = obj.filterImage(inputImage, struct('pixelThresRatio', 1)); % Only keep the largest component
            obj.getAngle(segments, true);
            segments = obj.detectCorners(segments);
            if isempty(segments)
                fprintf("No template chiplet found");
                return;
            end
            templateIm = segments{1}.image;
            templateCorners = zeros(4, 2);
            for l = 1:4
                templateCorners(l, :) = [segments{1}.corners{l}.x, segments{1}.corners{l}.y];
            end
            frame_fig = figure(12);
            frame_fig.Position = [200, 200, 560, 420];
            frame_ax = axes('Parent', frame_fig);
            imH = imagesc(frame_ax, templateIm);
            colormap(frame_ax, 'bone');

            polyH = drawpolygon(frame_ax, 'Position', templateCorners);
            set(get(frame_ax, 'Title'), 'String', sprintf('Press enter or right click the outside image to confirm template corners.'));
            imH.ButtonDownFcn = @ROIConfirm;
            frame_fig.KeyPressFcn = @ROIConfirm;
            if exist('waitUI', 'var') && waitUI
                uiwait(frame_fig);
            end
            templateCorners = round(polyH.Position);
            for l = 1:4
                segments{1}.corners{l}.x = templateCorners(l, 1);
                segments{1}.corners{l}.y = templateCorners(l, 2);
            end
            segments{1}.relCenterX = round(mean(templateCorners(:, 1)));
            segments{1}.relCenterY = round(mean(templateCorners(:, 2)));
            segments{1}.absCenterX = segments{1}.relCenterX+segments{1}.xmin;
            segments{1}.absCenterY = segments{1}.relCenterY+segments{1}.ymin;
            obj.cornerHorDist = (norm(templateCorners(1, :)-templateCorners(4, :))+norm(templateCorners(2, :)-templateCorners(3, :)))/2;
            obj.cornerVerDist = (norm(templateCorners(1, :)-templateCorners(2, :))+norm(templateCorners(3, :)-templateCorners(4, :)))/2;
            obj.template = segments{1};
            % delete(polyH);
            obj.savePrefData('template', obj.template);
            obj.enableTemplateMatching = prevMatchTemplate;
        end
        function [displayImage, segments] = processImage(obj, inputImage, args)
            if exist('args', 'var')
                [displayImage, segments] = obj.filterImage(inputImage, args);
            else
                [displayImage, segments] = obj.filterImage(inputImage);
            end

            if isempty(obj.angle_deg) || isnan(obj.angle_deg) || ~obj.angleCalibrated
                obj.getAngle(segments, true);
            end
            segments = obj.detectCorners(segments);


            % Normalize displayImage to uint16
            displayImage = double(displayImage);
            minVal = min(displayImage(:));
            maxVal = max(displayImage(:));
            displayImage = uint16((displayImage-minVal)*65535/(maxVal-minVal));
            

            if obj.showCorners
                for k = 1:length(segments)
                    xmin = segments{k}.xmin;
                    ymin = segments{k}.ymin;
                    xmax = xmin + size(segments{k}.image, 2)-1;
                    ymax = ymin + size(segments{k}.image, 1)-1;
                    displayImage(ymin:ymax, xmin:xmax) = displayImage(ymin:ymax, xmin:xmax).*uint16((~segments{k}.cornerMask));
                end
            end
        end

        function [displayImage, segments] = filterImage(obj, inputImage, args)
            % Parse args
            if exist('args', 'var') && isfield(args, 'binarizeThresRatio')
                binarizeThresRatio = args.binarizeThresRatio;
            else
                binarizeThresRatio = obj.binarizeThresRatio;
            end
            if exist('args', 'var') && isfield(args, 'cutoffLow')
                cutoffLow = args.cutoffLow;
            else
                cutoffLow = obj.cutoffLow;
            end
            if exist('args', 'var') && isfield(args, 'cutoffHigh')
                cutoffHigh = args.cutoffHigh;
            else
                cutoffHigh = obj.cutoffHigh;
            end
            if exist('args', 'var') && isfield(args, 'minPixel')
                minPixel = args.minPixel;
            else
                minPixel = obj.minPixel;
            end
            if exist('args', 'var') && isfield(args, 'diskRadius')
                diskRadius = args.diskRadius;
            else
                diskRadius = obj.diskRadius;
            end
            if exist('args', 'var') && isfield(args, 'pixelThresRatio')
                % The second/third/... largest components is also valid if their pixel size is larger than the fisrt*pixelThresRatio
                pixelThresRatio = args.pixelThresRatio;
            else
                pixelThresRatio = obj.pixelThresRatio;
            end
            if exist('args', 'var') && isfield(args, 'display')
                display = args.display;
            else
                display = obj.display;
            end
            
            % Preprocess image
            if isstring(inputImage) || ischar(inputImage)
                try
                    inputImage = imread(inputImage);
                catch
                    input_mat = load(inputImage);
                    inputImage = input_mat.image.image;
                    inputImage = uint16(floor(double(inputImage)*65535/double(max(inputImage(:)))));
                end
            else
                inputImage = uint16(floor(double(inputImage)*65535/double(max(inputImage(:)))));
            end
            if size(inputImage, 3) == 3
                inputImage = rgb2gray(inputImage);
            end

            % First binarization
            bin1Image = obj.binarize(inputImage)*65535;

            % 2D bandpass filter
            filteredImage = obj.bandpassFilter(bin1Image);

            % Second binarization (slightly different from the first: image contains negative part)
            bin2Image = obj.binarize(filteredImage);

            % Imopen
            openedImage = bwareaopen(bin2Image, minPixel);

            % Imclose
            closedImage = imclose(openedImage, strel('disk',diskRadius));

            % Select valid segments
            [selectedImage, segments] = obj.selectSegments(closedImage);

            for k = 1:length(segments)
                segIm = segments{k}.image;
                segments{k}.rawImage = inputImage(segments{k}.ymin:segments{k}.ymin+size(segIm, 1)-1, segments{k}.xmin:segments{k}.xmin+size(segIm, 2)-1); 
            end

            function cancelCallback(hObj, event)
                if ~isempty(obj) && isvalid(obj) && isprop(obj, 'plotAllIntermediate')
                    obj.plotAllIntermediate = false;
                end
                delete(hObj);
            end
            if obj.plotAllIntermediate
                fig = figure(5);
                fig.CloseRequestFcn = @cancelCallback;
                % Displaying Input Image and Output Image
                subplot(2, 3, 1), imshow(inputImage), set(get(gca, 'Title'), 'String', 'Input image');
                subplot(2, 3, 2), imshow(bin1Image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", binarizeThresRatio));
                subplot(2, 3, 3), imshow(filteredImage, []), set(get(gca, 'Title'), 'String', sprintf("2D bandpass filter\ncutoff: [%d, %d]", cutoffHigh, cutoffLow));
                subplot(2, 3, 4), imshow(bin2Image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", binarizeThresRatio));
                subplot(2, 3, 5), imshow(openedImage), set(get(gca, 'Title'), 'String', sprintf("Imopen min pixel: %d", minPixel));
                subplot(2, 3, 6), imshow(selectedImage), set(get(gca, 'Title'), 'String', sprintf("Imclose disk radius: %d\nKeep biggest component", diskRadius));
            end

            switch display
            case Drivers.ImageProcessor.displayTypes{1}
                displayImage = inputImage;
            case Drivers.ImageProcessor.displayTypes{2}
                displayImage = bin1Image;
            case Drivers.ImageProcessor.displayTypes{3}
                displayImage = filteredImage;
            case Drivers.ImageProcessor.displayTypes{4}
                displayImage = bin2Image;
            case Drivers.ImageProcessor.displayTypes{5}
                displayImage = openedImage;
            case Drivers.ImageProcessor.displayTypes{6}
                displayImage = closedImage;
            case Drivers.ImageProcessor.displayTypes{7}
                displayImage = selectedImage;
            end
        end
        function im = binarize(obj, im, thresRatio)
            if ~exist('thresRatio', 'var')
                thresRatio = obj.binarizeThresRatio;
            end 
            n_pixel = numel(im);
            maxVal = double(max(im(:)));
            minVal = double(min(im(:)));
            binNum = 1000;
            for k = linspace(maxVal, minVal, binNum)
                if sum(im(:)>=k) > n_pixel*thresRatio
                    im = (im>=k);
                    break;
                end
            end
        end

        function im = bandpassFilter(obj, im, low, high)
            if ~exist('low', 'var')
                low = obj.cutoffLow;
            end
            if ~exist('high', 'var')
                high = obj.cutoffHigh;
            end
            % M : no of rows (height of the image)
            % N : no of columns (width of the image)
            [M, N] = size(im);
            
            % Getting Fourier Transform of the im
            % using MATLAB library function fft2 (2D fast fourier transform)  
            FT_img = fft2(double(im));
            
            % Designing filter
            u = 0:(M-1);
            idx = find(u>M/2);
            u(idx) = u(idx)-M;
            v = 0:(N-1);
            idy = find(v>N/2);
            v(idy) = v(idy)-N;
            
            % MATLAB library function meshgrid(v, u) returns 2D grid
            %  which contains the coordinates of vectors v and u. 
            % Matrix V with each row is a copy of v, and matrix U 
            % with each column is a copy of u
            [V, U] = meshgrid(v, u);
            
            % Calculating Euclidean Distance
            D = sqrt(U.^2+V.^2);
            
            % Comparing with the cut-off frequency and 
            % determining the filtering mask
            H = double(D < high & D > low);
            
            % Convolution between the Fourier Transformed image and the mask
            G = H.*FT_img;
            
            % Getting the resultant image by Inverse Fourier Transform
            % of the convoluted image using MATLAB library function
            % ifft2 (2D inverse fast fourier transform)  
            im = real(ifft2(double(G)));
        end

        function [processedImage, segments] = selectSegments(obj, im, pixelThresRatio)
            if ~exist('pixelThresRatio', 'var')
                pixelThresRatio = obj.pixelThresRatio;
            end
            CC = bwconncomp(im);
            numPixels = cellfun(@numel,CC.PixelIdxList);
            [num,idx] = sort(numPixels, 'descend');
            max_num = max(num);
            n_valid_sections = numel(num(num >= max_num*pixelThresRatio));
            size_x = size(im, 2);
            size_y = size(im, 1);
            processedImage = zeros(size_y, size_x);
            segments = cell(1, n_valid_sections);
            for k = 1:n_valid_sections
                [ys, xs] = ind2sub([size_y, size_x], CC.PixelIdxList{idx(k)});
                xmin = min(xs);
                xmax = max(xs);
                ymin = min(ys);
                ymax = max(ys);
                segIm = zeros(ymax-ymin+1, xmax-xmin+1);
                inds = sub2ind([ymax-ymin+1, xmax-xmin+1], ys-ymin+1, xs-xmin+1);
                segIm(inds) = 1;
                segment = struct('ymin', ymin, 'xmin', xmin, 'image', segIm);
                segments{k} = segment;
                processedImage(CC.PixelIdxList{idx(k)}) = 1;
            end
        end

        function angle = getAngle(obj, segments, showPlots, resolution_deg)
            if ~exist('resolution_deg', 'var')
                resolution_deg = 0.1;
            end
            if ~exist('showPlots', 'var')
                showPlots = false;
            end
            nSegments = length(segments);
            angles = [-90:resolution_deg:90];
            nAngles = length(angles);
            vars = zeros(nSegments, nAngles);
            for k = 1:nSegments
                segIm = segments{k}.image;
                segY = size(segIm, 1);
                segX = size(segIm, 2);
                line_im = ones(obj.waveguideWidth_pixel, segX);
                for l = 1:nAngles
                    deg = angles(l);
                    segImRotated = imrotate(segIm, -deg, 'crop');
                    vars(k, l) = var(conv2(segImRotated, line_im, 'valid'), 0, 'all');
                end
            end
            meanVars = mean(vars, 1);
            [maxVar, idx] = max(meanVars);
            angle = angles(idx);
            obj.angle_deg = angle;
            if showPlots && nSegments >= 1
                fig = figure(7);
                fig.Position = [100, 100, 900, 250*(nSegments)];
                for k = 1:nSegments
                    s1 = subplot(nSegments, 3, 1+3*(k-1));
                    imshow(segments{k}.image);
                    s2 = subplot(nSegments, 3, 2+3*(k-1));
                    imshow(imrotate(segments{k}.image, -angle, 'crop'));
                end
                s = subplot(nSegments, 3, 3);
                s.Position = [0.7, 0.1, 0.25, 0.8];
                plot(s, angles, meanVars);
                xlim(s, [-90, 90]);
                set(get(gca, 'XLabel'), 'String', 'Offset angle (deg)');
                set(get(gca, 'YLabel'), 'String', 'Variance');
            end 
            obj.angleCalibrated = true;
        end
        function segments = detectCorners(obj, segments, showPlots) % `Corners` are in image coordinates (y, x)
            nSegments = length(segments);
            if nSegments == 0
                return
            end
            
            if isempty(obj.angle_deg) || isnan(obj.angle_deg)
                obj.getAngle(segments, true);
            end
            corners = cell(1, 4);
                % 1: top left (closest to (1, 1));
                % 2: bottom left (y_size, 1); 
                % 3: bottom right (y_size, x_size);
                % 4: top right (1, x_size);

                %     ^    1 ----------------------------------- 4
                %     1      | (1, 1)              (1, x_size) |
                %     |      |                                 |
                %     |      |                                 |
                %     |      |                                 |
                %     |      |                                 |
                %     y      |                                 |
                %     |      |                                 |
                %     |      |                                 |
                %     |      |                                 |
                %     |      |                                 |
                %  y_size    |                                 |
                %     v      | (y_size, 1)    (y_size, x_size) |
                %          2 ----------------------------------- 3
                
                %           < 1 ---------  x  ------- x_size  >

            angles = [0, 90, 180, 270]; % Positive: counter clockwise
            w = obj.waveguideWidth_pixel;
            lr = obj.cornerLengthRatio; % (length ratio) How many times corner edges are longer than its width 

            cornerIm = zeros((2*lr+1)*w);
            cornerImCenterOffset = lr*w + round(w/2);
            cornerImSize = (2*lr+1)*w;

            % cornerIm(lr*w+1:(lr+1)*w, lr*w+1:(lr+1)*w) = 1; % Center
            cornerIm((lr+1)*w+1:(2*lr+1)*w, lr*w+1:(lr+1)*w) = 1; % lower edge
            cornerIm(lr*w+1:(lr+1)*w, (lr+1)*w+1:(2*lr+1)*w) = 1; % right edge
            
            cornerImPositive = cornerIm; % Only include the positive parts for plotting
            cornerImPositive(lr*w+1:(lr+1)*w, lr*w+1:(lr+1)*w) = 1; % Center
            
            cornerIm(1:(lr+1)*w, 1:(lr+1)*w) = -1; % left edge

            if exist('showPlots', 'var') && showPlots
                fig = figure(9);
                fig.Position = [100, 100, 1200, 600];
                subplot(nSegments+1, 5, 1);
                imshow(cornerIm, []);
                % colormap('jet');
                for l = 1:4
                    s = subplot(nSegments+1, 5, l+1);
                    imshow(imrotate(cornerIm, obj.angle_deg+angles(l), 'crop'), []);
                    % colormap('jet');
                end
            end

            for k = 1:nSegments
                segIm = segments{k}.image;
                segSizeX = size(segIm, 2);
                segSizeY = size(segIm, 1);

                if obj.enableTemplateMatching && ~isempty(obj.template) &&  segSizeX > size(obj.template.image, 2)*(1-obj.tolerance) && segSizeY > size(obj.template.image, 1)*(1-obj.tolerance)
                    continue;
                end
                if exist('showPlots', 'var') && showPlots

                    identityMask = zeros((2*lr+1)*w);
                    identityMask(lr*w+round(w/2), lr*w+round(w/2)) = 1;
                    
                    subplot(nSegments+1, 5, 5*k+1);
                    imshow(xcorr2(segIm, identityMask), []);
                end
                for l = 1:4
                    corrResult = xcorr2(segIm, imrotate(cornerIm, obj.angle_deg+angles(l), 'crop'));
                    avg = mean2(corrResult);
                    [maxVal, maxIdx] = max(corrResult(:));
                    [maxY, maxX] = ind2sub(size(corrResult), maxIdx);
                    if exist('showPlots', 'var') && showPlots
                        subplot(nSegments+1, 5, 5*k+l+1);
                        imshow(corrResult, []);
                        set(get(gca, 'XLabel'), 'String', sprintf("avg: %f\nmax: %f\n", avg, maxVal));
                    end
                    cornerX = maxX-cornerImCenterOffset+1;
                    cornerY = maxY-cornerImCenterOffset+1;

                    corners{l} = struct('x', cornerX, 'y', cornerY, 'val', maxVal, 'valid', false);
                    segments{k}.corners = corners;
                end
            end
            
            % Check the validity of each corners
            for k = 1:nSegments 
                segIm = segments{k}.image;
                segSizeX = size(segIm, 2);
                segSizeY = size(segIm, 1);
                if obj.enableTemplateMatching && ~isempty(obj.template) &&  segSizeX > size(obj.template.image, 2)*(1-obj.tolerance) && segSizeY > size(obj.template.image, 1)*(1-obj.tolerance)
                    % Use template to match all corners and centers. Override the previous detection results
                    segments{k} = obj.matchTemplate(segments{k});
                else
                    seg = segments{k};
                    segments{k}.relCenterX = NaN; % Assign values for early termination (continue)
                    segments{k}.relCenterY = NaN;
                    segments{k}.absCenterX = NaN;
                    segments{k}.absCenterY = NaN;
                    segX = size(seg.image, 2);
                    segY = size(seg.image, 1);
                    corners = seg.corners;
                    cornerVals = zeros(4, 1);
                    cornerValid = zeros(4, 1);
                    cornerPos = zeros(4, 2); % (y, x);
                    segments{k}.cornerValid = cornerValid;
                    for l = 1:4
                        cornerVals(l) = corners{l}.val;
                        cornerPos(l, :) = [corners{l}.y, corners{l}.x];
                    end
                    [maxVal, maxIdx] = max(cornerVals);
                    segments{k}.cornerVals = cornerVals;
                    segments{k}.cornerPos = cornerPos;
                    if maxVal < 200
                        fprintf("Corners of segment %d are not detected.", k);
                        continue;
                    end
                    
                    for l = 1:4
                        if corners{l}.val > maxVal*obj.cornerValidThres
                            corners{l}.valid = true;
                        end
                    end
                    
                    
                    % Use Template to verify the relative position of four corners
                    if ~isempty(obj.template) && isstruct(obj.template)
                        templateX = size(obj.template.image, 2);
                        templateY = size(obj.template.image, 1);
                        ratio = 1+obj.tolerance;
                        if corners{1}.y > obj.template.corners{1}.y*ratio + 10 || corners{1}.x > obj.template.corners{1}.x*ratio + 10
                            corners{1}.valid = false;
                        end
                        if segY - corners{2}.y > max(templateY - obj.template.corners{2}.y, 1)*ratio + 10 || corners{2}.x > obj.template.corners{2}.x*ratio + 10
                            corners{2}.valid = false;
                        end
                        if segY - corners{3}.y > max(templateY - obj.template.corners{3}.y, 1)*ratio + 10 || segX - corners{3}.x > max(templateX - obj.template.corners{3}.x, 1)*ratio + 10
                            corners{3}.valid = false;
                        end
                        if corners{4}.y > obj.template.corners{4}.y*ratio + 10 || segX - corners{4}.x > max(templateX - obj.template.corners{4}.x, 1)*ratio + 10
                            corners{4}.valid = false;
                        end
                        [sortedVals, idxs] = sort(cornerVals, 'descend');
                        for l = 1:4
                            if corners{idxs(l)}.valid
                                idx = idxs(l);
                                break; % Get the valid corner with the largest correlation value
                            end
                        end
                        for l = 1:4
                            if l == idx || corners{l}.valid == false
                                continue;
                            end
                            templateDiffX = obj.template.corners{l}.x-obj.template.corners{idx}.x;
                            templateDiffY = obj.template.corners{l}.y-obj.template.corners{idx}.y;
                            actualDiffX = corners{l}.x-corners{idx}.x;
                            actualDiffY = corners{l}.y-corners{idx}.y;
                            % fprintf("templateDiffY %d actualDiffY %d templateDiffX %d actualDiffX %d\n", templateDiffY, actualDiffY, templateDiffX, actualDiffX);
                            if abs(actualDiffY-templateDiffY) > abs(templateDiffY)*obj.tolerance + 10 || abs(actualDiffX-templateDiffX) > abs(templateDiffX)*obj.tolerance + 10
                                corners{l}.valid = false;
                            end
                        end

                    end

                    for l = 1:4
                        cornerValid(l) = corners{l}.valid;
                    end
                    segments{k}.corners = corners;
                    segments{k}.cornerValid = cornerValid;

                    horOffset = obj.cornerHorDist/2*[-sin(obj.angle_deg/180*pi), cos(obj.angle_deg/180*pi)];
                    verOffset = obj.cornerVerDist/2*[cos(obj.angle_deg/180*pi), sin(obj.angle_deg/180*pi)];

                    switch sum(cornerValid)
                    
                    case 4
                        % All corners are matched
                        center = mean(cornerPos, 1);
                    case 3
                        % Only one corner is not matched: 
                        unmatchedIdx = find(~cornerValid);
                        prevIdx = modulo(unmatchedIdx-1, 4);
                        nextIdx = modulo(unmatchedIdx+1, 4);
                        oppositeIdx = modulo(unmatchedIdx+2, 4);
                        % Derive the chiplet center by only two corners 
                        center = mean(cornerPos([prevIdx, nextIdx], :), 1);
                    case 2
                        % Two corners are matched:
                        matchedIdx = find(cornerValid);
                        if isequal(matchedIdx, [1; 3]) || isequal(matchedIdx, [2; 4])
                            center = mean(cornerPos(matchedIdx, :), 1);
                        else % Two neighbor corners
                            if isnan(obj.cornerHorDist) || isnan(obj.cornerVerDist)
                                continue;
                            end
                            if isequal(matchedIdx, [1; 2]) % left
                                center = mean(cornerPos(matchedIdx, :), 1) + horOffset;
                            elseif isequal(matchedIdx, [2; 3]) % bottom
                                center = mean(cornerPos(matchedIdx, :), 1) - verOffset;
                            elseif isequal(matchedIdx, [3; 4]) % right
                                center = mean(cornerPos(matchedIdx, :), 1) - horOffset;
                            else % top
                                center = mean(cornerPos(matchedIdx, :), 1) + verOffset;
                            end
                        end
                    case 1
                        matchedIdx = find(cornerValid);
                        if segments{k}.corners{matchedIdx}.val > min(max(segments{k}.cornerVals)*0.8, 250) % if the only corner is valid enough: still useful to find the center position
                            switch matchedIdx
                            case 1
                                center = cornerPos(matchedIdx, :) + horOffset + verOffset;
                            case 2
                                center = cornerPos(matchedIdx, :) + horOffset - verOffset;
                            case 3
                                center = cornerPos(matchedIdx, :) - horOffset - verOffset;
                            case 4
                                center = cornerPos(matchedIdx, :) - horOffset + verOffset;
                            end
                        end

                    otherwise
                        continue;
                    end
                    segments{k}.relCenterX = round(center(2));
                    segments{k}.relCenterY = round(center(1));
                    segments{k}.absCenterX = segments{k}.relCenterX+segments{k}.xmin;
                    segments{k}.absCenterY = segments{k}.relCenterY+segments{k}.ymin;
                end
            end



            
            % Add cornerMask to each segment for display
            for k = 1:nSegments
                segIm = segments{k}.image;

                segSizeX = size(segIm, 2);
                segSizeY = size(segIm, 1);
                % The corner area of `cornerMask` is 1 and the rest is 0.
                cornerMask = zeros(segSizeY, segSizeX);
                for l = 1:4
                    corner = segments{k}.corners{l};
                    if ~corner.valid % Not a valid corner. Skip adding masks
                        continue;
                    end
                    cornerX = corner.x;
                    cornerY = corner.y;
                    % Relative overlap coordinate of segment image
                    segOverlapXmin = max(1, cornerX+cornerImCenterOffset-1-cornerImSize+1);
                    segOverlapXmax = min(segSizeX, cornerX+cornerImCenterOffset-1);
                    segOverlapYmin = max(1, cornerY+cornerImCenterOffset-1-cornerImSize+1);
                    segOverlapYmax = min(segSizeY, cornerY+cornerImCenterOffset-1);

                    % Relative overlap coordinate of corner image
                    tempCornerIm = imrotate(cornerImPositive, obj.angle_deg+angles(l), 'crop');
                    cornerOverlapXmin = max(1, cornerImSize-(cornerX+cornerImCenterOffset-1)+1);
                    cornerOverlapXmax = min(cornerImSize, cornerImSize-(cornerX+cornerImCenterOffset-1-segSizeX));
                    cornerOverlapYmin = max(1, cornerImSize-(cornerY+cornerImCenterOffset-1)+1);
                    cornerOverlapYmax = min(cornerImSize, cornerImSize-(cornerY+cornerImCenterOffset-1-segSizeY));
                    cornerMask(segOverlapYmin:segOverlapYmax, segOverlapXmin:segOverlapXmax) = ...
                        or(cornerMask(segOverlapYmin:segOverlapYmax, segOverlapXmin:segOverlapXmax), ...
                        tempCornerIm(cornerOverlapYmin:cornerOverlapYmax, cornerOverlapXmin:cornerOverlapXmax)) ; % Add corners
                    cornerMask(confine(cornerY-1, 1, segSizeY):confine(cornerY+1, 1, segSizeY), confine(cornerX-1, 1, segSizeX):confine(cornerX+1, 1, segSizeX)) = 0; % Add dots
                end
                if ~isnan(segments{k}.relCenterX) && ~isnan(segments{k}.relCenterY)
                    cornerMask(confine(segments{k}.relCenterY-2, 1, segSizeY):confine(segments{k}.relCenterY+2, 1, segSizeY), confine(segments{k}.relCenterX-2, 1, segSizeX):confine(segments{k}.relCenterX+2, 1, segSizeX)) = 1;
                end
                segments{k}.cornerMask = cornerMask;
            end
        end
        function [segment, maxCorr] = matchTemplate(obj, segment, showPlots)
            % showPlots: bool
            
            xcorrResult = xcorr2(double(segment.image),double(obj.template.image));
            [maxCorr,idx] = max(xcorrResult(:));
            [posY, posX] = ind2sub(size(xcorrResult),idx);
            templateSizeY = size(obj.template.image, 1);
            templateSizeX = size(obj.template.image, 2);
            segment.relCenterX = posX - templateSizeX + obj.template.relCenterX;
            segment.relCenterY = posY - templateSizeY + obj.template.relCenterY;
            segment.absCenterX = segment.relCenterX + segment.xmin;
            segment.absCenterY = segment.relCenterY + segment.ymin;
            
            for l = 1:4
                segment.corners{l}.x = posX - templateSizeX + obj.template.corners{l}.x;
                segment.corners{l}.y = posY - templateSizeY + obj.template.corners{l}.y;
                segment.cornerPos(l, :) = [segment.corners{l}.y, segment.corners{l}.x];
                segment.corners{l}.valid = true;
                segment.corners{l}.val = NaN;
            end
            segment.cornerValid = [true;true;true;true];
            segment.cornerVal = nan(4, 1);
            segment.corrVal = maxCorr;

            if exist('show_plots', 'var') && show_plots
                try 
                    close(13);
                catch
                end
                corr_fig = figure(13);
                s1 = subplot(2, 2, 1); imshow(segment.image); set(get(s1, 'Title'), 'String', sprintf("Processed input image"));
                s2 = subplot(2, 2, 2); imshow(obj.template.image); set(get(s2, 'Title'), 'String', sprintf("Trimmed template image"));
                s3 = subplot(2, 2, 3);
                surf(s3, xcorrResult); shading(s3, "flat"); set(get(s3, 'Title'), 'String', 'Cross correlation results');
                s4 = subplot(2, 2, 4);
                imshow(segment.image); 
                hold(s4, 'on');
                plot(s4, [y], [x], 'r.', 'MarkerSize', 10);
            end
        
        end
    end
end

function val = confine(val, lower_bound, upper_bound)
    val = max(min(val, upper_bound), lower_bound);
end

function result = modulo(input, divider)
    result = mod(input, divider);
    if result == 0
        result = divider;
    end
end 