
function initialize(obj, status, managers, ax)
    obj.msmH = managers.MetaStage;



    if isempty(obj.sites) || ~obj.useSitesMemory
        try
            data = load(obj.dataDir + "/" + obj.sitesDataPath);
            if isfield(data, 'sites')
                data = data.sites;
                if isfield(data, 'sites')
                    data = data.sites;
                end
            end
            if isfield(data, 'validSites')
                data = data.validSites;
            end

            loadSuccess = true;
        catch
            loadSuccess = false;
        end
        if obj.importSitesData && loadSuccess
            obj.sites = data;
        else
            obj.acquireSites(managers);
        end
    end

    if isempty(managers.Imaging.current_image)
        source_on = obj.imaging_source.source_on;
        obj.imaging_source.on;
        obj.imaging_source.power = 80;
        managers.Path.select_path('APD1'); %this may be unnecessary
        obj.sites.image = managers.Imaging.snap; %take image snapshot
        if ~source_on
            obj.imaging_source.off;
        end
    else
        obj.sites.image = managers.Imaging.current_image.info;
    end
    
    sites = obj.sites;
    c = fix(clock);
    save(obj.dataDir + "/" + sprintf("initialized1_%d_%d_%d_%d_%d.mat", c(2), c(3), c(4), c(5), c(6)), 'sites');

    % By now, sites absolute position should be stored in obj.sites

    % Draw all sites in image
    fig = ax.Parent;
    im = imagesc(ax, obj.sites.image);
    obj.exp_imH = im;
    N = size(obj.sites.positions, 1);

    xabs = obj.sites.positions(:, 1);
    yabs = obj.sites.positions(:, 2);
    markerSize = ones(N, 1)*0.1*min(fig.Position(3), fig.Position(4));
    if strcmp(obj.method, 'EMCCD')
        freqs_THz = obj.sites.freqs_THz;
        freq_max = max(freqs_THz);
        freq_min = min(freqs_THz);
        cmap = jet(256);
        colors = cmap(floor((freqs_THz-freq_min)*255/(freq_max-freq_min)+1), :);
    end
    for k = 1:N
        if strcmp(obj.method, 'EMCCD')
            h = drawpoint(ax, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)*100, 'Color', colors(k, :));
            h.UserData = freqs_THz(k);
        else
            h = drawpoint(ax, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)*100, 'Color', [0, 0, 1]);
        end
        if isempty(im.UserData) || isempty(im.UserData.h)
            im.UserData = struct();
            im.UserData.h = h;
        else
            im.UserData.h(end+1) = h;
        end
    end

    ms = managers.MetaStage.active_module; % MetaStage instance
    ms.sample_num = obj.sampleNum;
    
    X = ms.get_meta_pref('X');
    Y = ms.get_meta_pref('Y');
    ni = Drivers.NIDAQ.dev.instance('dev1');

    if ~strcmp(X.reference.name, 'X')
        X.set_reference(ni.getLines('X', 'out').get_meta_pref);
    end
    if ~strcmp(Y.reference.name, 'Y')
        Y.set_reference(ni.getLines('Y', 'out').get_meta_pref);
    end

    
    Z = ms.get_meta_pref('Z');
    Target = ms.get_meta_pref('Target');
    counter = Drivers.Counter.instance('APD1', 'CounterSync');
    if ~strcmp(Target.reference.name, 'count')
        Target.set_reference(counter.get_meta_pref('count'));
    end
    if ~strcmp(Z.reference.name, 'count')
        Z.set_reference(counter.get_meta_pref('count')); % Set to an arbitrary readonly preference to ignore when optimizing
    end
    % obj.sites.APDCount = zeros(N, 1);
    counter = Drivers.Counter.instance('APD1', 'CounterSync');
    if ~counter.running
        counter.start;
    end

    if obj.optimizePos
        if obj.sampleNum < 5
            warning("obj.sampleNum for optimization should be at least 5. Set obj.sampleNum to 5.");
            obj.sampleNum = 5;
        end
        prev_key_step_x = ms.key_step_x;
        prev_key_step_y = ms.key_step_y;
        ms.key_step_x = 0.0005;
        ms.key_step_y = 0.0005;
        for k = 1:N
            assert(~obj.abort_request, 'User aborted');
            status.String = sprintf("Locating site %d/%d\n", k, N);
            h = im.UserData.h(k);
            h.Color = [1, 0, 0];
            newAbsPos = obj.locateSite(obj.sites.positions(k, 1:2));

            obj.sites.positions(k, 1:2) = newAbsPos;
            [count, st] = Target.get_avg_val(obj.sampleNum);
            obj.sites.APDCount(k) = count;
            h.Position = newAbsPos;
            if strcmp(obj.method, 'EMCCD')
                h.Color = colors(k, :);
            else
                h.Color = [0, 1, 0];
            end
            h.MarkerSize = min(fig.Position(3), fig.Position(4))*10*(count/10000);
            h.Label = sprintf("  %d", k);
        end
        ms.key_step_x = prev_key_step_x;
        ms.key_step_y = prev_key_step_y;
    else
        
        
        % Get apd count directly
        for k = 1:N
            assert(~obj.abort_request, 'User aborted');
            if obj.sampleNum == 0 
                try
                    count = obj.sites.APDCount(k);
                    assert(count > 0, "APDCount should be a positive number.")
                catch
                    warning("Sample count unavailable. Set obj.sampleNum to 1.")
                    obj.sampleNum = 1;
                end
            end
            
            if obj.sampleNum > 0
                obj.gotoSite(k);
                [count, st] = Target.get_avg_val(obj.sampleNum, 1);
            end
            obj.sites.APDCount(k) = count;
            h = obj.exp_imH.UserData.h(k);
            if strcmp(obj.method, 'EMCCD')
                h.Color = colors(k, :);
            else
                h.Color = [0, 1, 0];
            end
            h.MarkerSize = min(fig.Position(3), fig.Position(4))*10*(count/10000);
            h.Label = sprintf("  %d", k);
        end
    end
    
    if obj.sortByAPD
        sites = obj.sites;
        [obj.sites.APDCount, sitesIdx] = sort(sites.APDCount, 'descend');
        obj.sites.positions = sites.positions(sitesIdx, :);
        validNum = sum(sites.APDCount>obj.apdThres);
        obj.sites.APDCount = obj.sites.APDCount(1:validNum);
        obj.sites.positions = obj.sites.positions(1:validNum, :);
        if strcmp(obj.method, 'EMCCD')
            obj.sites.freqs_THz = sites.freqs_THz(sitesIdx);
            obj.sites.freqs_THz = obj.sites.freqs_THz(1:validNum);

            if isfield(sites, 'wavelengths_nm') && length(sites.wavelengths_nm) == N
                obj.sites.wavelengths_nm = sites.wavelengths_nm(sitesIdx);
                obj.sites.wavelengths_nm = obj.sites.wavelengths_nm(1:validNum);
            end
        end
        obj.exp_imH.UserData.h = obj.exp_imH.UserData.h(sitesIdx);
        for k = 1:validNum
            obj.exp_imH.UserData.h(k).Label = sprintf("  %d", k);
        end
        for k = validNum+1:N
            obj.exp_imH.UserData.h(k).delete;
        end
        obj.exp_imH.UserData.h = obj.exp_imH.UserData.h(1:validNum);
    end
    assert(~obj.abort_request, "User abort");
    sites = obj.sites;
    c = fix(clock);
    save(obj.dataDir + "/" + sprintf("initialized2_%d_%d_%d_%d_%d.mat", c(2), c(3), c(4), c(5), c(6)), 'sites');

end