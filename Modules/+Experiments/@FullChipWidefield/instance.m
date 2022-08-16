function obj = instance(varargin)
    mlock;
    persistent Objects
    if isempty(Objects)
        Objects = Experiments.FullChipWidefield.empty(1,0);
    end
    for i = 1:length(Objects)
        if isvalid(Objects(i)) && isequal(varargin,Objects(i).singleton_id)
            obj = Objects(i);
            return
        end
    end
    obj = Experiments.FullChipWidefield(varargin{:});
    obj.singleton_id = varargin;
    obj.imaging_source = Sources.Cobolt_PB.instance;
    obj.experiments = [Experiments.Spectrum.instance];
    Objects(end+1) = obj;
end