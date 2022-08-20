function obj = instance()
    mlock;
    persistent Object
    if isempty(Object) || ~isvalid(Object)
        Object = Drivers.FullChipDataAnalyzer();
    end
    obj = Object;
end