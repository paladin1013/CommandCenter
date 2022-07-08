function fig = plot_records(obj, dim, axis_available, axis_name)
    % `axis_available` and `axis_name` should be consistent with the order of obj.record_array{i}.pos
    if ~exist('axis_available', 'var')
        % Which axis is in use
        axis_available = 1;
    end
    fig = figure;
    ax = axis;
    record_dim = sum(~isnan(obj.record_array{1}.pos));
    assert(dim == record_dim, sprintf("Input dimension (%d) is not consistent with recorded position dimension (%d).", length(find(axis_available)), dim));
    
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
    end
end
