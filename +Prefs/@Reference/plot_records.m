function fig = plot_records(obj, dim, axis_available, axis_name)
    % `axis_available` and `axis_name` should be consistent with the order of obj.record_array{i}.pos
    if ~exist('axis_available', 'var')
        % Which axis is in use
        axis_available = 1;
    end
    fig = figure;
    ax = axes('Parent', fig);
    record_dim = length(find(axis_available));
    assert(dim == record_dim, sprintf("Input dimension (%d) is not consistent with recorded position dimension (%d).", length(find(axis_available)), dim));
    function cbh = draw_color_bar(fig, min, max, cmap, pos)
        ax2 = axes('Parent', fig);
        colormap(cmap);
        cbh = colorbar('east'); % Colorbar handle
        ax2.Visible = 'off';
        caxis([min, max]);
        ylabel(cbh, 'Iteration number', 'Rotation', 90);
        cbh.Label.Position(1) = 2;
        cbh.Position(1) = 0.9;
        if exist('pos', 'var')
            set(cbh, 'Position', pos);
        end
    end
    switch dim
        case 1
            n = length(obj.record_array);
            x = zeros(1, n);
            val = zeros(1,n);
            st = zeros(1, n);
            x_axis = find(axis_available);
            for k = 1:n
                record = obj.record_array{k};
                x(k) = record.pos(x_axis);
                val(k) = record.val;
                st(k) = record.st;
            end
            errorbar(x, val, st, '.');
            maxval = max(val);
            minval = min(val);
            hold on;
            colors = flip(hot(n));
            for k = 1:n
                line(x(k), val(k), 'Color', colors(k, :), 'Marker', '.', 'MarkerSize', ceil(50*(val(k)-minval+1)/(maxval-minval)));
            end

            if exist('axis_name', 'var')
                set(get(gca, 'XLabel'), 'String', axis_name(x_axis));
            end
            if ~isempty(obj.parent.get_meta_pref('Target').reference)
                set(get(gca, 'YLabel'), 'String', obj.parent.get_meta_pref('Target').reference.name);
                
            end
        case 2
            n = length(obj.record_array);
            x = zeros(1, n);
            y = zeros(1, n);
            val = zeros(1,n);
            st = zeros(1, n);
            ax_idx = find(axis_available);
            x_axis = ax_idx(1);
            y_axis = ax_idx(2);
            for k = 1:n
                record = obj.record_array{k};
                x(k) = record.pos(x_axis);
                y(k) = record.pos(y_axis);              
                val(k) = record.val;
                st(k) = record.st;
            end
            maxval = max(val);
            minval = min(val);
            plot3([x;x], [y;y], [val-st; val+st], 'b-');
            hold on;
            colors = flip(hot(n));
            for k = 1:n
                line(x(k), y(k), val(k), 'Color', colors(k, :), 'Marker', '.', 'MarkerSize', ceil(50*(val(k)-minval+1)/(maxval-minval)));
            end
%                     plot3(x, y, val, '-');
            if exist('axis_name', 'var')
                set(get(gca, 'XLabel'), 'String', axis_name(x_axis));
                set(get(gca, 'YLabel'), 'String', axis_name(y_axis));
            end
            if ~isempty(obj.parent.get_meta_pref('Target').reference)
                set(get(gca, 'ZLabel'), 'String', obj.parent.get_meta_pref('Target').reference.name);
            end
            
        otherwise
            fprintf("Plotting records of dimision %d is not supported", dim);
            return;
    end
    ax.Position(3) = 0.7;
    draw_color_bar(fig, 1, n, flipud(colormap('hot')))
end
