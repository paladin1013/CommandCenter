
function initialize(obj, status, managers, ax)
    obj.msmH = managers.MetaStage;
    if isempty(obj.sites)
        try
            data = load(obj.sitesDataPath);
            obj.sites = data.sites;
        catch err
            status.String = "Loading sites data failed. Start acquiring sites.";
            sites = obj.AcquireSites(managers);
            
            save(obj.sitesDataPath, 'sites');
        end
    end

    fig = ax.Parent;
    im = imagesc(ax, obj.sites.image);
    N = size(obj.sites.positions, 1);

    xabs = obj.sites.positions(:, 1);
    yabs = obj.sites.positions(:, 2);
    markerSize = ones(N, 1)*0.1*min(fig.Position(3), fig.Position(4));
    if obj.includeFreq
        freqs_THz = obj.sites.freqs_THz;
        freq_max = max(freqs_THz);
        freq_min = min(freqs_THz);
        cmap = jet(256);
        colors = cmap(floor((freqs_THz-freq_min)*255/(freq_max-freq_min)+1), :);
    end
    for k = 1:N
        if obj.includeFreq
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
    X = ms.get_meta_pref('X');
    Y = ms.get_meta_pref('Y');
    ni = Drivers.NIDAQ.dev.instance('dev1');
    X.set_reference(ni.getLines('X', 'out').get_meta_pref);
    Y.set_reference(ni.getLines('Y', 'out').get_meta_pref);

    
    Z = ms.get_meta_pref('Z');
    Target = ms.get_meta_pref('Target');
    counter = Drivers.Counter.instance('APD1', 'CounterSync');
    Target.set_reference(counter.get_meta_pref('count'));
    Z.set_reference(counter.get_meta_pref('count')); % Set to an arbitrary readonly preference to ignore when optimizing
    obj.sites.APDCount = zeros(N, 1);


    obj.sites.freqs_THz = zeros(N, 1);

    for k = 1:N
        
        status.String = sprintf("Locating site %d/%d\n", k, N);
        h = im.UserData.h(k);
        h.Color = [1, 0, 0];
        assert(~obj.abort_request, 'User aborted');
        [newAbsPos, newFreq] = obj.locateSite(managers.MetaStage, obj.sites.positions(k, 1:2), obj.sites.freqs_THz(k));
        newAbsPos = obj.sites.positions(k, 1:2);
        newFreq = obj.sites.freqs_THz(k);
        obj.sites.positions(k, 1:2) = newAbsPos;
        obj.sites.freqs_THz(k) = newFreq;
        count = Target.read;
        obj.sites.APDCount(k) = count;
        h.Position = newAbsPos;
        h.Color = [0, 1, 0];
        h.MarkerSize = min(fig.Position(3), fig.Position(4))*10*(count/10000);
        h.Label = sprintf("  %d", k);
    end
    sites = obj.sites;
    save(obj.sitesDataPath, 'sites');

end