timeBinResults = data.data.data.timeBinResults(5:4:end, :);

binNum = size(timeBinResults, 2);
bins = [1:binNum] * data.data.data.bin_width_ns;
widthNum = size(timeBinResults, 1);

% lightBLUE = [0.356862745098039,0.811764705882353,0.956862745098039];
% darkBLUE = [0.0196078431372549,0.0745098039215686,0.670588235294118];

% blueGRADIENTflexible = @(i,N) [1, 0, 0] + ([0, 0, 1]-[1, 0, 0])*((i-1)/(N-1));

c=[1 0 0;1 0.5 0;1 1 0; 0.5 1 0; 0 1 0; 0 1 1;0 0.5 1; 0 0 1; 0.5 0 1; 1 0 1];
fig = figure;
hold on;
for k = 1:widthNum
    plot(bins, timeBinResults(k, :), 'Color', c(k, :));
    hold on;
end





