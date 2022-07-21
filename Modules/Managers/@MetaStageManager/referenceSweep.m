function result = referenceSweep(obj, sweepAxes, sweepPoints, observeAxes, plotResult, sampleNum, sampleInterval_s)
    % sweepPoints: should be a {1*Nsweep} cell array, each cell element contains a list with all sweeping points.
    % result: {val, st} (st stands for standard variation)
    Nsweep = length(sweepAxes);
    Nobserve = length(observeAxes);

    assert(Nsweep >= 1, "At least one sweep axis.");
    assert(Nobserve >= 1, "At least one observe axis.");
    if ~exist('plotResult', 'var')
        plotResult = true;
    end
    if ~exist('sampleNum', 'var')
        sampleNum = obj.active_module.sample_num;
    end
    if ~exist('delay', 'var')
        sampleInterval_s = obj.active_module.sample_interval;
    end
    assert(all(size(sweepPoints) == [1, Nsweep]), sprintf("sweepRanges should be a {1*%d} cell array, but got %d*%d instead.", Nsweep, size(sweepPoints, 1), size(sweepPoints, 2)))
    assert(sampleNum >= 1 && ceil(sampleNum) == sampleNum, "sampleNum should be an interger larger than 1");
    assert(sampleInterval_s > 0, "sampleInterval should be a double value larger than 0.");

    allAxes = ["X", "Y", "Z", "Target"];
    sweepRefs = Prefs.Reference.empty(0, 1);
    observeRefs = Prefs.Reference.empty(0, 1);
    ms = obj.active_module;
    for k = 1:Nsweep
        axis_name = sweepAxes(k);
        assert(any(strcmp(axis_name, allAxes)), sprintf("sweepAxes(%d):'%s' does not belong to ['X', 'Y', 'Z', 'Target'].", k, axis_name));
        sweepRefs(k) = ms.get_meta_pref(axis_name);
    end
    for k = 1:Nobserve
        axis_name = observeAxes(k);
        assert(any(strcmp(axis_name, allAxes)), sprintf("observeAxes(%d):'%s' does not belong to ['X', 'Y', 'Z', 'Target'].", k, axis_name));
        assert(~any(strcmp(axis_name, sweepAxes)), sprintf("observeAxes should not overlap with sweepAxes"));
        observeRefs(k) = ms.get_meta_pref(axis_name);
        if strcmp(observeRefs(k).reference.name, 'count')
            counter = observeRefs(k).reference.parent;
            running = counter.running;
            if ~running
                counter.start;
            end
        end
    end
    

    if Nsweep == 1
        if plotResult
            try close(20); catch; end
            fig = figure(20);
            fig.NumberTitle = 'off';
            fig.Name = 'Reference sweep result';
            ax = axes('Parent', fig); 
        end
        points = sweepPoints{1};
        pointNum = length(points);
        result = struct('val', zeros(pointNum, Nobserve), 'st', zeros(pointNum, Nobserve));
        for k = 1:pointNum
            val = points(k);
            sweepRefs(1).writ(val);
            for l = 1:Nobserve
                tempResult = zeros(1, sampleNum);
                for m = 1:sampleNum
                    pause(sampleInterval_s);
                    tempResult(m) = observeRefs(l).read;
                end
                result.val(k, l) = mean(tempResult);
                result.st(k, l) = std(tempResult);
            end
            updatePlot(points, result, k, ax)
        end
    end
end

function updatePlot(points, result, pointNum, ax)
    while ~isempty(ax.Children)
        ax.Children(1).delete;
    end
    Nobserve = size(result.val, 2);
    plotH = cell(1, Nobserve);
    colors = lines(Nobserve);
    for l = 1:Nobserve
        plotH{l} = errorfill(points(1:pointNum),result.val(1:pointNum, l)',result.st(1:pointNum, l)','parent',ax, 'color', colors(l, :));
    end
end