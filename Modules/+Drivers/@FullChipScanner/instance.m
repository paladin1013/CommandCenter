function obj = instance()
    mlock;
    persistent Object
    if isempty(Object) || ~isvalid(Object)
        Object = Drivers.FullChipScanner();
    end
    obj = Object;
end