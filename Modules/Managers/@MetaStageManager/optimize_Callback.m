function obj = optimize_Callback(obj, src, evt, axis_name)
    ms = obj.active_module;
    pref = ms.get_meta_pref(axis_name);
    global optimizing; % How to let different callback functions share a same variable?
    if ~isstring(optimizing) && ~ischar(optimizing)
        optimizing = "";
    end
    if src.Value == true
        if ~strcmp(optimizing, "")
            warning("Optimization on %s is already started. Please stop the running optimization to start a new one.", optimizing);
            src.Value = false;

        else % No optimization process has been started yet.
            if isempty(pref.parent.get_meta_pref('Target').reference)
                warning("Reference 'Target' is not set properly. Please set a target to start optimization.");
                optimizing = "";
                src.Value = false;
                return;
            end
            
            try
                ms.start_target;
            catch err
                src.Value = false;
                optimizing = "";
                rethrow(err);
                return;
            end
            optimizing = pref.name;
            start_pos = pref.read;
            


            base_step = ms.(sprintf('key_step_%s', lower(pref.name)));
            step = base_step;
            prev_step = 0;

            % Record all tried positions and values
            obj.record_array = {};
            record = struct;


            % Set the optimization range to [start_pos - max_range, start_pos + max_range]
            % The optimization will automatically stop once current value is out of range.
            max_range = 20*abs(base_step); 
            max_iteration = 50;
            min_step = ms.min_step_ratio*base_step; % Optimization will stop if the current step is too short and there is no improvement.
            
            fixed_pos = pref.read;
            sweep_num = ms.sweep_num;
            % Sweep [-5:5]*base_step to find a starting point of optimization
            for k = -sweep_num:sweep_num
                test_pos = fixed_pos + k*base_step;
                pref.writ(test_pos);
                [avg, st] = obj.get_target_avg;
                record.pos = test_pos;
                record.val = avg;
                record.st = st;
                obj.record_array{end+1} = record;
            end

            max_val = -1e10;
            for l = 1:length(obj.record_array)
                record = obj.record_array{l};
                if record.val >= max_val
                    max_pos = record.pos;
                    max_val = record.val;
                end
            end
            fixed_pos = max_pos; % Set the best position to be the fixed point
            fixed_val = max_val;
            % fixed_val = obj.get_target_avg;


            iteration_num = 0;
            direction_changed = false; % A flag to record whether the step direction is changed after the previous iteration.
            while(optimizing == pref.name)
                % Use hill climbing to optimize a single axis
                % Step length is based on key_step_(pref.name).
                
                if (abs(fixed_pos + step-start_pos) > max_range)
                    fprintf("Optimization position runing out of range. Abort.\n");
                    optimizing = "";
                    src.Value = false;
                    pref.writ(fixed_pos);
                    break;
                end

                if (iteration_num > max_iteration)
                    fprintf("Optimization iteration rounds exceed %d. Abort.\n", max_iteration);
                    optimizing = "";
                    src.Value = false;
                    pref.writ(fixed_pos);
                    break;
                end
                test_pos = fixed_pos + step;
                Nrecords = length(obj.record_array);
                use_record = false;
                for l = 1:Nrecords
                    if all(test_pos == obj.record_array{l}.pos)
                        avg = obj.record_array{l}.val;
                        use_record = true;
                        break
                    end
                end

                if ~use_record
                    pref.writ(test_pos);
                    [avg, st] = obj.get_target_avg;
                    record.pos = test_pos;
                    record.val = avg;
                    record.st = st;
                    obj.record_array{end+1} = record;
                end
                diff = avg - fixed_val;
                
                iteration_num = iteration_num + 1;
                fprintf("Optimizing axis %s (%s) it:%d step:%.2e previous_step:%.2e fixed_pos: %.2e fixed_val: %.2e test_pos: %.2e, try_val: %.2e.\n", pref.name, pref.reference.name, iteration_num, step, prev_step, fixed_pos, fixed_val, test_pos, avg);

                if diff > 0 % Is a successful optimization step. Keep moving on this direction.
                    direction_changed = false;
                    fixed_val = avg;
                    fixed_pos = fixed_pos + step;
                    prev_step = step;
                else % Fails to optimize: try another direction or shorten the step length.
                    
                    if direction_changed || prev_step == step% If already failed in last iteration, shorten the step length.
                        prev_step = step;
                        step = step / 2;
                        if (abs(step) < min_step)
                            fprintf("Reach local maximum. Abort.\n")
                            pref.writ(fixed_pos);
                            optimizing = "";
                            src.Value = false;
                            break;
                        end
                        direction_changed = false; % Refresh this flag.
                    else % The first time to fail
                        prev_step = step;
                        step = -step;
                        direction_changed = true;
                    end
                end
            end % End while loop
            if strcmp(ms.optimize_option, "minimize")
                for k = 1:length(obj.record_array)
                    obj.record_array{k}.val = -obj.record_array{k}.val;
                end
            end
            if ms.plot_record
                obj.plot_records(1, 1, pref.name);
            end
            
        end
    else % src.Value == false
        if pref.name == optimizing
            optimizing = ""; % to end an optimization
            fprintf("Optimization of axis %s (%s) is interrupted.\n", pref.name, pref.reference.name);
        else % pref.name ~= optimizing, which should not happen if operated correctly
            warning("Optimization of axis %s is interrupted by button in %s.\n", optimizing, pref.name);
            optimizing = "";
        end
    end

end



