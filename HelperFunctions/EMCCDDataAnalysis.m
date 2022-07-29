function EMCCDDataAnalysis(EMCCD_data_path, WL_data_path, load_processed_data, processed_data_path)
    if ~exist('EMCCD_data_path', 'var')
        EMCCD_data_path = 'Data/EMCCD_raw_data.mat';
    end
    if ~exist('WL_data_path', 'var')
        WL_data_path = 'Data/wightlight_data.mat';
    end
    if ~exist('processed_data_path', 'var')
        processed_data_path = 'Data/EMCCD_processed_data.mat';
    end

    if exist('load_processed_data', 'var') && (load_processed_data==true)
        try
            d = load(processed_data_path);
            d = d.d;
        catch
            fprintf("%s file does not exist, loading original data from %s\n", processed_data_path, EMCCD_data_path);
            d = load(EMCCD_data_path);
        end
    else
        d = load(EMCCD_data_path);
    end
    wl = load(WL_data_path);

    % Find the number of non-NaN elements:
    validFrameNum = sum(~isnan(d.data.data.data.freqMeasured))-1;
    freqs = d.data.data.data.freqMeasured(1:validFrameNum);
    imgs = d.data.data.data.images_EMCCD(:, :, 1:validFrameNum);

    %%
    % Emitter filter
    mincount = 10000; %filter emitter
    rxmin = 0;
    rymin = 0;
    rxmax = 500;
    rymax = 500;

    %display
    ylim_min = 00;
    ylim_max = 500;
    xlim_min = 0;
    xlim_max = 500;
    %

    if ~isfield(d, 'imgs2')
        d.imgs2 = imgs;

        for ii = 1:length(freqs)
            if ~mod(ii, 10)
                ii;
            end
            %             d.imgs2(:,:,ii) = flatten(imgaussfilt(remove_spikes(imgs(:,:,ii), 3),1));
            d.imgs2(:, :, ii) = imgaussfilt(remove_spikes(imgs(:, :, ii), 3), 1);
        end
        save(processed_data_path, 'd');
    end

    imgs2 = d.imgs2(:, :, 1:length(freqs));

    try close(1); catch; end
    fig1 = figure(1);

    allpts0 = reshape(imgs2, [512 * 512, length(freqs)]);
    allpts0(max(allpts0, [], 2) < mincount, :) = [];

    p0 = zeros(5, length(allpts0(:, 1)));
    [p0(5, :), p0(3, :)] = find(allpts0 == max(allpts0, [], 2));

    box('on');

    for i = 1:length(allpts0(:, 1))
        p0(4, i) = allpts0(p0(5, i), p0(3, i));
        [a, b] = find(d.imgs2(:, :, p0(3, i)) == p0(4, i));
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

    labels = [];

    wgc = [];
    wgw = [];
    wgx = [];
    wgy = [];
    wgpx = [];
    wgpy = [];
    wgym = [];
    for i = 1:length(fres)
        hold on
        if (realx(i) < rxmax) & (realx(i) > rxmin) & (realy(i) < rymax) & (realy(i) > rymin)
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
        ylim([40 length(wgpx)])
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
        ylim([0 length(wgpx)])
        xlim([-1.6 1.6])
        yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
        yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});

        xlabel('Detuned (GHz)')
        ylabel('Emitter number')
        % yticks([])

        set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')

    end

    s1 = subplot(1, 4, 1);

    img = squeeze(max(imgs2, [], 3));
    % imagesc(d.data.data.data.images_EMCCD(rxmin:rxmax,rymin:rymax,2))
    imH = imagesc(wl.image.image(:, :));
    % imagesc(imgs(:,:,28))
    colormap('bone')
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

    scatter(rymin, rxmin, 'w', 'filled')
    scatter(rymax, rxmax, 'w', 'filled', 's')

    hold off

    xlim([xlim_min xlim_max])
    ylim([ylim_min ylim_max])
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
            line([wgc(i) wgc(i)], [mincount 6.5e4], 'Color', 'k', 'LineStyle', '--')
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

    set(gcf, 'position', [10, 10, 1200, 800])
    

