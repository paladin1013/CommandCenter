classdef PicoHarpCalibration < Modules.Experiment
    %Experimental wrapper for Drivers.PicoHarp300
    

    properties(SetObservable, GetObservable)
        pb_IP = Prefs.String('None Set','set','set_pb_IP','help_text','Hostname for computer running pulseblaster server');
        NIDAQ_dev = Prefs.String('None Set','set','set_NIDAQ_dev','help_text','Device name for NIDAQ (found/set in NI-MAX)');
    end
    properties(SetObservable,AbortSet)
        picoharpH;
        pbH;
        nidaqH;


        data
        meta
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        PH_connection = false;
        Ch0_CFDzero = 20;% mV
        Ch0_CFDlevel = 20;% mV
        Ch1_CFDzero = 20;% mV
        Ch1_CFDlevel = 20;% mV
        Binning = 0;
        Offset = 0;
        StopAtOverflow = false;
        OverflowCounts = 65535; %65535 is max value
        windowTime_us = 500;
        PH_Mode         = 2; % 2 for T2 and 3 for T3 and 0 for histogram


        signCoefficients = [-1, 1; -1, 0; 0, 1; -1, -1; 1, 1];
        timeOffsetsStr_ns = 'linspace(0, 1000, 11)';
        timeOffsets_us = linspace(0, 1000, 11)/1000;
        vars = {'signCoefficients', 'timeOffsetsStr_ns'};
        APDline = 3;
        SyncPBLine = 6;
        syncPulseWidth_us = 0.1;
        rounds = 10;
        samples = 500;

        prefs = { 'rounds', 'samples','windowTime_us', 'syncPulseWidth_us', 'pb_IP', 'NIDAQ_dev', 'PH_connection', 'PH_serialNr','PH_BaseResolution','PH_Mode','Ch0_CFDzero','Ch0_CFDlevel','Ch1_CFDzero','Ch1_CFDlevel','StopAtOverflow','OverflowCounts', 'timeOffsetsStr_ns'
        };
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};

    end
    properties(SetAccess=private,Hidden)
        %picoharpH; %handle to PicoHarp300
        listeners;
        abort_request = false;
        acquiring = false;
    end
    methods(Access=private)
        function obj = PicoHarpCalibration()
            obj.loadPrefs;
        end
    end


    methods(Static)
        function obj = instance(varargin)
            % This file is what locks the instance in memory such that singleton
            % can perform properly. 
            % For the most part, varargin will be empty, but if you know what you
            % are doing, you can modify/use the input (just be aware of singleton_id)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Experiments.PicoHarpCalibration.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(varargin,Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Experiments.PicoHarpCalibration(varargin{:});
            obj.singleton_id = varargin;
            Objects(end+1) = obj;
        end
    end
    methods
        function run( obj,status,managers,ax)
            % Main run method (callback for CC run button)
            obj.abort_request = false;
            status.String = 'Experiment started';
            obj.prepPlot(ax);
            assert(~isempty(obj.picoharpH), "PicoHarp300 is not connected");

            [signCoefficientsSetNum, ~] = size(obj.signCoefficients);
            obj.data.counts = NaN([signCoefficientsSetNum,length(obj.timeOffsetsStr_ns), obj.rounds, obj.samples]);
            obj.data.diff = NaN([signCoefficientsSetNum,length(obj.timeOffsetsStr_ns), obj.rounds, obj.samples]);
            obj.data.timeTags = cell([signCoefficientsSetNum,length(obj.timeOffsetsStr_ns), obj.rounds, obj.samples]);
            obj.data.errorRate = NaN([signCoefficientsSetNum, length(obj.timeOffsetsStr_ns)]);

            obj.meta.prefs = obj.prefs2struct;
            obj.SetPHconfig;

            for i = 1:length(obj.vars)
                obj.meta.vars(i).name = obj.vars{i};
                obj.meta.vars(i).vals = obj.(obj.vars{i});
            end
            
            obj.meta.position = managers.Stages.position; % Stage position

            f = figure('visible','off','name',mfilename);
            a = axes('Parent',f);
            p = plot(NaN,'Parent',a);

            try
                
                % Construct APDPulseSequence once, and update apdPS.seq
                % Not only will this be faster than constructing many times,
                % APDPulseSequence upon deletion closes PulseBlaster PH_connection
                apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
                

                for signCnt = 1:size(obj.signCoefficients, 1)
                    signCoefficient = obj.signCoefficients(signCnt, :);
                    for offsetCnt = 1:numel(obj.timeOffsets_us)
                        syncPulseOffset_us = obj.timeOffsets_us(offsetCnt);
                        assert(floor(100*syncPulseOffset_us) == 100*syncPulseOffset_us, "The syncPulseOffset should be integer times of resolution (0.01 us).")
                        for roundCnt = 1:obj.rounds
                            drawnow('limitrate'); 
                            assert(~obj.abort_request,'User aborted.');

                            statusString = sprintf("signCoefficient: %d, %d (%i/%i)\ntimeOffset_us: %.2f (%i/%i)\n, Progress: %i/%i rounds\n", signCoefficient(1), signCoefficient(2), signCnt, signCoefficientsSetNum, syncPulseOffset_us, offsetCnt, numel(obj.timeOffsets_us), roundCnt, obj.rounds);
                            status.String = statusString;
                            
                            pulseSeq = obj.BuildPulseSequence(signCoefficient*syncPulseOffset_us);
                            assert(pulseSeq~= false, "Error building pulse sequence");
                            pulseSeq.repeat = obj.samples;
                            apdPS.seq = pulseSeq;
                            apdPS.start(1000); % hard coded
                            [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;
                            apdPS.stream(p);
                            obj.picoharpH.PH_StopMeas;
                            


                            assert(length(rawTttrData0) == 5*obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",5*obj.samples - 3, length(rawTttrData0)))
                            obj.data.counts(signCnt, offsetCnt, roundCnt,:) = p.YData;
                            for sampleCnt = 1:obj.samples
                                obj.data.timeTags{signCnt, offsetCnt, roundCnt, sampleCnt} = rawTttrData1((rawTttrData1>rawTttrData0(sampleCnt*5-4)) & (rawTttrData1<rawTttrData0(sampleCnt*5-3)))-rawTttrData0(sampleCnt*5-4);
                                obj.data.diff(signCnt, offsetCnt, roundCnt, sampleCnt) = length(obj.data.timeTags{signCnt, offsetCnt, roundCnt, sampleCnt}) - obj.data.counts(signCnt, offsetCnt, roundCnt, sampleCnt);

                            end
                        end
                        diff = obj.data.diff(signCnt, offsetCnt, :, :);
                        count = obj.data.counts(signCnt, offsetCnt, :, :);
                        obj.data.positiveErrorRate(signCnt, offsetCnt) = sum(diff(diff>0), 'all')/ sum(count, 'all');
                        obj.data.negativeErrorRate(signCnt, offsetCnt) = -sum(diff(diff<0), 'all')/ sum(count, 'all');
                        obj.data.errorRate(signCnt, offsetCnt) = sum(abs(diff), 'all')/ sum(count, 'all');
                        ax.UserData.plots(1).YData = obj.data.positiveErrorRate(signCnt, 1:offsetCnt);
                        ax.UserData.plots(2).YData = obj.data.negativeErrorRate(signCnt, 1:offsetCnt);
                        ax.UserData.plots(3).YData = obj.data.errorRate(signCnt, 1:offsetCnt);
                        ax.UserData.plots(1).XData = obj.timeOffsets_us(1:offsetCnt);
                        ax.UserData.plots(2).XData = obj.timeOffsets_us(1:offsetCnt);
                        ax.UserData.plots(3).XData = obj.timeOffsets_us(1:offsetCnt);
                        
                    end

                end
            catch err
            end
            delete(f);
            if exist('err','var')
                rethrow(err)
            end

        end

        function s = BuildPulseSequence(obj, syncPulseOffset)

            s = sequence('PicoHarpCalibration');
            APDchannel = channel('APDgate','color','b','hardware',obj.APDline-1,'counter','APD1');
            SyncChannel = channel('PicoHarpSync', 'color', 'c', 'hardware', obj.SyncPBLine-1);
            s.channelOrder = [APDchannel,SyncChannel];
            
            s1 = node(s.StartNode, APDchannel,'units','us', 'delta', 10);
            
            
            begin_sync = node(s1,SyncChannel,'units','us', 'delta',-1.5+syncPulseOffset(1));
            test = node(begin_sync,SyncChannel,'units','us', 'delta',obj.syncPulseWidth_us);
            
            for k = 1:3
                test = node(test, SyncChannel,'units','us', 'delta', 0.5-obj.syncPulseWidth_us);
                test = node(test, SyncChannel,'units','us', 'delta', obj.syncPulseWidth_us);
            end
            
            
            s2 = node(s1 ,APDchannel,'units','us','delta', obj.windowTime_us);
            
            
            
            
            
            end_sync = node(s2,SyncChannel,'units','us', 'delta',syncPulseOffset(2));
            node(end_sync,SyncChannel,'units','us', 'delta',obj.syncPulseWidth_us);
            
            
            end
            
        
        function prepPlot(obj,ax)
            hold(ax, 'on'); 

            plotH(1) = plot(ax, [0], [0], 'Color', 'r');
            plotH(2) = plot(ax, [0], [0], 'Color', 'g');
            plotH(3) = plot(ax, [0], [0], 'Color', 'b');
            legend(ax, {'Positive error rate', 'Negative error rate', 'Error rate'});
            ax.UserData.plots = plotH;
            xlabel("Offset time (us)");
            ylabel("Miscount rate");
            set(ax,'xlimmode','auto','ylimmode','auto','ytickmode','auto')

        end
        
        function SetPHconfig(obj)
            obj.picoharpH.PH_SetInputCFD(0,obj.Ch0_CFDlevel,obj.Ch0_CFDzero);
            obj.picoharpH.PH_SetInputCFD(1,obj.Ch1_CFDlevel,obj.Ch1_CFDzero);
            obj.picoharpH.PH_SetBinning(obj.Binning);
            obj.picoharpH.PH_SetOffset(obj.Offset);
            obj.picoharpH.PH_SetStopOverflow(obj.StopAtOverflow,obj.OverflowCounts); %65535 is max value
            % obj.picoharpH.PH_SetSyncOffset(obj.SyncOffset);
            % obj.picoharpH.PH_SetSyncDiv(obj.SyncDivider);
        end
        
        function abort(obj)
            obj.abort_request = true;
        end
        
        function dat = GetData(obj,~,~)
            dat = [];
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
        function set.PH_connection(obj,val)
            if val
                obj.PH_serialNr = 'connecting...';
                drawnow;
                try
                    obj.picoharpH = Drivers.PicoHarp300.instance(obj.PH_Mode);
                catch err
                    obj.PH_connection = false;
                    obj.PH_serialNr = 'No device';
                    rethrow(err)
                end
                obj.PH_connection = true;
                obj.PH_serialNr = obj.picoharpH.SerialNr{1};
                obj.PH_BaseResolution = obj.picoharpH.PH_GetBaseResolution;
            % elseif ~isempty(obj.picoharpH)
            %     obj.picoharpH.delete;
            %     obj.PH_connection = false;
            %     obj.PH_serialNr = 'No device';
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
                obj.pb_IP = 'None Set';
                rethrow(err);
            end
        end
        function val = set_NIDAQ_dev(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.nidaqH = [];
            end
            try
                obj.nidaqH = Drivers.NIDAQ.dev.instance(val);
            catch err
                obj.nidaqH = [];
                obj.NIDAQ_dev = 'None Set';
                rethrow(err);
            end
        end
        function set.timeOffsetsStr_ns(obj, val)
            tempvals = eval(val);
            obj.timeOffsets_us = tempvals/1000;
            obj.timeOffsetsStr_ns = val;
        end
    end
end
