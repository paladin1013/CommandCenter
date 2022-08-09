function obj = instance()
    mlock;
    persistent Object
    if isempty(Object) || ~isvalid(Object)
        Object = Imaging.ChipletTracker();
    end
    obj = Object;
end