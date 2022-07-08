function obj = optimize_Callback(obj, src, evt)
    ms = obj.parent; % MetaStage
    global optimizing; % How to let different callback functions share a same variable?
    if ~isstring(optimizing) && ~ischar(optimizing)
        optimizing = "";
    end
    if src.Value == true
        if optimizing ~= ""
            warning("Optimization on %s is already started. Please stop the running optimization to start a new one.", optimizing);
            src.Value = false;

        else % No optimization process has been started yet.
            if isempty(obj.parent.get_meta_pref('Target').reference)
                warning("Reference 'Target' is not set properly. Please set a target to start optimization.");
                optimizing = "";
                src.Value = false;
                return;
            end
            if strcmp(ms.get_meta_pref('Target').reference.name, 'count')
                counter = ms.get_meta_pref('Target').reference.parent;
                running = counter.running;
                if ~running
                    counter.start;
                end
            end

            optimizing = obj.name;
            start_pos = obj.read;
            


            base_step = ms.(sprintf('key_step_%s', lower(obj.name)));
            step = base_step;

            % Record all tried positions and values
            obj.record_array = {};
            record = struct;


            % Set the optimization range to [start_pos - max_range, start_pos + max_range]
            % The optimization will automatically stop once current value is out of range.
            max_range = 20*base_step; 
            max_iteration = 50;
            min_step = 0.1*base_step; % Optimization will stop if the current step is too short and there is no improvement.
            
            fixed_pos = obj.read;
            sweep_num = 0;
            % Sweep [-5:5]*base_step to find a starting point of optimization
            for k = -sweep_num:sweep_num
                test_pos = fixed_pos + k*base_step;
                obj.writ(test_pos);
                [avg, st] = obj.get_avg_val;
                record.pos = test_pos;
                record.val = avg;
                record.st = st;
                obj.record_array{end+1} = record;
            end

                
            max_val = 0;
            for l = 1:length(obj.record_array)
                record = obj.record_array{l};
                if record.val >= max_val
                    max_pos = record.pos;
                    max_val = record.val;
                end
            end
            fixed_pos = max_pos; % Set the best position to be the fixed point
            fixed_val = max_val;
            % fixed_val = obj.get_avg_val;


            iteration_num = 0;
            direction_changed = false; % A flag to record whether the step direction is changed after the previous iteration.
            while(optimizing == obj.name)
                % Use hill climbing to optimize a single axis
                % Step length is based on key_step_(obj.name).
                
                if (abs(fixed_pos + step-start_pos) > max_range)
                    fprintf("Optimization position runing out of range. Abort.\n");
                    optimizing = "";
                    src.Value = false;
                    obj.writ(fixed_pos);
                    break;
                end

                if (iteration_num > max_iteration)
                    fprintf("Optimization iteration rounds exceed %d. Abort.\n", max_iteration);
                    optimizing = "";
                    src.Value = false;
                    obj.writ(fixed_pos);
                    break;
                end
                test_pos = fixed_pos + step;
                obj.writ(test_pos);
                [avg, st] = obj.get_avg_val;
                record.pos = test_pos;
                record.val = avg;
                record.st = st;
                obj.record_array{end+1} = record;
                diff = avg - fixed_val;
                
                iteration_num = iteration_num + 1;
                fprintf("Optimizing axis %s (%s) it:%d step:%.2e fixed_pos: %.2e fixed_val: %.2e test_pos: %.2e, try_val: %.2e.\n", obj.name, obj.reference.name, iteration_num, step, fixed_pos, fixed_val, test_pos, avg);

                if diff > 0 % Is a successful optimization step. Keep moving on this direction.
                    direction_changed = false;
                    fixed_val = avg;
                    fixed_pos = fixed_pos + step;
                else % Fails to optimize: try another direction or shorten the step length.
                    
                    if direction_changed % If already failed in last iteration, shorten the step length.

                        step = step / 2;
                        if (abs(step) < min_step)
                            fprintf("Reach local maximum. Abort.\n")
                            obj.writ(fixed_pos);
                            optimizing = "";
                            src.Value = false;
                            break;
                        end
                        direction_changed = false; % Refresh this flag.
                    else % The first time to fail
                        step = -step;
                        direction_changed = true;
                    end
                end
            end % End while loop
            obj.plot_records(1, 1, obj.name);
            
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



