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
        readoutPulseDelay_us = 1;
        readoutPulseTime_us = 10;
        CounterLength_us = 10;
        tauTimes_us = 'linspace(0,100,101)'; %eval(tauTimes_us) will define sweepTimes


        % For PicoHarp300 tttr mode
        % show_prefs = {'PH_serialNr','PH_BaseResolution'};
        % readonly_prefs = {'PH_serialNr','PH_BaseResolution'};
        PicoHarp300 = Drivers.PicoHarp300.empty(1,0);
        PH_serialNr = 'No device';
        PH_BaseResolution = 'No device';
        WRAPAROUND=210698240; % Time period (ps) between two overflow signals
        
    end
    properties
        tauTimes = linspace(0,100,101); %will be in us
    end
    properties(Constant)
        nCounterBins = 2; %number of APD bins for this pulse sequence,20 is the maximum
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
            obj.prefs = [obj.prefs,{'PicoHarp300', 'PH_Mode', 'PH_serialNr', 'PH_BaseResolution', 'resLaser','repumpLaser','MWSource_init', 'MWSource_read','MW_freq_MHz_init', 'MW_freq_MHz_read','MW_power_dBm_init','MW_power_dBm_read','MWline','APDline','repumpTime_us','resOffset_us',...
            'readoutPulseTime_us','CounterLength_us','tauTimes_us'}]; %additional preferences not in superclass
            obj.loadPrefs;
        end
    end

    methods
        
        function val = set_picoharp_dev(obj,val, ~)
            MODE = str2num(val);
            mlock
            persistent Objects;
            % if isempty(Objects)
            %     Objects = Drivers.PicoHarp300.empty(1,0);
            % end
            if strcmp(val,'None Set') % Short circuit
                obj.PicoHarp300 = [];
            end
            find_instance = 0;
            % for i = 1:length(Objects)
            %     Objects(i).singleton_id
            %     if isvalid(Objects(i)) && isequal("PicoHarp300_Mode"+val,Objects(i).singleton_id)
            %         obj.PicoHarp300 = Objects(i);
            %         find_instance = 1;
            %         fprintf("Find initialized PicoHarp300_Mode%d", MODE);
            %         break
            %     end
            % end
            if (find_instance==0)
                try
                    obj.PicoHarp300 = Drivers.PicoHarp300.instance(MODE);
                catch err
                    % obj.PicoHarp300 = [];
                    % obj.PH_serialNr = 'None Set';
                    for i = 1:length(Objects)
                        Objects(i).singleton_id
                        if isvalid(Objects(i)) && isequal("PicoHarp300_Mode"+val,Objects(i).singleton_id)
                            obj.PicoHarp300 = Objects(i);
                            find_instance = 1;
                            fprintf("Find initialized PicoHarp300_Mode%d", MODE);
                            break
                        end
                    end
                    % rethrow(err);
                end
            end
            obj.PH_serialNr = obj.PicoHarp300.SerialNr{1};
            obj.PH_BaseResolution = obj.PicoHarp300.PH_GetBaseResolution;
        end

        pulseSeq = BuildPulseSequence(obj,tauIndex) %Defined in separate file
        
        function PreRun(obj,~,~,ax)
            obj.MWSource_init.set_frequency(obj.MW_freq_MHz_init);
            obj.MWSource_read.set_frequency(obj.MW_freq_MHz_read);
            obj.MWSource_init.set_power(obj.MW_power_dBm_init);
            obj.MWSource_read.set_power(obj.MW_power_dBm_read);
            obj.MWSource_init.source_on = 1; % still need to find out which state is which generator


            Resolution = obj.PicoHarp300.PH_GetResolution;
            Countrate0 = obj.PicoHarp300.PH_GetCountRate(0);
            Countrate1 = obj.PicoHarp300.PH_GetCountRate(1);
            obj.meta.resolution = Resolution;
            fprintf('\nResolution=%1dps Countrate0=%1d/s Countrate1=%1d/s', Resolution, Countrate0, Countrate1);

            %prepare axes for plotting
            hold(ax,'on');
            plotH(1) = plot(ax,obj.tauTimes,obj.data.sumCounts(1,:,1),'color','b');
            plotH(2) = plot(ax,obj.tauTimes,obj.data.sumCounts(1,:,2),'color','r');
            ax.UserData.plots = plotH;
            ylabel(ax,'Normalized PL');
            xlabel(ax,'Delay Time \tau (\mus)');
            hold(ax,'off');
            set(ax,'xlimmode','auto','ylimmode','auto','ytickmode','auto')
        end
        
        function UpdateRun(obj,~,~,ax,~,~)
            if obj.averages > 1
                averagedData = squeeze(nanmean(obj.data.sumCounts,1));
                meanError = squeeze(nanmean(obj.data.stdCounts,1));
            else
                averagedData = obj.data.sumCounts;
                meanError = obj.data.stdCounts;
            end
            
            %grab handles to data from axes plotted in PreRun
            %ax.UserData.plots(1).YData = averagedData(:,1);
            ax.UserData.plots(2).YData = averagedData(:,2);
%             ax.UserData.plots{1}.YNegativeDelta = meanError(:);
%             ax.UserData.plots{1}.YPositiveDelta = meanError(:);
%             ax.UserData.plots{1}.update;
%             drawnow limitrate;
            drawnow limitrate;
        end
        
        function PostRun(obj,~,~,ax)
            obj.PicoHarp300.PH_StopMeas;
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
