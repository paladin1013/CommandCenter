time_bin_result = data.data.data.time_bin_result;

sync_ns = data.data.data.sync_ns;
bin_width_ns = data.data.data.bin_width_ns;
time_tag = (1:ceil(sync_ns/bin_width_ns))*bin_width_ns;

fig = figure;
ax = axes;
plot(time_tag, time_bin_result);
xlim([1, sync_ns])
set(ax, 'YScale', 'log')


logfit_start_ns = 60;
logfit_end_ns = 70;

original_x = time_tag(time_tag > logfit_start_ns & time_tag < logfit_end_ns);
original_y = time_bin_result(time_tag > logfit_start_ns & time_tag < logfit_end_ns);

logcurve = polyfit((original_x), log(original_y), 1);
logfit_y = exp(polyval(logcurve, (original_x)));
hold on;
plot(original_x, logfit_y);

log_fig = figure;
plot((original_x), log(original_y))
hold on;
plot((original_x), log(logfit_y))

