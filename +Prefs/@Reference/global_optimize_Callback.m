function obj = global_optimize_Callback(obj, src, evt)
    ms = obj.parent; % MetaStage
    global optimizing; % How to let different callback functions share a same variable?

    function set_pos(test_pos)
        persistent prev_pos;
        if ~exist("prev_pos", "var") || isempty(prev_pos)
            prev_pos = start_pos; % To memorize the current position of an axis. If the position is not changed during iteration, there is no need to rewrite (which wastes time)
        end
        for m = 1:3
            if axis_available(m) == false || test_pos(m) == prev_pos(m)
                continue;
            end
            axis_reference{m}.writ(test_pos(m));
            prev_pos(m) = test_pos(m);
        end
    end

    function pos = get_pos()
        pos = NaN(1, 3);
        for m = 1:3
            if axis_available(m)
                pos(m) = axis_reference{m}.read;
            end
        end
    end
    if ~isstring(optimizing) && ~ischar(optimizing)
        optimizing = "";
    end
    if src.Value == true
        if optimizing ~= ""
            warning("Optimization on %s is already started. Please stop the running optimization to start a new one.", optimizing);
            src.Value = false;

        else % No optimization process has been started yet.
            optimizing = "Target";
            if strcmp(ms.get_meta_pref('Target').reference.name, 'count')
                counter = ms.get_meta_pref('Target').reference.parent;
                running = counter.running;
                if ~running
                    counter.start;
                end
            end

            % Record all avalable references
            
            axis_name = {'X', 'Y', 'Z'};
            axis_available = zeros(1, 3);
            axis_stop = ones(1, 3);
            axis_reference = cell(1, 3); % {Prefs.Reference()}
            axis_steponly = zeros(1, 3);
            axis_ref_name = cell(1, 3);

            base_step = zeros(1, 3);
            start_pos = NaN(1, 3);
            for k = 1:3
                mp = ms.get_meta_pref(axis_name{k});
                if ~isempty(mp.reference)
                    if isprop(mp.reference.parent, 'steponly') && mp.reference.parent.steponly
                        % Step-only preferences should not participate in global optimization. Optimization of step-only references should be done individually in the end of the procedure. 
                        axis_available(k) = 0;
                        axis_steponly(k) = 1;
                    else
                        axis_available(k) = 1;
                        axis_stop(k) = 0;
                        base_step(k) = ms.(sprintf("key_step_%s", lower(axis_name{k})));
                    end
                    axis_reference{k} = mp;
                    start_pos(k) = mp.read;
                    axis_ref_name{k} = mp.reference.name;
                end
            end
            step = base_step;
            obj.record_array = {};
            optimize_dim = sum(axis_available);
            
            [avg, st] = obj.get_avg_val;
            record = struct;
            record.pos = start_pos;
            record.val = avg;
            record.st = st;
            obj.record_array{end+1} = record;
            sweep_num = ms.sweep_num;

            % Do sweep along all avaliable axes
            for k = 1:3
                if axis_available(k) == false
                    continue
                end
                for l = -sweep_num:sweep_num
                    if l == 0
                        continue; % This origin point is aready tested
                    end
                    % Assign values
                    test_pos = start_pos;
                    test_pos(k) = test_pos(k) + 2*l*base_step(k);
                    set_pos(test_pos);

                    [avg, st] = obj.get_avg_val;

                    % Record results
                    record.pos = test_pos;
                    record.val = avg;
                    record.st = st;
                    obj.record_array{end+1} = record;
                end
            end

            % Find the maximum within the sweep results to be a starting point
            max_val = 0;
            for l = 1:length(obj.record_array)
                record = obj.record_array{l};
                if record.val >= max_val
                    max_pos = record.pos;
                    max_val = record.val;
                end
            end

            fixed_pos = max_pos;
            fixed_val = max_val;

            % Set the optimization range to [start_pos - max_range, start_pos + max_range]
            % The optimization will automatically stop once current value is out of range.
            max_range = 20*base_step; 
            max_iteration = 50;
            min_step = ms.min_step_ratio*base_step; % Optimization will stop if the current step is too short and there is no improvement.
            iteration_num = 0;
            direction_changed = zeros(1, 3);
            finish_ordinary_optimize = false;



            while(optimizing == obj.name && ~finish_ordinary_optimize)
                if all(axis_stop)
                    fprintf("No available axis to be optimized. Abort.\n");
                    finish_ordinary_optimize = true;
                    break;
                end
                % Use hill climbing to iteratively optimize all axes:
                % 1) Sweep along all available axes, to find a starting point
                % 2) Record `direction_changed` for all axes separately. 
                %   If one trial obtains larger target value, set fixed_pos to this point and clear all `direction_changed` flags. 
                %   Otherwise, flip the `direction_changed` flag if it is not set or shorten the step length for higher resolution.
                for k = 1:3
                    if axis_stop(k)
                        continue;
                    end
                    if abs(fixed_pos(k)+step(k)-start_pos(k))>max_range(k)
                        axis_stop(k) = true;
                        fprintf("Optimization position of %s running out of range. Disable this axis.\n");
                        continue;
                    end
                    test_pos = fixed_pos;
                    test_pos(k) = fixed_pos(k)+step(k);
                    set_pos(test_pos);
                    [avg, st] = obj.get_avg_val;
                    record.pos = test_pos;
                    record.val = avg;
                    record.st = st;
                    obj.record_array{end+1} = record;

                    diff = avg-fixed_val;
                    iteration_num = iteration_num + 1;
                    fprintf("Globally optimizing axis %s (%s) it:%d step:%.2e fixed_pos: %.2e fixed_val: %.2e test_pos: %.2e, try_val: %.2e.\n", axis_name{k}, axis_reference{k}.name, iteration_num, step(k), fixed_pos(k), fixed_val, test_pos(k), avg);
                    if diff > 0
                        direction_changed = zeros(1, 3); % Clear all flags
                        fixed_val = avg;
                        fixed_pos(k) = fixed_pos(k)+step(k);
                        % How to persistently optimize along this axis?
                    else
                        if direction_changed(k)
                            if abs(step(k)) >= min_step(k)
                                step(k) = step(k)/2;
                            end
                            if all(abs(step) <= min_step)
                                fprintf("All axes reaches local maximum. Abort.\n");
                                finish_ordinary_optimize = true;
                                break;
                            end
                            direction_changed(k) = false;
                        else
                            step(k) = -step(k);
                            direction_changed(k) = true;
                        end
                    end
                end % End for loop

            end % End while loop
            set_pos(fixed_pos);
            if ms.plot_record
                obj.plot_records(optimize_dim, axis_available, axis_ref_name);
            end
            if optimizing == obj.name
                % Optimize step-only references
                for k = 1:3
                    if axis_steponly(k)
                        mp = ms.get_meta_pref(axis_name{k});
                        src.Value = true;
                        optimizing = "";
                        mp.steponly_optimize_Callback(src);
                    end
                end
            end
            optimizing = "";
            src.Value = false;
        end
    else % src.Value == false
        if obj.name == optimizing
            optimizing = ""; % to end an optimization
            fprintf("Optimization of axis %s (%s) is interrupted.\n", obj.name, obj.reference.name);
        else % obj.name ~= optimizing, which should not happen if operated correctly
            warning("Optimization of axis %s is interrupted by button in %s.\n", optimizing, obj.name);
            optimizing = "";
        end
    end

end