function runMergedSeq(obj, ax, p, status)


    cntStartBin = ceil(mod(obj.PulseBound_ns(1), obj.PulsePeriod_ns)/obj.bin_width_ns);
    cntEndBin = ceil(mod(obj.PulseBound_ns(2), obj.PulsePeriod_ns)/obj.bin_width_ns);
    
    % line([obj.PulseBound_ns(1), obj.PulseBound_ns(1)], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
    % line([obj.PulseBound_ns(2), obj.PulseBound_ns(2)], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
    t = tic;
    nPulseWidths = length(obj.PulseWidths_ns);
    
    nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
    periodNum = 0;
    pws = obj.PulseWidths_ns;
    waveformName = sprintf("%s_%.1f_%.1f_%.1f_%dns_%d", 'square', pws(1), pws(2)-pws(1), pws(end), obj.PulsePeriod_ns, obj.PulseRepeat);
    AWGPulseGen(obj.PulseBase, pws, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName), 'square');
    obj.AWG.writeReadToSocket('SYST:ERR:ALL?');
    obj.AWG.loadWaveform(obj.AWG_Channel, waveformName);
    obj.AWG.setAmplitude(obj.AWG_Channel, obj.AWG_Amplitude_V);
    obj.AWG.setResolution(obj.AWG_Channel, 8);
    obj.AWG.setChannelOn(obj.AWG_Channel);
    obj.AWG.setRunMode(obj.AWG_Channel, 'T');
    obj.AWG.setTriggerSource(obj.AWG_Channel, obj.AWG_TriggerSource);
    obj.AWG.AWGStart;
    timeBinResults = zeros(nPulseWidths, nBins);
    pulseSeq = obj.BuildPulseSequence;
    pulseSeq.repeat = obj.samples;
    apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
    apdPS.seq = pulseSeq;
    obj.data.peakPos = zeros(1, nPulseWidths);


    cmap = jet(nPulseWidths);

    for k = 1:nPulseWidths
        line([0], [0], 'Parent', ax(2), 'Color', cmap(k, :));
        ax(2).Children(1).XData = (cntStartBin:cntEndBin)*obj.bin_width_ns;
        line([0], [0], 'Parent', ax(1));
    end
    if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)

        for averageIdx = 1:obj.averages
            drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
            status.String = [sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages), sprintf('Time elapsed %.2f', toc(t))];
            relativeTimeTags_ns = zeros(nPulseWidths, 10000);
            if averageIdx == 1
                apdPS.start(1000)
            else
                apdPS.start(1000, false, true); % hard coded
            end

            [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;
            apdPS.stream(p);

            obj.picoharpH.PH_StopMeas;

            assert(length(rawTttrData0) == obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",obj.samples - 3, length(rawTttrData0)))


            photonPt = 1;
            collectedPhotonCnt = zeros(1, nPulseWidths);
            for k = 1:(obj.samples-3)
                while(k < length(rawTttrData0) &&  photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)+obj.PulseDelay_ns*1000))
                    photonPt = photonPt + 1;
                end

                while(photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)+obj.PulseRepeat*obj.PulsePeriod_ns*nPulseWidths*1000+obj.PulseDelay_ns*1000))
                    relativeToSync_ns = (rawTttrData1(photonPt)-rawTttrData0(k))/1000-obj.PulseDelay_ns;
                    pwIdx = mod(floor(relativeToSync_ns/obj.PulsePeriod_ns), nPulseWidths)+1;
                    collectedPhotonCnt(pwIdx) = collectedPhotonCnt(pwIdx) + 1;
                    relativeTimeTags_ns(pwIdx, collectedPhotonCnt(pwIdx)) = relativeToSync_ns;


                    bin = ceil(mod(relativeToSync_ns, obj.PulsePeriod_ns)/obj.bin_width_ns);
                    if bin > 0
                        timeBinResults(pwIdx, bin) = timeBinResults(pwIdx, bin) + 1;
                    end

                    photonPt = photonPt + 1;
                end
            end
            periodNum = periodNum + (obj.PulseRepeat * (obj.samples-3));
            
            for pwIdx = 1:nPulseWidths
                obj.data.timeTags{pwIdx, averageIdx} = relativeTimeTags_ns(pwIdx, 1:collectedPhotonCnt(pwIdx));
            end
            totalPhotonNum = sum(timeBinResults, 2);
            sectionPhotonNum = sum(timeBinResults(:, cntStartBin:cntEndBin), 2);

            if obj.LogScale == 1
                set(ax(2), 'YScale', 'log')
            end
            [maxCnt, maxPt] = max(timeBinResults, [], 2); % Get peak position
            lineNum = 6;
            for k = 1:floor(nPulseWidths/lineNum):nPulseWidths
                ax(2).Children(k).YData = timeBinResults(k, cntStartBin:cntEndBin)/periodNum;
            end

            ax(2).YLim = [0, max(timeBinResults/periodNum, [], 'all')];
            yticks(ax(2), 'auto')
            ax(2).XLim = [obj.PulseBound_ns(1), obj.PulseBound_ns(2)];

            drawnow('limitrate');

            for k = 1:nPulseWidths
                ax(1).Children(k).YData = sectionPhotonNum(k)/periodNum;
                ax(1).Children(k).XData = obj.PulseWidths_ns(k);
                ax(1).Children(k).Color = cmap(k, :);
                ax(1).Children(k).MarkerSize = 20;
                ax(1).Children(k).Marker = '.';
            end
            ax(1).Children(end).YData = sectionPhotonNum/periodNum;
            ax(1).Children(end).XData = obj.PulseWidths_ns;
            ax(1).Children(end).Color = 'k';
            % ax(1).Children(2).YData = totalPhotonNum/periodNum;
            % ax(1).Children(2).XData = obj.PulseWidths_ns;
            yticks(ax(1), 'auto');
            % legend(ax(1), {'Within dashed-line window', 'Total probability',  'Shortest pulsewidth distribution', 'Longest pulsewidth distribution'}, 'Location', 'northwest');
            drawnow('limitrate');
            
            obj.data.peakPos = maxPt;
            obj.data.timeBinResults = timeBinResults;
            obj.data.sectionProbability = sectionPhotonNum'/periodNum;
            obj.data.totalProbability = totalPhotonNum'/periodNum;
        end % End calculating averages

    end
    
end % End checking pulse sequence