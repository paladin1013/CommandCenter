
image = imread("");
pattern = imread("");



imageEdge = edge(image, 'Prewitt');
patternEdge = edge(image, 'Prewitt');
[R, T] = icp(reshapePointwise(imageEdge), reshapePointwise(patternEdge));







function nBy3Img = reshapePointwise(img)
    [length, width] = size(img);
    [X, Y] = meshgrid(1:length, 1:width);
    X = reshape(X, 1, []);
    Y = reshape(Y, 1, []);
    Z = reshape(img, 1, []);
    nBy3Img = [X;Y;Z];
end