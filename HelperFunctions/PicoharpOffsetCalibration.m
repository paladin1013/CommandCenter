% load('\\houston.mit.edu\qpgroup\Experiments\Diamond\picoharp_calib\Experiments_PicoHarpCalibration2022_05_11_10_45_08.mat')

APDCount = squeeze(data.data.data.counts(1, 1, :, :));
diff = data.data.data.diff(1, 1, :, :);
% timeTags_ps = data.data.data.timeTags;
timeTagsCh0_ps = data.data.data.rawTimeTagsCh0(1, 1, :);
timeTagsCh1_ps = data.data.data.rawTimeTagsCh1(1, 1, :);

roundNum = numel(timeTagsCh0_ps);
sampleNum = (numel(timeTagsCh0_ps{1})+3)/5;
offsets_us = linspace(-1, 1, 21);
signCoefficients = [0, 1; 1, 1; -1, 1; -1, 0;-1, -1];

positiveErrorRate = zeros(size(signCoefficients, 1), numel(offsets_us));
negativeErrorRate = zeros(size(signCoefficients, 1), numel(offsets_us));
totalErrorRate = zeros(size(signCoefficients, 1), numel(offsets_us));


for signCnt = 1:size(signCoefficients, 1)
    for offsetCnt = 1:numel(offsets_us)
        fprintf("Offset: %.3f us (%d/%d)\n", offset_us, offsetCnt, numel(offsets_us));
        offset_us = offsets_us(offsetCnt);
        phCount = NaN([roundNum, sampleNum]);
        lineLength = fprintf("   round: %3d/%3d\n", 0, 0);

        for roundCnt = 1:roundNum
            fprintf(repmat('\b',1,lineLength));
            lineLength = fprintf("   round: %3d/%3d\n", roundCnt, roundNum);
            syncTT = timeTagsCh0_ps{1, 1, roundCnt};
            photonTT = timeTagsCh1_ps{1, 1, roundCnt};
            photonNum = length(photonTT);
            ptr = 1;
            for sampleCnt = 1:sampleNum
                startPulse = syncTT(sampleCnt*5-4)+offset_us*1e6*signCoefficients(signCnt, 1);
                endPulse = syncTT(sampleCnt*5-3)+offset_us*1e6*signCoefficients(signCnt, 2);
                % phCount(roundCnt, sampleCnt) = length(photonTT(photonTT>startPulse & photonTT<endPulse));
                while ptr < photonNum && photonTT(ptr)<startPulse
                    ptr = ptr + 1;
                end
                cnt = 0;
                while ptr < photonNum && photonTT(ptr)<endPulse
                    ptr = ptr + 1;
                    cnt = cnt + 1;
                end
                phCount(roundCnt, sampleCnt) = cnt;
            end
        end
        diff = phCount-APDCount;
        positiveErrorRate(signCnt, offsetCnt) = sum(diff(diff>0), 'all')/sum(APDCount, 'all');
        negativeErrorRate(signCnt, offsetCnt) = sum(-diff(diff<0), 'all')/sum(APDCount, 'all');
        totalErrorRate(signCnt, offsetCnt) = positiveErrorRate(signCnt, offsetCnt) + negativeErrorRate(signCnt, offsetCnt);
        fprintf(repmat('\b',1,lineLength));
        fprintf("  PositiveErr: %.4f, NegativeErr: %.4f, TotalErr: %.4f\n", positiveErrorRate(signCnt, offsetCnt), negativeErrorRate(signCnt, offsetCnt), totalErrorRate(signCnt, offsetCnt));
    end
    fig = figure(signCnt);
    plot(offsets_us, positiveErrorRate(signCnt, :));
    hold on;
    plot(offsets_us, negativeErrorRate(signCnt, :));
    plot(offsets_us, totalErrorRate(signCnt, :));
    hold off;
    set(get(gca, 'XLabel'), 'String', 'Offset (us)');
    set(get(gca, 'YLabel'), 'String', 'Error rate');
    set(get(gca, 'Title'), 'String', sprintf('Sign:%d, %d', signCoefficients(signCnt, 1), signCoefficients(signCnt, 2)));
    set(gca, 'xlimmode','auto','ylimmode','auto','ytickmode','auto')
    legend({'Positive error rate', 'Negative error rate', 'Total error rate'});
    % hold off;
end