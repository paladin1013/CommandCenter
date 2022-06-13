function runSeparatedSeq(obj, ax, p, status)
    nPulseWidths = length(obj.PulseWidths_ns);
    nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
    t = tic;
    cntStartBin = ceil(mod(obj.PulseBound_ns(1), obj.PulsePeriod_ns)/obj.bin_width_ns);
    cntEndBin = ceil(mod(obj.PulseBound_ns(2), obj.PulsePeriod_ns)/obj.bin_width_ns);
    line([cntStartBin, cntStartBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');
    line([cntEndBin, cntEndBin], [0, 1], 'Parent', ax(2), 'Color', 'k', 'LineStyle', '--');


    for pulseWidthIdx = 1:nPulseWidths
        drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
        periodNum = 0;
        pulseWidth_ns = obj.PulseWidths_ns(pulseWidthIdx);
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
        timeBinResult = zeros(1, nBins);
        pulseSeq = obj.BuildPulseSequence(pulseWidth_ns);
        pulseSeq.repeat = obj.samples;
        apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
        apdPS.seq = pulseSeq;
        % pulseSeq.draw;
        if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)

            for averageIdx = 1:obj.averages
                drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');

                status.String = [sprintf('PulseWidth = %g (%i/%i)\n', pulseWidth_ns,pulseWidthIdx, nPulseWidths), sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages), sprintf('Time elapsed %.2f', toc(t))];
            
                if averageIdx == 1
                    apdPS.start(1000)
                else
                    apdPS.start(1000, false, true); % hard coded
                end
                [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;
                apdPS.stream(p);

                obj.picoharpH.PH_StopMeas;


                % Count photon time tags
                photonPt = 1;
                collectedPhotonCnt = 0;
                relativeTimeTags_ns = zeros(1, 1000000);
                assert(length(rawTttrData0) == obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",obj.samples - 3, length(rawTttrData0)))
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
                        

                end

                % Update figures
                periodNum = periodNum + (obj.PulseRepeat*(obj.samples-3));
                ax(2).Children(3).YData = timeBinResult/periodNum;
                ax(2).Children(3).XData = (1:nBins)*obj.bin_width_ns;
                ax(2).YLim = [0, max(timeBinResult/periodNum, [], 'all')];
                yticks(ax(2), 'auto');
                
                % Record all data
                dat = reshape(p.YData,obj.nCounterBins,[])';
                obj.data.counts(averageIdx, pulseWidthIdx,:,:) = dat;
                obj.data.timeTags{pulseWidthIdx, averageIdx} = relativeTimeTags_ns(1:collectedPhotonCnt);
                if obj.recordAllTimeTags
                    obj.data.rawTimeTags0{pulseWidthIdx, averageIdx} = rawTttrData0;
                    obj.data.rawTimeTags1{pulseWidthIdx, averageIdx} = rawTttrData1;
                end
            end
        end

        % Find the photon probability in corresponding section (first 50 ns and last 50 ns)
        obj.data.timeBinResults(pulseWidthIdx, :) = timeBinResult';
        
        totalPhotonNum = sum(obj.data.timeBinResults(pulseWidthIdx, :));
        sectionPhotonNum = sum(obj.data.timeBinResults(pulseWidthIdx, cntStartBin:cntEndBin));
        obj.data.sectionProbability(pulseWidthIdx) = sectionPhotonNum/periodNum;
        obj.data.totalProbability(pulseWidthIdx) = totalPhotonNum/periodNum;

        if ax(1).Children(1).YData(1) < 0
            ax(1).Children(1).YData = [sectionPhotonNum/periodNum];
            ax(1).Children(1).XData = [pulseWidth_ns];
            ax(1).Children(2).YData = [totalPhotonNum/periodNum];
            ax(1).Children(2).XData = [pulseWidth_ns];
        else 
            ax(1).Children(1).YData = [ax(1).Children(1).YData, sectionPhotonNum/periodNum];
            ax(1).Children(1).XData = [ax(1).Children(1).XData, pulseWidth_ns];
            ax(1).Children(2).YData = [ax(1).Children(2).YData, totalPhotonNum/periodNum];
            ax(1).Children(2).XData = [ax(1).Children(2).XData, pulseWidth_ns];
        end
        yticks(ax(1), 'auto');
        drawnow('limitrate');
    end

end