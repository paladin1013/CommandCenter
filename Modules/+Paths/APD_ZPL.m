function APD_ZPL()
    % Usage: In CommandCenter Menu, select Path->New Path, then edit the path name and copy the contents into the function body. This should be replaced by reading from code directly.
    try
        apt = Drivers.APTFilterFlipper.instance(37000231, 'APD1');
        apt.setState(2, 1);
        sl1 = Drivers.Elliptec.Slider.instance("localhost", "ZPL_PSB_SLIDER");
        sl1.set_position(1);
        sl2 = Drivers.Elliptec.Slider.instance("localhost", "CONFOCAL_WIDEFIELD_SLIDER");
        sl2.set_position(1);
    catch err
        warning("APD_ZPL path is not successfully set. Please turn off Kinesis or reconnect.");
    end
end