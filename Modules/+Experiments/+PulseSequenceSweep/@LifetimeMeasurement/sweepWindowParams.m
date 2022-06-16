function sweepWindowParams(obj, ax, p, status)
    % To find the optimal `resonance laser window span & offset`

    offsets = eval(obj.resWindowOffsetStr_us);
    nOffsets = length(offsets);
    spans = eval(obj.resWindowSpanStr_us);
    nSpans = length(spans);
    pulseWidth_ns = obj.PulseWidths_ns;
    nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
    t = tic;
    cntStartBin = ceil(mod(obj.PulseBound_ns(1), obj.PulsePeriod_ns)/obj.bin_width_ns);
    cntEndBin = ceil(mod(obj.PulseBound_ns(2), obj.PulsePeriod_ns)/obj.bin_width_ns);
    line([cntStartBin, cntStartBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
    line([cntEndBin, cntEndBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');


    obj.data.timeTags = cell(nOffsets, nSpans, obj.averages);
    obj.data.sectionProbability = zeros(nOffsets, nSpans);
    obj.data.totalProbability = zeros(nOffsets, nSpans);
    obj.data.timeBinResults = zeros(nOffsets, nSpans, nBins);

    waveformName = sprintf("%s_%.1f_%dns_%d", 'square', pulseWidth_ns, obj.PulsePeriod_ns, obj.PulseRepeat);
    AWGPulseGen(obj.PulseBase, pulseWidth_ns, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName), 'square');
    obj.AWG.writeReadToSocket('SYST:ERR:ALL?');
    obj.AWG.loadWaveform(obj.AWG_Channel, waveformName);
    obj.AWG.setAmplitude(obj.AWG_Channel, obj.AWG_Amplitude_V);
    obj.AWG.setResolution(obj.AWG_Channel, 8);
    obj.AWG.setChannelOn(obj.AWG_Channel);
    obj.AWG.setRunMode(obj.AWG_Channel, 'T');
    obj.AWG.setTriggerSource(obj.AWG_Channel, obj.AWG_TriggerSource);
    obj.AWG.AWGStart;



    ax(1) = axes;
    colors = jet(nOffsets);
    for offsetIdx = 1:nOffsets

        line([-1], [-1], 'Parent', ax(1), 'Color', colors(offsetIdx, :));
        for spanIdx = 1:nSpans
            timeBinResult = zeros(1, nBins);

            fprintf("t1: %.2f\n", toc(t));
            obj.resWindowOffset_us = offsets(offsetIdx);
            obj.resWindowSpan_us = spans(spanIdx);
            drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
            periodNum = 0;
            pulseSeq = obj.BuildPulseSequence(pulseWidth_ns);
            fprintf("t2: %.2f\n", toc(t));
            pulseSeq.repeat = obj.samples;
            apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
            fprintf("t3: %.2f\n", toc(t));
            apdPS.seq = pulseSeq;
            if pulseSeq ~= false
                for averageIdx = 1:obj.averages
                    drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
                    status.String = [sprintf('offset = %g (%i/%i)\nspan = %g (%i/%i)\n', obj.resWindowOffset_us,offsetIdx, nOffsets, obj.resWindowSpan_us, spanIdx, nSpans), sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages), sprintf('Time elapsed %.2f', toc(t))];

                    fprintf("t4: %.2f\n", toc(t));

                    if averageIdx == 1 % Since each pulse sequence in all averages are the same, we only need to compile for the first round.
                        apdPS.start(1000) % hard coded
                    else
                        % skip the compile process
                        apdPS.start(1000, false, true); 
                    end
                    fprintf("t5: %.2f\n", toc(t));

                    [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;
                    fprintf("t6: %.2f\n", toc(t));

                    apdPS.stream(p);
                    fprintf("t7: %.2f\n", toc(t));

                    obj.picoharpH.PH_StopMeas;
                                    % Count photon time tags
                    photonPt = 1;
                    collectedPhotonCnt = 0;
                    relativeTimeTags_ns = zeros(1, 10000);
                    assert(length(rawTttrData0) == obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",obj.samples - 3, length(rawTttrData0)))
                    
                    % Analyze photon time tags
                    for k = 1:(obj.samples-3)
                        while(k < length(rawTttrData0) &&  photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)))
                            photonPt = photonPt + 1;
                        end
                        while(photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)+obj.PulseRepeat*obj.PulsePeriod_ns*1000))
                            collectedPhotonCnt = collectedPhotonCnt + 1;
                            relativeTimeTags_ns(collectedPhotonCnt) = (rawTttrData1(photonPt)-rawTttrData0(k)-obj.PulseDelay_ns*1000)/1000;
                            bin = ceil(mod((rawTttrData1(photonPt)-rawTttrData0(k)-obj.PulseDelay_ns*1000)/1000, obj.PulsePeriod_ns)/obj.bin_width_ns);
                            if bin > 0
                                timeBinResult(bin) = timeBinResult(bin) + 1;
                            end
                            photonPt = photonPt + 1;
                        end
                    end % End counting all samples
                    periodNum = periodNum + (obj.PulseRepeat*(obj.samples-3));
                    fprintf("t8: %.2f\n", toc(t));
                    ax(2).Children(3).YData = timeBinResult/periodNum;
                    ax(2).Children(3).XData = (1:nBins)*obj.bin_width_ns;
                    if max(timeBinResult/periodNum, [], 'all') > 0
                    ax(2).YLim = [0, max(timeBinResult/periodNum, [], 'all')];
                    end
                    yticks(ax(2), 'auto');
                    drawnow;

                end % End average for loop
            end % End pulse sequence validity check
            obj.data.timeBinResults(offsetIdx, spanIdx, :) = timeBinResult';
            fprintf("t6: %.2f\n", toc(t));
            
            totalPhotonNum = sum(timeBinResult);
            sectionPhotonNum = sum(timeBinResult(cntStartBin:cntEndBin));
            obj.data.sectionProbability(offsetIdx, spanIdx) = sectionPhotonNum/periodNum;
            obj.data.totalProbability(offsetIdx, spanIdx) = totalPhotonNum/periodNum;

            if ax(1).Children(1).YData(1) < 0
                ax(1).Children(1).YData = [totalPhotonNum/periodNum];
                ax(1).Children(1).XData = [obj.resWindowSpan_us];
            else
                ax(1).Children(1).YData = [ax(1).Children(1).YData, totalPhotonNum/periodNum];
                ax(1).Children(1).XData = [ax(1).Children(1).XData, obj.resWindowSpan_us];
            end
            yticks(ax(1), 'auto');
            drawnow('limitrate');    
        end % End span sweep

    end % End offset sweep

end