% function CavityEmitterDataAnalysis(EMCCD_data_path, WL_data_path, processed_data_path)
    % if ~exist('EMCCD_data_path', 'var')
    %     EMCCD_data_path = 'Experiments_ResonanceEMCCDonly2022_04_06_13_28_15.mat';
    % end
    % if ~exist('WL_data_path', 'var')
    %     WL_data_path = 'sep3W243d124_wl.mat';
    % end
    % if ~exist('processed_data_path', 'var')
    %     processed_data_path = 'EMCCD_processed_data.mat';
    % end

    % try
    %     d = load(processed_data_path)
    % catch
    %     frpintf("%s file does not exist, loading original from %d\n", processed_data_path, EMCCD_data_path);
    %     d = load(EMCCD_data_path);
    % end
    % freqs = d.data.data.data.freqMeasured;
    % wl = load(WL_data_path);
    % imgs = d.data.data.data.images_EMCCD(:, :, :);

    %%
    % Emitter filter
    mincount = 8000; %filter emitter
    rxmin = 100;
    rymin = 220;
    rxmax = 275;
    rymax = 305;

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
    end

    imgs2 = d.imgs2(:, :, 1:length(freqs));

    figure(1)

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

    % c=jet(length(wgpx));

    markerlist = ['o'; '+'; 'x'; 's'; 'd'; '^'; 'v'; '>'; '<'; 'p'; 'h'; '*'; '_'; '|'];
    markerlist2 = ['-o'; '-+'; '-x'; '-s'; '-d'; '-^'; '-v'; '->'; '-<'; '-p'; '-h'; '-*'; ];
    c = [1 0 0; 1 0.5 0; 1 1 0; 0.5 1 0; 0 1 0; 0 1 1; 0 0.5 1; 0 0 1; 0.5 0 1; 1 0 1];
    if length(wgpx) < 40

    end

    if length(wgpx) >= 40
        s2 = subplot(1, 4, 2)
        for i = 1:39
            hold on
            plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :))
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
        s4 = subplot(1, 4, 4)
        for i = 40:length(wgpx)
            hold on
            plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :))
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
        s2 = subplot(1, 4, 2)
        %  wgpx_max = max(wgpx, 1);
        for i = 1:length(wgpx)
            hold on
            % wgx_relative =wgx(i,:)-wgpx_max(1) ;
            plot(wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :))
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

    % legend(labels)
    %%

    s1 = subplot(1, 4, 1)

    img = squeeze(max(imgs2, [], 3));
    % imagesc(d.data.data.data.images_EMCCD(rxmin:rxmax,rymin:rymax,2))
    imagesc(wl.image.image(:, :))
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

    for i = 1:length(wgpx)
        hold on
        %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
        %         scatter(wgpx(i),wgpy(i),30, c(1+(i-floor(i/10)*10),:),markerlist(1+floor(i/10)),'Linewidth',2)
        scatter(wgpx(i), wgpy(i), 30, c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2)
        %     end
    end

    scatter(rymin, rxmin, 'w', 'filled')
    scatter(rymax, rxmax, 'w', 'filled', 's')

    hold off
    % set(s1,'DataAspectRatio',[1 1 1])
    % xticks([0 100 200 300 400])
    % yticks([0 100 200 300 400])
    % xlabel('y')
    % ylabel('x')

    xlim([xlim_min xlim_max])
    ylim([ylim_min ylim_max])
    xticks([])
    yticks([])
    set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')

    % Polygon ROI
    polyH = drawpolygon(s1, 'Position', [rymin, rymax, rymax, rymin;rxmin, rxmin, rxmax, rxmax]');
    


    % view(45,20)
    % title('(a) Emitter overlaid image','FontName', 'Times New Roman')
    %     function img = flatten(img0)
    %         img = img0 - imgaussfilt(img0, 10);
    %     end
    %%
    s3 = subplot(1, 4, 3)

    for i = 1:length(wgpx)
        hold on
        scatter(wgc(i), wgym(i), 30, c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2)
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

% end