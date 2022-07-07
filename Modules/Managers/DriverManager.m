classdef DriverManager < Base.Manager
    
    properties(SetAccess=private)
    end
    
    methods
        function obj = DriverManager(handles)
            obj = obj@Base.Manager(Modules.Driver.modules_package,handles,handles.panelDrivers);
            obj.blockOnLoad = handles.menu_drivers;
            set(handles.experiment_run,'callback',@obj.run)
        end
        

    end
    methods(Access=protected)
        function active_module_changed(obj,varargin)
            if ~isempty(obj.active_module)
                addlistener(obj.active_module,'save_request',@obj.forceSave);
            end
        end
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
                    if Nargin == 0
                        modules_temp{end+1} = eval(sprintf('%s.instance',class_str{i})); %#ok<AGROW>
                    else
                        prompt = {};
                        for k = 1:Nargin
                        prompt{k} = sprintf("Arg%d", k);
                        end
                        result = inputdlg(prompt, 'Driver initialization arguments', Nargin);
                        argstrcell = join(result, ',');
                        modules_temp{end+1} = eval(sprintf('%s.instance(%s)',class_str{i},argstrcell{1} )); %#ok<AGROW>
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
                        munlock([class_str{i} '.instance'])
                    end
                    errors{end+1} = sprintf('Error loading %s:\n%s',class_str{i},err.message); %#ok<AGROW>
                    msg = sprintf('Following error caught in <a href="matlab: opentoline(''%s'',%i)">%s (line %i)</a>:\n%s',err.stack(1).file,err.stack(1).line,err.stack(1).name,err.stack(1).line,err.message);
                    obj.log(msg,Base.Logger.ERROR) % This part of the log keeps the traceback
                end
            end
            if ~isempty(errors)
                errors = strjoin(errors,'\n\n');
                obj.error(errors)  % TODO: somehow keep track of traceback for these errors
            end
            set(obj.blockOnLoad,'enable','on')
        end
    end
    methods(Static)
        function [textH,h] = abortBox(name,abort_callback)
            h = msgbox('Experiment Started',sprintf('%s running',name),'help','modal');
            h.KeyPressFcn='';  % Prevent esc from closing window
            h.CloseRequestFcn = abort_callback;
            % Repurpose the OKButton
            button = findall(h,'tag','OKButton');
            set(button,'tag','AbortButton','string','Abort',...
                'callback',abort_callback)
            textH = findall(h,'tag','MessageBox');
            addlistener(textH,'String','PostSet',@Base.Manager.resizeMsgBox);
        end
    end
end

