function obj = steponly_optimize_Callback(obj, src, evt)
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
            ms.start_target;

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
            
            temp_pos = start_pos;
            temp_val = obj.get_avg_val;
            max_val = temp_val;


            iteration_num = 0;
            thres_ratio = 0.05; % Optimziation loop will break if the ending value is in the range [(1-thres_ratio)*max_val, (1+thre_ratio)*max_val]
            maximum_reached = false; % Whether the target value starts to decrease.
            increased = false; % Whether the target value has increased during the optimization.
            while(optimizing == obj.name)
                % Use hill climbing to optimize a single axis
                % Step length is based on key_step_(obj.name).
                
                if (abs(temp_pos + step-start_pos) > max_range)
                    fprintf("Optimization position runing out of range. Abort.\n");
                    optimizing = "";
                    src.Value = false;
                    obj.writ(temp_pos);
                    break;
                end

                if (iteration_num > max_iteration)
                    fprintf("Optimization iteration rounds exceed %d. Abort.\n", max_iteration);
                    optimizing = "";
                    src.Value = false;
                    obj.writ(temp_pos);
                    break;
                end
                test_pos = temp_pos + step;
                obj.writ(test_pos);
                [avg, st] = obj.get_avg_val;
                record.pos = test_pos;
                record.val = avg;
                record.st = st;
                obj.record_array{end+1} = record;
                diff = avg - temp_val;
                
                iteration_num = iteration_num + 1;
                fprintf("Optimizing axis %s (%s) it:%d step:%.2e temp_pos: %.2e temp_val: %.2e test_pos: %.2e, try_val: %.2e.\n", obj.name, obj.reference.name, iteration_num, step, temp_pos, temp_val, test_pos, avg);
                temp_val = avg;
                temp_pos = temp_pos + step;
                if diff > 0 % Is a successful optimization step. Keep moving on this direction.
                    increased = true;
                    if maximum_reached
                        if temp_val > max_val * (1+thres_ratio)
                            maximum_reached = false;
                        elseif temp_val > max_val * (1-thres_ratio)
                            % Approximately reaches the maximum position
                            src.Value = false;
                            optimizing = "";
                            fprintf("Optimization reaches maximum.\n")
                            break;
                        end
                        % if temp_val < max_val * (1-thres_ratio)
                        % do nothing and continue to optimize
                    end
                else % Fails to optimize: try another direction or shorten the step length.
                    % The first time to fail
                    if increased
                        maximum_reached = true;
                    end
                    step = -step;
                end
                max_val = max(temp_val, max_val);

            end % End while loop
            
            if strcmp(ms.optimize_option, "minimize")
                for k = 1:length(obj.record_array)
                    obj.record_array{k}.val = -obj.record_array{k}.val;
                end
            end
            
            if ms.plot_record
                obj.plot_records(1, 1, obj.name);
            end
            
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