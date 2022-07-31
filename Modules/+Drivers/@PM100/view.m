function view(obj)
    %VIEW Creates view for PM100
    obj.fig = figure('name', 'Thorlabs Power Meter PM100', 'HandleVisibility', 'Callback', 'IntegerHandle', 'off', ...
    'menu', 'none', 'numbertitle', 'off', 'closerequestfcn', @obj.close_req);
    obj.ax = axes('parent', obj.fig, 'units', 'normalized', 'OuterPosition', [0 0.15 1 0.85]);
    obj.plt = plot(obj.ax, 0, NaN);
    obj.fig.UserData = struct('x', [0], 'y', [NaN]);
    % Comment the following line to hide the text in the center of the axes
    obj.textH = text(0.5, 0.5, 'NaN', 'Parent', obj.ax, 'horizontalalignment', 'center', ...
    'units', 'normalized', 'fontsize', 50);
    xlabel(obj.ax, 'Time (s)')
    ylabel(obj.ax, sprintf('Power (%s)', obj.display_unit))
    panelH = uipanel(obj.fig, 'units', 'normalized', 'position', [0 0 1 0.15], 'title', 'Settings');


    % Control fields
    uicontrol(panelH, 'style', 'pushbutton', 'string', 'Start', ...
    'units', 'characters', 'callback', @(~, ~)obj.set_start, ...
        'horizontalalignment', 'left', 'position', [.5 0.5 10 1.5]);
    uicontrol(panelH, 'style', 'pushbutton', 'string', 'Stop', ...
        'units', 'characters', 'callback', @(~, ~)obj.set_stop, ...
        'horizontalalignment', 'left', 'position', [11 0.5 10 1.5]);
    uicontrol(panelH, 'style', 'pushbutton', 'string', 'Export', 'tooltipstring', 'Export line data to workspace', ...
        'units', 'characters', 'callback', @export, 'UserData', obj, ...
        'horizontalalignment', 'left', 'position', [21.5 0.5 10 1.5]);

    uicontrol(panelH, 'style', 'text', 'string', 'Unit:', 'horizontalalignment', 'right', ...
        'units', 'characters', 'position', [32 0.5 18 1.25]);
    uicontrol(panelH, 'style', 'popupmenu', 'string', {'W', 'mW', 'uW', 'nW'}, ...
        'units', 'characters', 'callback', @obj.update_unit_callback, ...
        'horizontalalignment', 'left', 'position', [51 0.5 10 1.5], 'Value', find(strcmp(obj.display_unit, {'W', 'mW', 'uW', 'nW'})));

    uicontrol(panelH, 'style', 'text', 'string', 'Update Rate (s):', 'horizontalalignment', 'right', ...
        'units', 'characters', 'position', [61 0.5 18 1.25]);
    uicontrol(panelH, 'style', 'edit', 'string', num2str(obj.update_rate), ...
        'units', 'characters', 'callback', @obj.update_rate_callback, ...
        'horizontalalignment', 'left', 'position', [80 0.5 10 1.5]);

    uicontrol(panelH, 'style', 'text', 'string', 'Window Max (s):', 'horizontalalignment', 'right', ...
        'units', 'characters', 'position', [91 0.5 18 1.25]);
    uicontrol(panelH, 'style', 'edit', 'string', num2str(obj.window_max), ...
        'units', 'characters', 'callback', @obj.window_max_callback, ...
        'horizontalalignment', 'left', 'position', [110 0.5 10 1.5]);
    obj.fig.Units = 'characters';
    obj.fig.Position(3) = 121;
end

function export(hObj, ~)
    base_name = 'powermeter_data';
    % Get first free powermeter_data variable
    if ~isempty(evalin('base', sprintf('whos(''%s'')', base_name)))
        answer = questdlg(sprintf('Overwrite existing %s in workspace?', base_name), 'PM100 Export', 'Continue', 'Cancel', 'Continue');
        if strcmp('Cancel', answer)
            % Do not assign anything
            return
        end
    end
    powermeter_data.x = hObj.UserData.plt.XData;
    powermeter_data.y = hObj.UserData.plt.YData;
    assignin('base', base_name, powermeter_data);
end


