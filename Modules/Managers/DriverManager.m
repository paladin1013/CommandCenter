classdef DriverManager < Base.Manager
    
    properties(SetAccess=private)
        module_args = {}; % Cell array of structs: {struct('name':..., 'argstr':...), ...}
        % To save and restore driver modules
    end
    
    methods
        function obj = DriverManager(handles)
            obj = obj@Base.Manager(Modules.Driver.modules_package,handles,handles.panelDrivers, handles.drivers_select);
            obj.blockOnLoad = handles.menu_drivers;
            obj.loadPrefs;
        end
    end

    methods
        function mSavePrefs(obj) % Manually save preferences for debugging
            obj.savePrefs;
        end
        function mLoadPrefs(obj) % Manually load preferences for debugging
            obj.loadPrefs;
        end
        function add_module_args(obj, module_args)
            % If module_args already exist, there is no need to add once
            % again.
            for l = 1:length(obj.module_args)
                if strcmp(module_args.name, obj.module_args{l}.name)
                    obj.module_args{l}.argstr = module_args.argstr;
                    return;
                end
            end
            obj.module_args{end+1} = module_args;
        end
        function remove_module_args(obj, module_name)
            for l = 1:length(obj.module_args)
                if strcmp(module_name, obj.module_args{l}.name)
                    obj.module_args(l) = [];
                    % return;
                end
            end
        end
                    
        function moduleBeingDestroyed(obj,hObject,varargin)
            obj.log('Destroying <a href="matlab: opentoline(''%s'',1)">%s</a>',which(class(hObject)),class(hObject))
            mask = obj.check_module_str(class(hObject));
            obj.remove_module_args(class(hObject));
            if strcmp(class(hObject), "Drivers.Counter")
                hObject.closeReq;
            end
            obj.modules(mask) = [];
        end
    end
    % methods(Static)
    %     function getAvailModules(package, parent_menu, fun_callback, fun_in_use)
    %         path = fileparts(fileparts(mfilename('fullpath'))); % Root CommandCenter/
    %         [prefix, module_strs, packages] = Base.GetClasses(path, 'Modules', package);  % Returns name without package name
            
    %         % Alphabetic order
    %         packages = sortrows(packages');
    %         module_strs = sortrows(module_strs');
            
    %         remove = findall(parent_menu, 'tag', 'module');
    %         for i = 1:length(remove)
    %             if remove ~= parent_menu
    %                 delete(remove(i));
    %             end
    %         end
            
    %         previousStuff = allchild(parent_menu); % Push these down to bottom
    %         if isempty(module_strs)
    %             uimenu(parent_menu, 'label', 'No Modules found', 'enable', 'off', 'tag', 'module');
    %         end
            
    %         for i = 1:numel(packages)
    %             package = fullfile(['+' strrep(prefix(1:end-1),'.','/+')], ['+' packages{i}]);
    %             h = uimenu(parent_menu, 'label', packages{i}, 'tag', 'module');
    %             Base.Manager.getAvailModules(package, h, fun_callback, fun_in_use); % Recursively call to populate
    %         end
            
    %         for i = 1:numel(module_strs)
    %             try
    %                 module_str = module_strs{i};
    %                 module_fullstr = [prefix module_str];
    %                 checked = 'off';
    %                 nargin([module_fullstr '.instance']);
    %                 if fun_in_use([prefix module_str])
    %                     checked = 'on';
    %                     if strcmp(parent_menu.Tag,'module') && ~startswith(parent_menu.Label,'<html>')
    %                         % Make bold
    %                         parent_menu.Label = sprintf('<html><font style="font-weight:bold">%s</font></html>',...
    %                             parent_menu.Label);
    %                     end
    %                 end
    %                 h = uimenu(parent_menu, 'label', module_str, 'checked', checked,...
    %                     'callback', fun_callback, 'tag', 'module');
    %                 h.UserData = module_fullstr;
    %             catch err
    %                 warning("%s is not a Module with .instance method!\n", module_str);
    %             end
    %         end
            
    %         for i = 1:length(previousStuff)
    %             previousStuff(i).Position = h.Position + i - 1;
    %         end
    %     end
    % end
    methods(Access=protected)

        
        function modules_temp = load_module_str(obj,class_str)
            set(obj.blockOnLoad,'enable','off')
            drawnow expose;
            errors = {};
            if ~isa(class_str,'cell')
                class_str = {class_str};
            end
            modules_temp = {};
            for i = 1:numel(class_str)
                nloaded_before = numel(getappdata(obj.handles.figure1,'ALLmodules'));
                try
                    super = superclasses(class_str{i});
                    singular_type = obj.type;
                    if obj.type(end)=='s'  % Because of how folder packages were labeled
                        singular_type = obj.type(1:end-1);
                    end
                    assert(ismember(sprintf('Modules.%s',singular_type),super),'Superclass of %s must be Modules.%s',class_str{i},singular_type)
                    Nargin = nargin(sprintf('%s.instance',class_str{i}));
                    if Nargin == -1
                        try
                            [arg_names, default_vals] = eval(sprintf('%s.get_default_args',class_str{i}));
                            Nargin = numel(arg_names);
                            result = inputdlg(arg_names, 'Driver initialization arguments', Nargin, default_vals);
                        catch err
                            fprintf("Nargin is -1 and get_default_args is not implemented in %s", class_str{i});
                            rethrow(err)
                        end
                        argstrcell = join(result, ',');
                        modules_temp{end+1} = eval(sprintf('%s.instance(%s)',class_str{i},argstrcell{1} )); %#ok<AGROW>
                        module_struct = struct();
                        module_struct.name = class_str{i};
                        module_struct.argstr = argstrcell{1};
                        obj.module_args{end+1} = module_struct;
                    elseif Nargin == 0
                        modules_temp{end+1} = eval(sprintf('%s.instance',class_str{i})); %#ok<AGROW>
                        module_struct = struct();
                        module_struct.name = class_str{i};
                        obj.module_args{end+1} = module_struct;
                    else
                        try
                            [arg_names, default_vals] = eval(sprintf('%s.get_default_args',class_str{i}));
                            assert(length(arg_names) == Nargin, "Number of default args (%d) is inconsistent with Nargin (%d).");
                            result = inputdlg(arg_names, 'Driver initialization arguments', Nargin, default_vals);

                        catch
                            warning("`get_default_args` method is not implemented in %s", class_str{i});
                            prompt = {};
                            for k = 1:Nargin
                                prompt{k} = sprintf("Arg%d:",k);
                            end
                            result = inputdlg(prompt, 'Driver initialization arguments', Nargin);
                        end
                        argstrcell = join(result, ',');
                        modules_temp{end+1} = eval(sprintf('%s.instance(%s)',class_str{i},argstrcell{1} )); %#ok<AGROW>
                        module_struct = struct();
                        module_struct.name = class_str{i};
                        module_struct.argstr = argstrcell{1};
                        obj.module_args{end+1} = module_struct;
                    end
                    addlistener(modules_temp{end},'ObjectBeingDestroyed',@obj.moduleBeingDestroyed);
                    obj.log('Initialized <a href="matlab: opentoline(''%s'',1)">%s</a>',which(class_str{i}),class_str{i})
                catch err
                    % IMPORTANT - remove from tracked modules (added in
                    % Base.Module constructor before error in subclass)
                    loaded_modules = getappdata(obj.handles.figure1,'ALLmodules');
                    % All new modules must be from attempted load and at
                    % the end (keep in mind, if module cleans up on its
                    % own, this list can change by more than 1 on each
                    % loop!
                    while numel(loaded_modules) > nloaded_before
                        delete(loaded_modules{end});
                        loaded_modules = getappdata(obj.handles.figure1,'ALLmodules');
                    end
                    if mislocked(class_str{i})
                        % Lock is the first thing called in
                        % module.instance, so even if an error before gets 
                        % added to loaded_modules, will still be locked.
                        munlock(class_str{i});
                    elseif mislocked([class_str{i} '.instance'])
                        munlock([class_str{i} '.instance']);
                    end
                    errors{end+1} = sprintf('Error loading %s:\n%s',class_str{i},err.message); %#ok<AGROW>
                    msg = sprintf('Following error caught in <a href="matlab: opentoline(''%s'',%i)">%s (line %i)</a>:\n%s',err.stack(1).file,err.stack(1).line,err.stack(1).name,err.stack(1).line,err.message);
                    obj.log(msg,Base.Logger.ERROR); % This part of the log keeps the traceback
                end
            end
            if ~isempty(errors)
                errors = strjoin(errors,'\n\n');
                obj.error(errors)  % TODO: somehow keep track of traceback for these errors
            end
            set(obj.blockOnLoad,'enable','on');
        end


        function modules_temp = load_module_str_with_args(obj,class_struct)
            set(obj.blockOnLoad,'enable','off')
            drawnow expose;
            errors = {};
            if ~isa(class_struct,'cell')
                class_struct = {class_struct};
            end
            modules_temp = {};
            for i = 1:numel(class_struct)
                nloaded_before = numel(getappdata(obj.handles.figure1,'ALLmodules'));
                try
                    super = superclasses(class_struct{i}.name);
                    singular_type = obj.type;
                    if obj.type(end)=='s'  % Because of how folder packages were labeled
                        singular_type = obj.type(1:end-1);
                    end
                    assert(ismember(sprintf('Modules.%s',singular_type),super),'Superclass of %s must be Modules.%s',class_struct{i}.name,singular_type)
                    if ~isfield(class_struct{i}, "argstr") || class_struct{i}.argstr == ""
                        modules_temp{end+1} = eval(sprintf('%s.instance',class_struct{i}.name)); %#ok<AGROW>
                    else
                        modules_temp{end+1} = eval(sprintf('%s.instance(%s)',class_struct{i}.name,class_struct{i}.argstr )); %#ok<AGROW>
                    end
                    obj.module_args{end+1} = class_struct{i};
                    addlistener(modules_temp{end},'ObjectBeingDestroyed',@obj.moduleBeingDestroyed);
                    obj.log('Initialized <a href="matlab: opentoline(''%s'',1)">%s</a>',which(class_struct{i}.name),class_struct{i}.name)
                catch err
                    % IMPORTANT - remove from tracked modules (added in
                    % Base.Module constructor before error in subclass)
                    loaded_modules = getappdata(obj.handles.figure1,'ALLmodules');
                    % All new modules must be from attempted load and at
                    % the end (keep in mind, if module cleans up on its
                    % own, this list can change by more than 1 on each
                    % loop!
                    while numel(loaded_modules) > nloaded_before
                        delete(loaded_modules{end});
                        loaded_modules = getappdata(obj.handles.figure1,'ALLmodules');
                    end
                    if mislocked(class_struct{i}.name)
                        % Lock is the first thing called in
                        % module.instance, so even if an error before gets 
                        % added to loaded_modules, will still be locked.
                        munlock(class_struct{i}.name);
                    elseif mislocked([class_struct{i}.name '.instance'])
                        munlock([class_struct{i}.name '.instance']);
                    end
                    errors{end+1} = sprintf('Error loading %s:\n%s',class_struct{i}.name,err.message); %#ok<AGROW>
                    msg = sprintf('Following error caught in <a href="matlab: opentoline(''%s'',%i)">%s (line %i)</a>:\n%s',err.stack(1).file,err.stack(1).line,err.stack(1).name,err.stack(1).line,err.message);
                    obj.log(msg,Base.Logger.ERROR); % This part of the log keeps the traceback
                end
            end
            if ~isempty(errors)
                errors = strjoin(errors,'\n\n');
                obj.error(errors)  % TODO: somehow keep track of traceback for these errors
            end
            set(obj.blockOnLoad,'enable','on');
        end

        function savePrefs(obj)
            for i = 1:numel(obj.prefs)
                try
                    setpref(obj.namespace,obj.prefs{i},obj.(obj.prefs{i}));
                catch err
                    warning('MANAGER:save_prefs','%s',err.message)
                end
            end
            % Save loaded modules as strings
            setpref(obj.namespace,'loaded_modules',obj.module_args)
        end
        function loadPrefs(obj)
            % Load modules
            if ispref(obj.namespace,'loaded_modules')
                module_args_bak = getpref(obj.namespace,'loaded_modules');
                obj.modules = obj.load_module_str_with_args(module_args_bak);
            else
                obj.modules = {};
            end
            % Load prefs
            for i = 1:numel(obj.prefs)
                if ispref(obj.namespace,obj.prefs{i})
                    pref = getpref(obj.namespace,obj.prefs{i});
                    try
                        obj.(obj.prefs{i}) = pref;
                    catch err
                        warning('MANAGER:load_prefs','Error on loadPrefs (%s): %s',obj.prefs{i},err.message)
                    end
                end
            end
        end
    end
end

