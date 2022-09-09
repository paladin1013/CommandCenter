function run( obj,status,managers,ax )
    % Main run method (callback for CC run button)
    %obj.PreRun(status,managers,ax);
    if check_call_stack_func('grabFrame')
        error('Please stop Video then start the experiment.');
    end
    if obj.cameraEMCCD.continuous
        obj.cameraEMCCD.stopVideo
    end

    if obj.use_powermeter && (isempty(obj.powermeter) || ~isvalid(obj.powermeter))
        try
            obj.powermeter = Drivers.PM100_remote.instance;
        catch
            warning("Powermeter is not connected. use_powermeter will be set to false.");
            obj.use_powermeter = false;
        end
    end
    timers = timerfindall;
    for k = 1:length(timers)
        if strcmp(timers(k).tag, 'Video Timer')
            % There exists other timers generated by `Imaging.startVideo`
            if strcmp(timers(k).Running, 'on')
                stop(timers(k)); % Stop all other timers
            end
            delete(timers(k));
        end
    end

    obj.autosave = Databases.AutoSave.instance;
    if strcmp(obj.autosave.exp_dir, "")
        obj.autosave.change_exp_dir;
    end

    if isempty(obj.poly_pos) || isempty(obj.rect_pos)
        obj.set_ROI;
    end
    pos = obj.rect_pos;
    rxmin = ceil(pos(1));
    rymin = ceil(pos(2));
    rxmax = floor(pos(1)+pos(3));
    rymax = floor(pos(2)+pos(4));
    poly_pos = obj.poly_pos;
    wl_img = obj.trimmed_wl_img;
    Npoints = length(obj.scan_points);
    freqs = zeros(1, Npoints);
    EMCCD_imgs = zeros(rymax-rymin+1, rxmax-rxmin+1, Npoints);
    if obj.filter_image
        filtered_imgs = zeros(rymax-rymin+1, rxmax-rxmin+1, Npoints);
    else
        filtered_imgs = [];
    end
    if obj.use_powermeter
        power_uW = zeros(1, Npoints);
    else
        power_uW = [];
    end

    % Stop all video timers

    obj.abort_request = false;
    status.String = 'Experiment started';
    drawnow;
    
    assert(~isempty(obj.percents),'percents is empty.');
%     assert(~isempty(obj.stop_V),'Stop is empty.');
%     assert(obj.start_V<obj.stop_V,'For now, start needs to be less that stop.');
%     assert(~isempty(obj.dwell_ms),'Dwell is empty.');
%     assert(~isempty(obj.total_time),'Total_time is empty.');
%     dwell = obj.dwell_ms*1e-3; % Convert to seconds

    obj.resLaser.on
    obj.repumpLaser.on
    obj.cameraEMCCD.binning = obj.EMCCD_binning;
    obj.cameraEMCCD.exposure = obj.EMCCD_exposure;
    obj.cameraEMCCD.EMGain = obj.EMCCD_gain;
    if obj.cameraEMCCD.core.isSequenceRunning
        obj.cameraEMCCD.core.stopSequenceAcquisition;
    end
    
    ROI_EMCCD = obj.cameraEMCCD.ROI;
    %imgSize_EMCCD = max(ROI_EMCCD) - min(ROI_EMCCD);
    imgSize_EMCCD = ROI_EMCCD(:,2) - ROI_EMCCD(:,1);
    raw_images = uint16(zeros(imgSize_EMCCD(1), imgSize_EMCCD(2), length(obj.scan_points)));
    freqs = NaN(1,length(obj.scan_points));
    if obj.wavemeter_override
        try
            obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu',obj.wavemeter_channel,true);
            obj.wavemeter.SetSwitcherSignalState(1);
        catch err
            warning(err.message);
            obj.wavemeter.delete;
            obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu',obj.wavemeter_channel,true);
        end
    end
    
    for i = 1 : length(obj.scan_points)
        drawnow('limitrate'); 
        if obj.abort_request
            % Save raw data first
            obj.discard_raw_data = false;
            freqs = freqs(1:i-1);
            power_uW = power_uW(1:i-1);
            EMCCD_imgs = EMCCD_imgs(:, :, 1:i-1);
            if ~isempty(filtered_imgs)
                filtered_imgs = filtered_imgs(:, :, 1:i-1);
            end
            successful_round = i-1;
            break;
        end
        % change laser wavelength
        % obj.resLaser.TunePercent(obj.scan_points(i));
        
