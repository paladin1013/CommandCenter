function ZPL()
    % Usage: In CommandCenter Menu, select Path->New Path, then edit the path name and copy the contents into the function body. This should be replaced by reading from code directly.
    try
        sl1 = Drivers.Elliptec.Slider.instance("18.25.29.30", "ZPL_PSB_SLIDER");
        sl1.set_position(1);
    catch err
        warning("ZPL path is not successfully set.  Please press `Ctrl-C` in the hwserver terminal.");
    end
end