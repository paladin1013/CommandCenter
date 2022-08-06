function center_pos = image_matching(processed_image, processed_template, show_plots)
    % plot: bool
    % ROI: [xmin, xmax; ymin, ymax];
    % processed_image = frame_detection(original_image, true);
    % processed_template = frame_detection(original_template, true);

    xcorr_result = xcorr2(double(processed_image),double(processed_template));
    [max_val,idx] = max(xcorr_result(:));
    [x,y] = ind2sub(size(xcorr_result),idx);
    center_pos = [x, y];
    if exist('show_plots', 'var') && show_plots
        corr_fig = figure;
        s1 = subplot(2, 2, 1); imshow(processed_image); set(get(s1, 'Title'), 'String', sprintf("Processed input image"));
        s2 = subplot(2, 2, 2); imshow(processed_template); set(get(s2, 'Title'), 'String', sprintf("Trimmed template image"));
        s3 = subplot(2, 2, 3);
        surf(s3, xcorr_result); shading(s3, "flat"); set(get(s3, 'Title'), 'String', 'Cross correlation results');
        s4 = subplot(2, 2, 4);
        imshow(processed_image); 
        hold(s4, 'on');
        plot(s4, [y], [x], 'r.', 'MarkerSize', 10);
    end

end
