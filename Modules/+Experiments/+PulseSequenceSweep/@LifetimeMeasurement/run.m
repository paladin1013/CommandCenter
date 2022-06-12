function run( obj,status,managers,ax)
% Main run method (callback for CC run button)

% Edit here down (save data to obj.data)
% Tips:
% - If using a loop, it is good practice to call:
%     drawnow; assert(~obj.abort_request,'User aborted.');
%     as frequently as possible
% - try/catch/end statements useful for cleaning up
% - You can get a figure-like object (to create subplots) by:
%     panel = ax.Parent; delete(ax);
%     ax(1) = subplot(1,2,1,'parent',panel);
% - drawnow can be used to update status box message and any plots

% Assert user implemented abstract properties correctly




assert(numel(obj.nCounterBins)==1 && isnumeric(obj.nCounterBins) && floor(obj.nCounterBins)==obj.nCounterBins,...
    'Property "nCounterBins" should be a single integer');
assert(~isempty(obj.picoharpH), "PicoHarp300 is not connected");
obj.SetPHconfig;

if (isempty(obj.AWG)|| ~isvalid(obj.AWG))
    try
        obj.set_AWG_IP;
    catch exception
        assert(false, 'AWG driver is not intialized properly.');
    end
end
assert(~isempty(obj.pbH)&&isvalid(obj.pbH),'PulseBluster driver is not intialized properly.');


%prepare axes for plotting
ax = plotyy(ax,[0], [-1], [0], [0]);

line([0], [-2], 'Parent', ax(1), 'Color', 'c');

set(ax(2),'YLim',[0 inf])
set(ax(2), 'XLim', [0 obj.PulsePeriod_ns])
set(ax(1),'YLim',[0 inf])
set(ax(1), 'XLim', [0 inf]) 
%             set(ax(2).XLabel,'String','Time (ns)')
set(ax(2).YLabel,'String','Time Bin Probability')
set(ax(1).XLabel,'String','PulseWidth (ns)')
set(ax(1).YLabel,'String','Total Probability')
ax(2).Box = 'off';
ax(1).Box = 'off';
ax(1).XColor = ax(1).YColor;
ax(2).XColor = ax(2).YColor;

status.String = 'Experiment started';
obj.abort_request = false;
drawnow;

nPulseWidths = length(obj.PulseWidths_ns);
nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
obj.data.counts = NaN([nPulseWidths, obj.averages, obj.samples,obj.nCounterBins]);
obj.data.timeTags = cell([nPulseWidths, obj.averages, obj.samples,obj.nCounterBins]);
obj.data.timeBinResults = zeros([nPulseWidths, nBins]);
obj.data.sectionProbability = zeros([1, nPulseWidths]);
obj.data.totalProbability = zeros([1, nPulseWidths]);

if obj.recordAllTimeTags
    obj.data.rawTimeTags0 = cell([nPulseWidths, obj.averages]);
    obj.data.rawTimeTags1 = cell([nPulseWidths, obj.averages]);
end

obj.meta.prefs = obj.prefs2struct;

obj.meta.PulseWidths = obj.PulseWidths_ns;

obj.meta.position = managers.Stages.position; % Stage position

f = figure('visible','off','name',mfilename);
a = axes('Parent',f);
p = plot(NaN,'Parent',a);


try
    obj.PreRun(status,managers,ax);
    
    % Construct APDPulseSequence once, and update apdPS.seq
    % Not only will this be faster than constructing many times,
    % APDPulseSequence upon deletion closes PulseBlaster connection
    apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
    t = tic;
    if obj.MergeSequence == false
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

                    assert(length(rawTttrData0) == obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",obj.samples - 3, length(rawTttrData0)))
                    photonPt = 1;
                    for k = 1:(obj.samples-3)
                        while(k < length(rawTttrData0) &&  photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)))
                            photonPt = photonPt + 1;
                        end
                        photonPtStart = photonPt;
                        while(photonPt <= length(rawTttrData1) && (rawTttrData1(photonPt) < rawTttrData0(k)+obj.PulseRepeat*obj.PulsePeriod_ns*1000))
                            bin = ceil(mod((rawTttrData1(photonPt)-rawTttrData0(k))/1000, obj.PulsePeriod_ns)/obj.bin_width_ns);
                            if bin > 0
                                timeBinResult(bin) = timeBinResult(bin) + 1;
                            end
                            photonPt = photonPt + 1;
                        end
                        % obj.data.timeTags{pulseWidthIdx, averageIdx, k, 1} = rawTttrData1(photonPtStart:photonPt);
                            

                    end
                    periodNum = periodNum + (obj.PulseRepeat*(obj.samples-3));
                    ax(2).Children(1).YData = timeBinResult/periodNum;
                    ax(2).Children(1).XData = (1:nBins)*obj.bin_width_ns;
                    yticks(ax(2), 'auto');
                    

                    dat = reshape(p.YData,obj.nCounterBins,[])';
                    obj.data.counts(averageIdx, pulseWidthIdx,:,:) = dat;
                    if obj.recordAllTimeTags
                        obj.data.rawTimeTags0{pulseWidthIdx, averageIdx} = rawTttrData0;
                        obj.data.rawTimeTags1{pulseWidthIdx, averageIdx} = rawTttrData1;
                    end
                end
            end

            % Find the photon probability in corresponding section (first 50 ns and last 50 ns)
            obj.data.timeBinResults(pulseWidthIdx, :) = timeBinResult';
            cntStart1_ns = 0.1;
            cntEnd1_ns = 50;
            cntStart2_ns = 450;
            cntEnd2_ns = 499.9;
            cntStartBin1 = ceil(mod(cntStart1_ns, obj.PulsePeriod_ns)/obj.bin_width_ns);
            cntEndBin1 = ceil(mod(cntEnd1_ns, obj.PulsePeriod_ns)/obj.bin_width_ns);
            cntStartBin2 = ceil(mod(cntStart2_ns, obj.PulsePeriod_ns)/obj.bin_width_ns);
            cntEndBin2 = ceil(mod(cntEnd2_ns, obj.PulsePeriod_ns)/obj.bin_width_ns);
            
            totalPhotonNum = sum(obj.data.timeBinResults(pulseWidthIdx, :));
            sectionPhotonNum = sum(obj.data.timeBinResults(pulseWidthIdx, cntStartBin1:cntEndBin1)) + sum(obj.data.timeBinResults(pulseWidthIdx, cntStartBin2:cntEndBin2));
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
    
    else 
        % Enabling merge sequence option. This will compile all pulsewidths into the same waveform. 
        obj.PreRun(status,managers,ax);
        drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
        periodNum = 0;
        pws = obj.pulseWidths_ns;
        waveformName = sprintf("%s_%.1f:%.1f:%.1f_%dns_%d", 'square', pws(1), pws(2)-pws(1), pws(end), obj.PulsePeriod_ns, obj.PulseRepeat);
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
        pulseSeq = obj.BuildPulseSequence(pulseWidth_ns);
        pulseSeq.repeat = obj.samples;
        apdPS.seq = pulseSeq;

        if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)

            for averageIdx = 1:obj.averages
                drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
                status.String = [sprintf('PulseWidth = %g (%i/%i)\n', pulseWidth_ns,pulseWidthIdx, nPulseWidths), sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages), sprintf('Time elapsed %.2f', toc(t))];




    end

    obj.picoharpH.PH_StopMeas;

catch err
end
delete(f);
if exist('err','var')
    rethrow(err)
end
end
