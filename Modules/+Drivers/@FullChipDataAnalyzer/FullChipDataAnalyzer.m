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
        reshapedGdsImg;
        reshapedWlImg;
    end
    properties(Constant)
        processMincount = 12000;
        sumMincount = 12000;
        frameWidth = 5;
        padding = 5;
        freqPadding = 50;
        nWaveguides = 6;
        backgroundNoise = 1400; % Derived from the medium of all EMCCD pixels.
        regionMap = {'center', 'frame', 'tip', 'bulk', 'out'};
        namespace = "Drivers_FullChipDataAnalyzer";
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
        function emitters = processChiplet(chipletData, drawFig)
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
                
                % For emitter image block: add padding to neighbor pixels
                xmin = max(min(tempXs)-Drivers.FullChipDataAnalyzer.padding, imageXmin);
                xmax = min(max(tempXs)+Drivers.FullChipDataAnalyzer.padding, imageXmax);
                ymin = max(min(tempYs)-Drivers.FullChipDataAnalyzer.padding, imageYmin);
                ymax = min(max(tempYs)+Drivers.FullChipDataAnalyzer.padding, imageYmax);
                freqIdxMin = max(min(peakIdx(tempIdx))-Drivers.FullChipDataAnalyzer.freqPadding, 1);
                freqIdxMax = min(max(peakIdx(tempIdx))+Drivers.FullChipDataAnalyzer.freqPadding, length(allFreqs));
                
                tempIntensities = peakIntensities(tempIdx);
                tempFreqs = peakFreqs(tempIdx);
                [maxIntensity, maxIdx] = max(tempIntensities);
                
                emitters(l).absPosX = tempXs(maxIdx);
                emitters(l).absPosY = tempYs(maxIdx);
                emitters(l).relPosX = emitters(l).absPosX - chipletData.widefieldData{1}.segment.absCenterX;
                emitters(l).relPosY = emitters(l).absPosY - chipletData.widefieldData{1}.segment.absCenterY;
                emitters(l).maxIntensity = double(maxIntensity);
                [region, centerDistance] = Drivers.FullChipDataAnalyzer.getRegion(emitters(l).absPosX, emitters(l).absPosY, chipletData.widefieldData{1}.segment);
                emitters(l).region = region;
                emitters(l).centerDistance = centerDistance;
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
                    'peakFreq_THz', peakFreq_THz, 'peakIntensity', peakIntensity, 'peakWidth_THz', peakWidth_THz);
                end
                emitters(l).spectrums = spectrums;
                emitters(l).maxSumIntensity = max(peakIntensity);
                emitters(l).valid = any(spectrumValid);
            end
            % valid = extractfield(emitters, 'valid');
            % emitters(~valid) = [];
        end
        function [region, centerDistance] = getRegion(absPosX, absPosY, segment, plotImage)
            cornerAbsPos_yx = segment.cornerPos+[segment.ymin, segment.xmin];
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
                waveguideDists(k) = getPointLineDistance(absPosX, absPosY, waveguideLines(k, 1, 2), waveguideLines(k, 1, 1), waveguideLines(k, 2, 2), waveguideLines(k, 2, 1), true); % Infinity length should be set to true.
            end
            if inpolygon(absPosY, absPosX, cornerAbsPos_yx(:, 1), cornerAbsPos_yx(:, 2)) && ~onFrame
                region = 'center';
                centerDistance = min(waveguideDists);
            elseif onFrame
                region = 'frame';
            elseif inpolygon(absPosY, absPosX, leftTipPolygon_yx(:, 1), leftTipPolygon_yx(:, 2)) || inpolygon(absPosY, absPosX, rightTipPolygon_yx(:, 1), rightTipPolygon_yx(:, 2))
                region = 'tip';
                centerDistance = min(waveguideDists);
            else
                region = 'bulk';
            end
            if exist('plotImage', 'var') && plotImage
                fig = figure;
                ax = axes(fig);
                imagesc(ax, segment.image);
                colormap('gray');
                hold(ax, 'on');
                plot(ax, segment.cornerPos([1, 2, 3, 4, 1], 2), segment.cornerPos([1, 2, 3, 4, 1], 1));
                for k = 1:6
                    plot(ax, waveguideLines(k, :, 2)-segment.xmin, waveguideLines(k, :, 1)-segment.ymin);
                end
                scatter(ax, absPosX-segment.xmin, absPosY-segment.ymin, 'filled');
            end
        end

        obj = instance();
        function plotDistance(emitters)
            regions = extractfield(emitters, 'region');
            distances = extractfield(emitters, 'centerDistance');
            sumIntensities = extractfield(emitters, 'maxSumIntensity');
            fig = figure;
            ax = axes(fig);
            scatter(ax, distances(strcmp(regions, 'center')), sumIntensities(strcmp(regions, 'center')));
            hold(ax, 'on');
            scatter(ax, distances(strcmp(regions, 'tip')), sumIntensities(strcmp(regions, 'tip')));
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

        function matchGds(obj)
            gdsImg = rgb2gray(imread(fullfile(obj.dataRootDir, "CleanedData", "chiplet_only.png")));
            gdsImg = (gdsImg>0);
            obj.gdsImg = gdsImg;
            wlImg = load(fullfile(obj.dataRootDir, "CleanedData", "wl_sample.mat"));
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
            rotationAngle = ((atan(wlLine1_yx(1)/wlLine1_yx(2))+atan(wlLine2_yx(1)/wlLine2_yx(2))+atan(wlLine3_yx(1)/wlLine3_yx(2))+atan(wlLine4_yx(1)/wlLine4_yx(2)))-(atan(gdsLine1_yx(1)/gdsLine1_yx(2))+atan(gdsLine2_yx(1)/gdsLine2_yx(2))+atan(gdsLine3_yx(1)/gdsLine3_yx(2))+atan(gdsLine4_yx(1)/gdsLine4_yx(2))))/4;


            % obj.reshapedGdsImg = imresize(obj.gdsImg, size(obj.gdsImg).*[verticalRatio, horizontalRatio]);
            obj.reshapedWlImg = imresize(obj.wlImg, size(obj.wlImg)./[verticalRatio, horizontalRatio]);
            obj.reshapedGdsImg = imrotate(obj.gdsImg, rotationAngle/pi*180);

            reshapedGdsImg = obj.reshapedGdsImg;
            reshapedWlImg = obj.reshapedWlImg;
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
        function sortWlImgs(obj)

        end
        
        function gdsMatchAll(obj, plotFig)
            
            [allFolders, allFileNames] = obj.getAllDataFiles;
            for k = 1:length(allFolders)
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', allFolders{k});
                dstDir = fullfile(obj.dataRootDir, 'ProcessedData', allFolders{k});

                [tokens,matches] = regexp(allFileNames{k},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                idx = str2num(tokens{1}{1});
                fprintf("Processing file '%s' (%d/%d), idx: %d.\n", allFileNames{k}, k, length(allFolders), idx);
                load(fullfile(srcDir, allFileNames{k}), 'wl_img');
                wl_img = rot90(wl_img, 2);
                reshapedWlImg = imresize(wl_img, size(wl_img)./[obj.gdsPosition.verticalRatio, obj.gdsPosition.horizontalRatio]);
                if isempty(obj.reshapedGdsImg)
                    if isempty(obj.gdsImg)
                        load(fullfile(obj.dataRootDir, 'CleanedData', 'reshapedGdsImg.mat'), 'reshapedGdsImg');
                    else
                        reshapedGdsImg = imrotate(obj.gdsImg, obj.gdsPosition.rotationAngle/pi*180);
                    end
                    obj.reshapedGdsImg = reshapedGdsImg;
                else
                    reshapedGdsImg = obj.reshapedGdsImg;
                end

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
                
                if exist('plotFig', 'var')
                    fusedFig = figure;
                    imshow(imfuse(reshapedWlImg, wlRef, reshapedGdsImg, gdsRef));
                    fusedFig.Position = [250 1 800 700];
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
            allExperimentEmitters = cell(length(folders), 1);
            for k = 1:length(folders)
                folder = folders(k);
                srcDir = fullfile(obj.dataRootDir, 'CleanedData', folder.name);
                dstDir = fullfile(obj.dataRootDir, 'ProcessedData', folder.name);
                if isfolder(srcDir) && ~contains(folder.name, '.')
                    if ~isfolder(dstDir)
                        mkdir(dstDir);
                    end
                    files = dir(srcDir);

                    % Process single experiment (multiple chiplets)
                    nValid = 0;
                    validFileNames = {};
                    for l = 1:length(files)
                        file = files(l);
                        % fprintf('Checking file %s (%d/%d)\n', file.name, l, length(files));
                        [tokens,matches] = regexp(file.name,'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                        if ~isempty(tokens)
                            nValid = nValid + 1;
                            fprintf("Find widefield data file '%s'\n", file.name);
                            validFileNames{end+1} = file.name;
                            if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                                [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                                chipletCoordX = str2num(subTokens{1}{1});
                                chipletCoordY = str2num(subTokens{1}{2});
                                load(fullfile(srcDir, file.name), 'coordX', 'coordY');
                                assert(chipletCoordX == coordX && chipletCoordY == coordY, 'Chiplet coordinate inside data does not match with the file name.');
                            end
                        end
                    end

                    allEmitters = cell(nValid, 1);

                    for l = 1:nValid
                        % Parallel can be used if more data is required (though more memory might be required)
                        [tokens,matches] = regexp(validFileNames{l},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                        idx = str2num(tokens{1}{1});
                        fprintf("Loading file '%s' (%d/%d), idx: %d.\n", validFileNames{l}, l, nValid, idx);
                        chipletData = Drivers.FullChipDataAnalyzer.loadChipletData(fullfile(srcDir, validFileNames{l}));
                        fprintf("Start processing file '%s' (%d/%d), idx: %d.\n", validFileNames{l}, l, nValid, idx);
                        emitters = Drivers.FullChipDataAnalyzer.processChiplet(chipletData, false);
                        allEmitters{l} = emitters;
                        save(fullfile(dstDir, sprintf("chiplet%d_emitters.mat", idx)), "emitters");
                    end
                    emitters = horzcat(allEmitters{:});
                    allExperimentEmitters{k} = emitters;
                    save(fullfile(dstDir, "processed_emitters_data.mat"), "emitters");
                    copyfile(fullfile(dstDir, "processed_emitters_data.mat"), fullfile(sumDir, sprintf("%s.mat", folder.name)));
                end
            end
            emitters = horzcat(allExperimentEmitters{:});
            save(fullfile(sumDir, "all_emitters_data.mat"), emitters);
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


function distance = getPointLineDistance(x3,y3,x1,y1,x2,y2,infinityLength)
    % Get the distance from a point (x3, y3) to
    % a line segment defined by two points (x1, y1) and (x2, y2);
    % If the one of the two agnles are obtuse, which means the permendicular line is out of the line segment, 
    % will use the shortest distance to the end point instead.
    try
        
        % Find the numerator for our point-to-line distance formula.
        numerator = abs((x2 - x1) * (y1 - y3) - (x1 - x3) * (y2 - y1));
        
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