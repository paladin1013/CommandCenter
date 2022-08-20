classdef FullChipDataAnalyzer < Modules.Driver
    properties(SetObservable, GetObservable)
        workingDir = Prefs.String("", 'help', 'Base working directory.');
        append = Prefs.Boolean(false, 'help', 'Append to the current data when loading new data.');
        xmin = Prefs.Double(0, 'min', -20, 'max', 20, 'help', 'The minimum x chiplet coordinate');
        xmax = Prefs.Double(3, 'min', -20, 'max', 20, 'help', 'The maximum x chiplet coordinate');
        ymin = Prefs.Double(0, 'min', -20, 'max', 20, 'help', 'The minimum y chiplet coordinate');
        ymax = Prefs.Double(3, 'min', -20, 'max', 20, 'help', 'The maximum y chiplet coordinate');
        x = Prefs.Double(0, 'help', 'The current displaying x coordinate.');
        y = Prefs.Double(0, 'help', 'The current displaying y coordinate.');
        mincount = Prefs.Double(10000, 'help', 'Minimum thresold of EMCCD image count for an emitter.');
        draw = Prefs.Button('set', 'set_draw', 'help', 'Update figure of the current coordinate.')
    end

    properties
        prefs = {'workingDir', 'append', 'xmin', 'xmax', 'ymin', 'ymax', 'x', 'y', 'mincount'};
        data;
        figH;
        sumAxH;
        sumImH;
        cursH;
        coords; % Keep only valid coordinates
        wlSize = [512, 512]; % y, x
    end
    methods(Static)
        obj = instance()
    end

    methods(Access=private)
        function obj = FullChipDataAnalyzer()
            obj.loadPrefs;
        end
    end

    methods
        function loadData(obj, append, workingDir)
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
                    newX = newData.coordX;
                    newY = newData.coordY;
                    obj.coords(end+1, :) = [newX, newY];
                    obj.data{newX-obj.xmin+1, newY-obj.ymin+1} = struct('x', newX, 'y', newY, 'widefieldData', [newData.data1, newData.data2], 'wl', newData.wl);
                end
            end
        end
        function initFig(obj)
            if isempty(obj.figH) || ~isvalid(obj.figH)
                obj.figH = figure;
            end
            figure(obj.figH);
            obj.sumAxH = subplot(1, 5, 1);
            sumIm = zeros(obj.wlSize.*[obj.ymax-obj.ymin+1, obj.xmax-obj.xmin+1]);
            for k = 1:size(obj.coords, 1)
                coord = obj.coords(k, :);
                tempX = coord(1);
                tempY = coord(2);
                wlX = obj.wlSize(2);
                wlY = obj.wlSize(1);
                sumIm((tempY-obj.ymin)*wlY+1:(tempY-obj.ymin+1)*wlY, (tempX-obj.xmin)*wlX + 1:(tempX-obj.xmin+1)*wlX) = obj.data{tempX, tempY}.wl;
            end
            obj.sumImH = imagesc(obj.sumAxH, sumIm);
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
        function moveCoord(obj,hObj,event)
            switch event.Key
                case 'rightarrow'
                    obj.x = obj.x + 1;
                case 'leftarrow'
                    obj.x = obj.x - 1;
                case 'uparrow'
                    obj.y = obj.y + 1;
                case 'downarrow'
                    obj.y = obj.y - 1;
            end
            obj.updateFig;
        end
        function delete(obj,hObj,event)
%             da.figH.delete;
        end
        function updateFig(obj)

        end
        function val = set_draw(obj, val, ~)
            obj.updateFig;
        end
    end
end