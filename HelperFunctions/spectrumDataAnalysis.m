function result = spectrumDataAnalysis(data, thres)
    % data: cell(1, N), each item in data should has field {wavelength: M*1 double, intensity: M*1 double}
    % thres: double, determine 
    
    while isfield(data, 'data')
        data = data.data;
    end

    N = 0;
    for k = 1:length(data)
        if isempty(data{k})
            N = k;
            break;
        end
        if k == length(data)
            N = length(data);
        end
    end
    assert(N > 0, "No valid spectrum data!");
    data = data(1:N);
    intensityMin = zeros(1, N); % 10th minimum intensity of each site (to exclude noise)
    intensityMax = zeros(1, N); % 3rd maximum intensity of each site (to exclude noise)
    hasPeak = zeros(1, N); % Whether a site has a peak
    peakPos = zeros(1, N);
    FWHM = zeros(1, N); % Full width at half maximum. Stay 0 if this site has no peak


    for k = 1:N
        wavelength = data{k}.wavelength;
        intensity = data{k}.intensity;
        sortedIntensity = sort(intensity, 'ascend');
        intensityMin(k) = sortedIntensity(10);
        intensityMax(k) = sortedIntensity(end-2);
        hasPeak(k) = (intensityMax(k)-intensityMin(k)) > thres;
        if ~hasPeak(k)
            continue;
        end
    end
    result = struct('intensityMin', intensityMin, 'intensityMax', intensityMax, 'hasPeak', hasPeak, 'FWHM', FWHM, 'peakPos', peakPos);
end