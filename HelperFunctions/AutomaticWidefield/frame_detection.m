function processed_image = frame_detection(input_image, make_plots, args)
    % Args: struct with fields {}
    if isstring(input_image) || ischar(input_image)
        try
            input_image = imread(input_image);
        catch
            input_mat = load(input_image);
            input_image = input_mat.image.image;
            input_image = uint8(floor(double(input_image)*256/double(max(input_image, [], 'all'))));
        end
    end

    if exist('args', 'var') && isfield(args, 'bin1_thres_ratio')
        bin1_thres_ratio = args.bin1_thres_ratio;
    else
        bin1_thres_ratio = 0.1;
    end
    if exist('args', 'var') && isfield(args, 'bin2_thres_ratio')
        bin2_thres_ratio = args.bin2_thres_ratio;
    else
        bin2_thres_ratio = 0.1;
    end
    if exist('args', 'var') && isfield(args, 'cutoff_low')
        cutoff_low = args.cutoff_low;
    else
        cutoff_low = 20;
    end
    if exist('args', 'var') && isfield(args, 'cutoff_high')
        cutoff_high = args.cutoff_high;
    else
        cutoff_high = 80;
    end
    if exist('args', 'var') && isfield(args, 'min_pixel')
        min_pixel = args.min_pixel;
    else
        min_pixel = 200;
    end
    if exist('args', 'var') && isfield(args, 'disk_radius')
        disk_radius = args.disk_radius;
    else
        disk_radius = 5;
    end



    if size(input_image, 3) == 3
        input_image = rgb2gray(input_image);
    end


    [counts, binLocations] = imhist(input_image);

    n = length(binLocations);
    count_sum = 0;
    total_sum = sum(counts);


    for k = n:-1:1
        count_sum = count_sum + counts(k);
        if count_sum > total_sum*bin1_thres_ratio
            mask = input_image > k;
            bin1_image = mask*255;
            break;
        end
    end

    % Saving the size of the bin1_image in pixels-
    % M : no of rows (height of the image)
    % N : no of columns (width of the image)
    [M, N] = size(bin1_image);
    
    % Getting Fourier Transform of the bin1_image
    % using MATLAB library function fft2 (2D fast fourier transform)  
    FT_img = fft2(double(bin1_image));
    
    % Designing filter
    u = 0:(M-1);
    idx = find(u>M/2);
    u(idx) = u(idx)-M;
    v = 0:(N-1);
    idy = find(v>N/2);
    v(idy) = v(idy)-N;
    
    % MATLAB library function meshgrid(v, u) returns 2D grid
    %  which contains the coordinates of vectors v and u. 
    % Matrix V with each row is a copy of v, and matrix U 
    % with each column is a copy of u
    [V, U] = meshgrid(v, u);
    
    % Calculating Euclidean Distance
    D = sqrt(U.^2+V.^2);
    
    % Comparing with the cut-off frequency and 
    % determining the filtering mask
    H = double(D < cutoff_high & D > cutoff_low);
    
    % Convolution between the Fourier Transformed image and the mask
    G = H.*FT_img;
    
    % Getting the resultant image by Inverse Fourier Transform
    % of the convoluted image using MATLAB library function
    % ifft2 (2D inverse fast fourier transform)  
    filtered_image = real(ifft2(double(G)));



    n_pixel = numel(filtered_image);

    for k = max(filtered_image(:)):-5:min(filtered_image(:))
        if sum(filtered_image(:)>=k) > n_pixel*bin2_thres_ratio
            bin2_image = filtered_image>=k;
            fprintf('Threshold value: %d\n', k);
            break;
        end 
    end

    opened_image = bwareaopen(bin2_image, min_pixel);

    closed_image = imclose(opened_image, strel('disk',disk_radius));

    CC = bwconncomp(closed_image);
    numPixels = cellfun(@numel,CC.PixelIdxList);
    [biggest,idx] = max(numPixels);
    for k = 1:length(numPixels)
        if k ~= idx
            closed_image(CC.PixelIdxList{k}) = 0;
        end
    end

    if exist('make_plots', 'var') && make_plots
        figure;
        % Displaying Input Image and Output Image
        subplot(2, 3, 1), imshow(input_image), set(get(gca, 'Title'), 'String', 'Input image');
        subplot(2, 3, 2), imshow(bin1_image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", bin1_thres_ratio));
        subplot(2, 3, 3), imshow(filtered_image, []), set(get(gca, 'Title'), 'String', sprintf("2D bandpass filter\ncutoff: [%d, %d]", cutoff_high, cutoff_low));
        subplot(2, 3, 4), imshow(bin2_image), set(get(gca, 'Title'), 'String', sprintf("Binarized thres ratio: %.2f", bin2_thres_ratio));
        subplot(2, 3, 5), imshow(opened_image), set(get(gca, 'Title'), 'String', sprintf("Imopen min pixel: %d", min_pixel));
        subplot(2, 3, 6), imshow(closed_image), set(get(gca, 'Title'), 'String', sprintf("Imclose disk radius: %d\nKeep biggest component", disk_radius));
    end
    processed_image = closed_image;
end