function obj = instance(host_ip)
    % error("error")
    mlock;
    persistent Objects
    if isempty(Objects)
        Objects = Drivers.Attocube.ANC350.empty(1,0);
    end
    serials = Drivers.Attocube.ANC350.get_serialNo(host_ip);
    singleton_id = serials{1};
    for i = 1:length(Objects)
        if isvalid(Objects(i)) && isequal(singleton_id, Objects(i).singleton_id)
            obj = Objects(i);
            return
        end
    end
    obj = Drivers.Attocube.ANC350(host_ip);
    obj.singleton_id = singleton_id;
    Objects(end+1) = obj;
    obj.spawnLines;
end