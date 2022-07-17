function validSites = doSpectrum(obj, status, managers)
    Nsites = size(obj.sites.positions, 1);
    Nexperiments = length(obj.experiments);
    obj.specData = cell(1, Nsites);
    obj.meta = cell(Nexperiments, Nsites);
    obj.currentExperiment = obj.experiments(1);


    if ~obj.skipSpectrum
        managers.Path.select_path('spectrometer');
        try close(10); catch; end
        try close(11); catch; end
        temp_fig = figure(10);
        temp_fig.Name = 'Experiment Result';
        temp_fig.NumberTitle = 'off';
        temp_fig.Position = [1800, 200, 560, 420];
        sum_fig = figure(11);
        sum_fig.Name = 'Accumulative Experiment Result';
        sum_fig.NumberTitle = 'off';
        sum_fig.Position = [1800, 800, 560, 420];


        cmap = distinguishable_colors(Nsites);
        temp_ax = axes('Parent', temp_fig);   
        for k = 1:Nsites
            % if strcmp(obj.method, 'Spectrum')
            h = obj.exp_imH.UserData.h(k);
            h.Color = [1, 1, 1];
            assert(~obj.abort_request, "User abort");
            obj.gotoSite(k);
            obj.currentExperiment.run(status, managers, temp_ax);
            temp_line = temp_ax.Children(1);
            set(get(temp_ax, 'Title'), 'String', sprintf('Spectrum of site %d', k));
            temp_line.Color = cmap(k, :);
            if k == 1
                sum_ax = copyobj(temp_ax, sum_fig);
                sum_line = sum_ax.Children(1);
            else
                sum_line(k) = copyobj(temp_line, sum_ax);
            end
            set(get(sum_ax, 'Title'), 'String', sprintf('Spectrum of sites %d~%d', 1, k));
            h.Color = cmap(k, :);
            obj.specData{k} = obj.currentExperiment.GetData;
        end
    else
        assert(isfield(obj.sites, 'spectrum') && length(obj.sites.spectrum) == Nsites, "Number of spectrum results in current memory is incorrect while skipping acquiring spectrum.");
        obj.specData = obj.sites.spectrum;
    end

    try close(12); catch; end
    result_fig = figure(12);
    result_fig.Name = 'Processed Result';
    result_fig.NumberTitle = 'off';
    result_fig.Position = [500, 100, 1200, 1200];
    

    result = spectrumDataAnalysis(obj.specData, obj.specThres);
    ax = axes('Parent', result_fig);    
    n = sum(result.hasPeak);
    cmap = distinguishable_colors(n);
    validIdx = find(result.hasPeak);
    for k = 1:n
        hold(ax, 'on');
        plot(ax, obj.specData{validIdx(k)}.wavelength, obj.specData{validIdx(k)}.intensity, 'Color', cmap(k, :));
    end
    set(get(ax, 'XLabel'), 'String', 'Wavelength (nm)');
    set(get(ax, 'YLabel'), 'String', 'Intensity (a.u.)');
    set(get(ax, 'Title'), 'String', sprintf('Processed spectrum of sites %d~%d', 1, n));
    l = 0;
    validSites = struct;
    validSites.positions = zeros(n, 3);
    validSites.APDCount = zeros(1, n);
    validSites.spectrum = cell(1, n);
    validSites.freqs_THz = zeros(1, n);
    validSites.wavelengths_nm = zeros(1, n); % TODO: should be the peak value of spectrum;
    for k = 1:Nsites
        h = obj.exp_imH.UserData.h(k);
        if ~result.hasPeak(k)
            h.Visible = 'off';
        else
            l = l+1;
            h.Color = cmap(l, :);
            validSites.positions(l, :) = obj.sites.positions(k, :);
            validSites.APDCount(l) = obj.sites.APDCount(k);
            validSites.spectrum{l} = obj.specData{k};
            [maxval, maxpos] = max(obj.specData{k}.intensity);
            validSites.wavelength_nm(l) = obj.specData{k}.wavelength(maxpos);
            validSites.freqs_THz(l) = 3e5/obj.specData{k}.wavelength(maxpos);
        end
    end
    validSites.method = 'Spectrum';
    if isprop(obj.sites, 'meta')
    validSites.meta = obj.sites.meta;
    end
    validSites.image = obj.sites.image;
    save('spectrum_valid_sites.mat', 'validSites');

end