classdef Reference < Base.Pref
    %REFERENCE acts as a pointer to other Prefs. set_reference is used to
    % set which Pref this reference points to. Upon setting a Pref to
    % reference, Prefs.Reference behaves exactly as the target Pref via
    % the GUI or the .read() or .writ() methods. This is especially useful
    % for making modules with general functionality.
    
    properties (Hidden)
        default = [];
        ui = Prefs.Inputs.ReferenceField;
        reference = []; % Prefs.Numeric.empty(1,0);
        steponly = false; % Steponly being `true` means this referenced value can only be changed gradually (e.g.Piezo, Resonant Laser) but not shift dramatically. 
        % Also, errors may occor when it come back to a previously set value.
        % This reference will be no longer allowed to participate in global optimization, and the steponly_optimizate requires the endpoint to be the maximal position. 
        lsh = [];
        record_array;
    end

    methods
        function obj = Reference(varargin)
            obj = obj@Base.Pref(varargin{:});
        end
        
        function tf = isnumeric(obj)
            if isempty(obj.reference)
                tf = false;
            else
                tf = obj.reference.isnumeric();
            end
        end
        
        function tosave = encodeValue(obj, ~) % Ignore the passed data value.
            if isempty(obj.reference)
                tosave = [];
            else
                tosave = obj.reference.encode();
            end
        end
        function [data, obj] = decodeValue(obj, saved)
            if isempty(saved)
                return
            end
            try
                obj.reference = Base.Pref.decode(saved);
                data = obj.reference.read();
            catch err
                % warning(err.identifier, '%s', err.message);
                pr = Base.PrefRegister.instance();
                obj.reference = pr.getPref(saved.pref, saved.parent.singleton_id);
                data = obj.reference.read();
            end
            
        end
        
        function obj = set_reference(obj, val)
            if ismember('Prefs.Inputs.LabelControlBasic', superclasses(val.ui)) && ~isa(val, 'Prefs.Reference') && ~ismember('Prefs.Reference', superclasses(val)) && ~isequal(obj.parent, val.parent)
                obj.reference = val;
                obj.readonly = val.readonly;
                if isprop(val.parent, "steponly") && val.parent.steponly
                    obj.steponly = true;
                end
                obj.parent.set_meta_pref(obj.property_name, obj);
                notify(obj.parent, 'update_settings');
            end
        end
        function obj = set_reference_Callback(obj, src, evt)
            pr = Base.PrefRegister.instance;
            pr.getMenu([], @obj.set_reference);
        end


        function [avg, st] = get_avg_val(obj, average_time, max_std_ratio)
            target = obj.parent.get_meta_pref('Target');
            if ~exist('average_time', 'var')
                average_time = 5;
            end
            if ~exist('max_std_ratio', 'var')
                max_std_ratio = 0.2;
            end
            test_vals = zeros(1, average_time);
            for k = 1:average_time
                pause(0.1)
                test_vals(k) = target.read;
            end
            avg = mean(test_vals);
            st = std(test_vals);
            if abs(st/avg) > max_std_ratio
                % The standart deviation is too large. Retake the measurement.
                average_time = average_time*2;
                test_vals = zeros(1, average_time);
                for k = 1:average_time
                    test_vals(k) = target.read;
                    pause(0.1)
                end
                avg = mean(test_vals);
                st = std(test_vals);
            end
        end

        
        function obj = link_callback(obj,callback)
            % This wraps ui.link_callback; careful overloading
            if ~isempty(obj.reference)
                obj.ui.link_callback({callback, obj.reference});
            end
        end
        
        function [obj,height_px,label_width_px] = make_UI(obj,varargin)
            % This wraps ui.make_UI; careful overloading
            [obj.ui, height_px, label_width_px] = obj.ui.make_UI(obj,varargin{:}, obj.readonly);
            obj.reference = obj.ui.gear.UserData;
        end
        
        % Calls to get and set value are now redirected to the pref that is being referenced.
        function val = get_value(obj, ~)
            if isempty(obj.reference)
                val = NaN;
            else
                val = obj.reference.read();
            end
        end
        function [obj, val] = set_value(obj, val)
            if ~isempty(obj.reference)
                obj.reference.writ(val);
            end
        end
        
        function val = get_ui_value(obj)
            val = obj.ui.get_value();
        end
        function obj = set_ui_value(obj,val)
            if ~isempty(obj.reference)
                obj.ui.set_value(val);
            end
            
        end
        
        function val = read(obj)
            if isempty(obj.reference)
                val = NaN;
            else
                val = obj.reference.read();
            end
        end
        function tf = writ(obj, val)

            if isempty(obj.reference)
                tf = false;
            else
                tf = obj.reference.writ(val);
            end
            if isprop(obj.parent, 'parent') && ~isempty(obj.parent.parent)
                msm = obj.parent.parent; % Handle to the MetaStageManager
                notify(msm, 'updated');
            end
        end
        obj = optimize_Callback(obj, src, evt);
        obj = global_optimize_Callback(obj, src, evt);
        obj = steponly_optimize_Callback(obj, src, evt);
        fig = plot_records(obj, dim, axis_available, axis_name);
    end
end
