classdef FullChipDataAnalyzer < matlab.mixin.Heterogeneous & handle

    properties
        dataRootDir = "";
        cmapName = 'lines'; % Name of the colormap
        gdsCorners = [];
        wlCorners = [];
        listeners = {};
        wlPolyH;
        gdsPolyH;
        gdsPosition = [];
        gdsImg;
        wlImg;
        gdsRectH;
        gdsAx;
        gdsFramePos;
        wgLines = {};
        prevChipletData;
        prevChipletDataPath;
        allWaveguidePositions;
        allCornerPositions;
        allChipletStatistics;
    end
    properties(Constant)
        processMincount = 12000;
        sumMincount = 12000;
        frameWidth = 5;
        waveguideWidth = 2;
        padding = 2;
        freqPadding = 50;
        nWaveguides = 6;
        pixel2nm = 160;
        backgroundNoise = 1400; % Derived from the medium of all EMCCD pixels.
        regionMap = {'center', 'frame', 'tip', 'bulk', 'out'};
        namespace = "Drivers_FullChipDataAnalyzer";
        extendRatio = 2/3;
        EMGain = 1200;
    end

    methods(Static)
        function chipletData = loadChipletData(path)
            lastSlashPos = find(path=='\', 1, 'last');
            if isempty(lastSlashPos)
                lastSlashPos = find(path=='/', 1, 'last');
            end
            dotPos = find(path=='.', 1, 'last');
            fileName = extractBetween(path, lastSlashPos+1, dotPos-1);
            fileName = fileName{1};
            date = extractBetween(path, lastSlashPos-16, lastSlashPos-13);
            date = str2num(date{1});
            [tokens,matches] = regexp(fileName,'[cC]hiplet_?(\d+)(.*)','tokens','match'); 
            chipletData = load(path);
            if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                chipletData.chipletIdx = str2num(tokens{1}{1});
                [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                chipletID = str2num(subTokens{1}{3});
                chipletData.chipletID = chipletID; 
                chipletData.nthChiplet = (date-824)*16+chipletData.chipletIdx;

                else
                chipletData.chipletIdx = NaN;
                chipletData.chipletID = NaN;
                chipletData.nthChiplet = NaN;
                fprintf("chipletID and chipletIdx is not assigned. Please consider to format the data file similar with `chiplet1_x0_y0_ID16`.\n");
            end 
        end  
        function region = getRegion(absPosX, absPosY, cornerPosition_xy, drawFig, wl_img)
            if ~exist('wl_img', 'var')
                xsize = 512;
                ysize = 512;
            else
                xsize = size(wl_img, 2);
                ysize = size(wl_img, 1);
            end

            cornerPosition_yx = cornerPosition_xy(:, [2, 1]);
            line1 = cornerPosition_yx(1:2, :); % Left
            line2 = cornerPosition_yx(2:3, :); % Bottom
            line3 = cornerPosition_yx(3:4, :); % Right
            line4 = cornerPosition_yx([4, 1], :); % Top
            frameWidth = Drivers.FullChipDataAnalyzer.frameWidth;
            waveguideSpacing = (norm(cornerPosition_yx(1, :)-cornerPosition_yx(2, :))+norm(cornerPosition_yx(4, :)-cornerPosition_yx(3, :)))/14;
            onFrame1 = getPointLineDistance(absPosX, absPosY, line1(1, 2), line1(1, 1), line1(2, 2), line1(2, 1)) < frameWidth;
            onFrame2 = getPointLineDistance(absPosX, absPosY, line2(1, 2), line2(1, 1), line2(2, 2), line2(2, 1)) < frameWidth + waveguideSpacing/2;
            onFrame3 = getPointLineDistance(absPosX, absPosY, line3(1, 2), line3(1, 1), line3(2, 2), line3(2, 1)) < frameWidth;
            onFrame4 = getPointLineDistance(absPosX, absPosY, line4(1, 2), line4(1, 1), line4(2, 2), line4(2, 1)) < frameWidth + waveguideSpacing/2;
            onFrame= onFrame1 || onFrame2 || onFrame3 || onFrame4;
            leftTipPolygon_yx = [cornerPosition_yx(1:2, :); cornerPosition_yx([2, 1], :)-[0, 75]] + [frameWidth, 0; -frameWidth, 0; -frameWidth, 0; frameWidth, 0];
            rightTipPolygon_yx = [cornerPosition_yx([4, 3], :); cornerPosition_yx([3, 4], :)+[0, 75]] + [frameWidth, 0; -frameWidth, 0; -frameWidth, 0; frameWidth, 0];
            centerDistance = NaN;
            if inpolygon(absPosY, absPosX, cornerPosition_yx(:, 1), cornerPosition_yx(:, 2)) && ~onFrame
                region = 'center';
            elseif onFrame
                region = 'frame';
            elseif inpolygon(absPosY, absPosX, leftTipPolygon_yx(:, 1), leftTipPolygon_yx(:, 2)) || inpolygon(absPosY, absPosX, rightTipPolygon_yx(:, 1), rightTipPolygon_yx(:, 2))
                region = 'tip';
            else
                region = 'bulk';
            end
            if exist('drawFig', 'var') && drawFig
                fig = figure;
                ax = axes(fig);
                imagesc(ax, wl_img);
                colormap('gray');
                hold(ax, 'on');
                plot(ax, cornerPosition_yx([1, 2, 3, 4, 1], 2), cornerPosition_yx([1, 2, 3, 4, 1], 1));
                % obj.plotRotLines(ax, cornerPosition_xy);
                scatter(ax, absPosX, absPosY, 'filled');
                fprintf("Distance: %f\n", centerDistance);
            end
        end

        obj = instance();
        
        

        function emitters = fitPeaks(emitters, drawFig, batchIdx) % Lorentzian fitting
            nEmitters = length(emitters);
            updatedEmitters = cell(nEmitters, 1);
            t = tic;
            prevT = t;
            for k = 1:nEmitters
                emitter = emitters(k);
                nSpectrums = length(emitter.spectrums);
                fittedLinewidth_THz = NaN(nSpectrums, 1);
                fittedPeakAmplitude = NaN(nSpectrums, 1);
                fittedBackground = NaN(nSpectrums, 1);
                for l = 1:nSpectrums
                    intensities = emitter.spectrums(l).sumIntensities;
                    freqs_THz = emitter.spectrums(l).freqs_THz;
                    nPoints = length(freqs_THz);
                    [peakIntensity, peakIdx] = max(intensities);
%                     fitStartIdx = max(1, peakIdx-40);
%                     fitEndIdx = min(nPoints, peakIdx+40);
                    fitFreqs_THz = freqs_THz';
                    prefitIntensities = double(intensities);
    
                    % limits.amplitudes = [0, Inf];
                    % limits.widths = [0, max(fitFreqs_THz)-min(fitFreqs_THz)];
                    % limits.locations = [min(fitFreqs_THz), max(fitFreqs_THz)];
                    % limits.background = [0 max(prefitIntensities)];
                    % [fitFreqs_THz, idx] = sort(fitFreqs_THz, 'ascend');
                    % prefitIntensities = prefitIntensities(idx);
                    % [~, findPeakFreqs, findPeakWidths, findPeakAmplitudes] = findpeaks(prefitIntensities,fitFreqs_THz);
                    % [init.amplitudes, findPeakIdx] = max(findPeakAmplitudes);
                    % init.locations = findPeakFreqs(findPeakIdx);
                    % init.widths = findPeakWidths(findPeakIdx);
                    % init.background = median(prefitIntensities);
                    % [f,new_gof,output] = lorentzfit(fitFreqs_THz, prefitIntensities, 1, init, limits);
                    %  postfitIntensities = f(fitFreqs_THz);
                    %  vals = struct('width', , 'amplitudes', 2*f.a1/f.c1)
                    %          figure; plot(fitFreqs_THz, fitIntensity); hold on; plot(fitFreqs_THz, fittedIntensity)

                    if sum(prefitIntensities>max(intensities)/5) > length(prefitIntensities)/5 % Indicates a broad peak
                        [vals,confs,fit_results,gofs,init,stop_condition] = fitpeaks(fitFreqs_THz,prefitIntensities,"FitType", "lorentz", "n", 1, "Span", 1);
                        postfitIntensities = fit_results{2}(fitFreqs_THz);
                        emitter.spectrums(l).fittedPeakFreq_THz = vals.locations;
                        emitter.spectrums(l).fittedLinewidth_THz = vals.widths*2;
                        emitter.spectrums(l).fittedPeakAmplitude = vals.amplitudes/vals.widths*2;
                        emitter.spectrums(l).fittedBackground = fit_results{2}.d;
                    else
                        [fitFreqs_THz, idx] = sort(fitFreqs_THz, 'ascend');
                        prefitIntensities = prefitIntensities(idx);
                        [~, findPeakFreqs, findPeakWidths, findPeakAmplitudes] = findpeaks(prefitIntensities,fitFreqs_THz);
                        [amplitude, findPeakIdx] = max(findPeakAmplitudes);
                        location = findPeakFreqs(findPeakIdx);
                        width = findPeakWidths(findPeakIdx);
                        background = median(prefitIntensities);
                        % YPRIME(X) = P1./((X - P2).^2 + P3) + C.
                        P2 = location;
                        % P1/P3 = amplitude; width^2/4 = P3
                        P3 = width^2/4;
                        P1 = amplitude*P3;
                        C = background;
                        [postfitIntensities, fittedParams, RESNORM RESIDUAL JACOBIAN] = lorentzfit_new(fitFreqs_THz, prefitIntensities, [P1, P2, P3, C], [], [], optimset('Display','off'));
                        emitter.spectrums(l).fittedPeakFreq_THz = fittedParams(2);
                        emitter.spectrums(l).fittedLinewidth_THz = sqrt(fittedParams(3)*4);
                        emitter.spectrums(l).fittedPeakAmplitude = fittedParams(1)/fittedParams(3);
                        emitter.spectrums(l).fittedBackground = fittedParams(4);
                    end
                    
                    % postfitIntensities = fit_result(fitFreqs_THz);
                    

                    if exist('drawFig', 'var') && drawFig
                        fitting_fig = figure;
                        fitting_ax = axes("Parent", fitting_fig);
                        plot(fitting_ax, fitFreqs_THz, prefitIntensities);
                        hold(fitting_ax, 'on');
                        plot(fitting_ax, fitFreqs_THz, postfitIntensities);
                        fitting_ax.Title.String = sprintf("Emitter No.%d", k);
                    end
                    emitter.spectrums(l).postfitIntensities = postfitIntensities;

                    fittedLinewidth_THz(l) = emitter.spectrums(l).fittedLinewidth_THz;
                    fittedPeakAmplitude(l) = emitter.spectrums(l).fittedPeakAmplitude;
                    fittedBackground(l) = emitter.spectrums(l).fittedBackground;
                end
                emitter.fittedLinewidth_THz = mean(fittedLinewidth_THz);
                emitter.fittedPeakAmplitude = mean(fittedPeakAmplitude);
                emitter.fittedBackground = mean(fittedBackground);
                updatedEmitters{k} = emitter;
                newT = toc(t);
                if exist('batchIdx', 'var')
                    fprintf("Batch %d: Finish fitting emitters %d/%d, last time: %.3f, total time: %.3f\n", batchIdx, k, nEmitters, newT-prevT, newT);
                else
                    fprintf("Finish fitting emitters %d/%d, last time: %.3f, total time: %.3f\n", k, nEmitters, newT-prevT, newT);
                end
                prevT = newT;
            end
            emitters = cell2mat(updatedEmitters);
        end
        % function plotRotLines(rotAx, rotCorners_xy)
        %     extWgLines = cell(1, 6);
        %     hold(rotAx, 'on');
        %     for k = 1:6
        %         startPos = (rotCorners_xy(1, :)*k+rotCorners_xy(2, :)*(7-k))/7;
        %         endPos = (rotCorners_xy(4, :)*k+rotCorners_xy(3, :)*(7-k))/7;
        %         extendedStartPos = startPos + (startPos-endPos)*Drivers.FullChipDataAnalyzer.extendRatio;
        %         extendedEndPos = endPos + (endPos-startPos)*Drivers.FullChipDataAnalyzer.extendRatio;
        %         extWgLines{k} = plot(rotAx, [extendedStartPos(1), extendedEndPos(1)], [extendedStartPos(2), extendedEndPos(2)], 'Color', 'r');
        %     end
        % end
        function emitters = parallelFitPeaks(emitters, batchSize)
            if ~exist('batchSize', 'var')
                batchSize = 500;
            end
            nEmitters = length(emitters);
            nBatches = ceil(nEmitters/batchSize);
            batchedEmitters = cell(nBatches, 1);
            for k = 1:nBatches
                batchedEmitters{k} = emitters((k-1)*batchSize+1:min(k*batchSize, nEmitters));
            end
            allEmitters = cell(nBatches, 1);
            parfor k = 1:nBatches
                batchEmitters = Drivers.FullChipDataAnalyzer.fitPeaks(batchedEmitters{k}, false, k);
                allEmitters{k} = batchEmitters;
            end
            emitters = vertcat(allEmitters{:})';
        end
    end
    methods
        function valid = getEmitterValidity(obj, emitters, drawFig)
            valid = cell2mat(extractfield(emitters, 'valid'));
            absPosX = extractfield(emitters, 'absPosX');
            absPosY = extractfield(emitters, 'absPosY');
            fittedX = extractfield(emitters, 'fittedX');
            fittedY = extractfield(emitters, 'fittedY');
            centerDistance = extractfield(emitters, 'centerDistance');
            nthChiplet = extractfield(emitters, 'nthChiplet');
            fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');

            valid = valid&((fittedX-absPosX).^2+(fittedY-absPosY).^2<0.5);
            valid = valid&(abs(fittedX-absPosX)<0.5)&(abs(fittedY-absPosY)<0.5);
            valid = valid&(isnan(centerDistance)|(abs(centerDistance)<5));
            valid = valid&(fittedLinewidth_THz>30e-6);
            % valid = valid & (nthChiplet~= 56) & (nthChiplet~= 17);
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allChipletValid.mat'), 'allChipletValid');
            invalidChiplets = find(~allChipletValid);
            for k = 1:length(invalidChiplets)
                valid = valid & (nthChiplet ~= invalidChiplets(k));
            end
            if exist('drawFig', 'var') && drawFig
                fig = figure;
                ax = axes(fig);
                scatter(ax, fittedX-absPosX, fittedY-absPosY, 5, 'filled');
            end
        end
        function obj = FullChipDataAnalyzer()
            obj.gdsCorners = obj.fetchPrefData('gdsCorners');
            obj.wlCorners = obj.fetchPrefData('wlCorners');
        end
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

        function emitters = processChiplet(obj, chipletData, drawFig)
            % Parallel can be used if more data is required
            if isstruct(chipletData) && isfield(chipletData, 'path') && ~isfield(chipletData, 'widefieldData')
                chipletIdx = chipletData.chipletIdx;
                chipletID = chipletData.chipletID;
                fprintf("Loading file %s, chipletIdx: %d, chipletID: %d\n", chipletData.path, chipletData.chipletIdx, chipletData.chipletID);
                % Take the data path as input
                chipletData = load(chipletData.path);
                chipletData.chipletIdx = chipletIdx;
                chipletData.chipletID = chipletID;
            end
            % Output data structure: cell array, each cell contain fields:
            %       absPosX, absPosY (absolute in the image), relPosX, relPosY (relative to the center of the chiplet), region ('center', 'frame', 'tip', 'bulk');
            %       brightness (Maximum of original EMCCD count), fittedBrightness (maximum count after Lorentzian filtering), resonantFreq_THz
            %       spectrums (struct array, contains `nSpectrums` spectrums)
            %           hasPeak (boolean), intensity (N*1 array), freqs_THz (N*1 array), fitStartIdx, fitEndIdx, fittedIntensity ((fitEndIdx-fitStartIdx+1)*1 array), peakFreq_THz (double), linewidth (double)
            nSpectrums = length(chipletData.widefieldData);
            assert(isfield(chipletData, 'chipletIdx'), "Please manually assign chipletData.chipletIdx (the n-th scanned chiplet).");
            assert(isfield(chipletData, 'chipletID'), "Please manually assign chipletData.chipletID (the ID number on the sample that represents this chiplet, can be seen on whitelight image).");

            allFilteredImgs = [];
            allFreqs = [];
            % Find all positions whose maximum intensity exceeds mincount (record x, y, freq, maxcount)
            maxFreqDiff = 0;
            for k = 1:nSpectrums
                tempData = chipletData.widefieldData{k};
                allFilteredImgs = cat(3, allFilteredImgs, tempData.filtered_imgs);
                allFreqs = [allFreqs, tempData.freqs];
                maxFreqDiff = max(maxFreqDiff, max(diff(tempData.freqs)));
            end

            [maxIntensity, maxIdx] = max(allFilteredImgs, [], 3);
            [validYs, validXs] = find(maxIntensity > Drivers.FullChipDataAnalyzer.processMincount); % Note that the image has different coordinate system than regular plots.
            validInds = sub2ind(size(allFilteredImgs(:, :, 1)), validYs, validXs);

            peakIntensities = maxIntensity(validInds);
            peakIdx = maxIdx(validInds);
            peakFreqs = transpose(allFreqs(peakIdx));

            

            % Remove neighborhood: for a specific frequency, there should be only one recorded spot in a small region.
            emitterIdx = dbscan([validXs, validYs, peakFreqs*max(min(2e4, 1/maxFreqDiff), 1e4)], 10, 1); % peakFreqs: usually only changes 0.05THz during a scan. Times 2e4 to get a closer order of magnitude with image pixels (usually 512).
          
            if ~exist('drawFig', 'var')
                drawFig = false;
            end
            if drawFig
                fig = figure;
                ax = axes(fig);
                scatter3(ax, validXs, validYs, peakFreqs, (peakIntensities-Drivers.FullChipDataAnalyzer.processMincount+500)/500, emitterIdx, 'filled');
                colormap(ax, 'lines');

            end
            nEmitters = length(unique(emitterIdx));

            emitters = [];
            imageXmax = size(allFilteredImgs, 1);
            imageXmin = 1;
            imageYmax = size(allFilteredImgs, 2);
            imageYmin = 1;

            fprintf("    Start automatic calculating waveguide positions.\n");
            wlFig = figure;
            wlAx = axes(wlFig);
            [waveguidePositions, cornerPositions] = obj.waveguideAutoMatch(chipletData.wl_img, drawFig, false, wlAx);
            hold(wlAx, 'on');
            
            fprintf("    Start processing emitters.\n")
            for l = 1:nEmitters
                tempIdx = find(emitterIdx==l);
                tempXs = validXs(tempIdx);
                tempYs = validYs(tempIdx);

                tempIntensities = peakIntensities(tempIdx);
                tempFreqs = peakFreqs(tempIdx);
                [maxIntensity, maxIdx] = max(tempIntensities);
                emitters(l).absPosX = tempXs(maxIdx);
                emitters(l).absPosY = tempYs(maxIdx);
                % For emitter image block: add padding to neighbor pixels
                xmin = max(emitters(l).absPosX-Drivers.FullChipDataAnalyzer.padding, imageXmin);
                xmax = min(emitters(l).absPosX+Drivers.FullChipDataAnalyzer.padding, imageXmax);
                ymin = max(emitters(l).absPosY-Drivers.FullChipDataAnalyzer.padding, imageYmin);
                ymax = min(emitters(l).absPosY+Drivers.FullChipDataAnalyzer.padding, imageYmax);
                freqIdxMin = max(min(peakIdx(tempIdx))-Drivers.FullChipDataAnalyzer.freqPadding, 1);
                freqIdxMax = min(max(peakIdx(tempIdx))+Drivers.FullChipDataAnalyzer.freqPadding, length(allFreqs));
                
                emitters(l).nthChiplet = chipletData.nthChiplet;

                emitters(l).relPosX = emitters(l).absPosX - chipletData.widefieldData{1}.segment.absCenterX;
                emitters(l).relPosY = emitters(l).absPosY - chipletData.widefieldData{1}.segment.absCenterY;
                emitters(l).maxIntensity = double(maxIntensity);

                emitters(l).resonantFreq_THz = tempFreqs(maxIdx);
                emitters(l).chipletIdx = chipletData.chipletIdx;
                emitters(l).chipletCoordX = chipletData.coordX;
                emitters(l).chipletCoordY = chipletData.coordY;
                emitters(l).chipletID = chipletData.chipletID;
                emitters(l).size_pixel = sum(emitterIdx==l);

                % Get spectrum
                findPeakIntensity = NaN(nSpectrums, 1);
                findPeakFreq = NaN(nSpectrums, 1);
                findPeakWidth_THz = NaN(nSpectrums, 1);
                findPeakAmplitude = NaN(nSpectrums, 1);
                spectrumValid = NaN(nSpectrums, 1);
                fittedX = NaN(nSpectrums, 1);
                fittedY = NaN(nSpectrums, 1);
                gaussianSigma = NaN(nSpectrums, 1);
                gaussianAmplitude = NaN(nSpectrums, 1);
                for k = 1:nSpectrums
                    % freqs_THz = reshape(freqs_THz, nPoints, 1);
                    % intensities = chipletData.widefieldData{k}.filtered_imgs(emitters(l).absPosY, emitters(l).absPosX, :);
                    % intensities = reshape(intensities, nPoints, 1);

                    tempBox = double(chipletData.widefieldData{k}.filtered_imgs(ymin:ymax, xmin:xmax, freqIdxMin:freqIdxMax));
                    nPoints = freqIdxMax-freqIdxMin+1;
                    % tempBackground = double(mean(tempBox, 'all'));
                    sumIntensities = reshape(sum(tempBox-Drivers.FullChipDataAnalyzer.backgroundNoise, [1, 2]), nPoints, 1);
                    freqs_THz = chipletData.widefieldData{k}.freqs(freqIdxMin:freqIdxMax);
                    
                    if max(sumIntensities) > Drivers.FullChipDataAnalyzer.sumMincount
                        hasPeak = true;
                        [peakIntensity, sumPeakIdx] = max(sumIntensities);
                        peakFreq_THz = freqs_THz(sumPeakIdx);
                        maxPlane = tempBox(:, :, sumPeakIdx);
                        props = regionprops(true(size(maxPlane)), maxPlane, 'WeightedCentroid');
                        fittedX(k) = props.WeightedCentroid(2)+xmin-1;
                        fittedY(k) = props.WeightedCentroid(1)+ymin-1;

                        % Fit the variance and amplitude of the 2d gaussian distribution
                        [X, Y] = meshgrid(xmin:xmax, ymin:ymax);
                        % Method 0: Use gaussian distribution formula directly
                        maxPlaneSum = sum(maxPlane(:));

                        gaussianSigma(k) = sqrt(sum(maxPlane(:).*((X(:)-fittedX(k)).^2+(Y(:)-fittedY(k)).^2))/maxPlaneSum);

                        gaussianAmplitude(k) = maxPlaneSum/2/pi/gaussianSigma(k)^2;
                        
                        % Method 1: iterative (most accurate but time-consuming)
                        
                        
                        % Method 2: Weighted regression (fastest)


                        % Use findpeaks to briefly get the linewidth and peak frequency (Usually incorrect);
                        % fitStartIdx = max(1, peakIdx-40);
                        % fitEndIdx = min(nPoints, peakIdx+40);
                        [sortedFreqs_THz, sortedIdx] = sort(freqs_THz, 'ascend');
                        sumIntensities = sumIntensities(sortedIdx);
                        
                        [findPeakIntensities, findPeakFreqs, findPeakWidths, findPeakAmplitudes] = findpeaks(sumIntensities, sortedFreqs_THz);
                        [maxIntensity, maxIdx] = max(findPeakIntensities);
                        peakWidth_THz = findPeakWidths(maxIdx);
                        findPeakIntensity(k) = findPeakIntensities(maxIdx);
                        findPeakFreq(k) = findPeakFreqs(maxIdx);
                        findPeakWidth_THz(k) = findPeakWidths(maxIdx);
                        findPeakAmplitude(k) = findPeakAmplitudes(maxIdx);
                        if sum(sumIntensities >= maxIntensity/3) < 2
                            % No other frequency points have intensitiy larger than half of the maximum intensity
                            spectrumValid(k) = false;
                        else
                            spectrumValid(k) = true;
                        end
                    else
                        hasPeak = false;
                        peakFreq_THz = NaN;
                        peakIntensity = NaN;
                        peakWidth_THz = NaN;
                        spectrumValid(k) = false;
                    end
                    spectrums(k) = struct('spectrumValid', spectrumValid(k), 'hasPeak', hasPeak, 'sumIntensities', sumIntensities, 'freqs_THz', freqs_THz, ...
                    'peakFreq_THz', peakFreq_THz, 'peakIntensity', peakIntensity, 'peakWidth_THz', peakWidth_THz, 'fittedX', fittedX(k), 'fittedY', fittedY(k), ...
                    'maxPlane', maxPlane, 'gaussianSigma', gaussianSigma(k), 'gaussianAmplitude', gaussianAmplitude(k));
                end
                emitters(l).spectrums = spectrums;
                emitters(l).maxSumIntensity = max(peakIntensity);
                emitters(l).valid = any(spectrumValid);
                emitters(l).fittedX = mean(fittedX);
                emitters(l).fittedY = mean(fittedY);
                emitters(l).gaussianSigma = mean(gaussianSigma);
                emitters(l).gaussianAmplitude = mean(gaussianAmplitude);


                region = obj.getRegion(emitters(l).fittedX, emitters(l).fittedY, cornerPositions);
                if strcmp(region, 'center') || strcmp(region, 'tip')
                    centerDistance = obj.getEmitterCenterDistance(emitters(l).fittedX, emitters(l).fittedY, waveguidePositions);
                else
                    centerDistance = NaN;
                end
                emitters(l).region = region;
                emitters(l).centerDistance = centerDistance;
                A = emitters(l).gaussianAmplitude/obj.EMGain;
                s = emitters(l).gaussianSigma;
                b = obj.backgroundNoise/obj.EMGain;
                emitters(l).posErr = sqrt((A/12+(4*b+A)*s^2)/(pi*s^2*A^2));
            end
            if drawFig
                region = extractfield(emitters, 'region');
                fittedX = extractfield(emitters, 'fittedX');
                fittedY = extractfield(emitters, 'fittedY');
                scatterSize = 10;
                center = strcmp(region, 'center');
                tip = strcmp(region, 'tip');
                bulk = strcmp(region, 'bulk');
                frame = strcmp(region, 'frame');
                scatter(wlAx, fittedX(center), fittedY(center), scatterSize, 'filled');
                scatter(wlAx, fittedX(tip), fittedY(tip), scatterSize, 'filled');
                scatter(wlAx, fittedX(bulk), fittedY(bulk), scatterSize, 'filled');
                scatter(wlAx, fittedX(frame), fittedY(frame), scatterSize, 'filled');
            end
            % valid = extractfield(emitters, 'valid');
            % emitters(~valid) = [];
        end

        function gdsFramePos = getGdsFrame(obj, gdsImg)
            gdsFig = figure;
            obj.gdsAx = axes(gdsFig);
            gdsImH = imagesc(obj.gdsAx, gdsImg);
            colormap(obj.gdsAx, 'gray');
            hold(obj.gdsAx, 'on');
            obj.gdsRectH = images.roi.Rectangle(obj.gdsAx, 'Position', [10, 10, size(gdsImg, 2)-10, size(gdsImg, 1)-10]);
            obj.updateFramePos;
            addlistener(obj.gdsRectH,'ROIMoved',@obj.updateFramePos);
            gdsImH.ButtonDownFcn = @ROIConfirm;
            gdsFig.KeyPressFcn = @ROIConfirm;
            uiwait(gdsFig);
            gdsFramePos = obj.gdsRectH.Position;
            obj.gdsFramePos = gdsFramePos;
            save(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "gdsFramePos.mat"), 'gdsFramePos');
        end

        function updateFramePos(obj, varargin)
            pos = obj.gdsRectH.Position;
            xmin = pos(1);
            ymin = pos(2);
            xlen = pos(3);
            ylen = pos(4);
            hold(obj.gdsAx, 'on');
            if isempty(obj.wgLines) || ~iscell(obj.wgLines)
                obj.wgLines = cell(1, 6);
            end
            for k = 1:6
                try
                    obj.wgLines{k}.delete;
                end
                obj.wgLines{k} = plot(obj.gdsAx, [xmin, xmin+xlen], [ymin+ylen*k/7, ymin+ylen*k/7], 'Color', 'r');
            end
        end
        function rotCorners_xy = getRotatedGdsCorners(obj, gdsImg, gdsFramePos, theta_deg, drawFig)
            % Calculate rotatedCorners for chiplet gds

            % fprintf("Original size: %d, %d\n", size(gdsImg, 2), size(gdsImg, 1));
            % fprintf("Rotated size: %d, %d\n", size(rotImg, 2), size(rotImg, 1));
            center_xy = [size(gdsImg, 2), size(gdsImg, 1)]/2;
            frameCorners_xy = [gdsFramePos(1), gdsFramePos(2); gdsFramePos(1), gdsFramePos(2)+gdsFramePos(4); gdsFramePos(1)+gdsFramePos(3), gdsFramePos(2)+gdsFramePos(4); gdsFramePos(1)+gdsFramePos(3), gdsFramePos(2)];
            vectors = frameCorners_xy - center_xy;
            rotVectors = vectors*[cosd(theta_deg), -sind(theta_deg); sind(theta_deg), cosd(theta_deg)];
            rotCorners_xy = rotVectors + center_xy;
            % xmin = rotCorners_xy(1, 1);
            % ymin = rotCorners_xy(1, 2);
            % xlen = rotCorners_xy(3, 1)-rotCorners_xy(1, 1);
            % ylen = rotCorners_xy(3, 2)-rotCorners_xy(1, 2);
            % rotFramePos = [xmin, ymin, xlen, ylen];
            if exist("drawFig", 'var') && drawFig
                rotImg = imrotate(gdsImg, theta_deg, 'nearest', 'crop');
                rotFig = figure;
                rotAx = axes(rotFig);
                imagesc(rotAx, rotImg);
                colormap(rotAx, 'gray');
                obj.plotRotLines(rotAx, rotCorners_xy);
            end
        end

        function getGdsTemplate(obj, wlImg, presetPosition)
            gdsImg = rgb2gray(imread(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "chiplet_only.png")));
            gdsImg = (gdsImg>0);
            obj.gdsImg = gdsImg;
            if ~exist('wlImg', 'var') || isempty(wlImg)
                wlImg = load(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "wl_sample.mat"));
            end

            if isfield(wlImg, 'wlImg')
                wlImg = wlImg.wlImg;
            end
            % wlImg = rot90(wlImg, 2);
            obj.wlImg = wlImg;
            wlFig = figure;
            wlFig.Position = [300 600 560 420];
            wlAx = axes(wlFig);
            wlImH = imagesc(wlAx, wlImg);
            colormap(wlAx, 'gray');
            wlXmax = size(wlImg, 2);
            wlYmax = size(wlImg, 1);
            hold(wlAx, 'on');
            if exist('presetPosition', 'var') && isfield(presetPosition, 'wlCorners')
                obj.wlCorners = presetPosition.wlCorners;
            end
            if ~isempty(obj.wlCorners)
                obj.wlPolyH = drawpolygon(wlAx, 'Position', obj.wlCorners);
            else
                obj.wlPolyH = drawpolygon(wlAx, 'Position', [1, 1; 1, wlYmax; wlXmax, wlYmax; wlXmax, 1]);
            end
            set(get(wlAx, 'Title'), 'String', sprintf('Press enter or right click the outside image to confirm template corners.'));
            % wlImH.ButtonDownFcn = @ROIConfirm;
            % wlFig.KeyPressFcn = @ROIConfirm;
            % uiwait(wlFig);
            obj.listeners{1} = addlistener(obj.wlPolyH, 'ROIMoved', @obj.updateMatching);


            gdsFig = figure;
            gdsFig.Position = [900 600 560 420];
            gdsAx = axes(gdsFig);
            gdsImH = imagesc(gdsAx, gdsImg);
            colormap(gdsAx, 'gray');
            gdsXmax = size(gdsImg, 2);
            gdsYmax = size(gdsImg, 1);
            hold(gdsAx, 'on');
            if exist('presetPosition', 'var') && isfield(presetPosition, 'gdsCorners')
                obj.gdsCorners = presetPosition.gdsCorners;
            end
            if ~isempty(obj.gdsCorners)
                obj.gdsPolyH = drawpolygon(gdsAx, 'Position', obj.gdsCorners);
            else
                obj.gdsPolyH = drawpolygon(gdsAx, 'Position', [1, 1; 1, gdsYmax; gdsXmax, gdsYmax; gdsXmax, 1]);
            end
            set(get(gdsAx, 'Title'), 'String', sprintf('Press enter or right click the outside image to confirm template corners.'));
            obj.listeners{2} = addlistener(obj.gdsPolyH, 'ROIMoved', @obj.updateMatching);
            obj.updateMatching;
            gdsImH.ButtonDownFcn = @ROIConfirm;
            gdsFig.KeyPressFcn = @ROIConfirm;
            uiwait(gdsFig);

        end

        function updateMatching(obj, varargin)
            wlCorners_yx = obj.wlPolyH.Position;
            obj.wlCorners = wlCorners_yx;
            wlLine1_yx = wlCorners_yx(1,:) - wlCorners_yx(2,:);
            wlLine2_yx = wlCorners_yx(2,:) - wlCorners_yx(3,:);
            wlLine3_yx = wlCorners_yx(3,:) - wlCorners_yx(4,:);
            wlLine4_yx = wlCorners_yx(4,:) - wlCorners_yx(1,:);

            gdsCorners_yx = obj.gdsPolyH.Position;
            obj.gdsCorners = gdsCorners_yx;
            gdsLine1_yx = gdsCorners_yx(1, :) - gdsCorners_yx(2, :);
            gdsLine2_yx = gdsCorners_yx(2, :) - gdsCorners_yx(3, :);
            gdsLine3_yx = gdsCorners_yx(3, :) - gdsCorners_yx(4, :);
            gdsLine4_yx = gdsCorners_yx(4, :) - gdsCorners_yx(1, :);

            obj.savePrefData('gdsCorners', obj.gdsCorners);
            obj.savePrefData('wlCorners', obj.wlCorners);

            verticalRatio = (norm(wlLine1_yx)+norm(wlLine3_yx))/(norm(gdsLine1_yx)+norm(gdsLine3_yx));
            horizontalRatio = (norm(wlLine2_yx)+norm(wlLine4_yx))/(norm(gdsLine2_yx)+norm(gdsLine4_yx));
            
            % rotate(gds, angle) -> wl
            sumAngleDiff = ((atan(wlLine1_yx(1)/wlLine1_yx(2))+atan(wlLine2_yx(1)/wlLine2_yx(2))+atan(wlLine3_yx(1)/wlLine3_yx(2))+atan(wlLine4_yx(1)/wlLine4_yx(2)))-(atan(gdsLine1_yx(1)/gdsLine1_yx(2))+atan(gdsLine2_yx(1)/gdsLine2_yx(2))+atan(gdsLine3_yx(1)/gdsLine3_yx(2))+atan(gdsLine4_yx(1)/gdsLine4_yx(2))));
            if sumAngleDiff > pi*3/4
                sumAngleDiff = sumAngleDiff - pi;
            elseif sumAngleDiff < -pi*3/4
                sumAngleDiff = sumAngleDiff + pi;
            end
            rotationAngle = sumAngleDiff/4;


            % reshapedGdsImg = imresize(obj.gdsImg, size(obj.gdsImg).*[verticalRatio, horizontalRatio]);
            reshapedWlImg = imresize(obj.wlImg, size(obj.wlImg)./[verticalRatio, horizontalRatio]);
            reshapedGdsImg = imrotate(obj.gdsImg, rotationAngle/pi*180, 'nearest', 'crop');
            

            save(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "reshapedImgs.mat"), 'reshapedGdsImg', 'reshapedWlImg');
            normedWlImg = reshapedWlImg - mean(reshapedWlImg, 'all');

            coarseRatio = 10;
            fineRange = 50;
            coarseConvResult = conv2(imresize(normedWlImg, size(normedWlImg)/coarseRatio), imresize(reshapedGdsImg, size(reshapedGdsImg)/coarseRatio), 'valid');
            [maxCorr,idx] = max(coarseConvResult(:));
            [posY, posX] = ind2sub(size(coarseConvResult),idx);
            xmin = max(1, posX*coarseRatio-fineRange);
            xmax = min(posX*coarseRatio+fineRange+size(reshapedGdsImg, 2), size(normedWlImg, 2));
            ymin = max(1, posY*coarseRatio-fineRange);
            ymax = min(posY*coarseRatio+fineRange+size(reshapedGdsImg, 1), size(normedWlImg, 1));

            convResult = conv2(normedWlImg(ymin:ymax, xmin:xmax), reshapedGdsImg, 'valid');

            convFig = figure(41);
            convFig.Position = [900 50 560 420];
            convAx = axes(convFig);
            hold(convAx, 'off');
            imagesc(convAx, convResult);
            [maxCorr,idx] = max(convResult(:));
            [posY, posX] = ind2sub(size(convResult),idx);
            gdsSize = size(reshapedGdsImg);
            gdsRef = imref2d(gdsSize, xmin+posX + [0, gdsSize(2)], ymin+posY+[0, gdsSize(1)]);
            wlRef = imref2d(size(reshapedWlImg));
            fusedFig = figure(42);
            imshow(imfuse(reshapedWlImg, wlRef, reshapedGdsImg, gdsRef));
            fusedFig.Position = [250 1 640 540];
            obj.gdsPosition = struct('verticalRatio', verticalRatio, 'horizontalRatio', horizontalRatio, 'rotationAngle', rotationAngle, 'posX', posX, 'posY', posY);
        end
        function [allFolders, allFileNames] = getAllDataFiles(obj)
            allFolders = {};
            allFileNames = {};
            folders = dir(fullfile(obj.dataRootDir, 'CleanedData'));
            for k = 1:length(folders)
                startNum = length(allFolders);
                folder = folders(k);
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', folder.name);
                if isfolder(srcDir) && ~contains(folder.name, '.')
                    files = dir(srcDir);
                    tempIdxes = [];
                    fprintf("Scanning srcDir: '%s'\n", srcDir);
                    nValid = 0;
                    for l = 1:length(files)
                        file = files(l);
                        % fprintf('Checking file %s (%d/%d)\n', file.name, l, length(files));
                        [tokens,matches] = regexp(file.name,'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                        if ~isempty(tokens)
                            nValid = nValid + 1;
                            idx = str2num(tokens{1}{1});
                            fprintf("Find widefield data file '%s'\n", file.name);
                            allFolders{end+1} = folder.name;
                            allFileNames{end+1} = file.name;
                            tempIdxes(end+1) =  idx;
                            if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                                [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                                chipletCoordX = str2num(subTokens{1}{1});
                                chipletCoordY = str2num(subTokens{1}{2});
                                load(fullfile(srcDir, file.name), 'coordX', 'coordY');
                                assert(chipletCoordX == coordX && chipletCoordY == coordY, 'Chiplet coordinate inside data does not match with the file name.');
                            end
                        end
                    end
                    [sortedIdx, sequence] = sort(tempIdxes, 'ascend');
                    endNum = length(allFolders);
                    allFileNames(startNum+1:endNum) = allFileNames(startNum+sequence);
                end
            end
        end
        function [allSize, allSlant] = categorizeWlImgs(obj)
            [allFolders, allFileNames] = obj.getAllDataFiles;
            fprintf("For the following inputs, press enter if it is the same as the previous one (except for the first image).\n");
            nImgs = length(allFolders);
            allSize = NaN(nImgs, 1); % 1 for small, 2 for medium, 3 for large
            allSlant = NaN(nImgs, 1); % 4 for slightly, 5 for medium, 6 for significantly
            for k = 1:nImgs
                load(fullfile(obj.dataRootDir, 'CleanedData', allFolders{k}, allFileNames{k}), 'wl_img');
                obj.gdsMatch(wl_img, obj.gdsPosition, true);
                
                pause(0.1);
                imSize = input("Please input the size of the chiplet (1 for small, 2 for medium, 3 for large)");
                while ~isempty(imSize) && ~any(imSize == [1, 2, 3]) || k == 1 && isempty(imSize)
                    imSize = input("Please input the size of the chiplet (1 for small, 2 for medium, 3 for large)");
                end
                if isempty(imSize)
                    imSize = prevSize;
                    slant = prevSlant;
                else
                    slant = input("Please input the slant of the image (4 for slightly, 5 for medium, 6 for significantly)");
                    while ~any(slant == [4, 5])
                        slant = input("Please input the slant of the image (4 for slightly, 5 for medium, 6 for significantly)");
                    end
                end
                prevSize = imSize;
                prevSlant = slant;
                allSize(k) = imSize;
                allSlant(k) = slant;
            end
            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'wlImgInfo.mat'), 'allSize', 'allSlant');
        end

        function initAllTemplates(obj, startNum)
            if ~exist('startNum', 'var')
                startNum = 1;
            end
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'wlImgInfo.mat'), 'allSize', 'allSlant'); % variables: allSize (64*1), allSlant(64*1)
            [allFolders, allFileNames] = obj.getAllDataFiles;
            nFiles = length(allFileNames);
            allGdsPositions = [];
            sizeDict = {"small", "medium", "large"};
            slantDict = {"slghtly", "medium", "significantly"};
            count = 0;
            for chipletSize = [1, 2, 3]
                for imSlant = [4, 5, 6]
                    count = count + 1;
                    if count < startNum
                        continue;
                    end
                    for k = 1:nFiles
                        if allSize(k) == chipletSize && allSlant(k) == imSlant
                            fprintf("Setting gds template for size: %d, slant: %d from experiment %s, file %s\n", chipletSize, imSlant, allFolders{k}, allFileNames{k});
                            load(fullfile(obj.dataRootDir, 'CleanedData', allFolders{k}, allFileNames{k}), "wl_img");
                            tempPositionFile = fullfile(obj.dataRootDir, 'CleanedData', 'GdsPositions', sprintf("gdsPosition_%d_%d.mat", chipletSize, imSlant));
                            if isfile(tempPositionFile)
                                load(tempPositionFile, 'gdsPosition');
                                obj.getGdsTemplate(wl_img, gdsPosition);
                            else
                                obj.getGdsTemplate(wl_img);
                            end

                            obj.gdsPosition.size = sizeDict{chipletSize};
                            obj.gdsPosition.slant = slantDict{imSlant-3};
                            obj.gdsPosition.wlCorners = obj.wlCorners;
                            obj.gdsPosition.gdsCorners = obj.gdsCorners;
                            obj.gdsPosition.sampleFolder = allFolders{k};
                            obj.gdsPosition.sampleFileName = allFileNames{k};
                            obj.gdsPosition.sampleIdx = k;
                            if isempty(allGdsPositions)
                                allGdsPositions = obj.gdsPosition;
                            else
                                allGdsPositions(end+1) = obj.gdsPosition;
                            end
                            gdsPosition = obj.gdsPosition;
                            save(tempPositionFile, 'gdsPosition');
                            break;
                        end
                    end
                end
            end
        end
        
        function plotFittedWaveguide(obj, wlImg, waveguidePositions, cornerPositions, ax)
            imagesc(ax, wlImg);
            colormap(ax, 'gray');
            hold(ax, 'on');
            plot(ax, cornerPositions([1, 2, 3, 4, 1], 1), cornerPositions([1, 2, 3, 4, 1], 2));
            cmap = lines(1);
            for k = 1:6
                xstart = waveguidePositions(k, 1);
                ystart = waveguidePositions(k, 2);
                xend = waveguidePositions(k, 3);
                yend = waveguidePositions(k, 4);

                xstartExtended = xstart + (xstart - xend)*obj.extendRatio;
                xendExtended = xend + (xend - xstart)*obj.extendRatio;
                ystartExtended = ystart + (ystart - yend)*obj.extendRatio;
                yendExtended = yend + (yend - ystart)*obj.extendRatio;
                plot(ax, [xstartExtended, xendExtended], [ystartExtended, yendExtended], 'Color', cmap);
            end
        end
        function [waveguidePositions, cornerPositions] = waveguideAutoMatch(obj, wlImg, drawFig, drawIntermediate, ax)

            
            ip = Drivers.ImageProcessor.instance();
            if exist('drawIntermediate', 'var') && drawIntermediate
                ip.plotAllIntermediate = true;
            else
                ip.plotAllIntermediate = false;
                drawIntermediate = false;
            end


            % wlImg = rot90(wlImg, 2);
            [waveguidePositions, cornerPositions] = ip.getWaveguidePositions(wlImg, drawIntermediate);

            if ~exist('drawFig', 'var') || ~drawFig
                return;
            end
            if ~exist('ax') || isempty(ax) || ~isvalid(ax)
                fig = figure;
                ax = axes(fig);
            end
            obj.plotFittedWaveguide(wlImg, waveguidePositions, cornerPositions, ax);
        end
        function [allWaveguidePositions, allCornerPositions] = getAllPositions(obj, drawFig, startNum)
            if ~exist('drawFig', 'var')
                drawFig = false;
            end
            [allFolders, allFileNames] = obj.getAllDataFiles;
            nChiplets = length(allFolders);
            allWaveguidePositions = NaN(nChiplets, 6, 4);
            allCornerPositions = NaN(nChiplets, 4, 2);

            if ~exist('startNum', 'var')
                startNum = 1;
            end
            for k = startNum:nChiplets
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', allFolders{k});
                dstDir = fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k});
                [tokens,matches] = regexp(allFileNames{k},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                idx = str2num(tokens{1}{1});
                fprintf("Processing file '%s' (%d/%d), idx: %d.\n", allFileNames{k}, k, length(allFolders), idx);
                load(fullfile(srcDir, allFileNames{k}), 'wl_img');
                % wl_img = rot90(wl_img, 2);
                if drawFig
                    fig = figure;
                    fig.Position = [500, 200, 1000, 800];
                    ax = axes(fig);
                    % allWaveguidePositions(k, :, :) = obj.gdsMatch(wl_img, gdsPosition, true, ax);
                    [allWaveguidePositions(k, :, :), allCornerPositions(k, :, :)] = obj.waveguideAutoMatch(wl_img, true, false, ax);
                    saveas(fig, fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k}, sprintf("automatch_chiplet%d.png", idx)));
                else
                    [allWaveguidePositions(k, :, :), allCornerPositions(k, :, :)] = obj.waveguideAutoMatch(wl_img, false, false);
                end
            end
            obj.allWaveguidePositions = allWaveguidePositions;
            obj.allCornerPositions = allCornerPositions;
            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allWaveguidePositions.mat'), 'allWaveguidePositions');
            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allCornerPositions.mat'), 'allCornerPositions');
        end
        function emitterGroups = divideEmitters(obj, emitters, chiplets)
            nthChiplet = extractfield(emitters, 'nthChiplet');
            if ~exist('chiplets' ,'var')
                chiplets = unique(nthChiplet);
            end
            
            nChiplets = length(chiplets);
            emitterGroups = cell(1, nChiplets);
            % valid = obj.getEmitterValidity(emitters);
            for k = 1:nChiplets
                emitterGroups{k} = emitters((nthChiplet == chiplets(k)));
            end
        end
        function rotCorners_xy = gdsMatch(obj, wl_img, gdsPosition, drawFig, fusedAx)
            % wl_img = rot90(wl_img, 2);
            reshapedWlImg = imresize(wl_img, size(wl_img)./[gdsPosition.verticalRatio, gdsPosition.horizontalRatio]);
            if isempty(obj.gdsImg)
                gdsImg = rgb2gray(imread(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "chiplet_only.png")));
                gdsImg = (gdsImg>0);
                obj.gdsImg = gdsImg;
            end


            reshapedGdsImg = imrotate(obj.gdsImg, gdsPosition.rotationAngle/pi*180, 'nearest', 'crop');
            normedWlImg = reshapedWlImg - mean(reshapedWlImg, 'all');

            coarseRatio = 10;
            fineRange = 50;
            coarseConvResult = conv2(imresize(normedWlImg, size(normedWlImg)/coarseRatio), imresize(reshapedGdsImg, size(reshapedGdsImg)/coarseRatio), 'valid');
            [maxCorr,idx] = max(coarseConvResult(:));
            [posY, posX] = ind2sub(size(coarseConvResult),idx);
            xmin = max(1, posX*coarseRatio-fineRange);
            xmax = min(posX*coarseRatio+fineRange+size(reshapedGdsImg, 2), size(normedWlImg, 2));
            ymin = max(1, posY*coarseRatio-fineRange);
            ymax = min(posY*coarseRatio+fineRange+size(reshapedGdsImg, 1), size(normedWlImg, 1));

            convResult = conv2(normedWlImg(ymin:ymax, xmin:xmax), reshapedGdsImg, 'valid');
            
            [maxCorr,idx] = max(convResult(:));
            [posY, posX] = ind2sub(size(convResult),idx);
            gdsSize = size(reshapedGdsImg);
            gdsRef = imref2d(gdsSize, xmin+posX + [0, gdsSize(2)], ymin+posY+[0, gdsSize(1)]);
            wlRef = imref2d(size(reshapedWlImg));
            if isempty(obj.gdsFramePos)
                try
                    load(fullfile(obj.dataRootDir, "CleanedData", "SupplementaryFiles", "gdsFramePos.mat"), 'gdsFramePos');
                    obj.gdsFramePos = gdsFramePos;
                catch
                    obj.gdsFramePos = obj.getGdsFrame(obj.gdsImg);
                end
            end
            rotCorners_xy = obj.getRotatedGdsCorners(obj.gdsImg, obj.gdsFramePos, gdsPosition.rotationAngle/pi*180);
            rotCorners_xy = rotCorners_xy + [xmin+posX, ymin+posY];
            rotCorners_xy = rotCorners_xy.*[gdsPosition.horizontalRatio, gdsPosition.verticalRatio];
            if exist('drawFig', 'var') && drawFig
                if ~exist('fusedAx', 'var') || isempty(fusedAx) || ~isvalid(fusedAx)
                    fusedFig = figure;
                    fusedAx = axes(fusedFig);
                end
                % imagesc(fusedAx, reshapedWlImg);
                imagesc(fusedAx, wl_img);
                colormap(fusedAx, 'gray');
                % imshow(imfuse(reshapedWlImg, wlRef, reshapedGdsImg, gdsRef));

                obj.plotRotLines(fusedAx, rotCorners_xy);
                fusedFig.Position = [250 1 800 700];
                pause(0.1);
            end
        end
        function plotSingleWL(obj, emitters, wlImg, ax)
            nthChiplet = unique(extractfield(emitters, 'nthChiplet'));
            if length(nthChiplet) > 1
                error("Emitters from more than one chiplets are included.");
            end
            
            cmap = lines(2);
            fittedX = extractfield(emitters, 'fittedX');
            fittedY = extractfield(emitters, 'fittedY');
            absPosX = extractfield(emitters, 'absPosX');
            absPosY = extractfield(emitters, 'absPosY');
            centerDistance = extractfield(emitters, 'centerDistance');
            region = extractfield(emitters, 'region');
            valid = obj.getEmitterValidity(emitters);
            fittedPeakAmplitude = extractfield(emitters, 'fittedPeakAmplitude');
            fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');
            
            if ~exist('ax', 'var') || isempty(ax) || ~isvalid(ax)
                fig = figure;
                ax = axes(fig);
            end
            obj.plotFittedWaveguide(wlImg, squeeze(obj.allWaveguidePositions(nthChiplet, :, :)), squeeze(obj.allCornerPositions(nthChiplet, :, :)), ax);
            hold(ax, 'on');
            tipValid = strcmp(region, 'tip');
            linewidthRef = 1e-4;
            tipFittedX = fittedX(tipValid);
            tipFittedY = fittedY(tipValid);
            tipPosErr = sqrt((tipFittedX - absPosX(tipValid)).^2+(tipFittedY - absPosY(tipValid)).^2);
            tipColors = max(0, min((1-abs(centerDistance(tipValid))')/1, 1)*cmap(2, :));
            % scatter(ax, tipFittedX, tipFittedY, fittedPeakAmplitude(tipValid)/50000, tipColors, 'filled');
            scatter(ax, tipFittedX, tipFittedY, 10, cmap(2, :), 'filled');
            tipFittedLinewidth_THz = fittedLinewidth_THz(tipValid);
            % for l = 1:sum(tipValid)
            %     line([tipFittedX(l)-tipPosErr(l), tipFittedX(l)+tipPosErr(l)], [tipFittedY(l), tipFittedY(l)], 'Color', tipColors(l, :), 'Parent', ax, 'LineWidth', 1);
            %     line([tipFittedX(l), tipFittedX(l)], [tipFittedY(l)+tipFittedLinewidth_THz(l)/linewidthRef, tipFittedY(l)-tipFittedLinewidth_THz(l)/linewidthRef], 'Color', tipColors(l, :), 'Parent', ax, 'LineWidth', 1);
            % end


            % centerValid = strcmp(region, 'center'); 
            % centerFittedX = fittedX(centerValid);
            % centerFittedY = fittedY(centerValid);
            % centerPosErr = sqrt((centerFittedX - absPosX(centerValid)).^2+(centerFittedY - absPosY(centerValid)).^2);
            % centerColors = max(0, min((1-abs(centerDistance(centerValid))')/1, 1)*cmap(1, :));
            % scatter(ax, centerFittedX, centerFittedY, fittedPeakAmplitude(centerValid)/50000, centerColors, 'filled');
            % centerFittedLinewidth_THz = fittedLinewidth_THz(centerValid);
            % for l = 1:sum(centerValid)
            %     line([centerFittedX(l)-centerPosErr(l), centerFittedX(l)+centerPosErr(l)], [centerFittedY(l), centerFittedY(l)], 'Color', centerColors(l, :), 'Parent', ax, 'LineWidth', 1);
            %     line([centerFittedX(l), centerFittedX(l)], [centerFittedY(l)+centerFittedLinewidth_THz(l)/linewidthRef, centerFittedY(l)-centerFittedLinewidth_THz(l)/linewidthRef], 'Color', centerColors(l, :), 'Parent', ax, 'LineWidth', 1);
            % end


            pause(0.3);
            
        end
        function [allWaveguidePositions, allCornerPositions] = plotChipletEmitters(obj, plotEmitters, emitters, startNum)
            % Deprecated
            [allFolders, allFileNames] = obj.getAllDataFiles;
            % load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'wlImgInfo.mat'), 'allSize', 'allSlant'); % variables: allSize (64*1), allSlant(64*1)
            if ~exist('startNum', 'var')
                startNum = 1;
            end
            nChiplets = length(allFolders);
            allWaveguidePositions = NaN(nChiplets, 6, 4);
            allCornerPositions = NaN(nChiplets, 4, 2);
            if exist('plotEmitters', 'var') && plotEmitters
                if ~exist('emitters', 'var') || isempty(emitters)
                    load(fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData', 'all_emitters_data.mat'), 'emitters')
                end
                nthChiplet = extractfield(emitters, 'nthChiplet');
                valid = obj.getEmitterValidity(emitters);
            end

            for k = startNum:nChiplets
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', allFolders{k});
                dstDir = fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k});
                [tokens,matches] = regexp(allFileNames{k},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                idx = str2num(tokens{1}{1});
                fprintf("Processing file '%s' (%d/%d), idx: %d.\n", allFileNames{k}, k, length(allFolders), idx);
                load(fullfile(srcDir, allFileNames{k}), 'wl_img');
                chipletSize = allSize(k);
                imSlant = allSlant(k);
                fprintf("ChipletSize: %d, ImageSlant: %d\n", chipletSize, imSlant);
                tempPositionFile = fullfile(obj.dataRootDir, 'CleanedData', 'GdsPositions', sprintf("gdsPosition_%d_%d.mat", chipletSize, imSlant));
                load(tempPositionFile, 'gdsPosition');
                fig = figure;
                if exist('plotEmitters', 'var') && plotEmitters
                    cmap = lines(2);
                    tipCbAx = axes(fig);
                    tipCbAx.Visible = 'off';
                    colormap(tipCbAx, linspace(1, 0, 64)'*cmap(2, :));
                    tipCbH = colorbar(tipCbAx);
                    tipCbH.Position = [0.92, 0.1, 0.03, 0.8];
                    centerCbAx = axes(fig);
                    centerCbAx.Visible = 'off';
                    colormap(centerCbAx, linspace(1, 0, 64)'*cmap(1, :));
                    centerCbH = colorbar(centerCbAx);
                    centerCbH.Position = [0.07, 0.1, 0.03, 0.8];
                end
                fusedAx = axes(fig);
                if ~exist('plotEmitters', 'var') || ~plotEmitters
                    [allWaveguidePositions(k, :, :), allCornerPositions(k, :, :)] = obj.waveguideAutoMatch(wl_img, true, false, fusedAx);
                else
                    [allWaveguidePositions(k, :, :), allCornerPositions(k, :, :)] = obj.waveguideAutoMatch(wl_img);
                    fusedAx.Position = [0.17, 0.1, 0.7, 0.8];
                end
                if exist('plotEmitters', 'var') && plotEmitters
                    obj.plotSingleWL(emitters(valid&(nthChiplet==k)), wl_img, fusedAx);
                end
                fig.Position = [500, 200, 1000, 800];
                saveas(fig, fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k}, sprintf("chiplet%d_size%d_slant%d.png", idx, chipletSize, imSlant)));
            end

            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allWaveguidePositions.mat'), 'allWaveguidePositions');
            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allCornerPositions.mat'), 'allCornerPositions');
        end 

        function centerDistance = getEmitterCenterDistance(obj, absPosX, absPosY, waveguidePositions)
            waveguideDists = NaN(6, 1);
            for m = 1:6
                waveguideDists(m) = getPointLineDistance(absPosX, absPosY, waveguidePositions(m, 1), waveguidePositions(m, 2), waveguidePositions(m, 3), waveguidePositions(m, 4), true, true); % Infinity length should be set to true.
            end
            [minval, closestLine] = min(abs(waveguideDists));
            centerDistance = waveguideDists(closestLine);
        end

        function emitters = updateEmitterProperties(obj, emitters, properties)
            if isstring(properties) || ischar(properties)
                properties = {properties};
            end
            for k = 1:length(properties)
                property = properties{k};
                if strcmp(property, 'posErr')
                    for l = 1:length(emitters)
                        A = emitters(l).gaussianAmplitude/obj.EMGain;
                        s = emitters(l).gaussianSigma;
                        b = obj.backgroundNoise/obj.EMGain;
                        emitters(l).posErr = sqrt((A/12+(4*b+A)*s^2)/(pi*s^2*A^2));
                    end
                elseif strcmp(property, 'region')
                    if isempty(obj.allCornerPositions)
                        load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allCornerPositions.mat'), 'allCornerPositions')
                        obj.allCornerPositions = allCornerPositions;
                    end
                    nthChiplet = extractfield(emitters, 'nthChiplet');
                    for l = 1:length(emitters)
                        emitters(l).region = obj.getRegion(emitters(l).absPosX, emitters(l).absPosY, squeeze(obj.allCornerPositions(nthChiplet(l), :, :)));
                    end
                elseif strcmp(property, 'centerDistance')
                    if isempty(obj.allWaveguidePositions)
                        load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allWaveguidePositions.mat'), 'allWaveguidePositions')
                        obj.allWaveguidePositions = allWaveguidePositions;
                    end
                    region = extractfield(emitters, 'region');
                    nthChiplet = extractfield(emitters, 'nthChiplet');
                    for k = 1:length(emitters)
                        if strcmp(region(k), 'center') || strcmp(region(k), 'tip')
                            emitters(k).centerDistance = obj.getEmitterCenterDistance(emitters(k).fittedX, emitters(k).fittedY, squeeze(obj.allWaveguidePositions(nthChiplet(k), :, :)));
                        else
                            emitters(k).centerDistance = NaN;
                        end
                    end
                    % chipletList = unique(nthChiplet);
                    % for k = 1:length(chipletList)
                    %     tempN = chipletList(k);
                    %     emitterIdx = find(nthChiplet==tempN & (strcmp(region, 'tip')|strcmp(region, 'center')));
                    %     for l = 1:length(emitterIdx)
                    %         absPosX = emitters(emitterIdx(l)).absPosX;
                    %         absPosY = emitters(emitterIdx(l)).absPosY;
                    %         emitters(emitterIdx(l)).centerDistance =obj.getEmitterCenterDistance(absPosX, absPosY, squeeze(obj.allWaveguidePositions(tempN, :, :)));
                    %     end
                    % end
                elseif strcmp(property, 'edgeDistance_nm') % Will first update normCenterDistance_nm
                    if isempty(obj.allChipletStatistics)
                        load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allChipletStatistics.mat'), 'allChipletStatistics')
                        obj.allChipletStatistics = allChipletStatistics;
                    end

                    for k = 1:length(emitters)
                        if ~isempty(emitters(k).centerDistance) && ~isnan(emitters(k).centerDistance)
                            centerDistance_nm = emitters(k).centerDistance*obj.pixel2nm;
                            tempChiplet = emitters(k).nthChiplet;
                            lowerEdge_pixel = obj.allChipletStatistics(tempChiplet).tipMin;
                            upperEdge_pixel = obj.allChipletStatistics(tempChiplet).tipMax;
                            wgWidth = obj.allChipletStatistics(tempChiplet).waveguideWidth_nm;
                            emitters(k).normCenterDistance_nm = (centerDistance_nm-lowerEdge_pixel)/(upperEdge_pixel-lowerEdge_pixel)*wgWidth - wgWidth/2;
                            emitters(k).normPosErr_nm = emitters(k).posErr*obj.pixel2nm/(upperEdge_pixel-lowerEdge_pixel)*wgWidth;
                            emitters(k).edgeDistance_nm = wgWidth/2-abs(emitters(k).normCenterDistance_nm);
                            emitters(k).edgeDistanceMin_nm = emitters(k).edgeDistance_nm - emitters(k).normPosErr_nm;
                            emitters(k).edgeDistanceMax_nm = min(wgWidth/2, emitters(k).edgeDistance_nm + emitters(k).normPosErr_nm);

                        end
                    end
                end
            end
        end

        function plotSingleScatter(obj, emitters, ax)
            cmap = lines(2);
            % fittedX = extractfield(emitters, 'fittedX');
            % fittedY = extractfield(emitters, 'fittedY');
            % xSize = 512;
            % ySize = 512;
            % fittedX = xSize + 1 - fittedX;
            % fittedY = ySize + 1 - fittedY;
            % absPosX = extractfield(emitters, 'absPosX');
            % absPosY = extractfield(emitters, 'absPosY');
            % absPosX = xSize + 1 - absPosX;
            % absPosY = ySize + 1 - absPosY;
            region = extractfield(emitters, 'region');
            fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');
            fittedPeakAmplitude = extractfield(emitters, 'fittedPeakAmplitude');
            % posErr_nm = extractfield(emitters, 'posErr')*obj.pixel2nm;
            normPosErr_nm = extractfield(emitters, 'normPosErr_nm');
            % centerDistance = extractfield(emitters, 'centerDistance');
            % centerDistance_nm = centerDistance * obj.pixel2nm;
            edgeDistance_nm = extractfield(emitters, 'edgeDistance_nm');
            edgeDistanceMin_nm = extractfield(emitters, 'edgeDistanceMin_nm');
            edgeDistanceMax_nm = extractfield(emitters, 'edgeDistanceMax_nm');

            scatterSize = 10;
            
            tipValid = strcmp(region, 'tip');
            % tipFittedX = fittedX(tipValid);
            % tipFittedY = fittedY(tipValid);
            % tipPosErr_nm = sqrt((tipFittedX - absPosX(tipValid)).^2+(tipFittedY - absPosY(tipValid)).^2)*obj.pixel2nm;
            tipPosErr_nm = normPosErr_nm(tipValid);
            tipEdgeDistance_nm = edgeDistance_nm(tipValid);
            tipEdgeDistanceMin_nm = edgeDistanceMin_nm(tipValid);
            tipEdgeDistanceMax_nm = edgeDistanceMax_nm(tipValid);
            tipFittedLinewidth_THz = fittedLinewidth_THz(tipValid);
            tipFOM = 30e-6./tipFittedLinewidth_THz;
            
            tipScatterH = scatter(ax, tipEdgeDistance_nm, tipFOM, scatterSize, 'filled', 'Color', cmap(2, :), 'MarkerFaceAlpha', 0.5, 'MarkerEdgeAlpha', 0.5);
            
            for l = 1:sum(tipValid)
                line([tipEdgeDistanceMin_nm(l), tipEdgeDistanceMax_nm(l)], [tipFOM(l), tipFOM(l)], 'Color', [cmap(1, :), 0.2], 'Parent', ax, 'LineWidth', 1);
                % line([tipEdgeDistance_nm(l), tipEdgeDistance_nm(l)], [tipFOM(l)+tipFOM(l), tipFOM(l)-tipFOM(l)], 'Color', cmap(2, :), 'Parent', ax, 'LineWidth', 1);
            end
            
            % centerValid = strcmp(region, 'center'); 
            % centerFittedX = fittedX(centerValid);
            % centerFittedY = fittedY(centerValid);
            % centerPosErr_nm = sqrt((centerFittedX - absPosX(centerValid)).^2+(centerFittedY - absPosY(centerValid)).^2)*obj.pixel2nm;
            % centerPosErr_nm = normPosErr_nm(centerValid);
            % centerEdgeDistance_nm = edgeDistance_nm(centerValid);
            % centerFittedLinewidth_THz = fittedLinewidth_THz(centerValid);
            % centerFOM = 30e-6./centerFittedLinewidth_THz;

            % hold(ax, 'on');
            % centerScatterH = scatter(ax, centerEdgeDistance_nm, centerFOM, scatterSize, 'filled', 'Color', cmap(1, :), 'MarkerFaceAlpha', 0.5, 'MarkerEdgeAlpha', 0.5)
            
            % for l = 1:sum(centerValid)
            %     line([centerEdgeDistance_nm(l)-centerPosErr_nm(l), centerEdgeDistance_nm(l)+centerPosErr_nm(l)], [centerFOM(l), centerFOM(l)], 'Color', [cmap(2, :), 0.2], 'Parent', ax, 'LineWidth', 1);
            %     % line([centerEdgeDistance_nm(l), centerEdgeDistance_nm(l)], [centerFOM(l)+centerFOM(l), centerFOM(l)-centerFOM(l)], 'Color', cmap(1, :), 'Parent', ax, 'LineWidth', 1);
            % end

            ax.LineWidth = 2;
            ax.FontSize = 13;
            box(ax, 'on');
            % ax.XLabel.String = "Distance to center (nm)";
            ax.XLabel.String = "Distance to edge (nm)";

            ax.YLabel.String = "FOM";
            ax.XLim = [0, 140];
            % legendH = legend(ax, [tipScatterH, centerScatterH], {'tip', 'center'});
            % legendH.Location = 'northwest';
            pause(0.1);
        end
        function plotScatters(obj, emitters, plotSingleChiplets, chiplets)
            nthChiplet = extractfield(emitters, 'nthChiplet');
            valid = obj.getEmitterValidity(emitters);
            if ~exist('chiplets', 'var')
                % plot all chiplets
                chiplets = unique(nthChiplet);
            end
            
            
            [allFolders, allFileNames] = obj.getAllDataFiles;
            inTarget = zeros(1, length(valid));
            for l = 1:length(chiplets)
                inTarget = inTarget | (nthChiplet == chiplets(l));
            end
            fig = figure;
            ax = axes(fig);
            obj.plotSingleScatter(emitters(inTarget&valid), ax);

            if exist('plotSingleChiplets', 'var') && plotSingleChiplets
                emitterGroups = obj.divideEmitters(emitters, chiplets);
                for k = 1:length(emitterGroups)
                    
                    lwFig = figure;
                    lwAx = axes(lwFig);
                    obj.plotSingleScatter(emitterGroups{k}, lwAx);

                end
            end
        end
        function updateAllChipletStatistics(obj, emitters)
            nthChiplet = extractfield(emitters, 'nthChiplet');
            if ~exist('chiplets', 'var')
                % plot all chiplets
                chiplets = unique(nthChiplet);
            end
            region = extractfield(emitters, 'region');
            valid = obj.getEmitterValidity(emitters);
            centerDistance = extractfield(emitters, 'centerDistance');
            posErr = extractfield(emitters, 'posErr');
            allChipletStatistics = [];
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'wlImgInfo.mat'), 'allSlant', 'allSize');
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allWaveguideWidth_nm.mat'), 'allWaveguideWidth_nm');
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allChipletValid.mat'), 'allChipletValid');

            for k = 1:length(chiplets)
                tipValid = valid & (nthChiplet == chiplets(k)) & strcmp(region, 'tip');
                tipCenterDistance_nm = centerDistance(tipValid) * obj.pixel2nm;
                tipPosErr_nm = posErr(tipValid)*obj.pixel2nm;
                tipAvg = mean(tipCenterDistance_nm);
                tipStd = std(tipCenterDistance_nm);
                tipMax = max(tipCenterDistance_nm+tipPosErr_nm);
                tipMin = min(tipCenterDistance_nm-tipPosErr_nm);
                centerValid = valid & (nthChiplet == chiplets(k)) & strcmp(region, 'center');
                centerCenterDistance_nm = centerDistance(centerValid) * obj.pixel2nm;
                centerPosErr_nm = posErr(centerValid)*obj.pixel2nm;
                centerAvg = mean(centerCenterDistance_nm);
                centerStd = std(centerCenterDistance_nm);
                centerMax = max(centerCenterDistance_nm+centerPosErr_nm);
                centerMin = min(centerCenterDistance_nm-centerPosErr_nm);
                allAvg = mean([tipCenterDistance_nm, centerCenterDistance_nm]);
                allStd = std([tipCenterDistance_nm, centerCenterDistance_nm]);
                allMax = max([tipMax, centerMax]);
                allMin = min([tipMin, centerMin]);
                chipletSize = allSize(chiplets(k));
                chipletValid = allChipletValid(chiplets(k));
                imSlant = allSlant(chiplets(k));
                waveguideWidth_nm = allWaveguideWidth_nm(chiplets(k));
                tempChipletStatistics = struct('nthChiplet', chiplets(k), 'tipAvg', tipAvg, 'tipStd', tipStd, 'tipMin', tipMin, 'tipMax', tipMax, ...
                'centerAvg', centerAvg, 'centerStd', centerStd, 'centerMin', centerMin, 'centerMax', centerMax, ...
                'allAvg', allAvg, 'allStd', allStd, 'allMin', allMin, 'allMax', allMax, ...
                'chipletSize', chipletSize, 'imSlant', imSlant, 'waveguideWidth_nm', waveguideWidth_nm, 'chipletValid', chipletValid);
                tempFields = fields(tempChipletStatistics);
                for k = 1:length(tempFields)
                    field = tempFields{k};
                    if isempty(tempChipletStatistics.(field))
                        tempChipletStatistics.(field) = NaN; % In case the chiplet is invalid
                    end
                end
                if isempty(allChipletStatistics)
                    allChipletStatistics = tempChipletStatistics;
                else
                    allChipletStatistics(end+1) = tempChipletStatistics;
                end
            end
            obj.allChipletStatistics = allChipletStatistics;
            save(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allChipletStatistics.mat'), 'allChipletStatistics');
        end
        function plotDistanceStatistics(obj, emitters, dataset, ax, plotRange)
            if isempty(obj.allChipletStatistics)
                load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allChipletStatistics.mat'), 'allChipletStatistics');
                obj.allChipletStatistics = allChipletStatistics;
            end

            assert(any(strcmp(dataset, ["tip", "center", "all"])), "Argument `dataset` should be on of the 'tip', 'center', 'all'");
            avg = extractfield(obj.allChipletStatistics, sprintf('%sAvg', dataset));
            std = extractfield(obj.allChipletStatistics, sprintf('%sStd', dataset));
            min = extractfield(obj.allChipletStatistics, sprintf('%sMin', dataset));
            max = extractfield(obj.allChipletStatistics, sprintf('%sMax', dataset));
            chipletSize = extractfield(obj.allChipletStatistics, 'chipletSize');
            imSlant = extractfield(obj.allChipletStatistics, 'imSlant');
            nthChiplet = extractfield(obj.allChipletStatistics, 'nthChiplet');
            waveguideWidth_nm = extractfield(obj.allChipletStatistics, 'waveguideWidth_nm');
            cmap = lines(3); % Use different color to represent different sizes (chipletSize = 1, 2, 3)
            markers = {'o', '^', '*'}; % Use different marker to represent different slants (chipletSize = 4, 5, 6)
            if ~exist('ax') || isempty(ax) || ~isvalid(ax)
                fig = figure;
                ax = axes(fig);
            end
            hold(ax, 'on');
            if exist('plotRange', 'var') && plotRange
                rangeFig = figure;
                rangeAx = axes(rangeFig);
                % scatter(rangeAx, waveguideWidth_nm, max-min, 'filled');
                scatter(rangeAx, nthChiplet, max-min, 'filled');

                rangeAx.LineWidth = 2;
                rangeAx.FontSize = 13;
                box(rangeAx, 'on');
                % rangeAx.XLabel.String = "Gds waveguide width (nm)";
                % rangeAx.XLim = [250, 290];
                rangeAx.XLabel.String = "Chiplet number";
                rangeAx.YLabel.String = "Distance range (nm)";
            end
            for k = 1:length(obj.allChipletStatistics)
                scatter(ax, nthChiplet(k), avg(k), markers{imSlant(k)-3}, 'filled', 'MarkerFaceColor', cmap(chipletSize(k), :), 'MarkerEdgeColor', cmap(chipletSize(k), :));
                line([nthChiplet(k), nthChiplet(k)], [avg(k)+std(k), avg(k)-std(k)], 'Color', cmap(chipletSize(k), :), 'Parent', ax, 'LineWidth', 2);
                line([nthChiplet(k), nthChiplet(k)], [min(k), max(k)], 'LineStyle', '--', 'Color', cmap(chipletSize(k), :), 'Parent', ax, 'LineWidth', 0.5);

            end
            ax.LineWidth = 2;
            ax.FontSize = 13;
            box(ax, 'on');
            ax.XLabel.String = "Chiplet number";
            ax.YLabel.String = "Distance to Center (nm)";

        end
        function plotEverything(obj, emitters, plotSingleChiplets, chiplets)
            nthChiplet = extractfield(emitters, 'nthChiplet');
            valid = obj.getEmitterValidity(emitters);
            if ~exist('chiplets', 'var')
                % plot all chiplets
                chiplets = unique(nthChiplet);
            end
            inTarget = zeros(1, length(valid));
            for l = 1:length(chiplets)
                inTarget = inTarget | (nthChiplet == chiplets(l));
            end
            scatterFig = figure;
            scatterFig.Position = [100, 300, 600, 500];
            scatterAx = axes(scatterFig);
            obj.plotSingleScatter(emitters(inTarget&valid), scatterAx);
        
            chipletsFig = figure;
            chipletsFig.Position = [800, 300, 600, 500];
            chipletsAx = axes(chipletsFig);
            obj.plotDistanceStatistics(emitters(inTarget&valid), 'tip', chipletsAx);

            pause(0.3);

            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allCornerPositions.mat'), 'allCornerPositions');
            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'allWaveguidePositions.mat'), 'allWaveguidePositions');
            obj.allCornerPositions = allCornerPositions;
            obj.allWaveguidePositions = allWaveguidePositions;

            if exist('plotSingleChiplets') && plotSingleChiplets
                [allFolders, allFileNames] = obj.getAllDataFiles;
                
                emitterGroups = obj.divideEmitters(emitters, chiplets);
                for k = 1:length(chiplets)
                    nthChiplet = chiplets(k);
                    fig = figure;
                    fig.Position = [100, 300, 1600, 700];
                    pause(0.1);
                    if isempty(emitterGroups{k})
                        continue
                    end

                    s1 = axes(fig);
                    s1 = subplot(1, 2, 1, s1);
                    obj.plotSingleScatter(emitterGroups{k}, s1);
                    s2 = axes(fig);
                    s2 = subplot(1, 2, 2, s2);
                    srcDir = fullfile(obj.dataRootDir, 'CleanedData', allFolders{nthChiplet});
                    dstDir = fullfile(obj.dataRootDir, 'ProcessedData', allFolders{nthChiplet});
                    [tokens,matches] = regexp(allFileNames{nthChiplet},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                    idx = str2num(tokens{1}{1});
                    fprintf("Processing file '%s' (%d/%d), idx: %d.\n", allFileNames{nthChiplet}, k, length(chiplets), idx);
                    load(fullfile(srcDir, allFileNames{nthChiplet}), 'wl_img');
                    obj.plotSingleWL(emitterGroups{k}, wl_img, s2);
                end
            end
        end
        function emitters = processAllExperiments(obj)
            if isempty(obj.dataRootDir)
                error("obj.dataRootDir is empty. Please assign the data directory.");
            end
            assert(isfolder(fullfile(obj.dataRootDir, 'CleanedData')), '`obj.dataRootDir` should contain folder `CleanedData`');
            dirs = dir(fullfile(obj.dataRootDir, 'CleanedData'));
            if ~isfolder(fullfile(obj.dataRootDir, 'ProcessedData'))
                mkdir(fullfile(obj.dataRootDir, 'ProcessedData'));
            end
            sumDir = fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData');
            if ~isfolder(sumDir)
                mkdir(sumDir);
            end
            folders = dir(fullfile(obj.dataRootDir, 'CleanedData'));
            [allFolders, allFileNames] = obj.getAllDataFiles;
            nValid = length(allFileNames);
            allEmitters = cell(nValid, 1);

            load(fullfile(obj.dataRootDir, 'CleanedData', 'SupplementaryFiles', 'gdsFramePos.mat'));
            for k = 1:nValid
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', allFolders{k});
                dstDir = fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k});
                % Parallel can be used if more data is required (though more memory might be required)
                [tokens,matches] = regexp(allFileNames{k},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                idx = str2num(tokens{1}{1});
                fprintf("Loading file '%s' (%d/%d), idx: %d.\n", allFileNames{k}, k, nValid, idx);
                if strcmp(fullfile(srcDir, allFileNames{k}), obj.prevChipletDataPath) && ~isempty(obj.prevChipletData)
                    chipletData = obj.prevChipletData;
                else
                    chipletData = Drivers.FullChipDataAnalyzer.loadChipletData(fullfile(srcDir, allFileNames{k}));
                end
                fprintf("Start processing file '%s' (%d/%d), idx: %d.\n", allFileNames{k}, k, nValid, idx);
                chipletData.nthChiplet = k;
                obj.prevChipletData = chipletData;
                obj.prevChipletDataPath = fullfile(srcDir, allFileNames{k});
                emitters = obj.processChiplet(chipletData, false);
                allEmitters{k} = emitters;
                save(fullfile(dstDir, sprintf("chiplet%d_emitters.mat", idx)), "emitters");
            end
            emitters = horzcat(allEmitters{:});
            save(fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData', "all_emitters_data.mat"), "emitters");
            emitters = obj.parallelFitPeaks(emitters);
            save(fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData', "all_emitters_data_fitted.mat"), "emitters");

            % emitters = horzcat(allExperimentEmitters{:});
            % save(fullfile(sumDir, "all_emitters_data.mat"), emitters);
        end
    end

end


function validSites = spacialFilter(polyPos, x, y)
    validSites = zeros(1, length(x));
    line1 = polyPos(1:2, :);
    line2 = polyPos(2:3, :);
    line3 = polyPos(3:4, :);
    line4 = polyPos([4, 1], :);
    minlen1 = min(norm(line1(1, :)-line1(2, :)), norm(line3(1, :)-line3(2, :)));
    minlen2 = min(norm(line2(1, :)-line2(2, :)), norm(line4(1, :)-line4(2, :)));

    for idx = 1:length(x)
        space_ratio = 0.05; % To ignore sites that is too close to the boundary
        % space_thres = 
        exist_space_line1 = getPointLineDistance(x(idx), y(idx), line1(1, 1), line1(1, 2), line1(2, 1), line1(2, 2)) > minlen2*space_ratio;
        exist_space_line2 = getPointLineDistance(x(idx), y(idx), line2(1, 1), line2(1, 2), line2(2, 1), line2(2, 2)) > minlen1*space_ratio;
        exist_space_line3 = getPointLineDistance(x(idx), y(idx), line3(1, 1), line3(1, 2), line3(2, 1), line3(2, 2)) > minlen2*space_ratio;
        exist_space_line4 = getPointLineDistance(x(idx), y(idx), line4(1, 1), line4(1, 2), line4(2, 1), line4(2, 2)) > minlen1*space_ratio;
        exist_space_all = exist_space_line1 && exist_space_line2 && exist_space_line3 && exist_space_line4;

        if inpolygon(x(idx), y(idx), polyPos(:, 1), polyPos(:, 2)) && exist_space_all
            validSites(idx) = 1;
        else
            validSites(idx) = 0;
        end
    end
end


function distance = getPointLineDistance(x3,y3,x1,y1,x2,y2,infinityLength,specifySide)
    % Get the distance from a point (x3, y3) to
    % a line segment defined by two points (x1, y1) and (x2, y2);
    % If the one of the two agnles are obtuse, which means the permendicular line is out of the line segment, 
    % will use the shortest distance to the end point instead.
    try
        
        % Find the numerator for our point-to-line distance formula.
        if exist('specifySide', 'var') && specifySide
            numerator = (x2 - x1) * (y1 - y3) - (x1 - x3) * (y2 - y1);
        else
            numerator = abs((x2 - x1) * (y1 - y3) - (x1 - x3) * (y2 - y1));
        end
        
        % Find the denominator for our point-to-line distance formula.
        denominator = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2);
        
        % Compute the distance.
        distance = numerator ./ denominator;
    catch ME
        errorMessage = sprintf('Error in program %s.\nError Message:\n%s',...
            mfilename, ME.message);
        uiwait(errordlg(errorMessage));
    end
    if ~exist('infinityLength', 'var') || ~infinityLength
        dist1 = norm([x3, y3]-[x1, y1]);
        dist2 = norm([x3, y3]-[x2, y2]);
        dist3 = norm([x2, y2]-[x1, y1]);
        if dist2^2 > dist1^2+dist3^2 || dist1^2 > dist2^2+dist3^2
            distance = min(dist1, dist2);
        end
    end
    
    return; % from getPointLineDistance()
end