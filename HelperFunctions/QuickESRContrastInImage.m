function [Contrast, pixels_of_interest] = QuickESRContrastInImage(data_img,norm_img,pixels_of_interest)
% function quickly finds the brightest XX number of pixels and uses them to
% find the ESR contrast.
[mImage, nImage] = size(norm_img);
data_img_1d = zeros(1,mImage*nImage);
data_img_1d(:) = norm_img;
if isempty(pixels_of_interest)
    [~, Pixel_ind_descend] = sort(data_img_1d, 'descend');
    nOfPoints = round(mImage*nImage*0.01); % pick the XX highest pixels points;
    pixels_of_interest=Pixel_ind_descend(1:nOfPoints);
end
Contrast = mean(data_img(pixels_of_interest)./norm_img(pixels_of_interest));
end
