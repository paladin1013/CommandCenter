classdef AWGPulseWidthSweep < Modules.Experiment
    properties(SetObservable,AbortSet)
        picoharpH;
        data
        meta
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        connection = false;
        SampleTime_ms = 1000; %ms
        SampleNum = 5;
        SyncDivider = uint8(1);
        SyncOffset = 0; %ms
        PulseWidthStr_ns = 'linspace(20, 40, 21)';
        PulseWidths_ns;
        PulsePeriod_ns = 100;
        MarkerWidth_ns = 10;
        PulseRepeat = 10;
        PulseBase = -1;
        AWG_Amplitude_V = 0.5;
        Ch0_CFDzero = 20;% mV
        Ch0_CFDlevel = 20;% mV
        Ch1_CFDzero = 20;% mV
        Ch1_CFDlevel = 20;% mV
        Binning = 0;
        Offset = 0; %ms - still not sure what offset is this
        StopAtOverflow = true;
        OverflowCounts = 65535; %65535 is max value
        prefs = {'connection'};
        bin_width_ns = 0.256;
        PH_Mode         = 2; % 2 for T2 and 3 for T3 and 0 for histogram
        SyncChannel = 0;
        PhotonChannel = 1;
        LogScale = true;

        AWG;
        PB;
        AWG_Channel = 1;
        AWG_SampleRate_GHz = 10;
        MergeSequence = false;
        PulseFileDir = '\\houston.mit.edu\qpgroup\Experiments\AWG70002B\waveforms';
        show_prefs = {'PB_IP','AWG_IP','AWG_Channel', 'AWG_SampleRate_GHz', 'AWG_Amplitude_V', 'PulseFileDir', 'PH_serialNr','PH_BaseResolution','connection','PH_Mode','SyncChannel', 'PhotonChannel', ...
        'PulsePeriod_ns','PulseWidthStr_ns', 'PulseShape', 'MarkerWidth_ns', 'PulseRepeat', 'PulseBase', 'bin_width_ns',  'SampleTime_ms', 'SampleNum', 'LogScale', 'MergeSequence'};
        
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};

    end
    properties(GetObservable, SetObservable)
        AWG_IP =    Prefs.String('None Set','set','set_AWG_IP', ...% 18.25.24.255
        'help_text','AWG IP for TCP connection');
        PB_IP =     Prefs.String('None Set','set','set_PB_IP', ... 
        'help_text','Hostname for computer running pulseblaster server');
        PulseShape = Prefs.MultipleChoice('Gaussian', 'choices', {'Gaussian', 'sine', 'square'});

        
    end
    properties(SetAccess=private,Hidden)
        %picoharpH; %handle to PicoHarp300
        listeners;
        abort_request = false;
        acquiring = false;
    end
    methods(Access=private)
        function obj = AWGPulseWidthSweep()
            obj.loadPrefs;
            obj.PulseWidths_ns = eval(obj.PulseWidthStr_ns);
        end
    end

    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Experiments.AWGPulseWidthSweep();
            end
            obj = Object;
        end
    end


    methods
        function run(obj,status,managers,ax)

            

            assert(~isempty(obj.picoharpH)&&isvalid(obj.picoharpH),'PicoHarp driver is not intialized properly.');
            if (isempty(obj.AWG)|| ~isvalid(obj.AWG))
                try
                    obj.set_AWG_IP;
                catch exception
                    assert(false, 'AWG driver is not intialized properly.');
                end
            end
            assert(~isempty(obj.PB)&&isvalid(obj.PB),'PulseBluster driver is not intialized properly.');
            status.String = 'Experiment started';
            obj.SetPHconfig;
            obj.data = [];
            obj.meta = [];
            ax = obj.prepPlot(ax);
            obj.abort_request = false;
            obj.acquiring = true;
            drawnow;
            t = tic;
            Resolution = obj.picoharpH.PH_GetResolution;
            % Countrate0 = obj.picoharpH.PH_GetCountRate(0);
            % Countrate1 = obj.picoharpH.PH_GetCountRate(1);
            Nwidths = length(obj.PulseWidths_ns);
            Nbins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);
            obj.meta.resolution = Resolution;
            obj.data.pulseWidths = obj.PulseWidths_ns;
            obj.data.timeBinResults = zeros(Nwidths, Nbins);
            obj.data.bin_width_ns = obj.bin_width_ns;
            obj.data.PulsePeriod_ns = obj.PulsePeriod_ns;
            obj.data.probability = zeros(1, Nwidths);
            if ~obj.MergeSequence
                for widthCnt = 1:Nwidths
                    if(obj.abort_request == true)
                        break
                    end
                    pulseWidth_ns = obj.PulseWidths_ns(widthCnt);
                    waveformName = sprintf("PulseWidth_%s_%.2f_ns", obj.PulseShape, pulseWidth_ns);
                    % if ~isfile(sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName))
                        AWGPulseGen(obj.PulseBase, pulseWidth_ns, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName), obj.PulseShape);
                    % end


                    obj.AWG.loadWaveform(obj.AWG_Channel, waveformName);
                    obj.AWG.setAmplitude(obj.AWG_Channel, obj.AWG_Amplitude_V);
                    obj.AWG.setResolution(obj.AWG_Channel, 9);
                    obj.AWG.setChannelOn(obj.AWG_Channel);
                    obj.AWG.AWGStart;

                    time_bin_result = zeros(1, Nbins);
                    photonNum = 0;
                    periodNum = 0;
                    for sampleCnt = 1:obj.SampleNum
                        if(obj.abort_request == true)
                            break
                        end
                        status.String = sprintf('Width Cnt: %d/%d, Sample Cnt: %d/%d\n Time Elapsed: %0.2f\n', widthCnt, Nwidths, sampleCnt,obj.SampleNum, toc(t));
                        pause(0.2);
                        % fprintf('\nResolution=%1dps Countrate0=%1d/s Countrate1=%1d/s', Resolution, Countrate0, Countrate1);
                        obj.picoharpH.PH_StartMeas(obj.SampleTime_ms);
                        result0 = double(zeros(1, obj.picoharpH.TTREADMAX));
                        result1 = double(zeros(1, obj.picoharpH.TTREADMAX));
                        progress = 0;
                        ctcdone = 0;
                        ofl_num = 0;
                        cnt0 = 0;
                        cnt1 = 0;
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
                                    result0(cnt0) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*Resolution;
                                else % chan == 1
                                    cnt1 = cnt1 + 1;
                                    result1(cnt1) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*Resolution;
                                end
                            end
                            if(nactual)
                                progress = progress + nactual;
                                time_bin_result = time_bin_result + PulsePhotonAnalysis(result0(cnt0_prev + 1:cnt0), result1(cnt1_prev + 1:cnt1), obj.PulsePeriod_ns, obj.bin_width_ns);
                            else
                                ctcdone = int32(0);
                                ctcdonePtr = libpointer('int32Ptr', ctcdone);
                                [ret, ctcdone] = calllib('PHlib', 'PH_CTCStatus', obj.picoharpH.DeviceNr, ctcdonePtr); 
                            end
                        end
                        obj.picoharpH.PH_StopMeas;
                        photonNum = photonNum + cnt1;
                        periodNum = periodNum + cnt0*obj.PulseRepeat;
                        ax(2).Children(1).YData = time_bin_result/periodNum;
                        ax(2).Children(1).XData = (1:Nbins)*obj.bin_width_ns;
                        yticks(ax(2), 'auto');
                        if obj.LogScale == 1
                            set(ax(2), 'YScale', 'log')
                        end
                        drawnow limitrate;

                    end
                    if ax(1).Children(1).YData(1) < 0
                        ax(1).Children(1).YData = [photonNum/periodNum];
                        ax(1).Children(1).XData = [pulseWidth_ns];
                    else 
                        ax(1).Children(1).YData = [ax(1).Children(1).YData, photonNum/periodNum];
                        ax(1).Children(1).XData = [ax(1).Children(1).XData, pulseWidth_ns];
                    end
                    yticks(ax(1), 'auto');
                    drawnow limitrate
                    obj.data.timeBinResults(widthCnt, :) = time_bin_result;
                    obj.data.probability(widthCnt) = cnt1/cnt0;
                end
            else
                % Merged Sequence
                waveformName = sprintf("PulseWidth_%s_ns", obj.PulseWidthStr_ns);
                % if ~isfile(sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName))
                    AWGPulseGen(obj.PulseBase, obj.PulseWidths_ns, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, sprintf('%s\\%s.txt', obj.PulseFileDir, waveformName), obj.PulseShape);
                % end
                obj.AWG.loadWaveform(obj.AWG_Channel, waveformName);
                obj.AWG.setAmplitude(obj.AWG_Channel, obj.AWG_Amplitude_V);
                obj.AWG.setResolution(obj.AWG_Channel, 9);
                obj.AWG.setChannelOn(obj.AWG_Channel);
                obj.AWG.AWGStart;
                photonNum = zeros(1, Nwidths);
                periodNum = 0;
                for sampleCnt = 1:obj.SampleNum
                    if(obj.abort_request == true)
                        break
                    end
                    status.String = sprintf('Sample Cnt: %d/%d\n Time Elapsed: %0.2f\n', sampleCnt,obj.SampleNum, toc(t));
                    pause(0.2);
                    obj.picoharpH.PH_StartMeas(obj.SampleTime_ms);
                    result0 = double(zeros(1, obj.picoharpH.TTREADMAX));
                    result1 = double(zeros(1, obj.picoharpH.TTREADMAX));
                    progress = 0;
                    ctcdone = 0;
                    ofl_num = 0;
                    cnt0 = 0;
                    cnt1 = 0;
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
                                result0(cnt0) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*Resolution;
                            else % chan == 1
                                cnt1 = cnt1 + 1;
                                result1(cnt1) = (double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag))*Resolution;
                            end
                        end
                        if(nactual)
                            progress = progress + nactual;
                            obj.timeBinResults = obj.timeBinResults + PulsePhotonAnalysis(result0(cnt0_prev + 1:cnt0), result1(cnt1_prev + 1:cnt1), obj.PulsePeriod_ns, obj.bin_width_ns);
                        else
                            ctcdone = int32(0);
                            ctcdonePtr = libpointer('int32Ptr', ctcdone);
                            [ret, ctcdone] = calllib('PHlib', 'PH_CTCStatus', obj.picoharpH.DeviceNr, ctcdonePtr); 
                        end
                    end
                    obj.picoharpH.PH_StopMeas;
                    periodNum = periodNum + cnt0*obj.PulseRepeat;
                    ax(1).Children(1).YData = sum(obj.timeBinResults, 2)'/periodNum;
                    ax(1).Children(1).XData = (1:Nbins)*obj.bin_width_ns;
                    yticks(ax(1), 'auto');
                    drawnow limitrate
                end
                obj.data.probability = sum(obj.timeBinResults, 2)'/periodNum;

            end
        end
        
        function ax = prepPlot(obj,ax)
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



        end
        
        function SetPHconfig(obj)
            obj.picoharpH.PH_SetInputCFD(0,obj.Ch0_CFDlevel,obj.Ch0_CFDzero);
            obj.picoharpH.PH_SetInputCFD(1,obj.Ch1_CFDlevel,obj.Ch1_CFDzero);
            obj.picoharpH.PH_SetBinning(obj.Binning);
            obj.picoharpH.PH_SetOffset(obj.Offset);
            obj.picoharpH.PH_SetStopOverflow(obj.StopAtOverflow,obj.OverflowCounts); %65535 is max value
            obj.picoharpH.PH_SetSyncOffset(obj.SyncOffset);
            obj.picoharpH.PH_SetSyncDiv(obj.SyncDivider);
        end
        
        function abort(obj)
            obj.abort_request = true;
        end



        function dat = GetData(obj,~,~)
            dat = [];
            for i=1:length(obj.show_prefs)
                obj.meta = setfield(obj.meta,obj.show_prefs{i},getfield(obj,obj.show_prefs{i}));
            end
            obj.meta.PH_serialNr = obj.PH_serialNr;
            
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
             
        function delete(obj)
            if ~isempty(obj.picoharpH)
                obj.picoharpH.delete;
            end
            delete(obj.listeners);
        end
        
        % Experimental Set methods
        function set.connection(obj,val)
            if val
                obj.PH_serialNr = 'connecting...';
                drawnow;


                try
                    obj.picoharpH = Drivers.PicoHarp300.instance(obj.PH_Mode);
                catch err
                    obj.connection = false;
                    obj.PH_serialNr = 'No device';
                    rethrow(err)
                end
                obj.connection = true;
                obj.PH_serialNr = obj.picoharpH.SerialNr{1};
                obj.PH_BaseResolution = obj.picoharpH.PH_GetBaseResolution;
            elseif ~isempty(obj.picoharpH)
                obj.picoharpH.delete;
                obj.connection = false;
                obj.PH_serialNr = 'No device';
            end
        end

        function val = set_AWG_IP(obj,val,~)
            emptyFlag = false;

            if strcmp(val,'None Set') % Short circuit
                emptyFlag = true;

                val = '18.25.24.255';
            end
                try
                    % currently '18.25.24.255'; 5/16/2022
                    obj.AWG=Drivers.AWG70002B.instance('visa',val);
                    obj.AWG_IP = val;
                    obj.AWG.reset();
                    obj.AWG.setExtRefClock();
                    obj.AWG.setSampleRate(obj.AWG_Channel, obj.AWG_SampleRate_GHz*1e9);
                catch err
                    rmfield(obj,'AWG');
                    obj.AWG = [];
                    obj.AWG_IP = 'None Set';
                    if emptyFlag == false
                        rethrow(err);
                        end
                end
        end


        function val = set_PB_IP(obj,val,~)
            emptyFlag = false;
            if strcmp(val,'None Set') % Short circuit
                val = 'localhost'; % Default value
                emptyFlag = true;
            end
            try
                obj.PB = Drivers.PulseBlaster.instance(val);
            catch err
                obj.PB = [];
                obj.PB_IP = 'None Set';
                if emptyFlag == false
                rethrow(err);
                end
            end
        end
        function set.PulseWidthStr_ns(obj,val)
            tempvals = eval(val);
            obj.PulseWidths_ns = tempvals;
            obj.PulseWidthStr_ns = val;
        end
    end
end