function run(obj,status,managers,ax)
    obj.exp_axH = ax;
    obj.abort_request = false;
    managers.Path.select_path('APD1');
    obj.initialize(status, managers, ax);

    Nsites = size(obj.sites.positions, 1);
    Nexperiments = length(obj.experiments);
    obj.data = cell(Nexperiments, Nsites);
    obj.meta = cell(Nexperiments, Nsites);


    obj.currentExperiment = obj.experiments(1);
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


    cmap = jet(Nsites);
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
        obj.data{1, k} = obj.currentExperiment.GetData;
    end

end