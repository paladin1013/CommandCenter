classdef Line < Modules.Driver
    %Drivers.Attocube.ANC350.Line is a wrapper for the knobs contained in an attocube axis
    
    properties(SetObservable, GetObservable)
        % Note: Maximum values are from manual. Might be hardware-dependent.
        LUT =    Prefs.String('', 'readonly', true, 'display_only', true, ...
                                            'help', 'LUT number for this attocube stepper.')
        
        % Modes other than 'stp+' are currently NotImplemented. Leaving this line in as a note that it is possible.
%         mode =      Prefs.MultipleChoice('stp+', 'choices', {'gnd', 'inp', 'cap', 'stp', 'off', 'stp+', 'stp-'},...
%                                             'help', 'Various operation modes available to each line. See manual for details.');
        name = Prefs.String('', 'readonly', true, 'help', 'Physical alias of this line');

        position = Prefs.Double(0, 'set', 'set_position', 'help', 'Actual position of ANC350 line.');


        % Stepping-related prefs.
        step =      Prefs.Integer(0,    'min', -Drivers.Attocube.ANC350.maxSteps, 'max', Drivers.Attocube.ANC350.maxSteps,'unit', '#', ...
                                            'set', 'set_step', 'display_only', true, ...
                                            'help', ['The core of the class. Setting step to X will cause the atto to step '...
                                                    'abs(X) steps in the sign(X) direction. Then, it will revert back to zero.']);
        frequency = Prefs.Integer(0,    'min', 0, 'max', 1e4, 'set', 'set_frequency',   'unit', 'Hz',...
                                            'help', 'Frequency at which steps occur for multi-step operations. This is the freqeuncy of the sawtooth.');
        amplitude = Prefs.Double(0,     'min', 0, 'max', 150, 'set', 'set_amplitude',   'unit', 'V',...
                                            'help', 'Voltage amplitude for stepping sawtooth.');
        
        % UI stuff to allow the user to step up and down. Future: replace with pref-based metastage.
        steps =     Prefs.Integer(Drivers.Attocube.ANC350.maxSteps, 'max', Drivers.Attocube.ANC350.maxSteps, 'unit', '#',...
                                            'help', 'Number of steps to use when using the Step Up and Step Down buttons.');
        step_up =   Prefs.Boolean(false, 'set', 'set_step_up',...
                                            'help', 'Button to command the atto to step up by `steps` steps.');
        step_down = Prefs.Boolean(false, 'set', 'set_step_down',...
                                            'help', 'Button to command the atto to step down by `steps` steps.');
        
        % Fine-adjustment-related prefs.
        DcVoltage =    Prefs.Double(0,     'min', 0, 'max', 150, 'set', 'set_DcVoltage',      'unit', 'V',...
                                            'help', 'Voltage that is added to the step waveform for a fine offset on the piezo.');
        output =     Prefs.Boolean(false, 'set', 'set_output', ...
                                            'help', 'Whether the output of this axis is enabled.')
        moving =     Prefs.Boolean(false, 'readonly', true, ...
                                            'help', 'Whether the axis is moving.')
    end
    properties(SetAccess=immutable, Hidden)
        parent; % Handle to Drivers.Attocube.ANC350 parent
    end
    properties(SetAccess=immutable)
        line;   % Index of the physical line of the parent that this D.A.Line controls.
    end
    
    
    methods(Static)
        function obj = instance(parent, line)
            parent.getInfo(line, 'LutName'); % Error if the parent does not possess this line
            
            name_array = {'X', 'Y', 'Z'};
            obj.name = name_array(line);
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.Attocube.ANC350.Line.empty(1,0);
            end
            id = [parent.host '_line' num2str(line)];
            for ii = 1:length(Objects)
                if isvalid(Objects(ii)) && isvalid(Objects(ii).parent) && isequal(id, Objects(ii).singleton_id)
                    obj = Objects(ii);
                    return
                end
            end
            obj = Drivers.Attocube.ANC350.Line(parent, line);
            obj.singleton_id = id;
            Objects(end+1) = obj;
        end
    end
    
    methods(Access=private)
        function obj = Line(parent, line)
            obj.parent = parent;
            obj.line = line;
            
            % obj.com('setm', 'stp+');   % Default; eventually change this to give the user more freedom.
            
            obj.getInfo();

            addlistener(obj.parent,'ObjectBeingDestroyed',@(~,~)obj.delete);
        end
    end
    
    methods
        function [response, numeric] = com(obj, command, varargin)
            if nargout == 2
                [response, numeric] = obj.parent.com(command, obj.parent.serialNo, obj.line-1, varargin{:});
            else
                response = obj.parent.com(command, obj.parent.serialNo, obj.line-1, varargin{:});
            end
        end
        function delete(~)
            % Do nothing.
        end
    end
    
    methods(Hidden)
        function stepu(obj, steps)
            obj.com('moveSteps', true, steps); % The second param is for [forward:bool] in python
        end
        function stepd(obj, steps)
            obj.com('moveSteps', false, steps);
        end
        function val = set_step(obj, val, ~)
            val = round(val);   % Only integer steps. (change to clean?)
            
            if val < 0
                obj.stepu(abs(val));
            elseif val > 0
                obj.stepd(abs(val));
            end
            
            val = 0;
        end
        function val = set_step_up(obj, ~, ~)
            obj.step = obj.steps;
            val = false;    % Turn button back off.
        end
        function val = set_step_down(obj, ~, ~)
            obj.step = -obj.steps;
            val = false;    % Turn button back off.
        end
    end
    
    methods(Hidden)
        function val = set_frequency(obj, val, ~)
            obj.com('setFrequency', val);
        end
        function val = set_amplitude(obj, val, ~)
            obj.com('setAmplitude', val);
        end
        function val = set_DcVoltage(obj, val, ~)
            obj.com('setDcVoltage', val);
        end
        function val = set_output(obj, val, ~)
            obj.com('setOutput', val);
        end
        
        function getInfo(obj)
            info = 0;
            for retryTime = 1:5
                try
                    info = obj.com('getInfo');
                catch err
                    warning("Connection retry time %d, error: %s", retryTime, err.message);
                    
                end
                if isstruct(info)
                    break
                end
            end
            
            obj.LUT =       info.LutName;
            obj.frequency = info.Frequency;
            obj.amplitude = info.Amplitude;
            obj.DcVoltage = info.DcVoltage;
            % [outputConnected, obj.output, obj.moving, targetReached, eotFwd, eotBwd, error] = deal(num2cell(info.AxisStatus'));
            obj.output = info.AxisStatus(2);
            obj.moving = info.AxisStatus(3);
            % AxisStatus (7*1 bool):
            % connected Output: If the axis is connected to a sensor.
            % enabled Output: If the axis voltage output is enabled.
            % moving Output: If the axis is moving.
            % target Output: If the target is reached in automatic positioning
            % eotFwd Output: If end of travel detected in forward direction.
            % eotBwd Output: If end of travel detected in backward direction.
            % error Output: If the axis' sensor is in error state.
        end
        
        function val = get_capacitance(obj, ~)

            val = obj.parent.getInfo(obj.line-1, 'Capacitance');
        end
    end
end

