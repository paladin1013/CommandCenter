classdef VoltageSweep < Modules.Experiment
    % Runs an experiment at every point in a voltage sweep.
    properties(SetObservable, GetObservable)
        keithley_gpib_addr   = Prefs.Integer(16, 'min', 1);
        keithley_gpib_num   = Prefs.Integer(0, 'min', 0);

        % begin_voltage   = Prefs.Double(0);
        % step_voltage    = Prefs.Double(.1, 'min', 0);
        % end_voltage     = Prefs.Double(1);
        voltage_list_str = '[0, 50, 100, 100, 50, 0, -50]';
        voltage_list = [];

        record_currents = Prefs.Boolean(true);
        
        experiment      = Prefs.ModuleInstance(Modules.Experiment.empty(0), 'inherits', {'Modules.Experiment'});
    end

    properties(Access=private)
        keithley = [];
    end

    properties
        data = [] % subclasses should not set this; it can be manipulated in GetData if necessary
        meta = [] % Store experimental settings
        prefs = {'keithley_gpib_addr', 'keithley_gpib_num','voltage_list_str', 'record_currents','experiment'};
    end

    methods(Static)
        function obj = instance(varargin)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Experiments.VoltageSweep.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(varargin, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Experiments.VoltageSweep(varargin{:});
            obj.singleton_id = varargin;
            Objects(end+1) = obj;
        end
%         function [dx,dy,dz,metric] = Track(Imaging,Stage,track_thresh)
%             % Imaging = handle to active imaging module
%             % Stage = handle to active stage module
%             % track_thresh = true --> force track
%             %                false --> return metric, but don't track
%             %                numeric --> if metric <= track_thresh, track
%
%             tracker = Drivers.Tracker.instance(Stage,Stage.galvoDriver);
%             dx = NaN;
%             dy = NaN;
%             dz = NaN;
%             metric = NaN;
%             try
%                 counter = Drivers.Counter.instance('APD1','APDgate');
%                 try
%                     metric = counter.singleShot(tracker.dwell);
%                 catch err
%                     counter.delete
%                     rethrow(err)
%                 end
%                 counter.delete
%                 if (islogical(track_thresh) && track_thresh) || (~islogical(track_thresh) && metric < track_thresh)
%                     currPosition = Stage.position;
%                     tracker.Track(false);
%                     newPosition = Stage.position;
%                     delta = newPosition-currPosition;
%                     dx = delta(1);
%                     dy = delta(2);
%                     dz = delta(3);
%                 end
%             catch err
%                 tracker.delete;
%                 rethrow(err)
%             end
%             tracker.delete;
%         end
    end
    methods(Access=private)
        function obj = VoltageSweep()
            obj.experiment = Experiments.SlowScan.Open.instance;
            obj.loadPrefs;
            obj.voltage_list = eval(obj.voltage_list_str);
        end
    end
    methods
        function run(obj, status, managers, ax)
            % step = sign(obj.end_voltage - obj.begin_voltage) * abs(obj.step_voltage);
            obj.data.volt = obj.voltage_list;
            
            if length(obj.voltage_list) == 1
                obj.data.volt = obj.voltage_list(1);
            end
            
            if obj.record_currents
                obj.data.curr = NaN(1,length(obj.data.volt));
            end
            obj.data.result = cell(1,length(obj.data.volt));

            obj.keithley = Drivers.Keithley2400.instance(obj.keithley_gpib_num, obj.keithley_gpib_addr);
            obj.keithley.mode = 'VOLT';
            obj.keithley.output = true;
           
            for ii = 1:length(obj.data.volt)
                obj.keithley.voltage = obj.data.volt(ii);

                if obj.record_currents
                    obj.data.curr(ii) = obj.keithley.measureCurrent();
                end
                status.String = sprintf("Current voltage: %d (%d/%d)\n", obj.data.volt(ii), ii, length(obj.data.volt));
                fprintf("Current voltage: %d (%d/%d)\n", obj.data.volt(ii), ii, length(obj.data.volt));
                obj.experiment.run(status, managers, ax);
                dat = obj.experiment.GetData();
                obj.data.result{ii} = dat;
            end

            obj.keithley.voltage = 0;
            obj.keithley.output = false;
        end
        function abort(obj)
            % Callback for when user presses abort in CC
            obj.keithley.voltage = 0;
            obj.keithley.output = false;
            obj.experiment.abort();
        end
        function dat = GetData(obj,~,~)
            % Callback for saving methods (note, lots more info in the two managers input!)
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
        function set.voltage_list_str(obj,val)
            tempvals = eval(val);
            obj.voltage_list = tempvals;
            obj.voltage_list_str = val;
        end
    end
end
