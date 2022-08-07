classdef ToggleButton < Prefs.Numeric
    %BUTTON for access to a "set" method that it is changing between two states 'on' and 'off'. For instance, 
    %
    %    Prefs.ToggleButton(false/true, 'string', 'Click Me!', 'name', 'Greeting', 'set', 'set_xxx')
    %
    % will create a UI line with 'Greeting: [ Click Me! ]' where the button is square bracketed.
    % Clicking the button will execute the set function and display 'Hello World' in the console.

    properties (Hidden)
        min = false;
        max = true;
    end
    
    properties (Hidden)
        default = false;
        string = '';
        ui = Prefs.Inputs.ToggleButtonField;
    end
    
    methods
        function obj = ToggleButton(varargin)
            obj = obj@Prefs.Numeric(varargin{:});
        end
        function validate(obj,val)
            val = obj.value;
%             validateattributes(val,{'char','string'},{'scalartext'})
        end
    end
    
end
