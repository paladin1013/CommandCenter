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

status.String = 'Experiment started';
obj.abort_request = false;
drawnow;

nPulseWidths = length(obj.PulseWidths_ns);
nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
obj.data.counts = NaN([obj.averages,nPulseWidths, obj.samples,obj.nCounterBins]);
obj.data.timeTags = cell([obj.averages, nPulseWidths, obj.samples,obj.nCounterBins]);
obj.data.timeBinResults = zeros([obj.averages, nPulseWidths, nBins]);
obj.data.probability = zeros([obj.averages, nPulseWidths]);

if obj.recordAllTimeTags
    obj.data.rawTimeTags0 = cell([obj.averages, nPulseWidths]);
    obj.data.rawTimeTags1 = cell([obj.averages, nPulseWidths]);
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
    


    for averageIdx = 1:obj.averages
        for pulseWidthIdx = 1:nPulseWidths
            drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
            pulseWidth_ns = obj.PulseWidths_ns(pulseWidthIdx);
            status.String = [sprintf('Progress (%i/%i averages):\n  ', averageIdx,obj.averages),sprintf('PulseWidth = %g (%i/%i)', pulseWidth_ns,pulseWidthIdx, nPulseWidths)];
            waveformName = sprintf("%s_%.1f_%dns_%d", 'square', pulseWidth_ns, obj.PulsePeriod_ns, obj.PulseRepeat);
            AWGPulseGen(obj.PulseBase, pulseWidth_ns, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName), 'square');
            obj.AWG.writeReadToSocket('SYST:ERR:ALL?');
            obj.AWG.loadWaveform(obj.AWG_Channel, waveformName);
            obj.AWG.setAmplitude(obj.AWG_Channel, obj.AWG_Amplitude_V);
            obj.AWG.setResolution(obj.AWG_Channel, 9);
            obj.AWG.setChannelOn(obj.AWG_Channel);
            obj.AWG.setRunMode(obj.AWG_Channel, 'T');
            obj.AWG.setTriggerSource(obj.AWG_Channel, obj.AWG_TriggerSource);
            obj.AWG.AWGStart;

            
            
            % BuildPulseSequence must take in vars in the order listed
            pulseSeq = obj.BuildPulseSequence;
            if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)
                pulseSeq.repeat = obj.samples;
                apdPS.seq = pulseSeq;
                t = tic;
                apdPS.start(1000); % hard coded
                % [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;

                rawTttrData0 = double(zeros(1, obj.picoharpH.TTREADMAX));
                rawTttrData1 = double(zeros(1, obj.picoharpH.TTREADMAX));
                progress = 0;
                ctcdone = 0;
                ofl_num = 0;
                cnt0 = 0;
                cnt1 = 0;
                time_bin_result = zeros(1, nBins);
                photonNum = 0;
                periodNum = 0;
                while(ctcdone == 0 && obj.abort_request == false)
                    [buffer, nactual] = obj.picoharpH.PH_ReadFiFo;
                    cnt0_prev = cnt0;
                    cnt1_prev = cnt1;
                    for k = 1:nactual
                        chan = bitand(bitshift(buffer(k),-28),15);
                        cur_time_tag = bitand(buffer(k), 2^28-1);
                        if (chan==15) % to detect an overflow signal
                            ofl_num = ofl_num + 1;
                        elseif (chan == 0)
                            cnt0 = cnt0 + 1;
                            rawTttrData0(cnt0) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*obj.PH_BaseResolution;
                        else % chan == 1
                            cnt1 = cnt1 + 1;
                            rawTttrData1(cnt1) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*obj.PH_BaseResolution;
                        end
                    end
                    if(nactual)
                        progress = progress + nactual;
                        time_bin_result = time_bin_result + PulsePhotonAnalysis(rawTttrData0(cnt0_prev + 1:cnt0), rawTttrData1(cnt1_prev + 1:cnt1), obj.PulsePeriod_ns, obj.bin_width_ns);
                    else
                        ctcdone = int32(0);
                        ctcdonePtr = libpointer('int32Ptr', ctcdone);
                        [ret, ctcdone] = calllib('PHlib', 'PH_CTCStatus', obj.picoharpH.DeviceNr, ctcdonePtr); 
                    end
                end
                obj.picoharpH.PH_StopMeas;
                apdPS.stream(p);
                

                % Retrieve data from picoharp and process to fit the two APD bins
                


                % assert(length(rawTttrData0) == 2*obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",2*obj.samples - 3, length(rawTttrData0)))
                % assert(length(rawTttrData0) == obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",obj.samples - 3, length(rawTttrData0)))
                % for k = 1:(obj.samples-3)
                %     obj.data.timeTags{averageIdx, pulseWidthIdx, k, 1} = rawTttrData1((rawTttrData1>rawTttrData0(k)) & (rawTttrData1<rawTttrData0(k)+obj.PulseRepeat*obj.PulsePeriod_ns/1e3))-rawTttrData0(k);
                %     obj.data.timeBinResults(averageIdx, pulseWidthIdx, :) = obj.data.timeBinResults(averageIdx, pulseWidthIdx, :) + PulsePhotonAnalysis(obj.data.timeTags{averageIdx, pulseWidthIdx, k, 1}, [0], obj.PulsePeriod_ns, obj.bin_width_ns);
                % end
                obj.data.timeBinResults(averageIdx, pulseWidthIdx, :) = time_bin_result;
                photonNum = photonNum + cnt1;
                periodNum = periodNum + cnt0*obj.PulseRepeat;
                obj.data.probability(averageIdx, pulseWidthIdx) = photonNum/periodNum;
                ax(2).Children(1).YData = obj.data.timeBinResults(averageIdx, pulseWidthIdx, :)/periodNum;
                ax(2).Children(1).XData = (1:nBins)*obj.bin_width_ns;
                yticks(ax(2), 'auto');

                if ax(1).Children(1).YData(1) < 0
                    ax(1).Children(1).YData = [photonNum/periodNum];
                    ax(1).Children(1).XData = [pulseWidth_ns];
                else 
                    ax(1).Children(1).YData = [ax(1).Children(1).YData, photonNum/periodNum];
                    ax(1).Children(1).XData = [ax(1).Children(1).XData, pulseWidth_ns];
                end

                dat = reshape(p.YData,obj.nCounterBins,[])';
                obj.data.counts(averageIdx, pulseWidthIdx,:,:) = dat;
                if obj.recordAllTimeTags
                    obj.data.rawTimeTags0{averageIdx, pulseWidthIdx} = rawTttrData0;
                    obj.data.rawTimeTags1{averageIdx, pulseWidthIdx} = rawTttrData1;
                end
                
            end
            
        end
    end
    obj.picoharpH.PH_StopMeas;

catch err
end
delete(f);
if exist('err','var')
    rethrow(err)
end
end
