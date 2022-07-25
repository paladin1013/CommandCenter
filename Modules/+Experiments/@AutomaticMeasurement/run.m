function run(obj,status,managers,ax)
    obj.exp_axH = ax;
    obj.abort_request = false;
    managers.Path.select_path('APD1');
    obj.initialize(status, managers, ax);

    Nsites = size(obj.sites.positions, 1);
    Nexperiments = length(obj.experiments);

    if strcmp(obj.method, 'Spectrum')
        obj.doSpectrum(status, managers);
    end

end