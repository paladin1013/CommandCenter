classdef ImageProcessor < Modules.Driver
    % ImageProcessor for chiplet recognition: take the raw image & template as input, and give processed image with matched positions as output. 
    properties(SetObservable, GetObservable)
        bin1ThresRatio = Prefs.Double(0.14, 'min', 0, 'max', 1, 'help', 'First binarize filter: pixels with value lower than this ratio threshold will be discarded.');
        cutoffLow = Prefs.Double(20, 'min', 0, 'max', 100, 'help', 'Filter lowerbound in the Fourier plane.');
        cutoffHigh = Prefs.Double(80, 'min', 50, 'max', 150, 'help', 'Filter upperbound in the Fourier plane.');
        bin2ThresRatio = Prefs.Double(0.14, 'min', 0, 'max', 1, 'help', 'First binarize filter: pixels with value lower than this ratio threshold will be discarded.');
        minPixel = Prefs.Integer(300, 'min', 0, 'max', 1000, 'help', 'Islands with connected pixel number less than this value will be discarded (when applying imopen).');
        diskRadius = Prefs.Integer(3, 'min', 0, 'max', 5, 'help', 'Disk radius when applying imclose. Gaps thinner than this value will be filled.');
        pixelThresRatio = Prefs.Double(0.5, 'min', 0, 'max', 1, 'help', 'When filtering the image, only components with pixel number larger than this ratio (against the largest component) will be kept. 1 if the largest is kept.');
        display = Prefs.MultipleChoice('Raw', 'allow_empty', false, 'choices', Drivers.ImageProcessor.displayTypes);
        plotAllIntermediate = Prefs.Boolean(false, 'help', 'Whether to display the intermediate filtered results.')
        waveguideWidth_pixel = Prefs.Integer(5, 'unit', 'pixel', 'min', 1, 'max', 20, 'help', 'Width of the waveguide in each chiplet. Used for angle detection.')
        angle_deg = Prefs.Double(NaN, 'allow_nan', true, 'unit', 'degree', 'min', -90, 'max', 90, 'help', 'The offset angle of the image relative to the horizontal position.')
        cornerLengthRatio = Prefs.Integer(6, 'allow_nan', false, 'min', 1, 'max', 10, 'help', 'When doing corner detection, the ratio between edge length and width.')
        showCorners = Prefs.Boolean(true, 'help', 'Whether to run corner detection and show all corners on the plot')
    end
    properties
        prefs = {'bin1ThresRatio','cutoffLow','cutoffHigh','bin2ThresRatio','minPixel','diskRadius','pixelThresRatio','display','plotAllIntermediate', 'waveguideWidth_pixel', 'angle_deg'};
        angleCalibrated = false;
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
        end
    end
    methods
        function [displayImage, segments] = processImage(obj, inputImage, args)
            % Parse args
            if exist('args', 'var') && isfield(args, 'bin1ThresRatio')
                bin1ThresRatio = args.bin1ThresRatio;
            else
                bin1ThresRatio = obj.bin1ThresRatio;
            end
            if exist('args', 'var') && isfield(args, 'bin2ThresRatio')
                bin2ThresRatio = args.bin2ThresRatio;
            else
                bin2ThresRatio = obj.bin2ThresRatio;
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
            bin1Image = obj.binarize(inputImage, obj.bin1ThresRatio)*65535;

            % 2D bandpass filter
            filteredImage = obj.bandpassFilter(bin1Image);

            % Second binarization (slightly different from the first: image contains negative part)
            bin2Image = obj.binarize(filteredImage, obj.bin2ThresRatio);

            % Imopen
            openedImage = bwareaopen(bin2Image, minPixel);

            % Imclose
            closedImage = imclose(openedImage, strel('disk',diskRadius));

            % Select valid segments
            [selectedImage, segments] = obj.selectSegments(closedImage);

            if obj.plotAllIntermediate
                fig = figure(5);
                % Displaying Input Image and Output Image
                subplot(2, 3, 1), imshow(inputImage), set(get(gca, 'Title'), 'String', 'Input image');
                subplot(2, 3, 2), imshow(bin1Image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", bin1ThresRatio));
                subplot(2, 3, 3), imshow(filteredImage, []), set(get(gca, 'Title'), 'String', sprintf("2D bandpass filter\ncutoff: [%d, %d]", cutoffHigh, cutoffLow));
                subplot(2, 3, 4), imshow(bin2Image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", bin2ThresRatio));
                subplot(2, 3, 5), imshow(openedImage), set(get(gca, 'Title'), 'String', sprintf("Imopen min pixel: %d", minPixel));
                subplot(2, 3, 6), imshow(selectedImage), set(get(gca, 'Title'), 'String', sprintf("Imclose disk radius: %d\nKeep biggest component", diskRadius));
            end
        
            
            if isempty(obj.angle_deg) || isnan(obj.angle_deg) || ~obj.angleCalibrated
                obj.getAngle(segments, true);
            end
            segments = obj.detectCorners(segments);



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
            % Normalize displayImage to uint16
            displayImage = double(displayImage);
            minVal = min(displayImage(:));
            maxVal = max(displayImage(:));
            displayImage = uint16((displayImage-minVal)*65535/(maxVal-minVal));
            
        end

        function im = binarize(obj, im, thresRatio)
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
            if showPlots
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
            if isempty(obj.angle_deg) || isnan(obj.angle_deg)
                obj.getAngle(segments, true);
            end
            nSegments = length(segments);
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
            % cornerIm(lr*w+1:(lr+1)*w, lr*w+1:(lr+1)*w) = 1; % Center
            cornerIm((lr+1)*w+1:(2*lr+1)*w, lr*w+1:(lr+1)*w) = 1; % lower edge
            cornerIm(lr*w+1:(lr+1)*w, (lr+1)*w+1:(2*lr+1)*w) = 1; % right edge

            cornerIm(1:lr*w, lr*w+1:(lr+1)*w) = -1; % upper edge
            cornerIm(lr*w+1:(lr+1)*w, 1:lr*w) = -1; % left edge

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
                    [maxy, maxx] = ind2sub(size(corrResult), maxIdx);
                    corners{l} = struct('x', maxx, 'y', maxy, 'val', maxVal);
                    segments{k}.corners = corners;
                    if exist('showPlots', 'var') && showPlots
                        subplot(nSegments+1, 5, 5*k+l+1);
                        imshow(corrResult, []);
                        set(get(gca, 'XLabel'), 'String', sprintf("avg: %f\nmax: %f\n", avg, maxVal));
                    end
                end
            end
        end
    end
end