function obj = instance()
    mlock;
    persistent Object
    if isempty(Object) || ~isvalid(Object)
        Object = Imaging.Hamamatsu();
    end
    obj = Object;
end