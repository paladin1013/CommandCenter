classdef OpenPhotodiode < Experiments.SlowScan.SlowScan_invisible
    %Open Open-loop laser sweep for slowscan
    % Set center freq_THz
    % Sweeps over percents (usually corresponding to a piezo in a resonator)
    %   - If tune_coarse = true, first moves laser to that frequency;
    %   otherwise scan is perfomed wherever the laser is
    %   - If center_scan = true, percents are relative to wherever the
    %   initial percentage is prior to starting sweep. This can be quite
    %   useful in combination with tune_coarse for lasers that don't leave
    %   the percent centered at 50 after tuning.
    %
    % NOTE: plotting averages over average loop, which might not be same
    % frequencies, or even close if laser mode hops. All averages are saved.

    properties(SetObservable,GetObservable,AbortSet)
        tune_coarse =           Prefs.Boolean(true,     'help_text', 'Whether to tune to the coarse value before the scan.');
        center_scan =           Prefs.Boolean(false,    'help_text', 'When true, percents will be shifted after tune_coarse completes to compensate position of percent.');
        post_scan_tune_max =    Prefs.Boolean(true,     'help_text', 'Whether to tune to the maximum value after the scan has completed.');
    end
    properties(SetObservable,AbortSet)
        freq_THz =      470;
        percents =      'linspace(0,100,101)'; %eval(percents) will define percents for open-loop scan [scan_points]
    end
    properties(SetAccess=private,Hidden)
        percentInitialPosition = 50; % used to center scan if user wants
    end
    properties(Constant)
        xlabel = 'Percent (%)';
    end
    methods(Static)
        % Static instance method is how to call this experiment
        % This is a separate file
        obj = instance()
    end
    methods(Access=private)
        function obj = OpenPhotodiode()
            obj.scan_points = eval(obj.percents);
            obj.prefs = [{'freq_THz','center_scan','tune_coarse','post_scan_tune_max','percents'}, obj.prefs];
            obj.loadPrefs; % Load prefs specified as obj.prefs
        end
    end
    
    methods
        function s = BuildPulseSequence(obj,freqIndex)
            %BuildPulseSequence Builds pulse sequence for repump pulse followed by APD
            %collection during resonant driving
            tunePoint = obj.scan_points(freqIndex);
            if obj.center_scan
                tunePoint = tunePoint - (50-obj.percentInitialPosition);
                % Only allow skipping points if center_scan enabled;
                % otherwise user entered a bad range for percents should error
                if tunePoint < 0 || tunePoint > 100
                    s = false;
                    return % Skip point by returning false
                end
            end
            obj.resLaser.TunePercent(tunePoint);
            obj.resLaser.on;
            PDvalue = obj.nidaqH.ReadAILine('PDreadout');
            obj.data.PDvalues(freqIndex) = PDvalue;
            obj.resLaser.off;
            s = BuildPulseSequence@Experiments.SlowScan.SlowScan_invisible(obj,freqIndex);
        end
        function PreRun(obj,~,managers,ax)
            if obj.tune_coarse
                obj.resLaser.TuneCoarse(obj.freq_THz);
            end
            obj.percentInitialPosition = obj.resLaser.GetPercent;
            PreRun@Experiments.SlowScan.SlowScan_invisible(obj,[],managers,ax);
        end  
        function PostRun(obj,~,managers,ax)
            if obj.post_scan_tune_max
                x = obj.data.freqs_measured;
                y = obj.data.sumCounts;

                % Find the frequency of the maximum value.
                arg = find(y == nanmax(y));
                if isempty(arg)
                    target_max = NaN;
                else
                    target_max = x(arg(1));
                end
                
                obj.meta.post_scan_freq_max = target_max;
                obj.resLaser.tune(obj.resLaser.c/target_max);
            end
        end
        function set.percents(obj,val)
            numeric_vals = str2num(val); %#ok<ST2NM> str2num uses eval but is more robust for numeric input
            assert(~isempty(numeric_vals),'Must have at least one value for percents.');
            assert(min(numeric_vals)>=0&&max(numeric_vals)<=100,'Percents must be between 0 and 100 (inclusive).');
            obj.scan_points = numeric_vals;
            obj.percents = val;
        end
    end
end
