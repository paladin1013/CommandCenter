classdef FullChipDataAnalyzer_bak < matlab.mixin.Heterogeneous & handle
    properties
        srcDir = ""; % Source directory.
        dstDir = ""; % Destination directory. Will save processed data under this directory
        dataRootDir = ""; % Root directory of all experiment data. Will be used in `processAllExperiments
        append = false; % Append to the current data when loading new data.
        xmin = 0; % The minimum x chiplet coordinate
        xmax = 3; % The maximum x chiplet coordinate
        ymin = 0; % The minimum y chiplet coordinate
        ymax = 3; % The maximum y chiplet coordinate
        x = 0; % The current displaying x coordinate.
        y = 0; % The current displaying y coordinate.
        mincount = 3000; % Minimum display thresold of EMCCD image count. Emitters with intensity larger than this value will be shown in plots.
        
        emitterMinSize = 3; % To filter out noise, only emitters with size large than this value will be recorded
        freqBin_GHz = 0.01; % Width of frequency binning when loading data.
        cmapName = 'lines'; % Name of the colormap
    end
    properties(Constant)
        processMincount = 10000;
        frameWidth = 5;
        padding = 5;
        nWaveguides = 6;
        backgroundNoise = 1450; % Derived from the medium of all EMCCD pixels.
        regionMap = {'center', 'frame', 'tip', 'bulk', 'out'};
    end

    properties
        data;
        chipletData;
        idxTable;
        figH;
        sumAxH;
        sumImH;
        wlAxH;
        wlImH;
        countAxH;
        spectrum1AxH;
        spectrum2AxH;
        cursH;
        coords; % Keep only valid coordinates
        wlSize = [512, 512]; % y, x
        initialized = false;

        % For summary figure
        allFigH;
        allAxH;
        allImH;
        jointCountAxH;
        gdsAxH;
        gdsImH;
        sumCountAxH;
        trimmedWLPosition;
        chipletColors;
        gdsData;
        chipletWiseAxH;
        locationWiseAxH;
        


        allChipletEmitters;
        allChipletStatistics;
        allExperimentStatistics;
        allExperimentEmitters;
    end
    methods(Static)
        % Methods have to be static to process in parallel
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
        function emitters  = fitPeaks(emitters, drawFig, batchIdx) % Lorentzian fitting
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
                    intensities = emitter.spectrums(l).intensities;
                    freqs_THz = emitter.spectrums(l).freqs_THz;
                    nPoints = length(freqs_THz);
                    [peakIntensity, peakIdx] = max(intensities);
                    fitStartIdx = max(1, peakIdx-40);
                    fitEndIdx = min(nPoints, peakIdx+40);
                    fitFreqs_THz = freqs_THz(fitStartIdx:fitEndIdx);
                    prefitIntensities = double(intensities(fitStartIdx:fitEndIdx));

            %          limits.amplitudes = [0, Inf];
            %          limits.widths = [0, max(fitFreqs_THz)-min(fitFreqs_THz)];
            %          limits.locations = [min(fitFreqs_THz), max(fitFreqs_THz)];
            %          limits.background = [0 max(fitIntensity)];
            %          [~, findPeakFreqs, ffindPeakWidths, findPeakAmplitudes] = findpeaks(fitIntensity,fitFreqs_THz);
            %          [init.amplitudes, findPeakIdx] = max(findPeakAmplitudes);
            %          init.locations = findPeakFreqs(findPeakIdx);
            %          init.widths = findPeakWidths(findPeakIdx);
            %          init.background = median(fitIntensity);
            %          [f,new_gof,output] = lorentzfit(fitFreqs_THz, fitIntensity, 1, init, limits);
            %          fittedIntensity = f(fitIntensity);
            %          figure; plot(fitFreqs_THz, fitIntensity); hold on; plot(fitFreqs_THz, fittedIntensity)
                    [vals,confs,fit_results,gofs,init,stop_condition] = fitpeaks(fitFreqs_THz,prefitIntensities,"FitType", "lorentz", "n", 1, "Span", 1);
                    % emitters are not satisfying .....
                    postfitIntensities = fit_results{2}(fitFreqs_THz);
                    if exist('drawFig', 'var') && drawFig
                        fitting_fig = figure;
                        fitting_ax = axes("Parent", fitting_fig);
                        plot(fitting_ax, fitFreqs_THz, prefitIntensities);
                        hold(fitting_ax, 'on');
                        plot(fitting_ax, fitFreqs_THz, postfitIntensities);
                        fitting_ax.Title.String = sprintf("Emitter No.%d", k);
                    end
                    emitter.spectrums(l).postfitIntensities = postfitIntensities;
                    emitter.spectrums(l).fittedLinewidth_THz = vals.widths*2;
                    emitter.spectrums(l).fittedPeakAmplitude = vals.amplitudes/vals.widths*2;
                    emitter.spectrums(l).fittedBackground = fit_results{2}.d;
                    emitter.spectrums(l).fitStartIdx = fitStartIdx;
                    emitter.spectrums(l).fitEndIdx = fitEndIdx;
                    
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
        function [emitters, sumResults] = processChiplet(chipletData, drawFig)
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
            sumResults = struct();
            sumResults.absPosXs = NaN(1, nEmitters);
            sumResults.absPosYs = NaN(1, nEmitters);
            sumResults.maxIntensities = NaN(1, nEmitters);
            sumResults.resonantFreqs_THz = NaN(1, nEmitters);
            sumResults.regionIdxes = NaN(1, nEmitters);
            sumResults.sizes_pixel = NaN(1, nEmitters);
            sumResults.findPeakWidth_THz = NaN(1, nEmitters);
            sumResults.findPeakAmplitude = NaN(1, nEmitters);
            sumResults.findPeakIntensity = NaN(1, nEmitters);
            sumResults.emitterValid = NaN(1, nEmitters);
            
            sumResults.nEmitters = nEmitters;
            sumResults.wl_img = chipletData.wl_img;
            sumResults.chipletIdx = chipletData.chipletIdx;
            sumResults.chipletCoordX = chipletData.coordX;
            sumResults.chipletCoordY = chipletData.coordY;
            sumResults.chipletID = chipletData.chipletID;
            for l = 1:nEmitters
                tempIdx = find(emitterIdx==l);
                tempXs = validXs(tempIdx);
                tempYs = validYs(tempIdx);
                tempIntensities = peakIntensities(tempIdx);
                tempFreqs = peakFreqs(tempIdx);
                [maxIntensity, maxIdx] = max(tempIntensities);
                emitters(l).absPosX = tempXs(maxIdx);
                emitters(l).absPosY = tempYs(maxIdx);
                emitters(l).relPosX = emitters(l).absPosX - chipletData.widefieldData{1}.segment.absCenterX;
                emitters(l).relPosY = emitters(l).absPosY - chipletData.widefieldData{1}.segment.absCenterY;
                emitters(l).maxIntensity = double(maxIntensity);
                emitters(l).region = Drivers.FullChipDataAnalyzer.getRegion(emitters(l).absPosX, emitters(l).absPosY, chipletData.widefieldData{1}.segment);
                emitters(l).resonantFreq_THz = tempFreqs(maxIdx);
                emitters(l).chipletIdx = chipletData.chipletIdx;
                emitters(l).chipletCoordX = chipletData.coordX;
                emitters(l).chipletCoordY = chipletData.coordY;
                emitters(l).chipletID = chipletData.chipletID;
                emitters(l).size_pixel = sum(emitterIdx==l);

                sumResults.absPosXs(l) = tempXs(maxIdx);
                sumResults.absPosYs(l) = tempYs(maxIdx);
                sumResults.maxIntensities(l) = double(maxIntensity);
                sumResults.regionIdxes(l) = find(strcmp(emitters(l).region, Drivers.FullChipDataAnalyzer.regionMap));
                sumResults.resonantFreqs_THz(l) = tempFreqs(maxIdx);
                sumResults.sizes_pixel(l) = emitters(l).size_pixel;
                % Get spectrum
                findPeakIntensity = NaN(nSpectrums, 1);
                findPeakFreq = NaN(nSpectrums, 1);
                findPeakWidth_THz = NaN(nSpectrums, 1);
                findPeakAmplitude = NaN(nSpectrums, 1);

                spectrumValid = NaN(nSpectrums, 1);
                for k = 1:nSpectrums
                    nPoints = length(chipletData.widefieldData{k}.freqs);
                    freqs_THz = chipletData.widefieldData{k}.freqs;
                    freqs_THz = reshape(freqs_THz, nPoints, 1);
                    intensities = chipletData.widefieldData{k}.filtered_imgs(emitters(l).absPosY, emitters(l).absPosX, :);
                    intensities = reshape(intensities, nPoints, 1);
                    if max(intensities) > Drivers.FullChipDataAnalyzer.processMincount
                        hasPeak = true;
                        [peakIntensity, peakIdx] = max(intensities);
                        peakFreq_THz = freqs_THz(peakIdx);
                        % Use findpeaks to briefly get the linewidth and peak frequency (Usually incorrect);
                        fitStartIdx = max(1, peakIdx-40);
                        fitEndIdx = min(nPoints, peakIdx+40);
                        fitFreqs_THz = freqs_THz(fitStartIdx:fitEndIdx);
                        fitIntensities = double(intensities(fitStartIdx:fitEndIdx));    
                        [sortedFreqs_THz, sortedIdx] = sort(fitFreqs_THz, 'ascend');
                        fitIntensities = fitIntensities(sortedIdx);

                        [findPeakIntensities, findPeakFreqs, findPeakWidths, findPeakAmplitudes] = findpeaks(fitIntensities, sortedFreqs_THz);
                        [maxIntensity, maxIdx] = max(findPeakIntensities);
                        peakWidth_THz = findPeakWidths(maxIdx);
                        findPeakIntensity(k) = findPeakIntensities(maxIdx);
                        findPeakFreq(k) = findPeakFreqs(maxIdx);
                        findPeakWidth_THz(k) = findPeakWidths(maxIdx);
                        findPeakAmplitude(k) = findPeakAmplitudes(maxIdx);
                        if sum(intensities >= maxIntensity/2) < 2
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
                    spectrums(k) = struct('spectrumValid', spectrumValid(k), 'hasPeak', hasPeak, 'intensities', intensities, 'freqs_THz', freqs_THz, ...
                    'peakFreq_THz', peakFreq_THz, 'peakIntensity', peakIntensity, 'peakWidth_THz', peakWidth_THz);
                end
                emitters(l).spectrums = spectrums;
                emitters(l).findPeakWidth_THz = mean(findPeakWidth_THz);
                emitters(l).findPeakAmplitude = mean(findPeakAmplitude);
                emitters(l).findPeakIntensity = mean(findPeakIntensity);
                emitters(l).emitterValid = any(spectrumValid);
                sumResults.findPeakWidth_THz(l) = mean(findPeakWidth_THz);
                sumResults.findPeakAmplitude(l) = mean(findPeakAmplitude);
                sumResults.findPeakIntensity(l) = mean(findPeakIntensity);
                sumResults.emitterValid(l) = emitters(l).emitterValid;
            end
        end
        function emitters = fitPeak3D(emitters, drawFig, batchIdx)
            
        end
        function emitters = processChiplet3D(chipletData, drawFig)
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
                xmin = max(min(tempXs)-obj.padding, imageXmin);
                xmax = min(max(tempXs)+obj.padding, imageXmax);
                ymin = max(min(tempYs)-obj.padding, imageYmin);
                ymax = min(max(tempYs)+obj.padding, imageYmax);

                tempIntensities = peakIntensities(tempIdx);
                tempFreqs = peakFreqs(tempIdx);
                [maxIntensity, maxIdx] = max(tempIntensities);
                % emitters(l).absPosX = tempXs(maxIdx);
                % emitters(l).absPosY = tempYs(maxIdx);
                % emitters(l).relPosX = emitters(l).absPosX - chipletData.widefieldData{1}.segment.absCenterX;
                % emitters(l).relPosY = emitters(l).absPosY - chipletData.widefieldData{1}.segment.absCenterY;
                emitters(l).maxIntensity = double(maxIntensity);
                emitters(l).region = Drivers.FullChipDataAnalyzer.getRegion(emitters(l).absPosX, emitters(l).absPosY, chipletData.widefieldData{1}.segment);
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
                    nPoints = length(chipletData.widefieldData{k}.freqs);
                    freqs_THz = chipletData.widefieldData{k}.freqs;
                    freqs_THz = reshape(freqs_THz, nPoints, 1);
                    % intensities = chipletData.widefieldData{k}.filtered_imgs(emitters(l).absPosY, emitters(l).absPosX, :);
                    % intensities = reshape(intensities, nPoints, 1);
                    intensities = 
                    
                    if max(intensities) > Drivers.FullChipDataAnalyzer.processMincount
                        hasPeak = true;
                        [peakIntensity, peakIdx] = max(intensities);
                        peakFreq_THz = freqs_THz(peakIdx);
                        % Use findpeaks to briefly get the linewidth and peak frequency (Usually incorrect);
                        fitStartIdx = max(1, peakIdx-40);
                        fitEndIdx = min(nPoints, peakIdx+40);
                        fitFreqs_THz = freqs_THz(fitStartIdx:fitEndIdx);
                        fitIntensities = double(intensities(fitStartIdx:fitEndIdx));    
                        [sortedFreqs_THz, sortedIdx] = sort(fitFreqs_THz, 'ascend');
                        fitIntensities = fitIntensities(sortedIdx);

                        [findPeakIntensities, findPeakFreqs, findPeakWidths, findPeakAmplitudes] = findpeaks(fitIntensities, sortedFreqs_THz);
                        [maxIntensity, maxIdx] = max(findPeakIntensities);
                        peakWidth_THz = findPeakWidths(maxIdx);
                        findPeakIntensity(k) = findPeakIntensities(maxIdx);
                        findPeakFreq(k) = findPeakFreqs(maxIdx);
                        findPeakWidth_THz(k) = findPeakWidths(maxIdx);
                        findPeakAmplitude(k) = findPeakAmplitudes(maxIdx);
                        if sum(intensities >= maxIntensity/2) < 2
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
                    spectrums(k) = struct('spectrumValid', spectrumValid(k), 'hasPeak', hasPeak, 'intensities', intensities, 'freqs_THz', freqs_THz, ...
                    'peakFreq_THz', peakFreq_THz, 'peakIntensity', peakIntensity, 'peakWidth_THz', peakWidth_THz);
                end
            end
        end
        function region = getRegion(absPosX, absPosY, segment)
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

            

            if inpolygon(absPosY, absPosX, cornerAbsPos_yx(:, 1), cornerAbsPos_yx(:, 2)) && ~onFrame
                region = 'center';
            elseif onFrame
                region = 'frame';
            elseif inpolygon(absPosY, absPosX, leftTipPolygon_yx(:, 1), leftTipPolygon_yx(:, 2)) || inpolygon(absPosY, absPosX, rightTipPolygon_yx(:, 1), rightTipPolygon_yx(:, 2))
                region = 'tip';
            else
                region = 'bulk';
            end
        end
        obj = instance()
    end

    methods(Access=private)
        function obj = FullChipDataAnalyzer()
            obj.initialized = true;
        end
    end

    methods
        function getCenterDistance(obj, emitters)


        end
        function processAllExperiments(obj, dataRootDir)
            if ~exist('dataRootDir', 'var')
                dataRootDir = obj.dataRootDir;
            end
            assert(isfolder(fullfile(dataRootDir, 'CleanedData')), '`dataRootDir` should contain folder `CleanedData`');
            if ~isfolder(fullfile(dataRootDir, 'ProcessedData'))
                mkdir(fullfile(dataRootDir, 'ProcessedData'));
            end
            sumDir = fullfile(dataRootDir, 'ProcessedData', 'AllChipletsData');
            if ~isfolder(sumDir)
                mkdir(sumDir);
            end
            files = dir(fullfile(dataRootDir, 'CleanedData'));
            for k = 1:length(files)
                file = files(k);
                obj.srcDir = fullfile(dataRootDir, 'CleanedData', file.name);
                obj.dstDir = fullfile(dataRootDir, 'ProcessedData', file.name);
                if isfolder(obj.srcDir) && ~contains(file.name, '.')
                    if ~isfolder(obj.dstDir)
                        mkdir(obj.dstDir);
                    end
                    obj.processExperiment;
                    copyfile(fullfile(obj.dstDir, "processed_emitters_data.mat"), fullfile(sumDir, sprintf("%s.mat", file.name)));
                end
            end

            [emitters, sumResults] = obj.parallelFitPeaks;
            obj.aggregateAllExperiments(sumDir);
            obj.plotAllStatistic(sumResults);
        end
        function processExperiment(obj)
            assert(~isempty(obj.srcDir), "Source directory is empty. Please assign obj.srcDir before processing data.");
            assert(~isempty(obj.dstDir), "Destination directory is empty. Please assign obj.dstDir before processing data.");
            if ~exist(obj.dstDir, 'dir')
                mkdir(obj.dstDir);
            end
            % Take in the recorded result `Chipletxxx.mat` and return & save emitter data (`emitters_chiplet_xxx.mat`)
            files = dir(obj.srcDir);
            nValid = 0;
            validFileNames = {};
            for k = 1:length(files)
                file = files(k);
                % fprintf('Checking file %s (%d/%d)\n', file.name, k, length(files));
                [tokens,matches] = regexp(file.name,'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                if ~isempty(tokens)
                    nValid = nValid + 1;
                    fprintf("Find widefield data file '%s'\n", file.name);
                    validFileNames{end+1} = file.name;
                    if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                        [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                        chipletCoordX = str2num(subTokens{1}{1});
                        chipletCoordY = str2num(subTokens{1}{2});
                        load(fullfile(obj.srcDir, file.name), 'coordX', 'coordY');
                        assert(chipletCoordX == coordX && chipletCoordY == coordY, 'Chiplet coordinate inside data does not match with the file name.');
                    end
                end

            end
            obj.chipletData = cell(1, nValid);
            obj.idxTable = zeros(obj.xmax-obj.xmin+1, obj.ymax-obj.ymin+1);

            for k = 1:nValid
                % Parallel can be used if more data is required (though more memory is required)
                [tokens,matches] = regexp(validFileNames{k},'[cC]hiplet_?(\d+)(.*)\.mat$','tokens','match');
                idx = str2num(tokens{1}{1});
                fprintf("Loading file '%s' (%d/%d), idx: %d.\n", validFileNames{k}, k, nValid, idx);
                tempData = load(fullfile(obj.srcDir, validFileNames{k}));
                if isfield(tempData, 'data')
                    tempData = tempData.data;
                end
                if length(tokens{1}) >= 2 && ~isempty(tokens{1}{2})
                    [subTokens, subMatches] = regexp(tokens{1}{2}, '_x(\d+)_y(\d+)_ID(\d+)', 'tokens', 'match');
                    chipletID = str2num(subTokens{1}{3});
                    tempData.chipletID = chipletID;   
                end
                tempData.chipletIdx = idx;
                fprintf("Start processing file '%s' (%d/%d), idx: %d.\n", validFileNames{k}, k, nValid, idx);
                [emitters, sumResults]= obj.processChiplet(tempData, false);
                save(fullfile(obj.dstDir, sprintf("chiplet%d_processed_data.mat", idx)), "emitters", "sumResults");
            end
            obj.aggregateData;
        end
        function aggregateAllExperiments(obj, sumDir)
            files = dir(sumDir);
            obj.allExperimentEmitters = [];

            obj.allExperimentStatistics = struct;
            obj.allExperimentStatistics.absPosXs = [];
            obj.allExperimentStatistics.absPosYs = [];
            obj.allExperimentStatistics.maxIntensities = [];
            obj.allExperimentStatistics.resonantFreqs_THz = [];
            obj.allExperimentStatistics.regionIdxes = [];
            obj.allExperimentStatistics.chipletIdxes = [];
            obj.allExperimentStatistics.chipletCoordsX = [];
            obj.allExperimentStatistics.chipletCoordsY = [];
            obj.allExperimentStatistics.chipletIDs = [];
            obj.allExperimentStatistics.experimentName = [];
            obj.allExperimentStatistics.sizes_pixel = [];
            obj.allExperimentStatistics.findPeakWidth_THz = [];
            obj.allExperimentStatistics.findPeakAmplitude = [];
            obj.allExperimentStatistics.findPeakIntensity = [];
            obj.allExperimentStatistics.emitterValid = [];
            for k = 1:length(files)
                file = files(k);
                [tokens, matches] = regexp(file.name, 'Widefield(.+).mat', 'tokens', 'match');
                if isempty(tokens)
                    continue;
                end
                experimentName = sprintf("%s", tokens{1}{1});
                load(fullfile(sumDir, file.name), 'allChipletStatistics', 'allChipletEmitters');
                nEmitters = length(allChipletStatistics.absPosXs);
                if isempty(obj.allExperimentEmitters)
                    obj.allExperimentEmitters = allChipletEmitters;
                else
                    obj.allExperimentEmitters(end+1:end+nEmitters) = allChipletEmitters;
                end
                obj.allExperimentStatistics.absPosXs(end+1:end+nEmitters) = allChipletStatistics.absPosXs;
                obj.allExperimentStatistics.absPosYs(end+1:end+nEmitters) = allChipletStatistics.absPosYs;
                obj.allExperimentStatistics.maxIntensities(end+1:end+nEmitters) = allChipletStatistics.maxIntensities;
                obj.allExperimentStatistics.resonantFreqs_THz(end+1:end+nEmitters) = allChipletStatistics.resonantFreqs_THz;
                obj.allExperimentStatistics.regionIdxes(end+1:end+nEmitters) = allChipletStatistics.regionIdxes;
                obj.allExperimentStatistics.chipletIdxes(end+1:end+nEmitters) = allChipletStatistics.chipletIdxes;
                obj.allExperimentStatistics.chipletCoordsX(end+1:end+nEmitters) = allChipletStatistics.chipletCoordsX;
                obj.allExperimentStatistics.chipletCoordsY(end+1:end+nEmitters) = allChipletStatistics.chipletCoordsY;
                obj.allExperimentStatistics.chipletIDs(end+1:end+nEmitters) = allChipletStatistics.chipletIDs;
                obj.allExperimentStatistics.sizes_pixel(end+1:end+nEmitters) = allChipletStatistics.sizes_pixel;
                obj.allExperimentStatistics.experimentName(end+1:end+nEmitters) = experimentName;
                obj.allExperimentStatistics.findPeakWidth_THz(end+1:end+nEmitters) = allChipletStatistics.findPeakWidth_THz;
                obj.allExperimentStatistics.findPeakAmplitude(end+1:end+nEmitters) = allChipletStatistics.findPeakAmplitude;
                obj.allExperimentStatistics.findPeakIntensity(end+1:end+nEmitters) = allChipletStatistics.findPeakIntensity;
                obj.allExperimentStatistics.emitterValid(end+1:end+nEmitters) = allChipletStatistics.emitterValid;
            end
            allExperimentStatistics = obj.allExperimentStatistics;
            allExperimentEmitters = obj.allExperimentEmitters;

            save(fullfile(sumDir, "all_experiments_data.mat"), "allExperimentStatistics", "allExperimentEmitters");
        end
        function aggregateData(obj)
            obj.allChipletEmitters = [];
            obj.allChipletStatistics = struct;
            obj.allChipletStatistics.absPosXs = [];
            obj.allChipletStatistics.absPosYs = [];
            obj.allChipletStatistics.maxIntensities = [];
            obj.allChipletStatistics.resonantFreqs_THz = [];
            obj.allChipletStatistics.regionIdxes = [];
            obj.allChipletStatistics.chipletIdxes = [];
            obj.allChipletStatistics.chipletCoordsX = [];
            obj.allChipletStatistics.chipletCoordsY = [];
            obj.allChipletStatistics.chipletIDs = [];
            obj.allChipletStatistics.sizes_pixel = [];
            obj.allChipletStatistics.findPeakWidth_THz = [];
            obj.allChipletStatistics.findPeakAmplitude = [];
            obj.allChipletStatistics.findPeakIntensity = [];
            obj.allChipletStatistics.emitterValid = [];
            nChiplets = (obj.xmax-obj.xmin+1)*(obj.ymax-obj.ymin+1);
            
            for idx = 1:nChiplets
                fileName = sprintf("chiplet%d_processed_data.mat", idx);
                if ~isfile(fullfile(obj.dstDir, fileName))
                    fprintf("File %s does not exist. Please call obj.processData first.\n", fileName);
                    continue
                end
                load(fullfile(obj.dstDir, fileName), 'emitters', 'sumResults');
                nEmitters = length(emitters);
                if isempty(obj.allChipletEmitters)
                    obj.allChipletEmitters = emitters;
                else
                    obj.allChipletEmitters(end+1:end+nEmitters) = emitters;
                end
                obj.allChipletStatistics.absPosXs(end+1:end+nEmitters) = sumResults.absPosXs;
                obj.allChipletStatistics.absPosYs(end+1:end+nEmitters) = sumResults.absPosYs;
                obj.allChipletStatistics.maxIntensities(end+1:end+nEmitters) = sumResults.maxIntensities;
                obj.allChipletStatistics.resonantFreqs_THz(end+1:end+nEmitters) = sumResults.resonantFreqs_THz;
                obj.allChipletStatistics.regionIdxes(end+1:end+nEmitters) = sumResults.regionIdxes;
                obj.allChipletStatistics.chipletIdxes(end+1:end+nEmitters) = sumResults.chipletIdx;
                obj.allChipletStatistics.chipletCoordsX(end+1:end+nEmitters) = sumResults.chipletCoordX;
                obj.allChipletStatistics.chipletCoordsY(end+1:end+nEmitters) = sumResults.chipletCoordY;
                obj.allChipletStatistics.chipletIDs(end+1:end+nEmitters) = sumResults.chipletID;
                obj.allChipletStatistics.sizes_pixel(end+1:end+nEmitters) = sumResults.sizes_pixel;
                obj.allChipletStatistics.findPeakWidth_THz(end+1:end+nEmitters) = sumResults.findPeakWidth_THz;
                obj.allChipletStatistics.findPeakAmplitude(end+1:end+nEmitters) = sumResults.findPeakAmplitude;
                obj.allChipletStatistics.findPeakIntensity(end+1:end+nEmitters) = sumResults.findPeakIntensity;
                obj.allChipletStatistics.emitterValid(end+1:end+nEmitters) = sumResults.emitterValid;
                
                obj.chipletData{idx} = struct('idx', idx, 'chipletCoordX', sumResults.chipletCoordX, 'chipletCoordY', sumResults.chipletCoordY, 'wl_img', sumResults.wl_img, 'emitters', emitters);
                if sumResults.chipletCoordX >= obj.xmin && sumResults.chipletCoordX <= obj.xmax && sumResults.chipletCoordY >= obj.ymin && sumResults.chipletCoordY <= obj.ymax
                    obj.idxTable(sumResults.chipletCoordX-obj.xmin+1, sumResults.chipletCoordY-obj.ymin+1) = idx;
                end
            end
            allChipletStatistics = obj.allChipletStatistics;
            allChipletEmitters = obj.allChipletEmitters;
            save(fullfile(obj.dstDir, "processed_emitters_data.mat"), "allChipletStatistics", "allChipletEmitters");
        end
        function idx = getChipletIdx(obj, x, y)
            idx = obj.idxTable(x-obj.xmin+1, y-obj.ymin+1);
        end
        function cleanData(obj, srcDir, srcIDs, targetDir, targetIDs, targetCoordsX, targetCoordsY, numbers)
            files = dir(srcDir);
            for k = 1:length(files)
                file = files(k);
                % fprintf('Checking file %s (%d/%d)\n', file.name, k, length(files));
                [tokens,matches] = regexp(file.name,'[cC]hiplet_?(\d+).mat','tokens','match');
                if isempty(tokens)
                    continue;
                end
                id = str2num(tokens{1}{1});
                if ~any(id == srcIDs)
                    continue;
                end
                idx = find(id==srcIDs);
                targetID = targetIDs(idx);
                coordX = targetCoordsX(idx);
                coordY = targetCoordsY(idx);
                if exist('tempData', 'var')
                    clear('tempData');
                end
                fprintf("Loading %s\n", file.name);
                tempData = load(fullfile(srcDir, file.name));
                stagePos = tempData.stagePos;
                widefieldData = tempData.widefieldData;
                wl_img = tempData.wl_img;
                fprintf("Saving chiplet%d_x%d_y%d_ID%d.mat\n", targetID, coordX, coordY, numbers(idx));
                save(fullfile(targetDir, sprintf("chiplet%d_x%d_y%d_ID%d.mat", targetID, coordX, coordY, numbers(idx))), 'coordX', 'coordY', 'stagePos', 'widefieldData', 'wl_img');
            end
        end
        

        function [emitters, sumResults] = parallelFitPeaks(obj, emitters, batchSize)
            if ~exist('emitters', 'var')
                if isempty(obj.dataRootDir)
                    error("obj.dataRootDir is empty. Please assign the data directory.");
                end
                dirs = dir(fullfile(obj.dataRootDir, 'CleanedData'));
                validFiles = cell(0, 2);
                for k = 1:length(dirs)
                    folderName = dirs(k).name;
                    if contains(folderName, "Widefield")
                        files = dir(fullfile(obj.dataRootDir, 'ProcessedData', folderName));
                        for l = 1:length(files)
                            fileName = files(l).name;
                            if contains(fileName, "chiplet") && contains(fileName, '_processed_data.mat') && ~contains(fileName, 'fitted')
                                filePath = fullfile(folderName, fileName);
                                validFiles{end+1, 1} = folderName;
                                validFiles{end, 2} = fileName;
                                fprintf("Find valid processed data file %s (%d)\n", filePath, length(validFiles));
                            end
                        end
                    end
                end
                if ~exist('dataRootDir', 'var')
                    dataRootDir = obj.dataRootDir;
                end
                nValidFiles = size(validFiles, 1);
                allEmitters = cell(nValidFiles, 1);
                allSumResults = cell(nValidFiles, 1);
                parfor k = 1:nValidFiles
                    fprintf("Processing file %s\n", fullfile(dataRootDir, 'ProcessedData', validFiles{k, 1}, validFiles{k, 2}));
                    newData = load(fullfile(dataRootDir, 'ProcessedData', validFiles{k, 1}, validFiles{k, 2}));
                    emitters = newData.emitters;
                    sumResults = newData.sumResults;
                    emitters = Drivers.FullChipDataAnalyzer.fitPeaks(emitters, false, k);
                    sumResults.fittedLinewidth_THz = extractfield(emitters, "fittedLinewidth_THz");
                    allEmitters{k} = emitters;
                    allSumResults{k} = sumResults;
                end
                for k = 1:nValidFiles
                    emitters = allEmitters{k};
                    sumResults = allSumResults{k};
                    save(fullfile(dataRootDir, 'ProcessedData', validFiles{k, 1}, sprintf("fitted_%s", validFiles{k, 2})), 'emitters', 'sumResults');
                end

                emitters = vertcat(allEmitters{:});
                if ~isfolder(fullfile(dataRootDir, 'ProcessedData', 'AllChipletsData'))
                    mkdir(fullfile(dataRootDir, 'ProcessedData', 'AllChipletsData'));
                end
                save(fullfile(dataRootDir, 'ProcessedData', 'AllChipletsData', 'fitted_emitters.mat'), "emitters", '-v7.3');
                sumResults = obj.extractSumResults(emitters);
                save(fullfile(dataRootDir, 'ProcessedData', 'AllChipletsData', 'fitted_sumResults.mat'), "sumResults", '-v7.3');

            else
                
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

                emitters = cell2mat(vertcat(allEmitters{:}));
                sumResults = obj.extractSumResults(emitters);
            end

        end

        function emitters = loadAllEmitters(obj, dataRootDir)
            if ~exist('dataRootDir', 'var')
                if isempty(obj.dataRootDir)
                    error("obj.dataRootDir is empty. Please assign the data directory.");
                end
                dataRootDir = obj.dataRootDir;
            end
            dirs = dir(fullfile(obj.dataRootDir, 'CleanedData'));
            validFiles = cell(0, 2);
            for k = 1:length(dirs)
                folderName = dirs(k).name;
                if contains(folderName, "Widefield")
                    files = dir(fullfile(obj.dataRootDir, 'ProcessedData', folderName));
                    for l = 1:length(files)
                        fileName = files(l).name;
                        if contains(fileName, "chiplet") && contains(fileName, '_processed_data.mat') && contains(fileName, 'fitted')
                            filePath = fullfile(folderName, fileName);
                            validFiles{end+1, 1} = folderName;
                            validFiles{end, 2} = fileName;
                            fprintf("Find valid processed data file %s (%d)\n", filePath, length(validFiles));
                        end
                    end
                end
            end
            nValidFiles = size(validFiles, 1);
            allEmitters = cell(nValidFiles, 1);
            for k = 1:nValidFiles
                filePath = fullfile(dataRootDir, 'ProcessedData', validFiles{k, 1}, validFiles{k, 2});
                fprintf("Loading file %s, (%d/%d)\n", filePath, k, nValidFiles);
                load(filePath, 'emitters')
                allEmitters{k} = emitters;
            end
            emitters = vertcat(allEmitters{:});
        end
        function sumResults = extractSumResults(obj, emitters)
            sumResults = struct;            
            sumResults.absPosXs = extractfield(emitters, "absPosX");
            sumResults.absPosYs = extractfield(emitters, "absPosY");
            sumResults.maxIntensities = extractfield(emitters, "maxIntensity");
            sumResults.regions = extractfield(emitters, "region");
            sumResults.regionIdxes = NaN(1, length(sumResults.regions));
            for k = 1:4
                sumResults.regionIdxes(strcmp(sumResults.regions, obj.regionMap{k})) = k;
            end
            sumResults.resonantFreqs_THz = extractfield(emitters, "resonantFreq_THz");
            sumResults.chipletIdxes = extractfield(emitters, "chipletIdx");
            sumResults.chipletCoordsX = extractfield(emitters, "chipletCoordX");
            sumResults.chipletCoordsY = extractfield(emitters, "chipletCoordY");
            sumResults.chipletIDs = extractfield(emitters, "chipletID");
            sumResults.sizes_pixel = extractfield(emitters, "size_pixel");
            sumResults.fittedLinewidth_THz = extractfield(emitters, "fittedLinewidth_THz");
            sumResults.fittedPeakAmplitude = extractfield(emitters, "fittedPeakAmplitude");
            sumResults.fittedBackground = extractfield(emitters, "fittedBackground");
            if ~isempty(obj.dataRootDir)
                save(fullfile(obj.dataRootDir, 'ProcessedData', 'AllChipletsData', 'extractedSumResults.mat'), "sumResults");
            end
        end
        
        function plotHistCurve(obj, sumResults, brCurveAxH, freqCurveAxH, linewidthCurveAxH)
            % Plot histogram and convert into curve on brightness and frequency.


            cmap = eval(sprintf("%s(4)", obj.cmapName));
            % plot brightness histogram
            normBr = sumResults.maxIntensities/65536;
            histFigH = figure;
            brHistAxH = axes(histFigH);
            brHistHs = cell(1, 4);
            brCurveHs = cell(1, 4);
            brHistY = cell(1, 4);
            brHistX = cell(1, 4);
            for k = 1:4
                brHistHs{k} = histogram(brHistAxH, normBr(sumResults.regionIdxes == k));
                brHistHs{k}.Normalization = 'probability';
                brHistHs{k}.BinWidth = 0.01;
                brHistHs{k}.DisplayStyle = 'stairs';
                hold(brHistAxH, 'on');
                brHistY{k} = brHistHs{k}.Values;
                brHistX{k} = (brHistHs{k}.BinEdges(2:end)+brHistHs{k}.BinEdges(1:end-1))/2;
                brCurveHs{k} = plot(brCurveAxH, brHistX{k}, brHistY{k}, 'Color', cmap(k, :));
                hold(brCurveAxH, 'on');
            end
            delete(brHistAxH);
            brCurveAxH.XLabel.String = "Normalized brightness";
            brCurveAxH.YLabel.String = "Probability";
            brCurveAxH.FontSize = 16;
            legends = cell(1, 4);
            for k = 1:4
                legends{k} = sprintf('%s\t\tN=%d', obj.regionMap{k}, sum(sumResults.regionIdxes == k));
            end
            legend(brCurveAxH, legends);


            % plot brightness histogram

            freqHistAxH = axes(histFigH);
            freqHistHs = cell(1, 4);
            freqCurveHs = cell(1, 4);
            freqHistX = cell(1, 4);
            freqHistY = cell(1, 4);
            for k = 1:4
                freqHistHs{k} = histogram(freqHistAxH, sumResults.resonantFreqs_THz(sumResults.regionIdxes == k));
                freqHistHs{k}.Normalization = 'probability';
                freqHistHs{k}.BinWidth = 0.001;
                freqHistHs{k}.DisplayStyle = 'stairs';
                hold(freqHistAxH, 'on');
                freqHistX{k} = (freqHistHs{k}.BinEdges(2:end)+freqHistHs{k}.BinEdges(1:end-1))/2;
                freqHistY{k} = freqHistHs{k}.Values;
                freqCurveHs{k} = plot(freqCurveAxH, freqHistX{k}, freqHistY{k}, 'Color', cmap(k, :));
                hold(freqCurveAxH, 'on');
            end
            delete(freqHistAxH);
            freqCurveAxH.XLabel.String = "Frequency (THz)";
            freqCurveAxH.YLabel.String = "Probability";
            freqCurveAxH.FontSize = 16;


            % plot linewidth histogram

            linewidthHistAxH = axes(histFigH);
            linewidthHistHs = cell(1, 4);
            linewidthCurveHs = cell(1, 4);
            linewidthHistX = cell(1, 4);
            linewidthHistY = cell(1, 4);
            for k = 1:4
                linewidthHistHs{k} = histogram(linewidthHistAxH, sumResults.fittedLinewidth_THz(sumResults.regionIdxes == k));
                linewidthHistHs{k}.Normalization = 'probability';
                linewidthHistHs{k}.BinWidth = 0.00001;
                linewidthHistHs{k}.DisplayStyle = 'stairs';
                hold(linewidthHistAxH, 'on');
                linewidthHistX{k} = (linewidthHistHs{k}.BinEdges(2:end)+linewidthHistHs{k}.BinEdges(1:end-1))/2;
                linewidthHistY{k} = linewidthHistHs{k}.Values;
                linewidthCurveHs{k} = plot(linewidthCurveAxH, linewidthHistX{k}, linewidthHistY{k}, 'Color', cmap(k, :));
                hold(linewidthCurveAxH, 'on');
            end
            delete(linewidthHistAxH);
            linewidthCurveAxH.XLabel.String = "linewidth (THz)";
            linewidthCurveAxH.YLabel.String = "Probability";
            linewidthCurveAxH.FontSize = 16;
            linewidthCurveAxH.XLim = [0, 0.001];
            delete(histFigH);
        end

        function plotChiplet(obj, sumResults)
            sumFigH = figure;
            sumFigH.Position = [100, 100, 1200, 1200];
            wlAxH = axes(sumFigH);
            wlImH = imagesc(wlAxH, sumResults.wl_img);
            colormap(wlAxH, 'bone');
            emitterAxH = axes(sumFigH);
            cmap = eval(sprintf("%s(4)", obj.cmapName));
            scatter(emitterAxH, sumResults.absPosXs, sumResults.absPosYs, sumResults.maxIntensities/1e3, sumResults.regionIdxes);
            colormap(emitterAxH, obj.cmapName);


            wlAxH.YDir = 'normal';
            wlAxH.YLim = [0.5, 512.5];
            wlAxH.XLim = [0.5, 512.5];
            emitterAxH.YLim = [0.5, 512.5];
            emitterAxH.XLim = [0.5, 512.5];
            emitterAxH.Visible = false;
            wlAxH.Position = [0.1, 0.55, 0.35, 0.35];
            wlAxH.FontSize = 16;
            emitterAxH.Position = [0.1, 0.55, 0.35, 0.35];
            emitterAxH.FontSize = 16;
            linkaxes([wlAxH,emitterAxH]);
            freqAxH = axes(sumFigH);
            scatter(freqAxH, sumResults.resonantFreqs_THz, sumResults.maxIntensities/65536, 10, sumResults.regionIdxes, 'filled');
            colormap(freqAxH, obj.cmapName);
            freqAxH.Position = [0.55, 0.55, 0.35, 0.35];
            freqAxH.FontSize = 16;
            freqAxH.XLabel.String = "Frequency (THz)";
            freqAxH.YLabel.String = "Intensity";

            brCurveAxH = axes(sumFigH);
            freqCurveAxH = axes(sumFigH);
            obj.plotHistCurve(sumResults, brCurveAxH, freqCurveAxH);
            brCurveAxH.Position = [0.1, 0.1, 0.35, 0.35];
            freqCurveAxH.Position = [0.55, 0.1, 0.35, 0.35];
        end

        function plotAllStatistic(obj, sumResults)
            if ~exist('sumResults', 'var')
                sumResults = obj.allChipletStatistics;
            end
            allFigH = figure;
            brCurveAxH = subplot(1, 3, 1);
            freqCurveAxH = subplot(1, 3, 2);
            linewidthCurveAxH = subplot(1, 3, 3);
            obj.plotHistCurve(sumResults, brCurveAxH, freqCurveAxH, linewidthCurveAxH);
        end

        
        function updateData(obj, append, srcDir)
            if ~exist('append', 'var')
                append = obj.append;
            end
            if ~exist('srcDir', 'var')
                srcDir = obj.srcDir;
            end
            files = dir(srcDir);
            if ~append
                obj.data = cell(obj.xmax-obj.xmin+1, obj.ymax-obj.ymin+1);
                obj.coords = zeros(0, 2);
            end
            for k = 1:length(files)
                file = files(k);
                fprintf('Checking file %s (%d/%d)\n', file.name, k, length(files));
                if endsWith(file.name, '.mat')
                    fprintf('Loading Matlab data\n');
                    newData = load(fullfile(srcDir, file.name));
                    newX = newData.data.coordX;
                    newY = newData.data.coordY;
                    if append && isfield(obj.data{newX-obj.xmin+1, newY-obj.ymin+1}, 'widefieldData')
                        prevData = obj.data{newX-obj.xmin+1, newY-obj.ymin+1};
                        assert(isequal(size(prevData.widefieldData(1).wl_img), size(newData.data.data1.widefieldData(1).wl_img)), "Size of the new ROI is inconsistent with the old.");
                        obj.data{newX-obj.xmin+1, newY-obj.ymin+1} = struct('x', newX, 'y', newY, 'widefieldData', [prevData.widefieldData, newData.data.data1, newData.data.data2], 'wl', newData.data.wl);
                    else
                        obj.coords(end+1, :) = [newX, newY];
                        obj.data{newX-obj.xmin+1, newY-obj.ymin+1} = struct('x', newX, 'y', newY, 'widefieldData', [newData.data.data1, newData.data.data2], 'wl', newData.data.wl);
                    end
                end
            end
        end
        function selectCoord(obj,hObj,event)
            pt = event.IntersectionPoint([1, 2]); %point that was just clicked
            pt = pt./obj.wlSize-0.5+[obj.xmin, obj.ymin];
            dist = pdist2(pt,obj.coords); %distance between selection and all points
            [~, coordID] = min(dist); % index of minimum distance to points
            coord = obj.coords(coordID, :);
            obj.x = coord(1);
            obj.y = coord(2);
            obj.updateFig;
        end
        function valid = checkCoord(obj, x, y)
            if isempty(obj.data{x-obj.xmin+1, y-obj.ymin+1})
                fprintf("Data of chiplet (x:%d, y:%d) is empty. Please reload the data.\n", x, y);
                valid = false;
                return;
            end
            if x > obj.xmax
                fprintf("x = %d reaches obj.xmax. Stop moving coordinate.\n", x);
                valid = false;
                return
            end
            if x < obj.xmin
                fprintf("x = %d reaches obj.xmin. Stop moving coordinate.\n", x);
                valid = false;
                return
            end
            if y > obj.ymax
                fprintf("y = %d reaches obj.ymax. Stop moving coordinate.\n", y);
                valid = false;
                return
            end
            if y < obj.ymin
                fprintf("y = %d reaches obj.ymin. Stop moving coordinate.\n", y);
                valid = false;
                return
            end
            valid = true;
        end
        function moveCoord(obj,hObj,event)
            switch event.Key
                case 'rightarrow'
                    if obj.checkCoord(obj.x+1, obj.y)
                        obj.x = obj.x + 1;
                        obj.updateFig;
                    end
                case 'leftarrow'
                    if obj.checkCoord(obj.x-1, obj.y)
                        obj.x = obj.x - 1;
                        obj.updateFig;
                    end
                case 'downarrow'
                    if obj.checkCoord(obj.x, obj.y+1)
                        obj.y = obj.y + 1;
                        obj.updateFig;
                    end
                case 'uparrow'
                    if obj.checkCoord(obj.x, obj.y-1)
                        obj.y = obj.y - 1;
                        obj.updateFig;
                    end
            end
        end
        function deleteFigH(obj,hObj,event)
            obj.figH.delete;
        end
        
        function updateFig(obj)
            t = tic;

            % Extract chiplet widefield data
            tempData = obj.data{obj.x-obj.xmin+1, obj.y-obj.ymin+1};
            assert(~isempty(tempData), sprintf("Data of chiplet (x:%d, y:%d) is empty. Please reload the data.", obj.x, obj.y))
            nDataSet = length(tempData.widefieldData); % Number of datasets of the current chiplet
            ROIsize = size(tempData.widefieldData(1).wl_img);
            wlImg = tempData.widefieldData(1).wl_img;
            filteredImgs = zeros(ROIsize(1), ROIsize(2), 0);
            freqs = zeros(1, 0);
            for k = 1:nDataSet
                tempFilteredImgs = tempData.widefieldData(k).filtered_imgs;
                nFrames = size(tempFilteredImgs, 3);
                freqs(end+1:end+nFrames) = tempData.widefieldData(k).freqs;
                filteredImgs(:, :, end+1:end+nFrames) = tempFilteredImgs;
            end
            polyPos = tempData.widefieldData(1).poly_pos;
            fprintf("time0: %f\n", toc(t));

            if isempty(obj.figH) || ~isvalid(obj.figH)
                obj.figH = figure;
            end
            axisNames = ["sumAxH", "wlAxH", "spectrum1AxH", "countAxH", "spectrum2AxH"];
            for k = 1:length(axisNames)
                if ~isempty(obj.(axisNames(k))) && isvalid(obj.(axisNames(k)))
                    delete(obj.(axisNames(k)));
                end
                figure(obj.figH);
                obj.(axisNames(k)) = subplot(5, 1, k);
            end
            figure(obj.figH);
            fprintf("time1: %f\n", toc(t));
            % Draw summary image
            sumIm = zeros(obj.wlSize.*[obj.ymax-obj.ymin+1, obj.xmax-obj.xmin+1]);
            wlX = obj.wlSize(2);
            wlY = obj.wlSize(1);
            for k = 1:size(obj.coords, 1)
                coord = obj.coords(k, :);
                tempX = coord(1);
                tempY = coord(2);
                if tempX < obj.xmin || tempX > obj.xmax || tempY < obj.ymin || tempY > obj.ymax
                    continue
                end
                sumIm((tempY-obj.ymin)*wlY+1:(tempY-obj.ymin+1)*wlY, (tempX-obj.xmin)*wlX + 1:(tempX-obj.xmin+1)*wlX) = obj.data{tempX-obj.xmin+1, tempY-obj.ymin+1}.wl;
            end
            obj.sumImH = imagesc(obj.sumAxH, sumIm);
            obj.sumAxH.Position = [0.05, 0.075, 0.25, 0.9];
            obj.sumAxH.XTickLabel = [obj.xmin:obj.xmax];
            obj.sumAxH.XTick = linspace(wlX/2, size(sumIm, 2)-wlX/2, obj.xmax-obj.xmin+1);
            obj.sumAxH.YTickLabel = [obj.xmin:obj.xmax];
            obj.sumAxH.YTick = linspace(wlY/2, size(sumIm, 1)-wlY/2, obj.ymax-obj.ymin+1);
            colormap(obj.sumAxH, 'bone');
            obj.sumImH.ButtonDownFcn = @obj.selectCoord;
            hold(obj.sumAxH, 'on');
            rectangle(obj.sumAxH, 'Position', [(obj.x-obj.xmin)*wlX + 1, (obj.y-obj.ymin)*wlY+1, wlX-1, wlY-1], 'LineWidth', 5, 'EdgeColor', 'r');
            obj.figH.KeyPressFcn = @obj.moveCoord;
            obj.figH.DeleteFcn = @obj.deleteFigH;
            fprintf("Updating chiplet figure of chiplet coordinate x:%d, y:%d\n", obj.x, obj.y);

            fprintf("time2: %f\n", toc(t));

            


            % Initialize record variables
            labels = [];
            wgc = [];
            wgw = [];
            wgx = [];
            wgy = [];
            wgpx = [];
            wgpy = [];
            wgym = [];
            allpts0 = reshape(filteredImgs, [numel(wlImg), length(freqs)]);
            allpts0(max(allpts0, [], 2) < obj.mincount, :) = [];
        
            p0 = zeros(5, length(allpts0(:, 1)));
            [p0(5, :), p0(3, :)] = find(allpts0 == max(allpts0, [], 2));


            fprintf("time4: %f\n", toc(t));
        
        
            for i = 1:length(allpts0(:, 1))
                p0(4, i) = allpts0(p0(5, i), p0(3, i));
                [a, b] = find(filteredImgs(:, :, p0(3, i)) == p0(4, i));
                p0(1, i) = a(1);
                p0(2, i) = b(1);
            end
            a1 = 1;
            fres = unique(p0(3, :));
            realx = zeros(1, length(fres));
            realy = zeros(1, length(fres));
            reali = zeros(1, length(fres));
            reala = zeros(1, length(fres));
            realf = zeros(1, length(fres));
            realpoints = zeros(5, length(fres));
            sloc = zeros(1, length(fres));
            swid = zeros(1, length(fres));
        
            for i = 1:length(fres)
                pmax = 0;
                ptx = [];
                pty = [];
                for j = 1:length(allpts0(:, 1))
                    if p0(3, j) == fres(i)
                        pmax = max(pmax, p0(4, j));
                        ptx = [ptx; p0(1, j)];
                        pty = [pty; p0(2, j)];
                    end
                end
                xi = find(p0(4, :) == pmax);
                xi = xi(1);
        
                realx(i) = p0(1, xi);
                realy(i) = p0(2, xi);
                reali(i) = p0(5, xi);
                reala(i) = p0(4, xi);
                realf(i) = p0(3, xi);
                %     realpoints(i)=p0(:,xi);
            end
            a1;
            c = jet(length(fres));
        
            yy = allpts0(reali, :);
        
            valid = spacialFilter(polyPos, realy, realx);
            for i = 1:length(fres)
                if valid(i) == 1
                    wgt = yy(i, :);
                    [wgtv, wgtp] = find(wgt == max(wgt));
    %                 wgt(max(1, wgtp - 2):min(length(yy), wgtp + 2)) = min(wgt);
    %                 if max(wgt(max(1, wgtp - floor(length(wgt) / 20)):min(length(wgt), wgtp + floor(length(wgt) / 20)))) > 0.5 * max(yy(i, :))
                        wgc = [wgc; freqs(wgtp)];
                        wgx = [wgx; (freqs - min(freqs) * ones(1, length(freqs))) * 1e3];
                        wgy = [wgy; yy(i, :)];
                        wgym = [wgym; max(yy(i, :))];
                        wgpx = [wgpx; realy(i)];
                        wgpy = [wgpy; realx(i)];
    %                 end
        
                end
        
            end
            if length(wgpx) == 0
                warning("No emitter found! Please trun down `mincount`.");
                return;
            end
            markerlist = ['o'; '>'; '<'; '+'; 'x'; 's'; 'd'; '^'; 'v'; 'p'; 'h'; '*'; '_'; '|'];
            markerlist2 = ['-o'; '->'; '-<'; '-+'; '-x'; '-s'; '-d'; '-^'; '-v'; '-p'; '-h'; '-*'; ];
            c = [1 0 0; 1 0.5 0; 1 1 0; 0.5 1 0; 0 1 0; 0 1 1; 0 0.5 1; 0 0 1; 0.5 0 1; 1 0 1];
            figureHandles = cell(length(wgpx), 3);
            if length(wgpx) >= 40                
                for i = 1:39
                    hold(obj.spectrum1AxH, 'on');
                    figureHandles{i, 2} = plot(obj.spectrum1AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end

                hold(obj.spectrum1AxH, 'off');
                box(obj.spectrum1AxH, 'on');
                ylim(obj.spectrum1AxH, [1, 41]);
                xlim(obj.spectrum1AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
                for i = 40:length(wgpx)
                    hold(obj.spectrum2AxH, 'on');
                    
                    figureHandles{i, 2} = plot(obj.spectrum2AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end
        
                hold(obj.spectrum2AxH, 'off');
                box(obj.spectrum2AxH, 'on');
                ylim(obj.spectrum2AxH, [40 length(wgpx)+1])
                xlim(obj.spectrum2AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                %     ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            else
                %  wgpx_max = max(wgpx, 1);
                for i = 1:length(wgpx)
                    hold(obj.spectrum1AxH, 'on');
                    % wgx_relative =wgx(i,:)-wgpx_max(1) ;
                    figureHandles{i, 2} = plot(obj.spectrum1AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end
        

                hold(obj.spectrum1AxH, 'off');
                box(obj.spectrum1AxH, 'on');
                ylim(obj.spectrum1AxH, [1, length(wgpx)+1])
                xlim(obj.spectrum1AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
        
            end
            
            img = squeeze(max(filteredImgs, [], 3));
            obj.wlImH = imagesc(obj.wlAxH, wlImg);
            colormap('bone')
            xlim(obj.wlAxH, [1, size(wlImg, 2)]);
            ylim(obj.wlAxH, [1, size(wlImg, 1)]);
            % xticks([])
            % yticks([])
            %     image(ax, hsv2rgb(H, V, V))
            % for i=1: length(fres)
            %     hold on
            %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
            %         scatter(realy(i+12*0),realx(i+12*0),30,c(length(fres)+1-i,:),'Linewidth',2)
            %     end
            % end
        
            sizeData = zeros(1, length((wgpx)));
            for i = 1:length(wgpx)
        
                sizeData(i) = (wgym(i)-obj.mincount)/(max(wgym)-obj.mincount)*100+30;
                hold(obj.wlAxH, 'on');
                %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
                %         scatter(wgpx(i),wgpy(i),30, c(1+(i-floor(i/10)*10),:),markerlist(1+floor(i/10)),'Linewidth',2)
                figureHandles{i, 1} = scatter(obj.wlAxH, wgpx(i), wgpy(i), sizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
                %     end
            end
        
        
            hold off
        
            xticks([])
            yticks([])
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            for i = 1:length(wgpx)
                hold(obj.countAxH, 'on')
                figureHandles{i, 3} = scatter(obj.countAxH, wgc(i), wgym(i), sizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
                %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                %     set(t1,'Color',[0 0 0]);
                if (i / 10 - floor(i / 10)) == 0
                    line([wgc(i) wgc(i)], [obj.mincount 6.5e4], 'Color', 'k', 'LineStyle', '--');
                end
            end
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            xlabel('Frequency (THz)')
            ylabel('Pixel count')
            box on
            title('EMCCD Gain:1200, Expose Time:500ms, Pixel:16um*16um')
            yticks([3e4, 6e4]);
            ylim([obj.mincount 6.5e4]);
            hold off
        
            set(obj.countAxH, 'Position', [0.35 0.1 0.4 0.15])
        
            % set(s1, 'Position', [0.08 0.38 0.58 0.58])
            set(obj.wlAxH, 'Position', [0.35 0.35 0.4 0.6])
        
            if length(wgpy) >= 40
                set(obj.spectrum2AxH, 'Position', [0.9 0.1 0.08 0.85]);
                set(obj.spectrum1AxH, 'Position', [0.8 0.1 0.08 0.85]);
            else
                set(obj.spectrum1AxH, 'Position', [0.8 0.1 0.15 0.85]);
                set(obj.spectrum2AxH, 'Visible', 'off');
            end
        
            set(obj.figH, 'position', [100, 100, 1600, 800])
            fprintf("time5: %f\n", toc(t));

        end
        function drawAll(obj)
            if isempty(obj.allFigH) || ~isvalid(obj.allFigH)
                obj.allFigH = figure;
                obj.allAxH = axes(obj.allFigH);
            end
            figure(obj.allFigH);
            if isempty(obj.allAxH) || ~isvalid(obj.allAxH)
                obj.allAxH = axes(obj.allFigH);
            end

            % Draw all image
            wl_example = obj.data{1, 1}.widefieldData(1).wl_img;
            allIm = zeros(size(wl_example).*[obj.ymax-obj.ymin+1, obj.xmax-obj.xmin+1]);
            trimXmin = obj.data{1, 1}.widefieldData(1).segment.xmin;
            trimXmax = trimXmin + size(wl_example, 2) - 1;
            trimYmin = obj.data{1, 1}.widefieldData(1).segment.ymin;
            trimYmax = trimYmin + size(wl_example, 1) - 1;
            wlX = size(wl_example, 2);
            wlY = size(wl_example, 1);
            
            nValidData = 0;
            for k = 1:size(obj.coords, 1)
                coord = obj.coords(k, :);
                tempX = coord(1);
                tempY = coord(2);
                if tempX < obj.xmin || tempX > obj.xmax || tempY < obj.ymin || tempY > obj.ymax
                    continue
                end
                % nValidData = nValidData + 1;
                allIm((tempY-obj.ymin)*wlY+1:(tempY-obj.ymin+1)*wlY, (tempX-obj.xmin)*wlX + 1:(tempX-obj.xmin+1)*wlX) = obj.data{tempX-obj.xmin+1, tempY-obj.ymin+1}.wl(trimYmin:trimYmax, trimXmin:trimXmax);
            end
            obj.allImH = imagesc(obj.allAxH, allIm);
            obj.allAxH.Position = [0.1, 0.4, 0.8, 0.55];
            obj.allAxH.XTick = [];
            obj.allAxH.YTick = [];
            % obj.allAxH.XTickLabel = [obj.xmin:obj.xmax];
            % obj.allAxH.XTick = linspace(wlX/2, size(allIm, 2)-wlX/2, obj.xmax-obj.xmin+1);
            % obj.allAxH.YTickLabel = [obj.xmin:obj.xmax];
            % obj.allAxH.YTick = linspace(wlY/2, size(allIm, 1)-wlY/2, obj.ymax-obj.ymin+1);
            % set(get(obj.allAxH, 'XLabel'), 'String', 'x');
            % set(get(obj.allAxH, 'YLabel'), 'String', 'y');
            set(obj.allAxH, 'FontSize', 16, 'FontName', 'Times New Roman')

            colormap(obj.allAxH, 'bone');
            % obj.allImH.ButtonDownFcn = @obj.selectCoord;
            hold(obj.allAxH, 'on');
            % rectangle(obj.allAxH, 'Position', [(obj.x-obj.xmin)*wlX + 1, (obj.y-obj.ymin)*wlY+1, wlX-1, wlY-1], 'LineWidth', 5, 'EdgeColor', 'r');
            % obj.allFigH.KeyPressFcn = @obj.moveCoord;
            obj.allFigH.DeleteFcn = @obj.deleteAllFigH;


            % Draw gds file figure
            files = dir(obj.srcDir);
            obj.gdsData = [];
            for k = 1:length(files)
                file = files(k);
                if endsWith(file.name, '.png') && contains(lower(file.name), 'gds')
                    obj.gdsData = imread(fullfile(obj.srcDir, file.name));
                    break
                end
            end
            assert(~isempty(obj.gdsData), "GDS Data is empty. Please copy gds file screenshot (gds.png) into working directory.");
            if ~isempty(obj.gdsAxH) && isvalid(obj.gdsAxH)
                delete(obj.gdsAxH);
            end
            obj.gdsAxH = axes(obj.allFigH);
            obj.gdsImH = imagesc(obj.gdsAxH, rot90(obj.gdsData, 2));

            gdsX = size(obj.gdsData, 2)/(obj.xmax-obj.xmin+1);
            gdsY = size(obj.gdsData, 1)/(obj.ymax-obj.ymin+1);

            obj.gdsAxH.XTick = linspace(1, size(obj.gdsData, 2), 7);
            obj.gdsAxH.XTickLabel = [0:50:300];
            obj.gdsAxH.XLabel.String = "x (\mum)";
            obj.gdsAxH.YTick = linspace(1, size(obj.gdsData, 1), 4);
            obj.gdsAxH.YTickLabel = [0:50:500];
            obj.gdsAxH.YLabel.String = "y (\mum)";

            obj.gdsAxH.Position = [0.55, 0.05, 0.35, 0.3];
            obj.gdsAxH.FontSize = 16;


            % Draw joint count-frequency figure
            for k = 1:length(obj.jointCountAxH(:))
                ax = obj.jointCountAxH{k};
                if ~isempty(ax) && isvalid(ax)
                    ax.delete;
                end
            end
            
            obj.jointCountAxH = cell((obj.xmax-obj.xmin+1), (obj.ymax-obj.ymin+1));
            
            nChiplets = (obj.xmax-obj.xmin+1)*(obj.ymax-obj.ymin+1);

            height = 0.3/nChiplets;
            obj.chipletColors = jet(nChiplets);
            for x = obj.xmin:obj.xmax
                for y = obj.ymin:obj.ymax
                    if isempty(obj.data{x-obj.xmin+1, y-obj.ymin+1})
                        continue;
                    end
                    newAx = axes(obj.allFigH);
                    wlOffset_xy = [wlX*(x-obj.xmin), wlY*(y-obj.ymin)] - [trimXmin-obj.data{x-obj.xmin+1, y-obj.ymin+1}.widefieldData(1).segment.xmin, trimYmin-obj.data{x-obj.xmin+1, y-obj.ymin+1}.widefieldData(1).segment.ymin];
                    obj.drawChiplet(x, y, newAx, obj.allAxH, wlOffset_xy, obj.chipletWiseAxH, obj.locationWiseAxH);
                    k = (y-obj.ymin)*(obj.xmax-obj.xmin+1)+(x-obj.xmin);
                    newAx.Position = [0.05, 0.05+(k)*height, 0.45, height];
                newAx.FontSize = 16;
                    newAx.XLim = [484.13, 484.16];
                    if k == 0
                        newAx.XLabel.String = 'Frequency (THz)';
                        newAx.XTick = [484.13, 484.14, 484.15, 484.16];
                        newAx.YTick = [];
                        newAx.YTickLabel = [];
                    else
                        newAx.XLabel = [];
                        newAx.XTick = [];
                        newAx.XTickLabel = [];
                        newAx.YTick = [];
                        newAx.YTickLabel = [];
                    end
                    newAx.YLabel.String = sprintf("%d", k+1);
                    newAx.YLabel.Rotation = 0;
                    newAx.YLabel.Color = 'black';
                    text(obj.allAxH, wlX*(x-obj.xmin+1)-30, wlY*(y-obj.ymin+1)-10, sprintf("%d", k+1), 'Color', 'white', 'FontSize', 16, 'FontName', 'Times New Roman');
                    text(obj.gdsAxH, gdsX*(x-obj.xmin+1)-60, gdsY*(y-obj.ymin+1)-15, sprintf("%d", k+1), 'Color', 'black', 'FontSize', 16, 'FontName', 'Times New Roman')
                    box(newAx, 'on');            
                    obj.jointCountAxH{x-obj.xmin+1, y-obj.ymin+1} = newAx;
                end
            end


            set(obj.allFigH, 'position', [100, 100, 1200, 1200])

        end


        function deleteAllFigH(obj,hObj,event)
            obj.allFigH.delete;
        end
        function drawChiplet(obj, chipletX, chipletY, countAxH, wlAxH, wlOffset_xy, chipletWiseAxH, locationWiseAxH)
            data = obj.data{chipletX-obj.xmin+1, chipletY-obj.ymin+1};
            assert(~isempty(data), sprintf("Data of chiplet (x:%d, y:%d) is empty. Please reload the data.", chipletX, chipletY))
            nDataSet = length(data.widefieldData); % Number of datasets of the current chiplet
            ROIsize = size(data.widefieldData(1).wl_img);
            wlImg = data.widefieldData(1).wl_img;
            filteredImgs = zeros(ROIsize(1), ROIsize(2), 0);
            freqs = zeros(1, 0);
            for k = 1:nDataSet
                tempFilteredImgs = data.widefieldData(k).filtered_imgs;
                nFrames = size(tempFilteredImgs, 3);
                freqs(end+1:end+nFrames) = data.widefieldData(k).freqs;
                filteredImgs(:, :, end+1:end+nFrames) = tempFilteredImgs;
            end
            polyPos = data.widefieldData(1).poly_pos;

            % Initialize record variables
            labels = [];
            wgc = [];
            wgw = [];
            wgx = [];
            wgy = [];
            wgpx = [];
            wgpy = [];
            wgym = [];
            allpts0 = reshape(filteredImgs, [numel(wlImg), length(freqs)]);
            allpts0(max(allpts0, [], 2) < obj.mincount, :) = [];
            p0 = zeros(5, length(allpts0(:, 1)));
            [p0(5, :), p0(3, :)] = find(allpts0 == max(allpts0, [], 2));
            for i = 1:length(allpts0(:, 1))
                p0(4, i) = allpts0(p0(5, i), p0(3, i));
                [a, b] = find(filteredImgs(:, :, p0(3, i)) == p0(4, i));
                p0(1, i) = a(1);
                p0(2, i) = b(1);
            end
            a1 = 1;
            fres = unique(p0(3, :));
            realx = zeros(1, length(fres));
            realy = zeros(1, length(fres));
            reali = zeros(1, length(fres));
            reala = zeros(1, length(fres));
            realf = zeros(1, length(fres));
            realpoints = zeros(5, length(fres));
            sloc = zeros(1, length(fres));
            swid = zeros(1, length(fres));
        
            for i = 1:length(fres)
                pmax = 0;
                ptx = [];
                pty = [];
                for j = 1:length(allpts0(:, 1))
                    if p0(3, j) == fres(i)
                        pmax = max(pmax, p0(4, j));
                        ptx = [ptx; p0(1, j)];
                        pty = [pty; p0(2, j)];
                    end
                end
                xi = find(p0(4, :) == pmax);
                xi = xi(1);
        
                realx(i) = p0(1, xi);
                realy(i) = p0(2, xi);
                reali(i) = p0(5, xi);
                reala(i) = p0(4, xi);
                realf(i) = p0(3, xi);
                %     realpoints(i)=p0(:,xi);
            end
            a1;
            c = jet(length(fres));
        
            yy = allpts0(reali, :);
        
            % valid = spacialFilter(polyPos, realy, realx);
            valid = ones(1, length(fres));
            for i = 1:length(fres)
                if valid(i) == 1
                    wgt = yy(i, :);
                    [wgtv, wgtp] = find(wgt == max(wgt));
    %                 wgt(max(1, wgtp - 2):min(length(yy), wgtp + 2)) = min(wgt);
    %                 if max(wgt(max(1, wgtp - floor(length(wgt) / 20)):min(length(wgt), wgtp + floor(length(wgt) / 20)))) > 0.5 * max(yy(i, :))
                        wgc = [wgc; freqs(wgtp)];
                        wgx = [wgx; (freqs - min(freqs) * ones(1, length(freqs))) * 1e3];
                        wgy = [wgy; yy(i, :)];
                        wgym = [wgym; max(yy(i, :))];
                        wgpx = [wgpx; realy(i)];
                        wgpy = [wgpy; realx(i)];
    %                 end
        
                end
        
            end
            if length(wgpx) == 0
                warning("No emitter found! Please trun down `mincount`.");
                return;
            end
            markerlist = ['o'; '>'; '<'; '+'; 'x'; 's'; 'd'; '^'; 'v'; 'p'; 'h'; '*'; '_'; '|'];
            markerlist2 = ['-o'; '->'; '-<'; '-+'; '-x'; '-s'; '-d'; '-^'; '-v'; '-p'; '-h'; '-*'; ];
            c = [1 0 0; 1 0.5 0; 1 1 0; 0.5 1 0; 0 1 0; 0 1 1; 0 0.5 1; 0 0 1; 0.5 0 1; 1 0 1];
            figureHandles = cell(length(wgpx), 3);  
            for i = 1:length(wgpx)
                sizeData(i) = (wgym(i)-obj.mincount)/(max(wgym)-obj.mincount)*100+30;
                hold(wlAxH, 'on');
                figureHandles{i, 1} = scatter(wlAxH, wgpx(i)+wlOffset_xy(1), wgpy(i)+wlOffset_xy(2), sizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
            end
            hold off

            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            for i = 1:length(wgpx)
                hold(countAxH, 'on')
                figureHandles{i, 3} = scatter(countAxH, wgc(i), wgym(i), 30, c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
            end
            hold off
            % scatter()
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


function distance = getPointLineDistance(x3,y3,x1,y1,x2,y2)
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
    dist1 = norm([x3, y3]-[x1, y1]);
    dist2 = norm([x3, y3]-[x2, y2]);
    dist3 = norm([x2, y2]-[x1, y1]);
    if dist2^2 > dist1^2+dist3^2 || dist1^2 > dist2^2+dist3^2
        distance = min(dist1, dist2);
    end
    
    return; % from getPointLineDistance()
end