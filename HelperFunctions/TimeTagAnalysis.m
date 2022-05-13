
% tt = squeeze(data.data.data.timeTags);

% times = NaN(1, numel(tt));
% nums = NaN(1, numel(tt));

% k = 1;
% for cnt = 1:size(tt, 1)
%     timeTags1 = tt{cnt, 1};
%     for l = 1:length(timeTags1)
%         times(k) = timeTags1(l);
%         nums(k) = cnt;
%         k = k+1;
%     end

% end

% scatter(times(1:k-1), nums(1:k-1), 'r')

% k = 1;  
% for cnt = 1:size(tt, 1)

%     timeTags2 = tt{cnt, 2};

%     for l = 1:length(timeTags2)
%     times(k) = timeTags2(l);
%     nums(k) = cnt;
%     k = k+1;
%     end
% end

% hold on;
% scatter(times(1:k-1), nums(1:k-1), 'b')

rawTT0 = data.data.data.rawTimeTags0;
rawTT1 = data.data.data.rawTimeTags1;

roundNum = numel(rawTT0);
sampleNum = (length(rawTT0{1})+3)/9;
preOffset_ps = 10e6;
postOffset_ps = 10e6; 

sampleTT = cell(1, roundNum*sampleNum);
duration = zeros(1, roundNum*sampleNum);
for roundCnt = 1:roundNum
    ptr = 1;
    for sampleCnt = 1:sampleNum
        startTime = rawTT0{roundCnt}(sampleCnt*9-8)-preOffset_ps;
        endTime = rawTT0{roundCnt}(sampleCnt*9-3)+postOffset_ps;
        duration((roundCnt-1)*sampleNum+sampleCnt) = endTime-startTime;
        photonNum = length(rawTT1{roundCnt});
        % phCount(roundCnt, sampleCnt) = length(rawTT1{roundCnt}(rawTT1{roundCnt}>startTime & rawTT1{roundCnt}<endTime));
        while ptr < photonNum && rawTT1{roundCnt}(ptr)<startTime
            ptr = ptr + 1;
        end
        cnt = 0;
        while ptr < photonNum && rawTT1{roundCnt}(ptr)<endTime
            ptr = ptr + 1;
            cnt = cnt + 1;
            sampleTT{(roundCnt-1)*sampleNum+sampleCnt}(cnt) = rawTT1{roundCnt}(ptr-1) - startTime;

        end
    end
end


k = 1;
times = NaN(1, numel(sampleTT));
nums = NaN(1, numel(sampleTT));
for cnt = 1:length(sampleTT)
    timeTags = sampleTT{cnt};
    if length(timeTags(timeTags<60e6)) < 2
        continue
    end
    for l = 1:length(timeTags)
        times(k) = timeTags(l);
        nums(k) = cnt;
        k = k+1;
    end
end
fig = figure;
durationAvg_ps = mean(duration);
durationStd_ps = std(duration);
scatter(times(1:k-1)/1e6, nums(1:k-1))
hold on;
line([preOffset_ps, preOffset_ps]/1e6, [0, length(sampleTT)], 'Color', 'k')
line(durationAvg_ps/1e6-[postOffset_ps, postOffset_ps]/1e6, [0, length(sampleTT)],  'Color', 'k')

set(get(gca, 'XLabel'), 'String', 'Time (us)');
set(get(gca, 'YLabel'), 'String', 'Sample No.');