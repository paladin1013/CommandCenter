classdef PolarizationAndReadoutEOM_tttr < Experiments.PulseSequenceSweep.PulseSequenceSweep_invisible
    %AllOpticalT1 Characterizes T1 by optically repumping then resonantly addressing with a swept time delay

    properties(SetObservable,AbortSet)
        resLaser = Modules.Source.empty(1,0); % Allow selection of source
        repumpLaser = Modules.Source.empty(1,0);
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
        %resPulse1Time_us = 10;
        readoutPulseDelay_us = 5;
        readoutPulseTime_us = 10;
        CounterLength_us = 10;
        tauTimes_us = 'linspace(0,100,101)'; %eval(tauTimes_us) will define sweepTimes

        
        picoharpH = Drivers.PicoHarp300.empty(1,0);
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        readonly_prefs = {'PH_serialNr','PH_BaseResolution'};
        SyncDivider = uint8(1);
        SyncOffset = 0; %ms
        Ch0_CFDzero = 20;% mV
        Ch0_CFDlevel = 20;% mV
        Ch1_CFDzero = 20;% mV
        Ch1_CFDlevel = 20;% mV
        Binning = 0;
        Offset = 0; %ms - still not sure what offset is this
        StopAtOverflow = true;
        OverflowCounts = 65535; %65535 is max value
        SyncPBLine = 6;
        SyncPulseWidth_us = 0.01;


        syncPulseBias_begin = 0; 
        syncPulseBias_end = 0; 
        recordAllTimeTags = false;
    end    
    
    properties
        tauTimes = linspace(0,100,101); %will be in us
    end
    properties(Constant)
        nCounterBins = 3; %number of APD bins for this pulse sequence,20 is the maximum
        counterSpacing = 0.1; %spacing between APD bins
        vars = {'tauTimes'}; %names of variables to be swept
    end
    properties(SetObservable, GetObservable)
        PH_Mode = Prefs.String('None Set', 'set', 'set_picoharp_dev', 'help_text', 'Set Picoharp300 device for time tag measurement')
    end

    methods(Static)
        obj = instance()
    end
    methods(Access=private)

        function obj = PolarizationAndReadoutEOM_tttr()
            obj.prefs = [obj.prefs,{'PH_Mode', 'PH_serialNr', 'PH_BaseResolution','Ch0_CFDzero', 'Ch0_CFDlevel', 'Ch1_CFDzero', 'Ch1_CFDlevel' 'resLaser','repumpLaser','MWSource_init', 'MWSource_read','MW_freq_MHz_init', 'MW_freq_MHz_read','MW_power_dBm_init','MW_power_dBm_read','MWline','APDline','repumpTime_us','resOffset_us',...
            'readoutPulseTime_us','CounterLength_us', 'SyncPBLine', 'SyncPulseWidth_us','tauTimes_us', 'recordAllTimeTags'}]; %additional preferences not in superclass
            
            obj.loadPrefs;
        end
    end

    methods
        
        function val = set_picoharp_dev(obj,val, ~)
            MODE = str2num(val);
            if strcmp(val,'None Set') % Short circuit
                obj.picoharpH = [];
            end
            obj.picoharpH = Drivers.PicoHarp300.instance(MODE);
            obj.PH_serialNr = obj.picoharpH.SerialNr{1};
            obj.PH_BaseResolution = obj.picoharpH.PH_GetBaseResolution;


            obj.picoharpH.PH_SetInputCFD(0,obj.Ch0_CFDlevel,obj.Ch0_CFDzero);
            obj.picoharpH.PH_SetInputCFD(1,obj.Ch1_CFDlevel,obj.Ch1_CFDzero);
            obj.picoharpH.PH_SetBinning(obj.Binning);
            obj.picoharpH.PH_SetOffset(obj.Offset);
            obj.picoharpH.PH_SetStopOverflow(obj.StopAtOverflow,obj.OverflowCounts); %65535 is max value
            obj.picoharpH.PH_SetSyncOffset(obj.SyncOffset);
            obj.picoharpH.PH_SetSyncDiv(obj.SyncDivider);
            
        end

        pulseSeq = BuildPulseSequence(obj,tauIndex) %Defined in separate file
        
        function PreRun(obj,~,~,ax)
            obj.MWSource_init.set_frequency(obj.MW_freq_MHz_init);
            obj.MWSource_read.set_frequency(obj.MW_freq_MHz_read);
            obj.MWSource_init.set_power(obj.MW_power_dBm_init);
            obj.MWSource_read.set_power(obj.MW_power_dBm_read);
            obj.MWSource_init.source_on = 1; % still need to find out which state is which generator

            % Resolution = obj.picoharpH.PH_GetResolution;
            % Countrate0 = obj.picoharpH.PH_GetCountRate(0);
            % Countrate1 = obj.picoharpH.PH_GetCountRate(1);
            % obj.meta.resolution = Resolution;
            % fprintf('\nResolution=%1dps Countrate0=%1d/s Countrate1=%1d/s', Resolution, Countrate0, Countrate1);

            %prepare axes for plotting
            hold(ax,'on');
            plotH(1) = plot(ax,obj.tauTimes,obj.data.counts(1,:,1),'color','b');
            plotH(2) = plot(ax,obj.tauTimes,obj.data.counts(1,:,2),'color','r');
            ax.UserData.plots = plotH;
            ylabel(ax,'Normalized PL');
            xlabel(ax,'Delay Time \tau (\mus)');
            hold(ax,'off');
            set(ax,'xlimmode','auto','ylimmode','auto','ytickmode','auto')
        end
        
        function UpdateRun(obj,~,~,ax,~,~)
            if obj.averages > 1
                averagedData = squeeze(nanmean(obj.data.counts,1));
            else
                averagedData = obj.data.counts;
            end
            
            %grab handles to data from axes plotted in PreRun
            %ax.UserData.plots(1).YData = averagedData(:,1);
            ax.UserData.plots(2).YData = averagedData(:,2);
%             ax.UserData.plots{1}.update;
%             drawnow limitrate;
            drawnow limitrate;
        end
        
        function PostRun(obj,~,~,ax)
            obj.picoharpH.PH_StopMeas;
        end

        function set.tauTimes_us(obj,val)
            %Note that order matters here; setting tauTimes first is
            %important in case of error
            tempvals = eval(val);
            obj.tauTimes = tempvals;
            obj.tauTimes_us = val;
        end
    end
end
