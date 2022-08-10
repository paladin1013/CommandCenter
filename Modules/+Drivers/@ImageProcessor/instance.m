function obj = instance()
    mlock;
    persistent Object
    if isempty(Object) || ~isvalid(Object)
        Object = Drivers.ImageProcessor();
    end
    obj = Object;
end