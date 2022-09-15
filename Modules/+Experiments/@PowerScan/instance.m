function obj = instance(varargin)
    mlock;
    persistent Objects
    if isempty(Objects)
        Objects = Experiments.PowerScan.empty(1,0);
    end
    for i = 1:length(Objects)
        if isvalid(Objects(i)) && isequal(varargin,Objects(i).singleton_id)
            obj = Objects(i);
            return
        end
    end
    obj = Experiments.PowerScan(varargin{:});
    obj.singleton_id = varargin;
    Objects(end+1) = obj;
end