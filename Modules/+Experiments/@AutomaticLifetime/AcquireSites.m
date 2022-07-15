function acquireSites(obj,managers)
    % sites = Experiments.AutoExperiment.AutoExperiment_invisible.SiteFinder_Confocal(managers,obj.imaging_source,obj.site_selection);
    % function sites = SiteFinder_Confocal(managers,imaging_source,site_selection)
        % Finds positions of peaks in image; if manual input, plots image and allows user input
        % Returns struct sites, with fields:
        %   image = image used in finding sites
        %   positions = [Nx2] array of positions
        %   wavelengths_nm = [N];
        %   freqs_THz = [N];
        %   manual_input = boolean, true if positions were user-supplied
        %   meta = empty if manual_input, else UserData from imfindpeaks
    sites = struct('image',[],'positions',[],'method',obj.method,'meta',[], 'freqs_THz', []);

    if isempty(managers.Imaging.current_image)
        source_on = obj.imaging_source.source_on;
        obj.imaging_source.on;
        obj.imaging_source.power = 80;
        managers.Path.select_path('APD1'); %this may be unnecessary
        sites.image = managers.Imaging.snap; %take image snapshot
        if ~source_on
            obj.imaging_source.off;
        end
    else
        sites.image = managers.Imaging.current_image.info;
    end

    obj.figH = figure('Position', [500,  100, 1000, 1000]);
    obj.axH = axes('parent',obj.figH);
    obj.ax2H = axes('parent',obj.figH); % For sites scatter plot
    obj.sitesH = scatter(obj.ax2H, [], []);
    cbH = colorbar(obj.ax2H);
    cbH.Visible = 'off';
    colormap(obj.ax2H, 'jet');
    obj.ax2H.Visible = 'off';
    axis(obj.ax2H, 'equal');
    linkaxes([obj.axH, obj.ax2H]);
    obj.ax2H.Position = obj.axH.Position;
   

    obj.imH = imagesc(sites.image.ROI(1,:),sites.image.ROI(2,:),sites.image.image,'parent',obj.axH);


    colormap(obj.axH,managers.Imaging.set_colormap);
    set(obj.axH,'ydir','normal')
    axis(obj.axH,'image')
    obj.imageROI = sites.image.ROI;
    xmin = obj.imageROI(1,1);
    xmax = obj.imageROI(1,2);
    ymin = obj.imageROI(2,1);
    ymax = obj.imageROI(2,2);
    obj.validROIPoly = drawpolygon(obj.axH,'Position', [xmin, ymax; xmax, ymax; xmax, ymin; xmin, ymin ], 'Color', 'b');
    obj.validROIPoly.Deletable = false;
    obj.validROIPoly.FaceAlpha = 0.1;
    obj.listeners{1} = addlistener(obj.validROIPoly, 'ROIMoved', @obj.updateROI);
    obj.listeners{2} = addlistener(obj.figH, 'LocationChanged', @obj.adjustMarkerSize);

    if strcmp(obj.method, 'EMCCD')
        if isempty(obj.emccdSites.baryPos)
            obj.loadSitesData(obj.emccdDataPath);
        end
        obj.listeners{3} = addlistener(obj, 'emccdSites', 'PostSet', @obj.updateEMCCDSites);
        obj.updateEMCCDSites;
        set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to fit the imported site region\nMiddle click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
    elseif strcmp(obj.method, 'Spectrum')
        obj.listeners{3} = addlistener(obj, 'findedSites', 'PostSet', @obj.updateFindedSites);
        title('Drag red region to set space filter, then close adjustment window when done.')
        [obj.finderH,panelH] = imfindpeaks(obj.imH); %returns array of NV locations
        obj.finderH.Visible = 'off'; % Turn off finderH. Use obj.sitesH to display sites location
        obj.findedSites.absPos = [obj.finderH.XData', obj.finderH.YData'];
        obj.listeners{4} = addlistener(obj.finderH, 'YData', 'PostSet', @obj.updateFindedSites);
        set(get(obj.axH, 'Title'), 'String', sprintf('Move the contrast bar to find peaks\nClose the setting panel to confirm\n'));
        uiwait(panelH);
        set(get(obj.axH, 'Title'), 'String', sprintf('Drag the ROI rectangle to bound the active region\nMiddle click on figure (outside the rectangle area) to confirm\n(DO NOT CLOSE THE FIGURE!)'));
    end
    obj.updateROI;
    obj.imH.ButtonDownFcn = @im_clicked2; % Wait until next click
    uiwait(obj.figH);


    obj.imH.UserData.h = [];
    xabs = obj.sitesH.XData;
    yabs = obj.sitesH.YData;
    markerSize = obj.sitesH.SizeData;
    obj.sitesH.Visible = false;
    obj.validROIPoly.Visible = 'off';

    if strcmp(obj.method, 'EMCCD')
        freqs_THz = obj.emccdSites.freqs_THz;
        freq_max = max(freqs_THz);
        freq_min = min(freqs_THz);
        cmap = colormap(obj.ax2H, 'jet');
        colors = cmap(floor((freqs_THz-freq_min)*255/(freq_max-freq_min)+1), :);
    end

    % Convert all scatter points into pointROI
    for k = 1:length(xabs)
        if strcmp(obj.method, 'EMCCD')
            h = drawpoint(obj.axH, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)/10, 'Color', colors(k, :));
            h.UserData = freqs_THz(k);
        else
            h = drawpoint(obj.axH, 'Position', [xabs(k), yabs(k)], 'MarkerSize', markerSize(k)/10);
        end
        if isempty(obj.imH.UserData.h)
            obj.imH.UserData.h = h;
        else
            obj.imH.UserData.h(end+1) = h;
        end
    end
    if strcmp(obj.method, 'Spectrum')
        title(sprintf('Drag to adjust\nLeft click to add new points\nRight click on point to get menu to delete.\nMiddle click on image to finish (DO NOT CLOSE!)'))
    else
        title(sprintf('Drag to adjust\nRight click on point to get menu to delete.\n\nMiddle click on image to finish (DO NOT CLOSE!)'))
    end
    
    obj.imH.ButtonDownFcn = @im_clicked;
    uiwait(obj.figH);


    % Save data to sites
    sites.positions = NaN(0,2);
    sites.wavelengths_nm = NaN(0, 1);
    sites.freqs_THz = NaN(0, 1);
    for i = 1:length(obj.imH.UserData.h)
        if isvalid(obj.imH.UserData.h(i))
            sites.positions(end+1,:) = obj.imH.UserData.h(i).Position;
            if strcmp(obj.method, 'EMCCD')
                sites.freqs_THz(end+1,1) = obj.imH.UserData.h(i).UserData;
                sites.wavelengths_nm(end+1) = 3e4/obj.imH.UserData.h(i).UserData;
            end
        end
    end
    sites.positions = [sites.positions, NaN(size(sites.positions,1),1)]; % Add z axis
    % sites.validROI = obj.validROI;
    obj.sites = sites;
    save(obj.sitesDataPath, 'sites');
    close(obj.figH)
    assert(~isempty(sites.positions),'No positions!')
    function im_clicked(hObj,eventdata)
        if eventdata.Button == 2
            uiresume;
            return
        end
        if eventdata.Button ~= 1
            return
        end
        if strcmp(obj.method, 'Spectrum')
            h = drawpoint(hObj.Parent, 'Position', eventdata.IntersectionPoint(1:2), 'MarkerSize', 0.01*min(obj.figH.Position(3), obj.figH.Position(4)));
            if isempty(hObj.UserData.h)
                hObj.UserData.h = h;
            else
                hObj.UserData.h(end+1) = h;
            end
        else
            fprintf("Manualy adding sites is prohibited in `includeFreq` mode.\n");
        end
    end
    function im_clicked2(hObj,eventdata)
        if eventdata.Button == 2
            uiresume;
            return
        end
    end
end