%         obj.resLaser.set_resonator_percent_limitrate(obj.scan_points(i));        
        t = tic;
        if (i > 1)
            if obj.accelerate
                obj.cameraEMCCD.startSnapping; % Start snapping EMCCD image in background (micro-controller)
            end
            % Process data from the previous round
            EMCCD_imgs(:, :, i-1) = raw_images(rymin:rymax, rxmin:rxmax, i-1);
            if obj.filter_image
                filtered_imgs(:, :, i-1) = imgaussfilt(remove_spikes(EMCCD_imgs(:, :, i-1), 3), 1);
            end
        else
            obj.resLaser.TunePercent(obj.scan_points(1)); % Spend longer time to make sure the first frequency spot is correct
            if obj.accelerate
                obj.cameraEMCCD.startSnapping;
            end
            pause(1);
        end
        if obj.wavemeter_override
            
            %obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu', obj.wavemeter_channel, false);
            freqs(i) = obj.wavemeter.getFrequency;
        else
            freqs(i) = obj.resLaser.getFrequency;
        end
        if obj.use_powermeter
            try
                power_uW(i) = obj.powermeter.get_power*1e3; % mW -> uW
            catch
                fprintf("Error getting power from powermeter. Try again.\n");
                try
                    power_uW(i) = obj.powermeter.get_power*1e3; % mW -> uW
                catch
                    fprintf("Error getting power from powermeter. Save NaN instead.\n");
                    power_uW(i) = NaN;
                end
            end
        end


        if i < length(obj.scan_points) % Get prepared for the next round
            obj.resLaser.TunePercentFast(obj.scan_points(i+1)); % No response / laser locking to save time.
        end
        if obj.accelerate
            raw_images(:,:,i) = uint16(obj.cameraEMCCD.fetchSnapping);
        else
            raw_images(:, :, i) = uint16(obj.cameraEMCCD.snapImage);
        end
        imagesc(ax,raw_images(:,:,i));
        hold(ax, 'on');
        rectangle(ax, 'Position', obj.rect_pos, 'EdgeColor', 'b', 'LineWidth', 1);
        poly = polyshape(obj.poly_pos(:, 1)+obj.rect_pos(1, 1), obj.poly_pos(:, 2)+obj.rect_pos(1, 2));
        polyH = plot(ax, poly, 'FaceAlpha', 0, 'EdgeColor', 'r', 'LineWidth', 1);
        hold(ax, 'off');
        title(freqs(i));
        successful_round = i;
    end
    if ~obj.abort_request
        EMCCD_imgs(:, :, end) = raw_images(rymin:rymax, rxmin:rxmax, end);
        if obj.filter_image
            filtered_imgs(:, :, end) = imgaussfilt(remove_spikes(EMCCD_imgs(:, :, end), 3), 1);
        end
    end

    EMCCD_imgs = uint16(EMCCD_imgs);
    if obj.filter_image
        filtered_imgs = uint16(filtered_imgs);
    end
    obj.processed_data = struct('freqs', freqs, 'filtered_imgs', filtered_imgs, 'wl_img', wl_img, 'poly_pos', poly_pos, 'full_wl_img', obj.wl_img);
    if obj.use_powermeter
        obj.processed_data.power_uW = power_uW;
    end
    if ~isempty(obj.segment)
        obj.processed_data.segment = obj.segment;
    end
    c = fix(clock);
    wait = msgbox('Please Wait, CommandCenter is saving data.');
    
    raw_images = raw_images(:, :, 1:successful_round);
    if ~isempty(filtered_imgs)
        filtered_imgs = filtered_imgs(:, :, 1:successful_round);
    end
    freqs = freqs(1:successful_round);
    power_uW = power_uW(1:successful_round);
    save(fullfile(obj.autosave.exp_dir, sprintf("Widefield_processed_data_%d_%d_%d_%d_%d.mat", c(2), c(3), c(4), c(5), c(6))), 'freqs', 'EMCCD_imgs', 'filtered_imgs', 'wl_img', 'poly_pos', 'power_uW', '-v7.3');
    if ~obj.discard_raw_data
        save(fullfile(obj.autosave.exp_dir, sprintf("Widefield_raw_data_%d_%d_%d_%d_%d.mat", c(2), c(3), c(4), c(5), c(6))), 'freqs', 'raw_images', 'wl_img', 'poly_pos', 'power_uW', '-v7.3');
    end
    obj.data.EMCCD_imgs = raw_images;
    obj.data.freqMeasured = freqs;
    obj.data.wl_img = wl_img;
    obj.data.poly_pos = poly_pos;
    obj.data.power_uW = power_uW;
    try
        delete(wait);
    end
    if ~obj.skip_analysis
        try
            EMCCDDataAnalysis(true, obj.autosave.exp_dir, obj.processed_data);
        catch err
            obj.abort_request = true;
            rethrow(err);
        end
    end
end

