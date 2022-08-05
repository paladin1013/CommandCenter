function EMCCDDataAnalysis(load_processed_data, working_dir, processed_data_file, EMCCD_data_file, WL_data_file, sites_save_path)
    % For `processed_data_file`, pass a struct directly (including fields {freqs, EMCCD_imgs, filtered_imgs, wl_img, poly_pos}) is also valid.
    if ~exist('EMCCD_data_file', 'var')
        EMCCD_data_file = 'EMCCD_raw_data.mat';
    end
    if ~exist('WL_data_file', 'var')
        WL_data_file = 'wightlight_data.mat';
    end
    if ~exist('processed_data_file', 'var')
        processed_data_file = 'EMCCD_processed_data.mat';
    end
    if ~exist('working_dir', 'var')
        working_dir = 'Data';
    end
    if ~exist('sites_save_path', 'var')
        sites_save_path = 'EMCCD_emitter_sites.mat';
    end
    
    if load_processed_data == false
        wl = load(fullfile(working_dir, WL_data_file));
        try close(42); catch; end
        roi_fig = figure(42);
        ax2 = axes('Parent', roi_fig);
        im2H = imagesc(ax2, wl.image.image(:, :));
        colormap(ax2, 'bone')
        im_size = size(wl.image.image(:, :));
        rectH = images.roi.Rectangle(ax2, 'Position', [1, 1, im_size(1)-1, im_size(2)-1]);
        set(get(ax2, 'Title'), 'String', sprintf('Please adjust ROI to trim the image and accelarate image processing\nRight click unconvered image to confirm ROI'));
        ax2.ButtonDownFcn = @ROIConfirm;
        im2H.ButtonDownFcn = @ROIConfirm;
        uiwait(roi_fig);
        pos = rectH.Position;
        rxmin = ceil(pos(1));
        rymin = ceil(pos(2));
        rxmax = floor(pos(1)+pos(3));
        rymax = floor(pos(2)+pos(4));
        delete(roi_fig);
        wl_img = wl.image.image(rymin:rymax, rxmin:rxmax);


        try close(41); catch; end
        result_fig = figure(41);
        ax = axes('Parent', result_fig);
        wlH = imagesc(ax, wl_img);
        colormap(ax, 'bone');
        x_size = size(wl_img, 2);
        y_size = size(wl_img, 1);
        size(wl_img, 1);
        polyH = drawpolygon(ax, 'Position', [1, x_size, x_size, 1; 1, 1, y_size, y_size]');
        set(get(ax, 'Title'), 'String', sprintf('Right click the image to confirm polygon ROI\nOnly emitters inside this region will be shown.'));
        wlH.ButtonDownFcn = @ROIConfirm;
        uiwait(result_fig);
        poly_pos = polyH.Position;
        delete(ax);

        fprintf("Finish trimming & setting ROI. Start loading image data.\n")
        
        
        
        d = load(fullfile(working_dir, EMCCD_data_file));
        if isfield(d, 'd')
            d = d.d;
        end
        % Find the number of non-NaN elements:
        validFrameNum = sum(~isnan(d.data.data.data.freqMeasured))-1;
        freqs = d.data.data.data.freqMeasured(1:validFrameNum);
        EMCCD_imgs = d.data.data.data.images_EMCCD(rymin:rymax, rxmin:rxmax, 1:validFrameNum);
        filtered_imgs = EMCCD_imgs;

        fprintf("Finish loading data. Start image Gaussian filtering.\n");
        
        clear('d'); % Delete d to free memory;           
        parfor ii = 1:length(freqs) % 
            %             d.filtered_imgs(:,:,ii) = flatten(imgaussfilt(remove_spikes(EMCCD_imgs(:,:,ii), 3),1));
            filtered_imgs(:, :, ii) = imgaussfilt(remove_spikes(EMCCD_imgs(:, :, ii), 3), 1);
        end
        save(fullfile(working_dir, processed_data_file), 'freqs', 'EMCCD_imgs', 'filtered_imgs', 'wl_img', 'poly_pos');
    else 
        if isstruct(processed_data_file) % Pass the structure directly
            freqs = processed_data_file.freqs;
            EMCCD_imgs = processed_data_file.EMCCD_imgs;
            filtered_imgs = processed_data_file.filtered_imgs;
            wl_img = processed_data_file.wl_img;
            poly_pos = processed_data_file.poly_pos;
            clear('processed_data_file'); % To save memory
        else % Load data from .mat file
            load(fullfile(working_dir, processed_data_file), 'freqs', 'EMCCD_imgs', 'filtered_imgs', 'wl_img', 'poly_pos');
        end
        try close(41); catch; end
        result_fig = figure(41);
    end


% Polygon ROI


    s1 = subplot(4, 1, 1);
    s2 = subplot(4, 1, 2);
    s3 = subplot(4, 1, 3);
    s4 = subplot(4, 1, 4);



    % Initialize shared variable
    labels = [];
    wgc = [];
    wgw = [];
    wgx = [];
    wgy = [];
    wgpx = [];
    wgpy = [];
    wgym = [];

    % Use input dialog to update mincount
    try close(43); catch; end
    panelH = figure(43);
    panelH.Name = 'Settings';
    panelH.HandleVisibility = 'Callback';
    panelH.NumberTitle = 'off';
    panelH.MenuBar = 'none';
    panelH.CloseRequestFcn = @cancelCallback;
    panelH.Position(3) = 300;
    panelH.Position(4) = 100;
    drawImage(10000);
    textH = uicontrol(panelH, 'style', 'text', 'string', 'mincount:', 'horizontalalignment', 'right', 'units', 'characters', 'position', [17, 4, 10, 1.5]);
    editH = uicontrol(panelH, 'style', 'edit', 'string', '10000', 'units', 'characters', 'horizontalalignment', 'left', 'position', [28, 4.2, 10, 1.5], 'callback', @testCallback);
    confirmH = uicontrol(panelH, 'style', 'pushbutton', 'units', 'characters', 'string', 'Confirm', 'horizontalalignment', 'left', 'position', [15, 1, 10, 1.5], 'callback', @confirmCallback);
    cancelH = uicontrol(panelH, 'style', 'pushbutton', 'units', 'characters', 'string', 'Cancel', 'horizontalalignment', 'left', 'position', [30, 1, 10, 1.5], 'callback', @cancelCallback);
    uiwait(panelH);
    mincount = str2double(editH.String);
    drawImage(mincount);
    delete(panelH);
    

    T = [1, 2, 3; 3, 4, 1];
    TR = triangulation(T, poly_pos);
    
    hold(s1, 'on');
    axes(s1);
    triplot(TR);
    tri1 = TR.Points(TR.ConnectivityList(1, :), :);
    tri2 = TR.Points(TR.ConnectivityList(2, :), :);
    sites = cell(1, length(wgpx));
    validCnt = 0;
    for k = 1:length(wgpx)
        cartPos = [wgpx(k), wgpy(k)];
        if(inpolygon(wgpx(k), wgpy(k), tri1(:, 1), tri1(:, 2)))
            baryPos = cartesianToBarycentric(TR, 1, cartPos);
            validCnt = validCnt + 1;
            sites{validCnt} = struct('baryPos', baryPos,'triangleInd', 1, 'frequency_THz', wgc(k), 'wavelength_nm', 3e5/wgc(k));
        elseif(inpolygon(wgpx(k), wgpy(k), tri2(:, 1), tri2(:, 2)))
            baryPos = cartesianToBarycentric(TR, 2, cartPos);
            validCnt = validCnt + 1;
            sites{validCnt} = struct('baryPos', baryPos,'triangleInd', 2, 'frequency_THz', wgc(k), 'wavelength_nm', 3e5/wgc(k));
        end
    end

    sites = sites(1:validCnt);
    fprintf("Sites data saved to %s\n", sites_save_path);
    save(fullfile(working_dir, sites_save_path), 'sites');


    

    

    function drawImage(mincount)
        % Initialize shared variable
        labels = [];
        wgc = [];
        wgw = [];
        wgx = [];
        wgy = [];
        wgpx = [];
        wgpy = [];
        wgym = [];
        
        figure(result_fig);
        delete(s1);
        delete(s2);
        delete(s3);
        delete(s4);
        allpts0 = reshape(filtered_imgs, [numel(wl_img), length(freqs)]);
        allpts0(max(allpts0, [], 2) < mincount, :) = [];
    
        p0 = zeros(5, length(allpts0(:, 1)));
        [p0(5, :), p0(3, :)] = find(allpts0 == max(allpts0, [], 2));
    
        box('on');
    
        for i = 1:length(allpts0(:, 1))
            p0(4, i) = allpts0(p0(5, i), p0(3, i));
            [a, b] = find(filtered_imgs(:, :, p0(3, i)) == p0(4, i));
            p0(1, i) = a(1);
            p0(2, i) = b(1);
        end
        a1 = 1;
        fres = unique(p0(3, :));
        realx = zeros(1, length(fres));
        realy = zeros(1, length(fres));
        reali = zeros(1, length(fres));
        reala = zeros(1, length(fres));
        realf = zeros(1, length(fres));
        realpoints = zeros(5, length(fres));
        sloc = zeros(1, length(fres));
        swid = zeros(1, length(fres));
    
        for i = 1:length(fres)
            pmax = 0;
            ptx = [];
            pty = [];
            for j = 1:length(allpts0(:, 1))
                if p0(3, j) == fres(i)
                    pmax = max(pmax, p0(4, j));
                    ptx = [ptx; p0(1, j)];
                    pty = [pty; p0(2, j)];
                end
            end
            xi = find(p0(4, :) == pmax);
            xi = xi(1);
    
            realx(i) = p0(1, xi);
            realy(i) = p0(2, xi);
            reali(i) = p0(5, xi);
            reala(i) = p0(4, xi);
            realf(i) = p0(3, xi);
            %     realpoints(i)=p0(:,xi);
        end
        a1;
        c = jet(length(fres));
    
        yy = allpts0(reali, :);
    
        valid = spacialFilter(poly_pos, realy, realx);
        for i = 1:length(fres)
            hold on
            if valid(i) == 1
                wgt = yy(i, :);
                [wgtv, wgtp] = find(wgt == max(wgt));
                wgt(max(1, wgtp - 2):min(length(yy), wgtp + 2)) = min(wgt);
                if max(wgt(max(1, wgtp - floor(length(wgt) / 20)):min(length(wgt), wgtp + floor(length(wgt) / 20)))) > 0.5 * max(yy(i, :))
                    wgc = [wgc; freqs(wgtp)];
                    wgx = [wgx; (freqs - min(freqs) * ones(1, length(freqs))) * 1e3];
                    wgy = [wgy; yy(i, :)];
                    wgym = [wgym; max(yy(i, :))];
                    wgpx = [wgpx; realy(i)];
                    wgpy = [wgpy; realx(i)];
                end
    
            end
    
        end
        if length(wgpx) == 0
            warning("No emitter found! Please trun down `mincount`.");
            return;
        end
        markerlist = ['o'; '+'; 'x'; 's'; 'd'; '^'; 'v'; '>'; '<'; 'p'; 'h'; '*'; '_'; '|'];
        markerlist2 = ['-o'; '-+'; '-x'; '-s'; '-d'; '-^'; '-v'; '->'; '-<'; '-p'; '-h'; '-*'; ];
        c = [1 0 0; 1 0.5 0; 1 1 0; 0.5 1 0; 0 1 0; 0 1 1; 0 0.5 1; 0 0 1; 0.5 0 1; 1 0 1];
        figureHandles = cell(length(wgpx), 3);
        if length(wgpx) >= 40
            s2 = subplot(1, 4, 2);
            for i = 1:39
                hold on
                figureHandles{i, 2} = plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                %     set(t1,'Color',[0 0 0]);
            end
    
            hold off
            box on
            ylim([0 40])
            xlim([-1.6 1.6])
            yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
            yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
    
            xlabel('Detuned (GHz)')
            ylabel('Emitter number')
            % yticks([])
    
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            s4 = subplot(1, 4, 4);
            for i = 40:length(wgpx)
                hold on
                figureHandles{i, 2} = plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                %     set(t1,'Color',[0 0 0]);
            end
    
            hold off
            box on
            ylim([40 length(wgpx)+1])
            xlim([-1.6 1.6])
            yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
            yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
    
            xlabel('Detuned (GHz)')
            %     ylabel('Emitter number')
            % yticks([])
    
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
        else
            s2 = subplot(1, 4, 2);
            %  wgpx_max = max(wgpx, 1);
            for i = 1:length(wgpx)
                hold on
                % wgx_relative =wgx(i,:)-wgpx_max(1) ;
                figureHandles{i, 2} = plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                %     set(t1,'Color',[0 0 0]);
            end
    
            hold off
            box on
            ylim([1 length(wgpx)+1])
            xlim([-1.6 1.6])
            yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
            yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
    
            xlabel('Detuned (GHz)')
            ylabel('Emitter number')
            % yticks([])
    
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
    
        end
    
        s1 = subplot(1, 4, 1);
    
        img = squeeze(max(filtered_imgs, [], 3));
        imH = imagesc(wl_img);
        colormap('bone')
        xlim(s1, [1, size(wl_img, 2)]);
        ylim(s1, [1, size(wl_img, 1)]);
        % xticks([])
        % yticks([])
        %     image(ax, hsv2rgb(H, V, V))
        % for i=1: length(fres)
        %     hold on
        %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
        %         scatter(realy(i+12*0),realx(i+12*0),30,c(length(fres)+1-i,:),'Linewidth',2)
        %     end
        % end
    
        SizeData = zeros(1, length((wgpx)));
        for i = 1:length(wgpx)
    
            SizeData(i) = (wgym(i)-mincount)/(max(wgym)-mincount)*100+30;
            hold on
            %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
            %         scatter(wgpx(i),wgpy(i),30, c(1+(i-floor(i/10)*10),:),markerlist(1+floor(i/10)),'Linewidth',2)
            figureHandles{i, 1} = scatter(wgpx(i), wgpy(i), SizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
            %     end
        end
    
    
        hold off
    
        xticks([])
        yticks([])
        set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
        s3 = subplot(1, 4, 3);
        for i = 1:length(wgpx)
            hold on
            figureHandles{i, 3} = scatter(wgc(i), wgym(i), SizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
            %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
            %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
            %     set(t1,'Color',[0 0 0]);
            if (i / 10 - floor(i / 10)) == 0
                line([wgc(i) wgc(i)], [mincount 6.5e4], 'Color', 'k', 'LineStyle', '--');
            end
        end
        set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
        xlabel('Frequency (THz)')
        ylabel('Pixel count')
        box on
        title('EMCCD Gain:1200, Expose Time:500ms, Pixel:16um*16um')
        yticks([3e4, 6e4]);
        ylim([mincount 6.5e4]);
        hold off
    
        set(s3, 'Position', [0.05 0.1 0.6 0.15])
        set(s2, 'Position', [0.7 0.1 0.12 0.85])
    
        % set(s1, 'Position', [0.08 0.38 0.58 0.58])
        set(s1, 'Position', [0.05 0.35 0.6 0.6])
    
        if length(wgpy) >= 40
            set(s4, 'Position', [0.85 0.1 0.12 0.85])
            set(s2, 'Position', [0.7 0.1 0.12 0.85])
        else
            set(s2, 'Position', [0.7 0.1 0.2 0.85])
        end
    
        set(result_fig, 'position', [100, 100, 1200, 800])
    end

    

    function cancelCallback(hObj, event)
        answer = questdlg('Are you sure to abort analysis?', 'Abort confirm', 'Yes', 'No', 'No');
        switch answer
        case 'Yes'
            if isprop(hObj, 'Style') && strcmp(hObj.Style, 'pushbutton')
                delete(hObj.Parent);
            else
                delete(hObj);
            end
            error("User aborted.")
        case 'No'
            return;
        end
    end

    function testCallback(hObj, event)  
        mincount = str2double(get(hObj,'string'));
        drawImage(mincount);
    end


    function confirmCallback(hObj, event)
        uiresume;
        return;
    end
end


function validSites = spacialFilter(poly_pos, x, y)
    validSites = zeros(1, length(x));
    line1 = poly_pos(1:2, :);
    line2 = poly_pos(2:3, :);
    line3 = poly_pos(3:4, :);
    line4 = poly_pos([4, 1], :);
    minlen1 = min(norm(line1(1, :)-line1(2, :)), norm(line3(1, :)-line3(2, :)));
    minlen2 = min(norm(line2(1, :)-line2(2, :)), norm(line4(1, :)-line4(2, :)));

    for idx = 1:length(x)
        space_ratio = 0.05; % To ignore sites that is to close to the boundary
        % space_thres = 
        exist_space_line1 = getPointLineDistance(x(idx), y(idx), line1(1, 1), line1(1, 2), line1(2, 1), line1(2, 2)) > minlen2*space_ratio;
        exist_space_line2 = getPointLineDistance(x(idx), y(idx), line2(1, 1), line2(1, 2), line2(2, 1), line2(2, 2)) > minlen1*space_ratio;
        exist_space_line3 = getPointLineDistance(x(idx), y(idx), line3(1, 1), line3(1, 2), line3(2, 1), line3(2, 2)) > minlen2*space_ratio;
        exist_space_line4 = getPointLineDistance(x(idx), y(idx), line4(1, 1), line4(1, 2), line4(2, 1), line4(2, 2)) > minlen1*space_ratio;
        exist_space_all = exist_space_line1 && exist_space_line2 && exist_space_line3 && exist_space_line4;

        if inpolygon(x(idx), y(idx), poly_pos(:, 1), poly_pos(:, 2)) && exist_space_all
            validSites(idx) = 1;
        else
            validSites(idx) = 0;
        end
    end
end


function distance = getPointLineDistance(x3,y3,x1,y1,x2,y2)
    % Get the distance from a point (x3, y3) to
    % a line defined by two points (x1, y1) and (x2, y2);
    try
        
        % Find the numerator for our point-to-line distance formula.
        numerator = abs((x2 - x1) * (y1 - y3) - (x1 - x3) * (y2 - y1));
        
        % Find the denominator for our point-to-line distance formula.
        denominator = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2);
        
        % Compute the distance.
        distance = numerator ./ denominator;
    catch ME
        errorMessage = sprintf('Error in program %s.\nError Message:\n%s',...
            mfilename, ME.message);
        uiwait(errordlg(errorMessage));
    end
    return; % from getPointLineDistance()
end

function ROIConfirm(hObj, event)
    if event.Button == 3
        uiresume;
        return;
    end
end
