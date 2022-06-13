function runMergedSeq(obj, ax, p, status)


    line([0], [-2], 'Parent', ax(2), 'Color', 'm');
    cntStartBin = ceil(mod(obj.PulseBound_ns(1), obj.PulsePeriod_ns)/obj.bin_width_ns);
    cntEndBin = ceil(mod(obj.PulseBound_ns(2), obj.PulsePeriod_ns)/obj.bin_width_ns);
    line([cntStartBin, cntStartBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
    line([cntEndBin, cntEndBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
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




    if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)

        for averageIdx = 1:obj.averages
            drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
            status.String = [sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages), sprintf('Time elapsed %.2f', toc(t))];
            relativeTimeTags_ns = zeros(nPulseWidths, 1000000);
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
            ax(2).Children(3).YData = timeBinResults(1, :)/periodNum;
            ax(2).Children(3).XData = (1:nBins)*obj.bin_width_ns;
            ax(2).Children(4).YData = timeBinResults(end, :)/periodNum;
            ax(2).Children(4).XData = (1:nBins)*obj.bin_width_ns;
            ax(2).YLim = [0, max(timeBinResults/periodNum, [], 'all')];
            yticks(ax(2), 'auto')

            drawnow('limitrate');

            ax(1).Children(1).YData = sectionPhotonNum/periodNum;
            ax(1).Children(1).XData = obj.PulseWidths_ns;
            ax(1).Children(2).YData = totalPhotonNum/periodNum;
            ax(1).Children(2).XData = obj.PulseWidths_ns;
            yticks(ax(1), 'auto');
            drawnow('limitrate');
            

        end % End calculating averages

        obj.data.timeBinResults = timeBinResults;
        obj.data.sectionProbability = sectionPhotonNum'/periodNum;
        obj.data.totalProbability = totalPhotonNum'/periodNum;
    end
    
end % End checking pulse sequence