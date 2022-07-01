timeBinResults = data.data.data.timeBinResults;
nBins = length(timeBinResults);
binWidth_ns = data.data.meta.prefs.bin_width_ns;
prob = timeBinResults/binWidth_ns/(data.data.meta.prefs.averages*data.data.meta.prefs.samples);

fig = figure;
ax = axes;

start_ns = 1;
end_ns = 512; 
startBin = ceil(start_ns/binWidth_ns);
endBin = floor(end_ns/binWidth_ns);
plot((startBin:endBin)*binWidth_ns, prob(startBin:endBin));
set(ax, 'YScale', 'log')

logfit_start_ns = 226;
logfit_end_ns = 238;
logfitStartBin = ceil(logfit_start_ns/binWidth_ns);
logfitEndBin = floor(logfit_end_ns/binWidth_ns);

original_x = (logfitStartBin:logfitEndBin)*binWidth_ns;
original_y = prob(logfitStartBin:logfitEndBin);

logcurve = polyfit((original_x), log(original_y), 1);
logfit_y = exp(polyval(logcurve, (original_x)));
hold on;
plot(original_x, logfit_y);

set(get(gca, 'XLabel'), 'String', 'Time (ns)');
set(get(gca, 'YLabel'), 'String', 'Photon Collection Probability ($ns^{-1}$)', 'Interpreter', 'latex');
% log_fig = figure;
% plot((original_x), log(original_y))
% hold on;
% plot((original_x), log(logfit_y))

lifetime_ns = 1/(-logcurve(1));