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
        framePos_xy;
        wgLines = {};
        prevChipletData;
        prevChipletDataPath;
    end
    properties(Constant)
        processMincount = 12000;
        sumMincount = 12000;
        frameWidth = 5;
        waveguideWidth = 2;
        padding = 2;
        freqPadding = 50;
        nWaveguides = 6;
        backgroundNoise = 1400; % Derived from the medium of all EMCCD pixels.
        regionMap = {'center', 'frame', 'tip', 'bulk', 'out'};
        namespace = "Drivers_FullChipDataAnalyzer";
        extendRatio = 2/3;
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
            
            [tokens,matches] = regexp(fileName,'[cC]hiplet_?(\d+)(.*)','tokens','match'); 
            chipletData = load(path);
            if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                chipletData.chipletIdx = str2num(tokens{1}{2});
                [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                chipletID = str2num(subTokens{1}{3});
                chipletData.chipletID = chipletID; 
            else
                chipletData.chipletIdx = NaN;
                chipletData.chipletID = NaN;
                fprintf("chipletID and chipletIdx is not assigned. Please consider to format the data file similar with `chiplet1_x0_y0_ID16`.\n");
            end 
        end 
        function emitters = processChiplet(chipletData, drawFig, cornerPosition_xy)
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
          
            if exist('drawFig', 'var') && drawFig
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
                    'peakFreq_THz', peakFreq_THz, 'peakIntensity', peakIntensity, 'peakWidth_THz', peakWidth_THz, 'fittedX', fittedX(k), 'fittedY', fittedY(k));
                end
                emitters(l).spectrums = spectrums;
                emitters(l).maxSumIntensity = max(peakIntensity);
                emitters(l).valid = any(spectrumValid);
                emitters(l).fittedX = mean(fittedX);
                emitters(l).fittedY = mean(fittedY);
                [region, centerDistance] = Drivers.FullChipDataAnalyzer.getRegion(emitters(l).fittedX, emitters(l).fittedY, cornerPosition_xy);
                emitters(l).region = region;
                emitters(l).centerDistance = centerDistance;
            end
            % valid = extractfield(emitters, 'valid');
            % emitters(~valid) = [];
        end
        function [region, centerDistance] = getRegion(absPosX, absPosY, cornerPosition_xy, drawFig, wl_img)
            if ~exist('wl_img', 'var')
                xsize = 512;
                ysize = 512;
            else
                xsize = size(wl_img, 2);
                ysize = size(wl_img, 1);
            end

            cornerPosition_xy = [xsize, ysize]+1 - cornerPosition_xy;
            cornerPosition_xy = cornerPosition_xy([3, 4, 1, 2], :);
            cornerAbsPos_yx = cornerPosition_xy(:, [2, 1]);
            line1 = cornerAbsPos_yx(1:2, :);
            line2 = cornerAbsPos_yx(2:3, :);
            line3 = cornerAbsPos_yx(3:4, :);
            line4 = cornerAbsPos_yx([4, 1], :);
            frameWidth = Drivers.FullChipDataAnalyzer.frameWidth;
            onFrame1 = getPointLineDistance(absPosX, absPosY, line1(1, 2), line1(1, 1), line1(2, 2), line1(2, 1)) < frameWidth;
            onFrame2 = getPointLineDistance(absPosX, absPosY, line2(1, 2), line2(1, 1), line2(2, 2), line2(2, 1)) < frameWidth;
            onFrame3 = getPointLineDistance(absPosX, absPosY, line3(1, 2), line3(1, 1), line3(2, 2), line3(2, 1)) < frameWidth;
            onFrame4 = getPointLineDistance(absPosX, absPosY, line4(1, 2), line4(1, 1), line4(2, 2), line4(2, 1)) < frameWidth;
            onFrame= onFrame1 || onFrame2 || onFrame3 || onFrame4;
            leftTipPolygon_yx = [cornerAbsPos_yx(1:2, :); cornerAbsPos_yx([2, 1], :)-[0, 75]] + [frameWidth, 0; -frameWidth, 0; -frameWidth, 0; frameWidth, 0];
            rightTipPolygon_yx = [cornerAbsPos_yx([4, 3], :); cornerAbsPos_yx([3, 4], :)+[0, 75]] + [frameWidth, 0; -frameWidth, 0; -frameWidth, 0; frameWidth, 0];
            centerDistance = NaN;
            
            waveguideLines = NaN(6, 2, 2); % 6 waveguides; 2 points; yx axis
            waveguideDists = NaN(6, 1);
            for k = 1:6
                waveguideLines(k, 1, :) = cornerAbsPos_yx(1, :)*k/7+cornerAbsPos_yx(2, :)*(7-k)/7;
                waveguideLines(k, 2, :) = cornerAbsPos_yx(4, :)*k/7+cornerAbsPos_yx(3, :)*(7-k)/7;
                waveguideDists(k) = getPointLineDistance(absPosX, absPosY, waveguideLines(k, 1, 2), waveguideLines(k, 1, 1), waveguideLines(k, 2, 2), waveguideLines(k, 2, 1), true, true); % Infinity length should be set to true.
            end
            if inpolygon(absPosY, absPosX, cornerAbsPos_yx(:, 1), cornerAbsPos_yx(:, 2)) && ~onFrame
                region = 'center';
                [minval, closestLine] = min(abs(waveguideDists));
                centerDistance = waveguideDists(closestLine);
            elseif onFrame
                region = 'frame';
            elseif inpolygon(absPosY, absPosX, leftTipPolygon_yx(:, 1), leftTipPolygon_yx(:, 2)) || inpolygon(absPosY, absPosX, rightTipPolygon_yx(:, 1), rightTipPolygon_yx(:, 2))
                region = 'tip';
                [minval, closestLine] = min(abs(waveguideDists));
                centerDistance = waveguideDists(closestLine);
            else
                region = 'bulk';
            end
            if exist('drawFig', 'var') && drawFig
                fig = figure;
                ax = axes(fig);
                imagesc(ax, wl_img);
                colormap('gray');
                hold(ax, 'on');
                plot(ax, cornerAbsPos_yx([1, 2, 3, 4, 1], 2), cornerAbsPos_yx([1, 2, 3, 4, 1], 1));
                Drivers.FullChipDataAnalyzer.plotRotLines(ax, cornerPosition_xy);
                scatter(ax, absPosX, absPosY, 'filled');
                fprintf("Distance: %f\n", centerDistance);
            end
        end

        obj = instance();
        function valid = getEmitterValidity(emitters, drawFig)
            valid = cell2mat(extractfield(emitters, 'valid'));
            absPosX = extractfield(emitters, 'absPosX');
            absPosY = extractfield(emitters, 'absPosY');
            fittedX = extractfield(emitters, 'fittedX');
            fittedY = extractfield(emitters, 'fittedY');
            centerDistance = extractfield(emitters, 'centerDistance');
            fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');

            valid = valid&((fittedX-absPosX).^2+(fittedY-absPosY).^2<0.5);
            valid = valid&(abs(fittedX-absPosX)<0.5)&(abs(fittedY-absPosY)<0.5);
            valid = valid&(abs(centerDistance)<5);
            valid = valid&(fittedLinewidth_THz>30e-6);
            if exist('drawFig', 'var') && drawFig
                fig = figure;
                ax = axes(fig);
                scatter(ax, fittedX-absPosX, fittedY-absPosY, 5, 'filled');
            end
        end
        

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
        function plotRotLines(rotAx, rotCorners_xy)
            extWgLines = cell(1, 6);
            hold(rotAx, 'on');
            for k = 1:6
                startPos = (rotCorners_xy(1, :)*k+rotCorners_xy(2, :)*(7-k))/7;
                endPos = (rotCorners_xy(4, :)*k+rotCorners_xy(3, :)*(7-k))/7;
                extendedStartPos = startPos + (startPos-endPos)*Drivers.FullChipDataAnalyzer.extendRatio;
                extendedEndPos = endPos + (endPos-startPos)*Drivers.FullChipDataAnalyzer.extendRatio;
                extWgLines{k} = plot(rotAx, [extendedStartPos(1), extendedEndPos(1)], [extendedStartPos(2), extendedEndPos(2)], 'Color', 'r');
            end
        end
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

        function framePos_xy = getGdsFrame(obj, gdsImg)
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
            framePos_xy = obj.gdsRectH.Position;
            obj.framePos_xy = framePos_xy;
            save(fullfile(obj.dataRootDir, "CleanedData", "framePos_xy.mat"), 'framePos_xy');
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
        function rotCorners_xy = getRotatedGdsCorners(obj, gdsImg, framePos_xy, theta_deg, drawFig)
            % Calculate rotatedCorners for chiplet gds

            % fprintf("Original size: %d, %d\n", size(gdsImg, 2), size(gdsImg, 1));
            % fprintf("Rotated size: %d, %d\n", size(rotImg, 2), size(rotImg, 1));
            center_xy = [size(gdsImg, 2), size(gdsImg, 1)]/2;
            frameCorners_xy = [framePos_xy(1), framePos_xy(2); framePos_xy(1), framePos_xy(2)+framePos_xy(4); framePos_xy(1)+framePos_xy(3), framePos_xy(2)+framePos_xy(4); framePos_xy(1)+framePos_xy(3), framePos_xy(2)];
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
            gdsImg = rgb2gray(imread(fullfile(obj.dataRootDir, "CleanedData", "chiplet_only.png")));
            gdsImg = (gdsImg>0);
            obj.gdsImg = gdsImg;
            if ~exist('wlImg', 'var') || isempty(wlImg)
                wlImg = load(fullfile(obj.dataRootDir, "CleanedData", "wl_sample.mat"));
            end

            if isfield(wlImg, 'wlImg')
                wlImg = wlImg.wlImg;
            end
            wlImg = rot90(wlImg, 2);
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
            

            save(fullfile(obj.dataRootDir, "CleanedData", "reshapedImgs.mat"), 'reshapedGdsImg', 'reshapedWlImg');
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
            save(fullfile(obj.dataRootDir, 'CleanedData', 'wlImgInfo.mat'), 'allSize', 'allSlant');
        end

        function initAllTemplates(obj, startNum)
            if ~exist('startNum', 'var')
                startNum = 1;
            end
            load(fullfile(obj.dataRootDir, 'CleanedData', 'wlImgInfo.mat'), 'allSize', 'allSlant'); % variables: allSize (64*1), allSlant(64*1)
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
        function rotCorners_xy = gdsAutoMatch(obj, wl_img, drawFig)
            wl_img = rot90(wl_img, 2);
            wl_img = imresize(wl_img, size(wl_img)*2);
            ip = Drivers.ImageProcessor.instance();
            [di, segments] = ip.processImage(wl_img);
            angle = ip.getAngle(segments(1), true);
            
            % resolution_deg = 0.02;
            % angles = [-30:resolution_deg:30];
            % nAngles = length(angles);
            % vars = zeros(1, nAngles);
            % lineImg = ones(size(wl_img, 2), obj.waveguideWidth);
            % for k = 1:nAngles
            %     deg = angles(k);
            %     rotWlImg = imrotate(wl_img, -deg, 'crop');
            %     vars(k) = var(conv2(rotWlImg, lineImg, 'valid'), 0, 'all');
            % end
            
            % [maxVar, idx] = max(vars);
            % maxAngle = angles(idx);
            % if exist('drawFig', 'var') && drawFig
            %     fig = figure;
            %     s1 = subplot(1, 3, 1);
            %     plot(s1, angles, vars);
            %     s2 = subplot(1, 3, 2);
            %     imshow(imrotate(wl_img, -maxAngle, 'bicubic', 'crop'));
            %     s3 = subplot(1, 3, 3);
            %     rotWlImg = imrotate(wl_img, -maxAngle, 'crop');
            %     convResults = conv2(rotWlImg, lineImg, 'valid');
            %     plot(s3, convResults)
            % end
            fig = figure;
            imshow(imrotate(wl_img, -angle, 'bicubic', 'crop'));
            
            
        end
        function rotCorners_xy = gdsMatch(obj, wl_img, gdsPosition, drawFig, fusedAx)
            wl_img = rot90(wl_img, 2);
            reshapedWlImg = imresize(wl_img, size(wl_img)./[gdsPosition.verticalRatio, gdsPosition.horizontalRatio]);
            if isempty(obj.gdsImg)
                gdsImg = rgb2gray(imread(fullfile(obj.dataRootDir, "CleanedData", "chiplet_only.png")));
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
            if isempty(obj.framePos_xy)
                try
                    load(fullfile(obj.dataRootDir, "CleanedData", "framePos_xy.mat"), 'framePos_xy');
                    obj.framePos_xy = framePos_xy;
                catch
                    obj.framePos_xy = obj.getGdsFrame(obj.gdsImg);
                end
            end
            rotCorners_xy = obj.getRotatedGdsCorners(obj.gdsImg, obj.framePos_xy, gdsPosition.rotationAngle/pi*180);
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
        function allFrameCorners_xy = plotChipletEmitters(obj, plotEmitters, emitters, startNum)
            [allFolders, allFileNames] = obj.getAllDataFiles;
            load(fullfile(obj.dataRootDir, 'CleanedData', 'wlImgInfo.mat'), 'allSize', 'allSlant'); % variables: allSize (64*1), allSlant(64*1)
            if ~exist('startNum', 'var')
                startNum = 1;
            end
            nChiplets = length(allFolders);
            allFrameCorners_xy = NaN(nChiplets, 4, 2);
            if exist('plotEmitters', 'var')
                if ~exist('emitters', 'var') || isempty(emitters)
                    load(fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData', 'all_emitters_data.mat'), 'emitters')
                end
                nthChiplet = extractfield(emitters, 'nthChiplet');
                fittedX = extractfield(emitters, 'fittedX');
                fittedY = extractfield(emitters, 'fittedY');
                xSize = 512;
                ySize = 512;
                fittedX = xSize + 1 - fittedX;
                fittedY = ySize + 1 - fittedY;
                absPosX = extractfield(emitters, 'absPosX');
                absPosY = extractfield(emitters, 'absPosY');
                absPosX = xSize + 1 - absPosX;
                absPosY = ySize + 1 - absPosY;
                centerDistance = extractfield(emitters, 'centerDistance');
                region = extractfield(emitters, 'region');
                valid = obj.getEmitterValidity(emitters);
                fittedPeakAmplitude = extractfield(emitters, 'fittedPeakAmplitude');
                fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');
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
                if exist('plotEmitters', 'var')
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
                allFrameCorners_xy(k, :, :) = obj.gdsMatch(wl_img, gdsPosition, true, fusedAx);
                fusedAx.Position = [0.17, 0.1, 0.7, 0.8];
                if exist('plotEmitters', 'var')
                    tipValid = valid & (nthChiplet == k) & strcmp(region, 'tip');
                    centerValid = valid & (nthChiplet == k) & strcmp(region, 'center'); 
                    hold(fusedAx, 'on');
                    linewidthRef = 1e-4;
                    tipFittedX = fittedX(tipValid);
                    tipFittedY = fittedY(tipValid);
                    tipPosErr = sqrt((tipFittedX - absPosX(tipValid)).^2+(tipFittedY - absPosY(tipValid)).^2);
                    tipColors = max(0, min((1-abs(centerDistance(tipValid))')/1, 1)*cmap(2, :));
                    scatter(fusedAx, tipFittedX, tipFittedY, fittedPeakAmplitude(tipValid)/50000, tipColors, 'filled');
                    tipFittedLinewidth_THz = fittedLinewidth_THz(tipValid);
                    for l = 1:sum(tipValid)
                        line([tipFittedX(l)-tipPosErr(l), tipFittedX(l)+tipPosErr(l)], [tipFittedY(l), tipFittedY(l)], 'Color', tipColors(l, :), 'Parent', fusedAx, 'LineWidth', 1);
                        line([tipFittedX(l), tipFittedX(l)], [tipFittedY(l)+tipFittedLinewidth_THz(l)/linewidthRef, tipFittedY(l)-tipFittedLinewidth_THz(l)/linewidthRef], 'Color', tipColors(l, :), 'Parent', fusedAx, 'LineWidth', 1);
                    end



                    centerFittedX = fittedX(centerValid);
                    centerFittedY = fittedY(centerValid);
                    centerPosErr = sqrt((centerFittedX - absPosX(centerValid)).^2+(centerFittedY - absPosY(centerValid)).^2);
                    centerColors = max(0, min((1-abs(centerDistance(centerValid))')/1, 1)*cmap(1, :));
                    scatter(fusedAx, centerFittedX, centerFittedY, fittedPeakAmplitude(centerValid)/50000, centerColors, 'filled');
                    centerFittedLinewidth_THz = fittedLinewidth_THz(centerValid);
                    for l = 1:sum(centerValid)
                        line([centerFittedX(l)-centerPosErr(l), centerFittedX(l)+centerPosErr(l)], [centerFittedY(l), centerFittedY(l)], 'Color', centerColors(l, :), 'Parent', fusedAx, 'LineWidth', 1);
                        line([centerFittedX(l), centerFittedX(l)], [centerFittedY(l)+centerFittedLinewidth_THz(l)/linewidthRef, centerFittedY(l)-centerFittedLinewidth_THz(l)/linewidthRef], 'Color', centerColors(l, :), 'Parent', fusedAx, 'LineWidth', 1);
                    end


                    pause(0.1);
                end
                fig.Position = [500, 200, 1000, 800];
                saveas(fig, fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k}, sprintf("chiplet%d_size%d_slant%d.png", idx, chipletSize, imSlant)));
            end

            save(fullfile(obj.dataRootDir, 'CleanedData', 'gdsFramePos.mat'), 'allFrameCorners_xy')
        end
        function fig = plotScatter(obj, emitters, plotAll, chiplets)
            nthChiplet = extractfield(emitters, 'nthChiplet');
            valid = obj.getEmitterValidity(emitters);
            if ~exist('chiplets', 'var')
                % plot all chiplets
                chiplets = unique(nthChiplet);
            end
            
            fittedX = extractfield(emitters, 'fittedX');
            fittedY = extractfield(emitters, 'fittedY');
            xSize = 512;
            ySize = 512;
            % fittedX = xSize + 1 - fittedX;
            % fittedY = ySize + 1 - fittedY;
            absPosX = extractfield(emitters, 'absPosX');
            absPosY = extractfield(emitters, 'absPosY');
            % absPosX = xSize + 1 - absPosX;
            % absPosY = ySize + 1 - absPosY;
            centerDistance = extractfield(emitters, 'centerDistance');
            region = extractfield(emitters, 'region');
            fittedLinewidth_THz = extractfield(emitters, 'fittedLinewidth_THz');
            fittedPeakAmplitude = extractfield(emitters, 'fittedPeakAmplitude');
            % fitted

            [allFolders, allFileNames] = obj.getAllDataFiles;

            nChiplets = length(allFolders);
            cmap = lines(2);
            pixel2nm = 160;
            centerDistance = centerDistance * pixel2nm;

            targetChiplets = {chiplets};
            if exist('plotAll', 'var') && plotAll
                for k = 1:length(chiplets)
                    targetChiplets{end+1} = chiplets(k);
                end
            end
            for k = 1:length(targetChiplets)
                inTarget = zeros(1, length(valid));
                targetChiplet = targetChiplets{k};
                for l = 1:length(targetChiplet)
                    inTarget = inTarget | (nthChiplet == targetChiplet(l));
                end
                tipValid = valid & inTarget & strcmp(region, 'tip');
                % tipValid = valid & strcmp(region, 'tip');
                
                lwFig = figure;
                lwAx = axes(lwFig);
                scatterSize = 10;
                
                tipCenterDistance = centerDistance(tipValid);
                tipFittedX = fittedX(tipValid);
                tipFittedY = fittedY(tipValid);
                tipPosErr = sqrt((tipFittedX - absPosX(tipValid)).^2+(tipFittedY - absPosY(tipValid)).^2)*pixel2nm;
                tipFittedLinewidth_THz = fittedLinewidth_THz(tipValid);
                tipFOM = 30e-6./tipFittedLinewidth_THz;
                
                scatter(lwAx, tipCenterDistance, tipFOM, scatterSize, 'filled', 'Color', cmap(2, :), 'MarkerFaceAlpha', 0.5, 'MarkerEdgeAlpha', 0.5);
                
                for l = 1:sum(tipValid)
                    line([tipCenterDistance(l)-tipPosErr(l), tipCenterDistance(l)+tipPosErr(l)], [tipFOM(l), tipFOM(l)], 'Color', [cmap(1, :), 0.2], 'Parent', lwAx, 'LineWidth', 1);
                    % line([tipCenterDistance(l), tipCenterDistance(l)], [tipFOM(l)+tipFOM(l), tipFOM(l)-tipFOM(l)], 'Color', cmap(2, :), 'Parent', lwAx, 'LineWidth', 1);
                end
                
                centerValid = valid & inTarget & strcmp(region, 'center'); 
                % centerValid = valid & s   trcmp(region, 'center');
                centerFittedX = fittedX(centerValid);
                centerFittedY = fittedY(centerValid);
                centerPosErr = sqrt((centerFittedX - absPosX(centerValid)).^2+(centerFittedY - absPosY(centerValid)).^2)*pixel2nm;

                centerCenterDistance = centerDistance(centerValid);
                centerFittedLinewidth_THz = fittedLinewidth_THz(centerValid);
                centerFOM = 30e-6./centerFittedLinewidth_THz;
                hold(lwAx, 'on');
                scatter(lwAx, centerCenterDistance, centerFOM, scatterSize, 'filled', 'Color', cmap(1, :), 'MarkerFaceAlpha', 0.5, 'MarkerEdgeAlpha', 0.5)
                
                for l = 1:sum(centerValid)
                    line([centerCenterDistance(l)-centerPosErr(l), centerCenterDistance(l)+centerPosErr(l)], [centerFOM(l), centerFOM(l)], 'Color', [cmap(2, :), 0.2], 'Parent', lwAx, 'LineWidth', 1);
                    % line([centerCenterDistance(l), centerCenterDistance(l)], [centerFOM(l)+centerFOM(l), centerFOM(l)-centerFOM(l)], 'Color', cmap(1, :), 'Parent', lwAx, 'LineWidth', 1);
                end
                lwAx.LineWidth = 2;
                lwAx.FontSize = 13;
                box(lwAx, 'on');
                lwAx.XLabel.String = "Distance (nm)";
                lwAx.YLabel.String = "FOM";
                % legend(lwAx, {'tip', 'center'}ax );
                pause(0.1);
            end
                
            % scatterSize = 10;
            % fig = figure;
            % ax = axes(fig);

            % scatter(ax, distances(strcmp(region, 'center')&valid), sumIntensities(strcmp(region, 'center')&valid), scatterSize, 'filled');
            % hold(ax, 'on');
            % scatter(ax, distances(strcmp(region, 'tip')&valid), sumIntensities(strcmp(region, 'tip')&valid), scatterSize, 'filled');
            % if isfield(emitters(1), 'fittedLinewidth_THz')

            %     hold(lwAx, 'on');
            %     scatter(lwAx, distances(strcmp(region, 'tip')&valid), fittedLinewidth_THz(strcmp(regions, 'tip')&valid), scatterSize, 'filled');
            % end
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

            load(fullfile(obj.dataRootDir, 'CleanedData', 'gdsFramePos.mat'));
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
                emitters = Drivers.FullChipDataAnalyzer.processChiplet(chipletData, false, squeeze(allFrameCorners_xy(k, :, :)));
                allEmitters{k} = emitters;
                save(fullfile(dstDir, sprintf("chiplet%d_emitters.mat", idx)), "emitters");
            end
            emitters = horzcat(allEmitters{:});
            save(fullfile(obj.dataRootDir, 'ProcessedData', "all_emitters_data.mat"), "emitters");
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