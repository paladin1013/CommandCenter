function run(obj,status,managers,ax)

    if obj.continue_experiment

    obj.abort_request = false;
    obj.initialize(status, managers, ax);
end