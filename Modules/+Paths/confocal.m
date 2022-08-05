function confocal()
    % Usage: In CommandCenter Menu, select Path->New Path, then edit the path name and copy the contents into the function body. This should be replaced by reading from code directly.
    try
        sl2 = Drivers.Elliptec.Slider.instance("18.25.29.30", "WIDEFIELD_CONFOCAL_SLIDER");
        sl2.set_position(2);
    catch err
        warning("APD_ZPL path is not successfully set. Please press `Ctrl-C` in the hwserver terminal.");
    end
end