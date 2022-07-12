classdef MetaStage < Base.Module
    %METASTAGE Wrapper for three Prefs.References
    
    properties(GetObservable, SetObservable)
        X = Prefs.Reference();
        Y = Prefs.Reference();
        Z = Prefs.Reference();
        Target = Prefs.Reference();
        
        key_step_x = Prefs.Double(0.001);
        key_step_y = Prefs.Double(0.001);
        key_step_z = Prefs.Double(1);
        joy_step_x = Prefs.Double(0.001);
        joy_step_y = Prefs.Double(0.001);
        joy_step_z = Prefs.Double(0.1);
        sweep_num = Prefs.Integer(0, 'min', 0, 'max', 10, 'help', 'Do parameter sweep before hill-climbing optimization to avoid being trapped into local maximum.');
        sample_num = Prefs.Integer(5, 'min', 1, 'max', 100, 'help', 'Number of samples to average in each optimization step.')
        sample_interval = Prefs.Double(0.1, 'min', 0, 'max', 10, 'help', 'Time delay between two samples.')
        plot_record = Prefs.Boolean(false, 'help', 'Whether to plot the intermediate results during the optimization.')
        min_step_ratio = Prefs.Double(0.1, 'min', 0.01, 'max', 1, 'help', 'The minimum step (resolution) of the optimiaztion')
    end
    properties(SetAccess=immutable)
        name;
        parent;
    end
    properties(Constant,Hidden)
        modules_package = 'MetaStage';
    end
    
    properties(SetObservable, AbortSet)
        show_prefs = {'X', 'Y', 'Z', 'Target'};
        prefs = {'X', 'Y', 'Z', 'Target', 'key_step_x', 'key_step_y', 'key_step_z', 'joy_step_x', 'joy_step_y', 'joy_step_z', 'sweep_num', 'smaple_num', 'sample_interval', 'min_step_ratio'};
    end
    methods(Static)
        function obj = instance(name, manager)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Modules.MetaStage.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(name,Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Modules.MetaStage(name, manager);
            obj.singleton_id = name;
            Objects(end+1) = obj;

        end
    end
    methods(Access=private)
        function obj = MetaStage(name, manager)
            obj.name = name;
            if ~isempty(manager)
                obj.parent = manager;
            end
            % obj.loadPrefs;
            % obj.namespace = sprintf("MetaStage.%s", name);
        end
    end
end