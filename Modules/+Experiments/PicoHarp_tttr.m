classdef PicoHarp_tttr < Modules.Experiment
    %Experimental wrapper for Drivers.PicoHarp300
    
    properties(SetObservable,AbortSet)
        picoharpH;
        data
        meta
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        connection = false;
        Tacq_ms = 1000; %ms
        MaxTime_s = 3600*10; %s
        MaxCounts = 10000;
        % SyncDivider = {uint8(1),uint8(2),uint8(4),uint8(8)};
        SyncDivider = uint8(1);
        SyncOffset = 0; %ms
        Ch0_CFDzero = 10;% mV
        Ch0_CFDlevel = 50;% mV
        Ch1_CFDzero = 10;% mV
        Ch1_CFDlevel = 50;% mV
        % Binning = num2cell(0:7); % Binning can be 0 to MAXBINSTEPS-1 %time resolution = (PH_BaseResolution*2^Binning) ps
        Binning = 0;
        Offset = 0; %ms - still not sure what offset is this
        StopAtOverflow = true;
        OverflowCounts = 65535; %65535 is max value
        prefs = {'connection'};
        PH_Mode         = 2; % 2 for T2 and 3 for T3 and 0 for histogram
        show_prefs = {'PH_serialNr','PH_BaseResolution','connection','PH_Mode', 'MaxTime_s','MaxCounts','Binning','SyncDivider','SyncOffset','Ch0_CFDzero','Ch0_CFDlevel','Ch1_CFDzero','Ch1_CFDlevel','Tacq_ms','StopAtOverflow','OverflowCounts'};
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};

    end
    properties(SetAccess=private,Hidden)
        %picoharpH; %handle to PicoHarp300
        listeners;
        abort_request = false;
        acquiring = false;
    end
    methods(Access=private)
        function obj = PicoHarp_tttr()
            obj.loadPrefs;
        end
    end
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Experiments.PicoHarp_tttr();
            end
            obj = Object;
        end
    end
    methods
        function run(obj,status,managers,ax)
            assert(~isempty(obj.picoharpH)&&isvalid(obj.picoharpH),'PicoHarp driver not intialized properly.');
            assert(isnumeric(obj.SyncDivider),'SyncDivider not set.')
            assert(isnumeric(obj.Binning),'Binning not set.')
            status.String = 'Experiment started';
            obj.SetPHconfig;
            obj.data = [];
            obj.meta = [];
            obj.prepPlot(ax);
            obj.abort_request = false;
            obj.acquiring = true;
            drawnow;


            %Note: after Init or SetSyncDiv you must allow 100 ms for valid new count rate readings
            pause(0.2);
            Resolution = obj.picoharpH.PH_GetResolution;
            Countrate0 = obj.picoharpH.PH_GetCountRate(0);
            Countrate1 = obj.picoharpH.PH_GetCountRate(1);
            obj.meta.resolution = Resolution;
            fprintf('\nResolution=%1dps Countrate0=%1d/s Countrate1=%1d/s', Resolution, Countrate0, Countrate1);
            t = tic;
            obj.picoharpH.PH_StartMeas(obj.Tacq_ms);
            result0 = double(zeros(1, obj.picoharpH.TTREADMAX));
            result1 = double(zeros(1, obj.picoharpH.TTREADMAX));
            progress = 0;
            ctcdone = 0;
            ofl_num = 0;
            cnt0 = 0;
            cnt1 = 0;
            while(ctcdone == 0 && obj.abort_request == false)
                [buffer, nactual] = obj.picoharpH.PH_ReadFiFo;
                % buffer(buffer == 4026531840) = 0;

                for k = 1:nactual
                    chan = bitand(bitshift(buffer(k),-28),15);
                    cur_time_tag = bitand(buffer(k), 2^28-1);
                    if (chan==15) % to detect an overflow signal
                        ofl_num = ofl_num + 1;
                    elseif (chan == 0)
                        cnt0 = cnt0 + 1;
                        result0(cnt0) = double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag);
                    else % chan == 1
                        cnt1 = cnt1 + 1;
                        result1(cnt1) = double(ofl_num) * double(obj.picoharpH.WRAPAROUND) + double(cur_time_tag);
                    end
                end

                    
                if(nactual)
                    progress = progress + nactual;
                    status.String = sprintf('Progress: %9d, Time Elapsed: %0.2f\n',progress, toc(t));
                    ax.Children(1).YData = result0(1:cnt0)*Resolution;
                    ax.Children(1).XData = [1:cnt0];
                    ax.Children(2).YData = result1(1:cnt1)*Resolution;
                    ax.Children(2).XData = [1:cnt1];
                    if max(cnt0, cnt1) > 0
                        set(ax, 'XLim', [0,  max(cnt0, cnt1)])
                    end
                    drawnow limitrate;
                else
                    ctcdone = int32(0);
                    ctcdonePtr = libpointer('int32Ptr', ctcdone);
                    [ret, ctcdone] = calllib('PHlib', 'PH_CTCStatus', obj.picoharpH.DeviceNr, ctcdonePtr); 
                end
            end
            % [time_tags0, time_tags1] = obj.picoharpH.PH_GetTimeTags;
            % ax.Children(2).YData = time_tags1;
            % ax.Children(2).XData = 1:length(time_tags1);

            % ax.Children(1).YData = time_tags0;
            % ax.Children(1).XData = 1:length(time_tags0);
            % drawnow limitrate;
            obj.picoharpH.PH_StopMeas;
            obj.data.y0 = result0(1:cnt0);
            obj.data.x0 = [1:cnt0];
            obj.data.y1 = result1(1:cnt1);
            obj.data.x1 = [1:cnt1];
            fprintf('\nDone\n');
        end
        
        function prepPlot(obj,ax)
            obj.data.x0 = [0];
            obj.data.y0 = [0];
            obj.data.x1 = [0];
            obj.data.y1 = [0];
            plot(ax,obj.data.x0,obj.data.y0, obj.data.x1, obj.data.y1);
            set(ax,'YLim',[0 inf])
            set(ax, 'XLim', [0 inf])
            set(ax.XLabel,'String','Count')
            set(ax.YLabel,'String','TimeStamp (ps)')
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
    end
end
