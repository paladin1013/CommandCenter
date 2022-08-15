function result = check_call_stack_func(func_name)
    % Check whether `func_name` is in the current call stack
    call_stack = dbstack;
    for k = 1:length(call_stack)
        if contains(call_stack(k).name, func_name)
            result = true;
            return
        end
    end
    result = false;
    return
end