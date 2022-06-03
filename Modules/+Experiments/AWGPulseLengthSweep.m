classdef AWGPulseLengthSweep < Modules.Experiment
    properties(SetObservable,AbortSet)
        picoharpH;
        data
        meta
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        connection = false;
        SampleTime_ms = 1000; %ms
        SampleNum = 100;
        SyncDivider = uint8(1);
        SyncOffset = 0; %ms
        PulseLength_ns = 1;
        PulsePeriod_ns = 100;
        MarkerLength_ns = 10;
        PulseRepeat = 100;
        Ch0_CFDzero = 10;% mV
        Ch0_CFDlevel = 50;% mV
        Ch1_CFDzero = 10;% mV
        Ch1_CFDlevel = 50;% mV
        Binning = 0;
        Offset = 0; %ms - still not sure what offset is this
        StopAtOverflow = true;
        OverflowCounts = 65535; %65535 is max value
        prefs = {'connection'};
        sync_ns = 300;
        bin_width_ns = 0.256;
        PH_Mode         = 2; % 2 for T2 and 3 for T3 and 0 for histogram
        SyncChannel = 0;
        PhotonChannel = 1;
        LogScale = true;

        AWG_IP =    Prefs.String('None Set','set','set_awg_IP', ...
        'help_text','AWG IP for TCP connection');
        PB_IP =     Prefs.String('None Set','set','set_pb_IP', ... % 18.25.28.34
                        'help_text','Hostname for computer running pulseblaster server');
        AWG_SampleRate_GHz = 10;
        PulseFileDir = '\\houston.mit.edu\qpgroup\Experiments\AWG70002B';
        show_prefs = {'AWG_IP', 'AWG_SampleRate_GHz', 'PulseFileDir', 'PB_IP', 'PH_serialNr','PH_BaseResolution','connection','PH_Mode','SyncChannel', 'PhotonChannel',
        'PulseLength_ns', 'PulsePeriod_ns', 'MarkerLength_ns', 'PulseRepeat', 'bin_width_ns',  'SampleTime_ms', 'SampleNum', 'LogScale'};
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};

    end
    properties(SetAccess=private,Hidden)
        %picoharpH; %handle to PicoHarp300
        listeners;
        abort_request = false;
        acquiring = false;
    end
    methods(Access=private)
        function obj = AWGPulseLengthSweep()
            obj.loadPrefs;
            
        end
    end

    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Experiments.AWGOptimize();
            end
            obj = Object;
        end
    end


    methods
        function run(obj,status,managers,ax)

            

            assert(~isempty(obj.picoharpH)&&isvalid(obj.picoharpH),'PicoHarp driver not intialized properly.');
            status.String = 'Experiment started';
            obj.SetPHconfig;
            obj.data = [];
            obj.meta = [];
            obj.prepPlot(ax);
            obj.abort_request = false;
            obj.acquiring = true;
            drawnow;
            t = tic;
            Resolution = obj.picoharpH.PH_GetResolution;
            Countrate0 = obj.picoharpH.PH_GetCountRate(0);
            Countrate1 = obj.picoharpH.PH_GetCountRate(1);
            obj.meta.resolution = Resolution;

            AWGPulseGen(obj.Amplitude, obj.PulseWidth_ns, obj.PulsePeriod_ns, obj.MarkerWidth_ns, obj.PulseRepeat, obj.AWG_SampleRate_GHz, obj.PulseFileDir+sprintf('\AWGPulseLengthSweep.txt'));


            

            time_bin_result = zeros(1, ceil(obj.sync_ns/obj.bin_width_ns));

            for Sample_cnt = 1:obj.SampleNum
                if(obj.abort_request == true)
                    break
                end
                status.String = sprintf('Sample Cnt: %d/%d, Time Elapsed: %0.2f\n', Sample_cnt,obj.SampleNum, toc(t));
                pause(0.2);
                fprintf('\nResolution=%1dps Countrate0=%1d/s Countrate1=%1d/s', Resolution, Countrate0, Countrate1);
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
                            result0(cnt0) = (double(ofl_num) * double(obj.picoharpH.WRAPASample) + double(cur_time_tag))*Resolution;
                        else % chan == 1
                            cnt1 = cnt1 + 1;
                            result1(cnt1) = (double(ofl_num) * double(obj.picoharpH.WRAPASample) + double(cur_time_tag))*Resolution;
                        end
                    end
                    if(nactual)
                        progress = progress + nactual;
                        time_bin_result = time_bin_result + PulsePhotonAnalysis(result0(cnt0_prev + 1:cnt0), result1(cnt1_prev + 1:cnt1), obj.sync_ns, obj.bin_width_ns);
                    else
                        ctcdone = int32(0);
                        ctcdonePtr = libpointer('ixnt32Ptr', ctcdone);
                        [ret, ctcdone] = calllib('PHlib', 'PH_CTCStatus', obj.picoharpH.DeviceNr, ctcdonePtr); 
                    end
                end
                obj.picoharpH.PH_StopMeas;
                ax.Children(1).YData = time_bin_result/cnt0/100;
                ax.Children(1).XData = (1:ceil(obj.sync_ns/obj.bin_width_ns))*obj.bin_width_ns;
                set(ax, 'XLim', [0 obj.sync_ns])
                if obj.LogScale == 1
                set(ax, 'YScale', 'log')
                end
                drawnow limitrate;
            end
            obj.data.time_bin_result = time_bin_result;
            obj.data.bin_width_ns = obj.bin_width_ns;
            obj.data.sync_ns = obj.sync_ns;
        end
        
        function prepPlot(obj,ax)
            obj.data.x0 = [0];
            obj.data.y0 = [0];
            plot(ax,obj.data.x0,obj.data.y0);
            set(ax,'YLim',[0 inf])
            set(ax, 'XLim', [0 inf])
            set(ax.XLabel,'String','Time (ns)')
            set(ax.YLabel,'String','Probability')
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
        
        function val = set_AWG_IP(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.AWG = [];
            end
            if isempty(obj.AWG)
                try
                    % currently '18.25.28.34'; 5/16/2022
                    obj.AWG=Drivers.AWG70002B.instance('visa',obj.AWG_IP);
    %                 obj.AWG=visa('tek', ['TCPIP0::' obj.AWG_IP '::INSTR']);
    %                 fopen(obj.AWG);
                catch err
                    rmfield(obj,'AWG');
    %                 obj.AWG = [];
                    obj.AWG_IP = 'None Set';
                    rethrow(err);
                end
            end
        end


        function dat = GetData(obj,~,~)
            dat = [];
            for i=1:length(obj.show_prefs)
                obj.meta = setfield(obj.meta,obj.show_prefs{i},getfield(obj,obj.show_prefs{i}));
            end
            obj.meta.PH_serialNr = obj.PH_serialNr
            
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

        function val = set_awg_IP(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.AWG = [];
            end
            if isempty(obj.AWG)
                try
                    % currently '18.25.28.34'; 5/16/2022
                    obj.AWG=Drivers.AWG70002B.instance('visa',obj.awg_IP);
    %                 obj.AWG=visa('tek', ['TCPIP0::' obj.awg_IP '::INSTR']);
    %                 fopen(obj.AWG);
                    obj.AWG.SampleRate = obj.AWG_SampleRate_GHz * 1000000000;
                    obj.AWG.Set;
                catch err
                    rmfield(obj,'AWG');
    %                 obj.AWG = [];
                    obj.awg_IP = 'None Set';
                    rethrow(err);
                end
            end
        end


        function val = set_pb_IP(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.pbH = [];
            end
            try
                obj.pbH = Drivers.PulseBlaster.instance(val);
            catch err
                obj.pbH = [];
                obj.PB_IP = 'None Set';
                rethrow(err);
            end
        end
    end
end