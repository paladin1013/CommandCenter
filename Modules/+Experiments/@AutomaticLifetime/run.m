function run(obj,status,managers,ax)
    obj.exp_axH = ax;
    obj.abort_request = false;
    obj.initialize(status, managers, ax);
end