classdef FullChipDataAnalyzer < Modules.Driver
    properties(SetObservable, GetObservable)
        workingDir = Prefs.String("", 'help', 'Base working directory.');
        append = Prefs.Boolean(false, 'help', 'Append to the current data when loading new data.');
        loadData = Prefs.Button('set', 'set_loadData', 'help', 'Load data from workind directory to Matlab.');
        xmin = Prefs.Integer(0, 'help', 'The minimum x chiplet coordinate');
        xmax = Prefs.Integer(3, 'help', 'The maximum x chiplet coordinate');
        ymin = Prefs.Integer(0, 'help', 'The minimum y chiplet coordinate');
        ymax = Prefs.Integer(3, 'help', 'The maximum y chiplet coordinate');
        x = Prefs.Integer(0, 'help', 'The current displaying x coordinate.');
        y = Prefs.Integer(0, 'help', 'The current displaying y coordinate.');
        mincount = Prefs.Integer(10000, 'help', 'Minimum thresold of EMCCD image count for an emitter.');
        freqBin_GHz = Prefs.Double(0.01, 'unit', 'GHz', 'help', 'Width of frequency binning when loading data.');
        countSelection = Prefs.MultipleChoice('average', 'choices', {'average', 'max', 'average of top 50%'}, 'help', 'Method to select the value for frequencybin');
        draw = Prefs.Button('set', 'set_draw', 'help', 'Update figure of the current coordinate.');
    end

    properties
        prefs = {'workingDir', 'append', 'loadData', 'xmin', 'xmax', 'ymin', 'ymax', 'x', 'y', 'mincount', 'draw'};
        data;
        figH;
        sumAxH;
        sumImH;
        wlAxH;
        wlImH;
        countAxH;
        spectrum1AxH;
        spectrum2AxH;
        cursH;
        coords; % Keep only valid coordinates
        wlSize = [512, 512]; % y, x
        initialized = false;
    end
    methods(Static)
        obj = instance()
    end

    methods(Access=private)
        function obj = FullChipDataAnalyzer()
            obj.loadPrefs;
            obj.initialized = true;
        end
    end

    methods
        function updateData(obj, append, workingDir)
            if ~exist('append', 'var')
                append = obj.append;
            end
            if ~exist('workingDir', 'var')
                workingDir = obj.workingDir;
            end
            files = dir(workingDir);
            if ~append
                obj.data = cell(obj.xmax-obj.xmin+1, obj.ymax-obj.ymin+1);
                obj.coords = zeros(0, 2);
            end
            for k = 1:length(files)
                file = files(k);
                fprintf('Checking file %s (%d/%d)\n', file.name, k, length(files));
                if endsWith(file.name, '.mat')
                    fprintf('Lodading Matlab data\n');
                    newData = load(fullfile(workingDir, file.name));
                    newX = newData.data.coordX;
                    newY = newData.data.coordY;
                    if append && isfield(obj.data{newX-obj.xmin+1, newY-obj.ymin+1}, 'widefieldData')
                        prevData = obj.data{newX-obj.xmin+1, newY-obj.ymin+1};
                        assert(isequal(size(prevData.widefieldData(1).wl_img), size(newData.data.data1.widefieldData(1).wl_img)), "Size of the new ROI is inconsistent with the old.");
                        obj.data{newX-obj.xmin+1, newY-obj.ymin+1} = struct('x', newX, 'y', newY, 'widefieldData', [prevData.widefieldData, newData.data.data1, newData.data.data2], 'wl', newData.data.wl);
                    else
                        obj.coords(end+1, :) = [newX, newY];
                        obj.data{newX-obj.xmin+1, newY-obj.ymin+1} = struct('x', newX, 'y', newY, 'widefieldData', [newData.data.data1, newData.data.data2], 'wl', newData.data.wl);
                    end
                end
            end
        end
        function selectCoord(obj,hObj,event)
            pt = event.IntersectionPoint([2,1]); %point that was just clicked
            dist = pdist2(pt,obj.coords); %distance between selection and all points
            [~, coordID] = min(dist); % index of minimum distance to points
            coord = obj.coords(coordID);
            obj.x = coord(1);
            obj.y = coord(2);
            obj.updateFig;
        end
        function valid = checkCoord(obj, x, y)
            if isempty(obj.data{x-obj.xmin+1, y-obj.ymin+1})
                fprintf("Data of chiplet (x:%d, y:%d) is empty. Please reload the data.\n", x, y);
                valid = false;
                return;
            end
            if x > obj.xmax
                fprintf("x = %d reaches obj.xmax. Stop moving coordinate.\n", x);
                valid = false;
                return
            end
            if x < obj.xmin
                fprintf("x = %d reaches obj.xmin. Stop moving coordinate.\n", x);
                valid = false;
                return
            end
            if y > obj.ymax
                fprintf("y = %d reaches obj.ymax. Stop moving coordinate.\n", y);
                valid = false;
                return
            end
            if y < obj.ymin
                fprintf("y = %d reaches obj.ymin. Stop moving coordinate.\n", y);
                valid = false;
                return
            end
            valid = true;
        end
        function moveCoord(obj,hObj,event)
            switch event.Key
                case 'rightarrow'
                    if obj.checkCoord(obj.x+1, obj.y)
                        obj.x = obj.x + 1;
                        obj.updateFig;
                    end
                case 'leftarrow'
                    if obj.checkCoord(obj.x-1, obj.y)
                        obj.x = obj.x - 1;
                        obj.updateFig;
                    end
                case 'downarrow'
                    if obj.checkCoord(obj.x, obj.y+1)
                        obj.y = obj.y + 1;
                        obj.updateFig;
                    end
                case 'uparrow'
                    if obj.checkCoord(obj.x, obj.y-1)
                        obj.y = obj.y - 1;
                        obj.updateFig;
                    end
            end
        end
        function deleteFigH(obj,hObj,event)
            obj.figH.delete;
        end
        function updateFig(obj)
            t = tic;

            % Extract chiplet widefield data
            tempData = obj.data{obj.x-obj.xmin+1, obj.y-obj.ymin+1};
            assert(~isempty(tempData), sprintf("Data of chiplet (x:%d, y:%d) is empty. Please reload the data.", obj.x, obj.y))
            nDataSet = length(tempData.widefieldData); % Number of datasets of the current chiplet
            ROIsize = size(tempData.widefieldData(1).wl_img);
            wl_img = tempData.widefieldData(1).wl_img;
            filtered_imgs = zeros(ROIsize(1), ROIsize(2), 0);
            freqs = zeros(1, 0);
            for k = 1:nDataSet
                tempFilteredImgs = tempData.widefieldData(k).filtered_imgs;
                nFrames = size(tempFilteredImgs, 3);
                freqs(end+1:end+nFrames) = tempData.widefieldData(k).freqs;
                filtered_imgs(:, :, end+1:end+nFrames) = tempFilteredImgs;
            end
            poly_pos = tempData.widefieldData(1).poly_pos;
            fprintf("time0: %f\n", toc(t));

            if isempty(obj.figH) || ~isvalid(obj.figH)
                obj.figH = figure;
            end
            axisNames = ["sumAxH", "wlAxH", "spectrum1AxH", "countAxH", "spectrum2AxH"];
            for k = 1:length(axisNames)
                if ~isempty(obj.(axisNames(k))) && isvalid(obj.(axisNames(k)))
                    delete(obj.(axisNames(k)));
                end
                figure(obj.figH);
                obj.(axisNames(k)) = subplot(5, 1, k);
            end
            figure(obj.figH);
            fprintf("time1: %f\n", toc(t));
            % Draw summary image
            sumIm = zeros(obj.wlSize.*[obj.ymax-obj.ymin+1, obj.xmax-obj.xmin+1]);
            wlX = obj.wlSize(2);
            wlY = obj.wlSize(1);
            for k = 1:size(obj.coords, 1)
                coord = obj.coords(k, :);
                tempX = coord(1);
                tempY = coord(2);
                sumIm((tempY-obj.ymin)*wlY+1:(tempY-obj.ymin+1)*wlY, (tempX-obj.xmin)*wlX + 1:(tempX-obj.xmin+1)*wlX) = obj.data{tempX-obj.xmin+1, tempY-obj.ymin+1}.wl;
            end
            obj.sumImH = imagesc(obj.sumAxH, sumIm);
            obj.sumAxH.Position = [0.05, 0.05, 0.25, 0.9];
            obj.sumAxH.XTickLabel = [obj.xmin:obj.xmax];
            obj.sumAxH.XTick = linspace(wlX/2, size(sumIm, 2)-wlX/2, obj.xmax-obj.xmin+1);
            obj.sumAxH.YTickLabel = [obj.xmin:obj.xmax];
            obj.sumAxH.YTick = linspace(wlY/2, size(sumIm, 1)-wlY/2, obj.ymax-obj.ymin+1);
            colormap(obj.sumAxH, 'bone');
            obj.sumImH.ButtonDownFcn = @obj.selectCoord;
            hold(obj.sumAxH, 'on');
            rectangle(obj.sumAxH, 'Position', [(obj.x-obj.xmin)*wlX + 1, (obj.y-obj.ymin)*wlY+1, wlX-1, wlY-1], 'LineWidth', 5, 'EdgeColor', 'r');
            obj.figH.KeyPressFcn = @obj.moveCoord;
            obj.figH.DeleteFcn = @obj.deleteFigH;
            fprintf("Updating chiplet figure of chiplet coordinate x:%d, y:%d\n", obj.x, obj.y);

            fprintf("time2: %f\n", toc(t));

            


            % Initialize record variables
            labels = [];
            wgc = [];
            wgw = [];
            wgx = [];
            wgy = [];
            wgpx = [];
            wgpy = [];
            wgym = [];
            allpts0 = reshape(filtered_imgs, [numel(wl_img), length(freqs)]);
            allpts0(max(allpts0, [], 2) < obj.mincount, :) = [];
        
            p0 = zeros(5, length(allpts0(:, 1)));
            [p0(5, :), p0(3, :)] = find(allpts0 == max(allpts0, [], 2));


            fprintf("time4: %f\n", toc(t));
        
        
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
                if valid(i) == 1
                    wgt = yy(i, :);
                    [wgtv, wgtp] = find(wgt == max(wgt));
    %                 wgt(max(1, wgtp - 2):min(length(yy), wgtp + 2)) = min(wgt);
    %                 if max(wgt(max(1, wgtp - floor(length(wgt) / 20)):min(length(wgt), wgtp + floor(length(wgt) / 20)))) > 0.5 * max(yy(i, :))
                        wgc = [wgc; freqs(wgtp)];
                        wgx = [wgx; (freqs - min(freqs) * ones(1, length(freqs))) * 1e3];
                        wgy = [wgy; yy(i, :)];
                        wgym = [wgym; max(yy(i, :))];
                        wgpx = [wgpx; realy(i)];
                        wgpy = [wgpy; realx(i)];
    %                 end
        
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
                for i = 1:39
                    hold(obj.spectrum1AxH, 'on');
                    figureHandles{i, 2} = plot(obj.spectrum1AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end

                hold(obj.spectrum1AxH, 'off');
                box(obj.spectrum1AxH, 'on');
                ylim(obj.spectrum1AxH, [1, 41]);
                xlim(obj.spectrum1AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
                for i = 40:length(wgpx)
                    hold(obj.spectrum2AxH, 'on');
                    
                    figureHandles{i, 2} = plot(obj.spectrum2AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end
        
                hold(obj.spectrum2AxH, 'off');
                box(obj.spectrum2AxH, 'on');
                ylim(obj.spectrum2AxH, [40 length(wgpx)+1])
                xlim(obj.spectrum2AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                %     ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            else
                %  wgpx_max = max(wgpx, 1);
                for i = 1:length(wgpx)
                    hold(obj.spectrum1AxH, 'on');
                    % wgx_relative =wgx(i,:)-wgpx_max(1) ;
                    figureHandles{i, 2} = plot(obj.spectrum1AxH, wgx(i, :) - wgx(i, find(wgy(i, :) == max(wgy(i, :)))) * ones(1, length(wgx(i, :))), i + wgy(i, :) / max(wgy(i, :)), markerlist2(1 + floor(i / 10)), 'linewidth', 2, 'Color', c(1 + (i - floor(i / 10) * 10), :));
                    %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                    %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                    %     set(t1,'Color',[0 0 0]);
                end
        

                hold(obj.spectrum1AxH, 'off');
                box(obj.spectrum1AxH, 'on');
                ylim(obj.spectrum1AxH, [1, length(wgpx)+1])
                xlim(obj.spectrum1AxH, [-1.6 1.6])
                yticks([0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100]);
                yticklabels({'0' 'o' '10' '+' '20' 'x' '30' 's' '40' 'd' '50' '^' '60' 'v' '70' '>' '80' '<' '90' 'p' '100'});
        
                xlabel('Detuned (GHz)')
                ylabel('Emitter number')
                % yticks([])
        
                set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
        
            end
            
            img = squeeze(max(filtered_imgs, [], 3));
            obj.wlImH = imagesc(obj.wlAxH, wl_img);
            colormap('bone')
            xlim(obj.wlAxH, [1, size(wl_img, 2)]);
            ylim(obj.wlAxH, [1, size(wl_img, 1)]);
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
        
                SizeData(i) = (wgym(i)-obj.mincount)/(max(wgym)-obj.mincount)*100+30;
                hold(obj.wlAxH, 'on');
                %     if (realx(i)<rxmax) & (realx(i)>rxmin) & (realy(i)<rymax) & (realy(i)>rymin)
                %         scatter(wgpx(i),wgpy(i),30, c(1+(i-floor(i/10)*10),:),markerlist(1+floor(i/10)),'Linewidth',2)
                figureHandles{i, 1} = scatter(obj.wlAxH, wgpx(i), wgpy(i), SizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
                %     end
            end
        
        
            hold off
        
            xticks([])
            yticks([])
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            for i = 1:length(wgpx)
                hold(obj.countAxH, 'on')
                figureHandles{i, 3} = scatter(obj.countAxH, wgc(i), wgym(i), SizeData(i), c(1 + (i - floor(i / 10) * 10), :), markerlist(1 + floor(i / 10)), 'Linewidth', 2);
                %     labels=[labels;strcat(num2str(i),':',{num2str((data.FOV.wgc(i)+0*(data.FOV.wgc(i)-484)*10000))},{'THz & '},{num2str(floor(data.FOV.wgw(i)))},{'MHz'})];
                %     t1=text(data.FOV.wgx(i,find(data.FOV.wgy(i,:)==max(data.FOV.wgy(i,:))))-0.34,1.05*max(data.FOV.wgy(i,:)),num2str(i),'FontSize', 13, 'FontWeight', 'bold');
                %     set(t1,'Color',[0 0 0]);
                if (i / 10 - floor(i / 10)) == 0
                    line([wgc(i) wgc(i)], [obj.mincount 6.5e4], 'Color', 'k', 'LineStyle', '--');
                end
            end
            set(gca, 'FontSize', 16, 'FontName', 'Times New Roman')
            xlabel('Frequency (THz)')
            ylabel('Pixel count')
            box on
            title('EMCCD Gain:1200, Expose Time:500ms, Pixel:16um*16um')
            yticks([3e4, 6e4]);
            ylim([obj.mincount 6.5e4]);
            hold off
        
            set(obj.countAxH, 'Position', [0.35 0.1 0.4 0.15])
        
            % set(s1, 'Position', [0.08 0.38 0.58 0.58])
            set(obj.wlAxH, 'Position', [0.35 0.35 0.4 0.6])
        
            if length(wgpy) >= 40
                set(obj.spectrum2AxH, 'Position', [0.9 0.1 0.08 0.85]);
                set(obj.spectrum1AxH, 'Position', [0.8 0.1 0.08 0.85]);
            else
                set(obj.spectrum1AxH, 'Position', [0.8 0.1 0.15 0.85]);
                set(obj.spectrum2AxH, 'Visible', 'off');
            end
        
            set(obj.figH, 'position', [100, 100, 1600, 800])
            fprintf("time5: %f\n", toc(t));

        end
        function val = set_draw(obj, val, ~)

            if ~obj.initialized
                return;
            end
            obj.updateFig;
        end
        function val = set_loadData(obj, val, ~)

            if ~obj.initialized
                return;
            end
            obj.updateData;
        end
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
        space_ratio = 0.05; % To ignore sites that is too close to the boundary
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