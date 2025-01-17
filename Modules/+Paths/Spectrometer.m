function spectrometer()
    % Usage: In CommandCenter Menu, select Path->New Path, then edit the path name and copy the contents into the function body. This should be replaced by reading from code directly.
    try
        apt = Drivers.APTFilterFlipper.instance(37000231, 'APD1');
        apt.setState(1, 1);
    catch err
        warning("spectrometer path is not successfully set. Please turn off Kinesis or reconnect.");
    end
end