classdef CMOS_CW_ODMR < Modules.Experiment
    %CMOS_CW_ODMR Description of experiment
    % Useful to list any dependencies here too

    properties(SetObservable,AbortSet)
        averages = 2;
        Laser = Modules.Source.empty(0,1);

        APD_line = 'APD1';
        APD_Sync_line = 'CounterSync';
        Exposure_ms = 100;

        SignalGenerator = Modules.Source.empty(0,1);
        MW_freqs_GHz = 'linspace(2.85,2.91,101)';
        MW_Power_dBm = -30;
        MW_freq_norm_GHz = 2; % If set to -1, will turn off

        % CMOS control properties
        PowerSupply = Moules.Source.empty(0,1); % Power supply source object
        MW_Control_line = '?'; % String pulse blaster line for microwave control
        keep_bias_on = false; % Boolean whether to keep bias on in between experiments
        VDD_VCO = 1; % Number representing VCO voltage (volts)
        VDD_Driver = 1; % Double representing river voltage (volts)
        Driver_Bias_1 = 1; % Double representing driver bias 1 (volts)
        Driver_Bias_2 = 1; % Double representing driver bias 2 (volts)
        VDD_VCO_Channel = ''; % String channel for VCO; no channel if empty
        VDD_Driver_Channel = ''; % String channel for Driver voltage; no channel if empty
        Driver_Bias_1_Channel = ''; % String channel for bias 1; no channel if empty
        Driver_Bias_2_Channel = ''; % String channel for bias 2; no channel if empty
    end
    properties
        prefs = {'MW_freqs_GHz','MW_freq_norm_GHz','MW_Power_dBm','Exposure_ms','averages','Laser',...
                 'SignalGenerator','PowerSupply','keep_bias_on','VDD_VCO','VDD_Driver','Driver_Bias_1','Driver_Bias_2','APD_line','MW_Control_line','APD_Sync_line','VDD_VCO_Channel','VDD_Driver_Channel','Driver_Bias_1_Channel','Driver_Bias_2_Channel'};
    end
    properties(SetAccess=private,Hidden)
        % Internal properties that should not be accessible by command line
        freq_list = linspace(2.85,2.91,101)*1e9; % Internal, set using MW_freqs_GHz
        data = [] % Useful for saving data from run method
        meta = [] % Useful to store meta data in run method
        abort_request = false; % Flag that will be set to true upon abort. Use in run method!
    end

    methods(Static)
        % Static instance method is how to call this experiment
        % This is a separate file
        obj = instance()
    end
    methods(Access=private)
        function obj = CMOS_CW_ODMR()
            % Constructor (should not be accessible to command line!)
            obj.path = 'APD1';
            obj.loadPrefs; % Load prefs specified as obj.prefs
        end
    end

    methods
        run(obj,status,managers,ax) % Main run method in separate file

        function abort(obj)
            % Callback for when user presses abort in CC
            obj.abort_request = true;
        end

        function dat = GetData(obj,stageManager,imagingManager)
            % Callback for saving methods
            dat.data = obj.data;
            dat.meta = obj.meta;
        end

        % Set methods allow validating property/pref set values
        function set.MW_freqs_GHz(obj,val)
            obj.freq_list = str2num(val)*1e9;
            obj.MW_freqs_GHz = val;
        end

        function set.keep_bias_on(obj,val)
            % Turn on/off power supply on changing keep_bias_on
            if val
                obj.PowerSupply.on();
            else
                obj.PowerSupply.off();
            end
            obj.keep_bias_on = val;
        end

        function set.VDD_VCO(obj,val)
            % Change power supply settings when changing bias voltage
            obj.PowerSupply.Channel = obj.VDD_VCO_Channel;
            obj.PowerSupply.Voltage = val;
            obj.PowerSupply.Source_Mode = 'Voltage';
            obj.VDD_VCO = val;
        end

        function set.VDD_Driver(obj,val)
            obj.PowerSupply.Channel = obj.VDD_Driver_Channel;
            obj.PowerSupply.Voltage = val;
            obj.PowerSupply.Source_Mode = 'Voltage';
            obj.VDD_Driver = val;
        end
        
        function set.Driver_Bias_1(obj,val)
            obj.PowerSupply.Channel = obj.Driver_Bias_1_Channel;
            obj.PowerSupply.Voltage = val;
            obj.PowerSupply.Source_Mode = 'Voltage';
            obj.Driver_Bias_1 = val;
        end

        function set.Driver_Bias_2 (obj,val)
            obj.PowerSupply.Channel = obj.Driver_Bias_2_Channel;
            obj.PowerSupply.Voltage = val;
            obj.PowerSupply.Source_Mode = 'Voltage';
            obj.Driver_Bias_2 = val;
        end

        function set.VDD_VCO_Channel(obj,val)
            % Check that channel exists and is different from other channels before changing
            if ~isempty(val) % Just set if channel is empty
                assert((val ~= VDD_Driver_Channel) && (val ~= Driver_Bias_1_Channel) && (val ~= Driver_Bias_2_Channel), 'Channel already assigned')
                obj.PowerSupply.queryPowerSupply('check_channel',val)
            end
            obj.VDD_VCO_Channel = val;
        end

        function set.VDD_Driver_Channel(obj,val)
            if ~isempty(val)
                assert((val ~= VDD_VCO_Channel) && (val ~= Driver_Bias_1_Channel) && (val ~= Driver_Bias_2_Channel), 'Channel already assigned')
                obj.PowerSupply.queryPowerSupply('check_channel',val)
            end
            obj.VDD_Driver_Channel = val;
        end

        function set.Driver_Bias_1_Channel(obj,val)
            if ~isempty(val)
                assert((val ~= Driver_VCO_Channel) && (val ~= VDD_Driver_Channel) && (val ~= Driver_Bias_2_Channel), 'Channel already assigned')
                obj.PowerSupply.queryPowerSupply('check_channel',val)
            end
            obj.VDD_Bias_1_Channel = val;
        end
        
        function set.Driver_Bias_2_Channel(obj,val)
            if ~isempty(val)
                assert((val ~= Driver_VCO_Channel) && (val ~= VDD_Driver_Channel) && (val ~= Driver_Bias_1_Channel), 'Channel already assigned')
                obj.PowerSupply.queryPowerSupply('check_channel',val)
            end
            obj.VDD_Bias_2_Channel = val;
        end
    end
end
