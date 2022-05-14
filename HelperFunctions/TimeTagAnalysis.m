
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
fr=zeros(1,30);
n0=zeros(1,30);
thre=18;
% for thre=1:30
rdw=50;
for rdw=10:10:50
% for thre=1:20
k = 1;
% binEnd_ps = (70:5:170)*1e6;
binEnd_ps = (65+rdw)*1e6;
times = NaN(1, numel(sampleTT));
nums = NaN(1, numel(sampleTT));
% binTimes = NaN(1, 100000);
bin2Cnt = NaN(length(binEnd_ps), numel(sampleTT));
binStart_ps = 65e6;
validCnt = 0;
figure(1)


for cnt = 1:length(sampleTT)
    timeTags = sampleTT{cnt};
    if length(timeTags(timeTags<60e6)) < thre
        continue
    end
    validCnt = validCnt + 1;
    for l = 1:length(timeTags)
        times(k) = timeTags(l);
        nums(k) = cnt;
        k = k+1;
    end
    for l = 1:length(binEnd_ps)
    bin2Cnt(l, validCnt) = sum(timeTags > binStart_ps & timeTags < binEnd_ps(l));
    end
end
bin2Cnt = bin2Cnt(:, 1:validCnt);
% fig = figure;
% durationAvg_ps = mean(duration);
% durationStd_ps = std(duration);
% scatter(times(1:k-1)/1e6, nums(1:k-1))
% hold on;
% line([preOffset_ps, preOffset_ps]/1e6, [0, length(sampleTT)], 'Color', 'k')
% line(durationAvg_ps/1e6-[postOffset_ps, postOffset_ps]/1e6, [0, length(sampleTT)],  'Color', 'k')
% 
% set(get(gca, 'XLabel'), 'String', 'Time (us)');
% set(get(gca, 'YLabel'), 'String', 'Sample No.');


% scatter (thre,(mean(bin2Cnt, 2)))
% % hold on
% fig = figure;
% ax = axes(fig);
h1=histogram(bin2Cnt,'FaceAlpha',0.3,'Normalization','probability');
hdata1=h1.Values;
hold on
meanCnt = mean(bin2Cnt, 2)
stdCnt = std(bin2Cnt, 0, 2)
% plot(binEnd_ps-binStart_ps, meanCnt, 'b');
% xlim([0 inf])
% hold on;
% plot(binEnd_ps-binStart_ps, stdCnt, 'r');
% end


%% third time bin
% for thre=1:20
k = 1;
% binEnd_ps = (70:5:170)*1e6;
binEnd_ps = (170+rdw)*1e6;
times = NaN(1, numel(sampleTT));
nums = NaN(1, numel(sampleTT));
% binTimes = NaN(1, 100000);
bin2Cnt = NaN(length(binEnd_ps), numel(sampleTT));
binStart_ps = 170e6;
validCnt = 0;
% figure(1)

for cnt = 1:length(sampleTT)
    timeTags = sampleTT{cnt};
    if length(timeTags(timeTags<60e6)) < thre
        continue
    end
    validCnt = validCnt + 1;
    for l = 1:length(timeTags)
        times(k) = timeTags(l);
        nums(k) = cnt;
        k = k+1;
    end
    for l = 1:length(binEnd_ps)
    bin2Cnt(l, validCnt) = sum(timeTags > binStart_ps & timeTags < binEnd_ps(l));
    end
end
bin2Cnt = bin2Cnt(:, 1:validCnt);
validCnt
% fig = figure;
% durationAvg_ps = mean(duration);
% durationStd_ps = std(duration);
% scatter(times(1:k-1)/1e6, nums(1:k-1))
% hold on;
% line([preOffset_ps, preOffset_ps]/1e6, [0, length(sampleTT)], 'Color', 'k')
% line(durationAvg_ps/1e6-[postOffset_ps, postOffset_ps]/1e6, [0, length(sampleTT)],  'Color', 'k')
% 
% set(get(gca, 'XLabel'), 'String', 'Time (us)');
% set(get(gca, 'YLabel'), 'String', 'Sample No.');


h2=histogram(bin2Cnt,'FaceAlpha',0.3,'Normalization','probability');
hdata2=h2.Values;
meanCnt = mean(bin2Cnt, 2)
stdCnt = std(bin2Cnt, 0, 2)

    i_e=min(length(hdata1),length(hdata2));
    fidelity=zeros(1,length(h2.Values));
    for i=2:i_e
       err1=sum(hdata1(1:i-1))/sum(hdata1);
       err2=sum(hdata2(i:length(hdata2)))/sum(hdata2);
       fidelity(i)=1-(err1+err2)/2;
    end
%     brightp=sum(hdata1(thre+1:length(hdata1)))/sum(hdata1);
%     darkp=sum(hdata2(thre+1:length(hdata2)))/sum(hdata2);
    i0=find(fidelity==max(fidelity))
%     fr(thre)=max(fidelity);
%     n0(thre)=validCnt;
figure(2)
    max(fidelity)
    scatter(rdw,max(fidelity),'r')
    scatter(rdw,max(fidelity)-(1-exp(-rdw/1200)),'b')
%     hold on
%     ini_f(thre)=brightp/(brightp+darkp);
end
% 
% figure(2)
% plot(1:30,fr,'r')
% figure(3)
% plot(1:30,n0,'b')
