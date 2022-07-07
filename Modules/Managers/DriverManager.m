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

