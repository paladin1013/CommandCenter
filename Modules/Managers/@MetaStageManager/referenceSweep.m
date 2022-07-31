function result = referenceSweep(obj, sweepAxes, sweepPoints, observeAxes, plotResult, sampleNum, sampleInterval_s)
    % sweepPoints: should be a {1*Nsweep} cell array, each cell element contains a list with all sweeping points.
    % result: {val, st} (st stands for standard variation)
    user_abort = false;
    boxH = abortBox(@(~,~)abort);
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
        end
        points = sweepPoints{1};
        pointNum = length(points);
        result = struct('val', zeros(pointNum, Nobserve), 'st', zeros(pointNum, Nobserve));
        for k = 1:pointNum
            if user_abort
                fprintf("User aborted.\n");
                break;
            end
            val = points(k);
            sweepRefs(1).writ(val);
            if k == 1
                pause(sampleInterval_s*sampleNum);
                for l = 1:Nobserve
                    tempResult = zeros(1, sampleNum);
                    for m = 1:sampleNum
                        pause(sampleInterval_s);
                        tempResult(m) = observeRefs(l).read;
                    end
                    result.val(k, l) = mean(tempResult);
                    result.st(k, l) = std(tempResult);
                end
            end
            for l = 1:Nobserve
                tempResult = zeros(1, sampleNum);
                for m = 1:sampleNum
                    pause(sampleInterval_s);
                    tempResult(m) = observeRefs(l).read;
                end
                result.val(k, l) = mean(tempResult);
                result.st(k, l) = std(tempResult);
            end
            if plotResult
                updatePlot(points, result, k)
            end
        end
    end
    if isvalid(boxH)
        delete(boxH);
    end
    function abort()
        user_abort = true;
        delete(boxH);
    end
    
    function updatePlot(points, result, pointNum)
        Nobserve = size(result.val, 2);
        plotH = cell(1, Nobserve);
        colors = lines(Nobserve);
        figure(20);
        for idx = 1:Nobserve
            ax = subplot(Nobserve, 1, idx);
            plotH{idx} = errorfill(points(1:pointNum),result.val(1:pointNum, idx)',result.st(1:pointNum, idx)','parent',ax, 'color', colors(idx, :));
            set(get(ax, 'XLabel'), 'String', sweepRefs(1).reference.name);
            set(get(ax, 'YLabel'), 'String', observeRefs(idx).reference.name);
        end
    end

end


function boxH = abortBox(abort_callback)
    boxH = msgbox('Reference sweep started');
    boxH.KeyPressFcn='';  % Prevent esc from closing window
    boxH.CloseRequestFcn = abort_callback;
    % Repurpose the OKButton
    button = findall(boxH,'tag','OKButton');
    set(button,'tag','AbortButton','string','Abort',...
        'callback',abort_callback)
end