function center_pos = image_matching(processed_image, processed_pattern, make_plots, patternROI)
    % plot: bool
    % ROI: [xmin, xmax; ymin, ymax];
    % processed_image = frame_detection(original_image, true);
    % processed_pattern = frame_detection(original_pattern, true);

    if ~exist('patternROI', 'var')
        col_has_val = any(processed_pattern, 1);
        row_has_val = any(processed_pattern, 2);
        patternROI = [find(col_has_val, 1), find(col_has_val, 1, 'last'); find(row_has_val, 1), find(row_has_val, 1, 'last')];
    end
    xmin = patternROI(1, 1);
    xmax = patternROI(1, 2);
    ymin = patternROI(2, 1);
    ymax = patternROI(2, 2);
    trimmed_pattern = processed_pattern(ymin:ymax, xmin:xmax);
    xcorr_result = xcorr2(processed_image,trimmed_pattern);
    [max_val,idx] = max(xcorr_result(:));
    [x,y] = ind2sub(size(xcorr_result),idx);
    center_pos = []
    if exist('make_plots', 'var') && make_plots
        corr_fig = figure;
        s1 = subplot(2, 2, 1); imshow(processed_image); set(get(s1, 'Title'), 'String', sprintf("Processed input image"));
        s2 = subplot(2, 2, 2); imshow(trimmed_pattern); set(get(s2, 'Title'), 'String', sprintf("Trimmed pattern image"));
        s3 = subplot(2, 2, 3);
        surf(s3, xcorr_result); shading(s3, "flat"); set(get(s3, 'Title'), 'String', 'Cross correlation results');
        s4 = subplot(2, 2, 4);
        if isstring(original_image) || ischar(original_image)
            try
                original_image = imread(original_image);
            catch
                input_mat = load(original_image);
                original_image = input_mat.image.image;
                original_image = uint8(floor(double(original_image)*256/double(max(original_image, [], 'all'))));
            end
        end
        imshow(original_image); 
        hold(s4, 'on');
        plot(s4, [y], [x], 'r.', 'MarkerSize', 10);
    end

end
