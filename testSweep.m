function s = testSweep
%     83844218
%     83830539

    ni =  Drivers.NIDAQ.dev.instance('dev1');
    pm =  Drivers.PM100.instance;
    hwp = Drivers.APTMotor.instance(83844218, [-Inf, Inf]);
    qwp = Drivers.APTMotor.instance(83830539, [-Inf, Inf]);
    ms = Sources.Msquared.instance;
    
    pm.wavelength = 620;
    pmp = pm.get_meta_pref('power');
    
    wl = ms.get_meta_pref('setpoint_');
    wm = ms.get_meta_pref('VIS_wavelength');
    
%     hwp.home()
%     qwp.home()
    
    hwpp = hwp.get_meta_pref('Position');
    qwpp = qwp.get_meta_pref('Position');
    
    pr = Base.PrefRegister.instance;
    mp = pr.register{1}.prefs.ao1;
%     mp1 = pr.register{1}.prefs.ao0;
    
    mr = Base.MeasurementRegister.instance;
    mm = mr.register(1).Drivers_NIDAQ_in;
    
%     s = Base.Sweep({mm}, {mp}, {0:.01:10}, struct(), .001);

%     s = Base.Sweep({mm}, {qwpp}, {0:.01:10}, struct(), .001);
%     s = Base.Sweep({mm, pmp, hwpp}, {hwpp}, {0:2:90}, struct(), 1);
    
    s = Base.Sweep({mm, pmp, wm}, {wl}, {618:.1:622}, struct(), 1);
end