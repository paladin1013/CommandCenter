classdef LifetimeMeasurement < Experiments.PulseSequenceSweep.PulseSequenceSweep_invisible
    %AllOpticalT1 Characterizes T1 by optically repumping then resonantly addressing with a swept time delay

    properties(SetObservable,AbortSet)


        % PB config
        resLaser = Modules.Source.empty(1,0); % Allow selection of source
        repumpLaser = Modules.Source.empty(1,0);

        UseMW = false;
        MWSource_init = Modules.Source.empty(1,0);
        MWSource_read = Modules.Source.empty(1,0);
        MW_freq_MHz_init = 2920;
        MW_freq_MHz_read = 3510;
        MW_power_dBm_init = -2; %this seems too much power, with our calibration should be around -16dbm for 1GHz
        MW_power_dBm_read = -1; 
        MWline = 4;
        invert_MW_line = false;


        APDline = 3;
        repumpTime_us = 1; %us
        resOffset_us = 0.1;
        % resTime_us = 10;
        % tauTimesStr_us = 'linspace(0,100,101)'; %eval(tauTimesStr_us) will define sweepTimes


        % AWG related
        UseAWG = true;
        AWGPBline = 8;
        AWG = Drivers.AWG70002B.empty(1, 0);
        PulseWidthStr_ns = 'linspace(20, 40, 21)';
        PulseWidths_ns;
        PulsePeriod_ns = 500;
        PulseDelay_ns = 750;
        PulseBound_ns = [200, 300];

        MarkerWidth_ns = 10;
        PulseRepeat = 20;
        PulseBase = -1;
        AWG_Amplitude_V = 0.5;
        AWG_Channel = 1;
        AWG_SampleRate_GHz = 10;
        AWG_TriggerSource = 'B';
        MergeSequence = true;
        PulseFileDir = '\\houston.mit.edu\qpgroup\Experiments\AWG70002B\waveforms';





        % PicoHarp configs
        picoharpH = Drivers.PicoHarp300.empty(1,0);
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        connection = false;
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};
        PH_Mode         = 2; % 2 for T2 and 3 for T3 and 0 for histogram
        SyncDivider = uint8(1);
        SyncOffset = 0; %ms
        Ch0_CFDzero = 20;% mV
        Ch0_CFDlevel = 20;% mV
        Ch1_CFDzero = 20;% mV
        Ch1_CFDlevel = 20;% mV
        SyncChannel = 0;
        PhotonChannel = 1;
        Binning = 0;
        Offset = 0; %ms - still not sure what offset is this
        StopAtOverflow = true;
        OverflowCounts = 65535; %65535 is max value
        SyncPBLine = 6;
        SyncPulseWidth_us = 0.01;
        syncPulseBias_begin = 0; 
        syncPulseBias_end = 0; 
        sweepResParams = true;
        resWindowSpan_us = 0.01;
        resWindowOffset_us = 0.01;
        resWindowSpanStr_us = 'linspace(0, 0.1, 11)';
        resWindowOffsetStr_us = 'linspace(0, 0.05, 6)';
        recordAllTimeTags = false;
        
        bin_width_ns = 1;
        LogScale = false;

    end    
    
    % properties
        % tauTimes_us = linspace(0,100,101); %will be in us
    % end
    properties(Constant)
        nCounterBins = 1; %number of APD bins for this pulse sequence,20 is the maximum
        counterSpacing = 0.1; %spacing between APD bins
        vars = {''}; %names of variables to be swept
    end
    properties(SetObservable, GetObservable)
        AWG_IP =    Prefs.String('None Set','set','set_AWG_IP', ...% 18.25.24.255
        'help_text','AWG IP for TCP connection');
        % PulseShape = Prefs.MultipleChoice('Gaussian', 'choices', {'Gaussian', 'sine', 'square'});
    end

    methods(Static)
        obj = instance()
    end
    methods(Access=private)

        function obj = LifetimeMeasurement()
            obj.prefs = [obj.prefs,{ 'AWG_IP', 'UseMW', 'MWSource_init', 'MWSource_read','MW_freq_MHz_init', 'MW_freq_MHz_read','MW_power_dBm_init','MW_power_dBm_read','MWline',...
            'UseAWG', 'PH_serialNr','PH_BaseResolution','connection', 'resLaser','repumpLaser','APDline','repumpTime_us', ...
            'AWGPBline', 'resOffset_us', 'SyncPBLine', 'SyncPulseWidth_us', 'sweepResParams', 'resWindowSpanStr_us', 'resWindowOffsetStr_us', 'resWindowSpan_us', 'resWindowOffset_us', 'recordAllTimeTags' ...
            'PulseWidthStr_ns', 'PulsePeriod_ns', 'PulseDelay_ns', 'PulseBound_ns', 'MarkerWidth_ns', 'PulseRepeat', 'PulseBase', 'bin_width_ns', 'AWG_Amplitude_V', 'AWG_Channel', 'AWG_SampleRate_GHz', 'AWG_TriggerSource', 'MergeSequence', 'PulseFileDir'
            }]; %additional preferences not in superclass
            obj.loadPrefs;
            obj.PulseWidths_ns = eval(obj.PulseWidthStr_ns);
        end
    end

    methods
        

        runMergedSeq(obj, ax, p, status)
        runSeparatedSeq(obj, ax, p, status)
        sweepWindowParams(obj, ax, p, status)
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

                val = '18.25.28.214';
            end
                try
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


        % function val = set_PB_IP(obj,val,~)
        %     emptyFlag = false;
        %     if strcmp(val,'None Set') % Short circuit
        %         val = 'localhost'; % Default value
        %         emptyFlag = true;
        %     end
        %     try
        %         obj.PB = Drivers.PulseBlaster.instance(val);
        %     catch err
        %         obj.PB = [];
        %         obj.PB_IP = 'None Set';
        %         if emptyFlag == false
        %         rethrow(err);
        %         end
        %     end
        % end

        pulseSeq = BuildPulseSequence(obj,tauIndex) %Defined in separate file
        
        function PreRun(obj,~,~,ax)

            if obj.UseMW
            obj.MWSource_init.set_frequency(obj.MW_freq_MHz_init);
            obj.MWSource_read.set_frequency(obj.MW_freq_MHz_read);
            obj.MWSource_init.set_power(obj.MW_power_dBm_init);
            obj.MWSource_read.set_power(obj.MW_power_dBm_read);
            obj.MWSource_init.source_on = 1; % still need to find out which state is which generator
            end

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

        function set.PulseWidthStr_ns(obj,val)
            tempvals = eval(val);
            obj.PulseWidths_ns = tempvals;
            obj.PulseWidthStr_ns = val;
        end
    end
end
