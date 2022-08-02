function run( obj,status,managers,ax )
    % Main run method (callback for CC run button)
    %obj.PreRun(status,managers,ax);
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
    filtered_imgs = zeros(rymax-rymin+1, rxmax-rxmin+1, Npoints);



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
    obj.data.images_EMCCD = NaN(imgSize_EMCCD(1), imgSize_EMCCD(2), length(obj.scan_points));
    obj.data.freqMeasured = NaN(1,length(obj.scan_points));
    if obj.wavemeter_override
        obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu',obj.wavemeter_channel,false);
        obj.wavemeter.SetSwitcherSignalState(1);
    end
    
    for i = 1 : length(obj.scan_points)
        drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
        % change laser wavelength
        % obj.resLaser.TunePercent(obj.scan_points(i));
        
%         obj.resLaser.set_resonator_percent_limitrate(obj.scan_points(i));        
        if (i > 1)
            obj.resLaser.TunePercentFast(obj.scan_points(i)); % No response / laser locking to save time.
            obj.cameraEMCCD.startSnapping; % Start snapping EMCCD image in background (micro-controller)
            % Process data from the previous round
            EMCCD_imgs(:, :, i-1) = obj.data.images_EMCCD(rymin:rymax, rxmin:rxmax, i-1);
            filtered_imgs(:, :, i-1) = imgaussfilt(remove_spikes(EMCCD_imgs(:, :, i-1), 3), 1);
        else
            obj.resLaser.TunePercent(obj.scan_points(1)); % Spend longer time to make sure the first frequency spot is correct
            obj.cameraEMCCD.startSnapping;
            pause(1);
        end
        if obj.wavemeter_override
            
            %obj.wavemeter = Drivers.Wavemeter.instance('qplab-hwserver.mit.edu', obj.wavemeter_channel, false);
            obj.data.freqMeasured(i) = obj.wavemeter.getFrequency;
        else
            obj.data.freqMeasured(i) = obj.resLaser.getFrequency;
        end
        freqs(i) = obj.data.freqMeasured(i);

        obj.data.images_EMCCD(:,:,i) = obj.cameraEMCCD.fetchSnapping;
        imagesc(ax,obj.data.images_EMCCD(:,:,i));
        title(obj.data.freqMeasured(i));
    end
    EMCCD_imgs(:, :, end) = obj.data.images_EMCCD(rymin:rymax, rxmin:rxmax, end);
    filtered_imgs(:, :, end) = imgaussfilt(remove_spikes(EMCCD_imgs(:, :, end), 3), 1);


    processed_data = struct('freqs', freqs, 'EMCCD_imgs', EMCCD_imgs, 'filtered_imgs', filtered_imgs, 'wl_img', wl_img, 'poly_pos', poly_pos);
    EMCCDDataAnalysis(true, obj.autosave.exp_dir, processed_data);
end

