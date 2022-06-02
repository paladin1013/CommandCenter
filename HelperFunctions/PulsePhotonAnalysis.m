function time_bin_result = PulsePhotonAnalysis(sync_time, photon_time, sync_ns, bin_width_ns, draw_fig)

    sync_pt = 1;
    photon_pt = 1;
    % time_bin_result = cell(1, length(sync_time));
    coordinate_time = zeros('like', photon_time);
    coordinate_round = zeros('like', photon_time);

    % for i = 1:length(sync_time)
    % %     time_bin_result{i} = [];
    % end
    while sync_pt < length(sync_time)-1 && photon_pt < length(photon_time)
        while photon_time(photon_pt) < sync_time(sync_pt+1)

            % time_bin_result{sync_pt} = [time_bin_result{sync_pt}, photon_time(photon_pt)-sync_time(sync_pt)];
            coordinate_time(photon_pt) = photon_time(photon_pt)-sync_time(sync_pt);
            coordinate_round(photon_pt) = sync_pt;
            photon_pt = photon_pt + 1;
            if photon_pt > length(photon_time)
                break
            end
        end
        sync_pt = sync_pt + 1;
    end



    if ~exist("sync_ns", "var")
        sync_ns = 10000;
    end
    % bin_width_ns = 0.256;
    if ~exist("bin_width_ns", "var")
        bin_width_ns = 1;
    end
    bin_num = ceil(sync_ns/bin_width_ns);

    time_bin_result = zeros(1, bin_num);

    for photon_cnt = 1:length(coordinate_time)
        bin =ceil(mod(coordinate_time(photon_cnt)/1000, sync_ns)/bin_width_ns);
        if bin ~= 0
        time_bin_result(bin) = time_bin_result(bin) + 1;
        end
    end

    if exist("draw_fig", 'var') && draw_fig
        figure;
        scatter(coordinate_time, coordinate_round)
        figure;
        plot((1:bin_num)*bin_width_ns, time_bin_result)
        set(get(gca, 'XLabel'), 'String', 'time (ns)');
        set(get(gca, 'YLabel'), 'String', 'Intensity (a.u.)');
        set(get(gca, 'Title'), 'String', sprintf("Resolution: %d ns", bin_width_ns));
    end
end