% Polygon ROI
    validSites = ones(1, length(wgpx));
    polyH = drawpolygon(s1, 'Position', [rxmin, rxmax, rxmax, rxmin; rymin, rymin, rymax, rymax]');
    polyListener = addlistener(polyH, 'ROIMoved', @polyMoveCallback);
    polyPos = polyH.Position;
    set(get(s1, 'Title'), 'String', 'Middle-click the image to save ROI');
    fig1.ButtonDownFcn = @ROIConfirm;
    imH.ButtonDownFcn = @ROIConfirm;
    s1.ButtonDownFcn = @ROIConfirm;
    uiwait(fig1);

    T = [1, 2, 3; 3, 4, 1];
    TR = triangulation(T, polyPos);
    hold(s1, 'on');
    triplot(TR);
    tri1 = TR.Points(TR.ConnectivityList(1, :), :);
    tri2 = TR.Points(TR.ConnectivityList(2, :), :);
    sites = cell(1, length(wgpx));
    validCnt = 0;
    for k = 1:length(wgpx)
        cartPos = [wgpx(k), wgpy(k)];
        if ~validSites(k)
            continue
        end
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
    savePath = 'Data/AutomaticMeasurementData/EMCCD_sites_file.mat';
    fprintf("Sites data saved to %s\n", savePath);
    save(savePath, 'sites');
    function polyMoveCallback(hObj, event)
        polyPos = hObj.Position;
        % line1 = polyPos(1:2)
        line1 = polyPos(1:2, :);
        line2 = polyPos(2:3, :);
        line3 = polyPos(3:4, :);
        line4 = polyPos([4, 1], :);
        minlen1 = min(norm(line1(1, :)-line1(2, :)), norm(line3(1, :)-line3(2, :)));
        minlen2 = min(norm(line2(1, :)-line2(2, :)), norm(line4(1, :)-line4(2, :)));

        for idx = 1:length(wgpx)
            space_ratio = 0.05; % To ignore sites that is to close to the boundary
            % space_thres = 
            exist_space_line1 = GetPointLineDistance(wgpx(idx), wgpy(idx), line1(1, 1), line1(1, 2), line1(2, 1), line1(2, 2)) > minlen2*space_ratio;
            exist_space_line2 = GetPointLineDistance(wgpx(idx), wgpy(idx), line2(1, 1), line2(1, 2), line2(2, 1), line2(2, 2)) > minlen1*space_ratio;
            exist_space_line3 = GetPointLineDistance(wgpx(idx), wgpy(idx), line3(1, 1), line3(1, 2), line3(2, 1), line3(2, 2)) > minlen2*space_ratio;
            exist_space_line4 = GetPointLineDistance(wgpx(idx), wgpy(idx), line4(1, 1), line4(1, 2), line4(2, 1), line4(2, 2)) > minlen1*space_ratio;
            exist_space_all = exist_space_line1 && exist_space_line2 && exist_space_line3 && exist_space_line4;

            if inpolygon(wgpx(idx), wgpy(idx), polyPos(:, 1), polyPos(:, 2)) && exist_space_all
                validSites(idx) = 1;
                for figIdx = 1:3
                    figureHandles{idx, figIdx}.Visible = true;
                end
                figureHandles{idx, 2}
            else
                validSites(idx) = 0;
                for figIdx = 1:3
                    figureHandles{idx, figIdx}.Visible = false;
                end
            end
        end
    end
    function ROIConfirm(hObj, event)
        if event.Button == 2
            uiresume;
            return;
        end
    end

    function distance = GetPointLineDistance(x3,y3,x1,y1,x2,y2)
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
        return; % from GetPointLineDistance()
    end
end