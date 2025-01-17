classdef Piezo < Modules.Imaging
    %CONFOCAL Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        maxROI = [0 10; 0 10];
        dwell = 1;                              % Per pixel in ms (will only update between frames)
        prefs = {'dwell','resolution','ROI'};
        data_name = 'Confocal';                 % For diamondbase (via ImagingManager)
        data_type = 'General';                  % For diamondbase (via ImagingManager)
        zigzag                                  % Mode of scan
    end
    properties(SetObservable)
        resolution = [120 120];                 % Pixels
        ROI = [0 10;0 10];                      % voltage
        continuous = false;
    end
    properties(SetAccess=immutable)
        galvos              % Handle to galvo controller
        counter             % Handle to counter driver
        ni
    end
    properties(Access=private)
        listeners
    end
    properties(SetObservable,SetAccess=private)
        mirror_up = false;
    end
    
    methods(Access=private)
        function obj = Piezo()
            obj.uses_stage = 'Stages.Piezo';
            obj.loadPrefs;
            obj.galvos = Drivers.NIDAQ.stage.instance('X','Y','Z','APD1','ScanSync');
            obj.zigzag = false;
            obj.counter = Drivers.Counter.instance('APD1','CounterSync');
            obj.ni = Drivers.NIDAQ.dev.instance('Dev1');
            try
                line = obj.ni.getLines('WidefieldMirror','out');
            catch err
                obj.ni.view;
                rethrow(err)
            end
            obj.mirror_up = logical(line.state);
            obj.listeners = addlistener(line,'state','PostSet',@obj.mirrorUpdate);
        end
    end
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Imaging.Confocal.Piezo();
            end
            obj = Object;
        end
    end
    methods
        function set.zigzag(obj,val)
            obj.galvos.zigzag = val;
        end
        function val = get.zigzag(obj)
            val = obj.galvos.zigzag;
        end
        function set.ROI(obj,val)
            % Update ROI without going outside maxROI
            val(1,1) = max(obj.maxROI(1,1),val(1,1)); %#ok<*MCSUP>
            val(1,2) = min(obj.maxROI(1,2),val(1,2));
            val(2,1) = max(obj.maxROI(2,1),val(2,1));
            val(2,2) = min(obj.maxROI(2,2),val(2,2));
            % Now make sure no cross over
            val(1,2) = max(val(1,1),val(1,2));
            val(2,2) = max(val(2,1),val(2,2));
            obj.ROI = val;
        end
        function focus(obj,ax,stageHandle)
        end
        function snap(obj,im,continuous)
            if nargin < 3
                continuous = false;
            end
            xres = obj.resolution(1);
            yres = obj.resolution(2);
            x = linspace(obj.ROI(1,1),obj.ROI(1,2),xres);
            y = linspace(obj.ROI(2,1),obj.ROI(2,2),yres);
            obj.galvos.SetupScan(x,y,obj.dwell)
            if ~continuous
                % If this is the same name as the modal figure already, it will replace it.
                h = msgbox('To stop scan, press abort.','ImagingManager','help','modal');
                h.KeyPressFcn='';  % Prevent esc from closing window
                h.CloseRequestFcn = @(~,~)obj.galvos.AbortScan;
                % Repurpose the OKButton
                button = findall(h,'tag','OKButton');
                % This silently aborts. Autosave will execute. Callback to
                % function that also throws error to avoid saving.
                set(button,'tag','AbortButton','string','Abort',...
                    'callback',@(~,~)obj.galvos.AbortScan)
                drawnow;
            end
            obj.galvos.StartScan;
            obj.galvos.StreamToImage(im)
            if ~continuous
                delete(h);
            end
        end
        function startVideo(obj,im)
            obj.continuous = true;
            while obj.continuous
                obj.snap(im,true)
            end
        end
        function stopVideo(obj)
            if strcmp(obj.galvos.taskPulseTrain.status,'Started')
                obj.galvos.AbortScan;
            end
            obj.continuous = false;
        end
        
        % Settings and Callbacks
        function  settings(obj,panelH,~,~)
            spacing = 1.5;
            num_lines = 4;
            line = 1;
            uicontrol(panelH,'style','text','string','Dwell (ms):','horizontalalignment','right',...
                'units','characters','position',[0 spacing*(num_lines-line) 18 1.25]);
            uicontrol(panelH,'style','edit','string',num2str(obj.dwell),...
                'units','characters','callback',@obj.dwellCallback,...
                'horizontalalignment','left','position',[19 spacing*(num_lines-line) 10 1.5]);
            line = 2;
            uicontrol(panelH,'style','text','string','X points (pixels):','horizontalalignment','right',...
                'units','characters','position',[0 spacing*(num_lines-line) 18 1.25]);
            uicontrol(panelH,'style','edit','string',num2str(obj.resolution(1)),'tag','x',...
                'units','characters','callback',@obj.resolutionCallback,...
                'horizontalalignment','left','position',[19 spacing*(num_lines-line) 10 1.5]);
            uicontrol(panelH,'style','pushbutton','string','Counter',...
                'units','characters','position',[32 spacing*(num_lines-line) 10 3],...
                'callback',@obj.StartCounterCallback)
            line = 3;
            uicontrol(panelH,'style','text','string','Y points (pixels):','horizontalalignment','right',...
                'units','characters','position',[0 spacing*(num_lines-line) 18 1.25]);
            uicontrol(panelH,'style','edit','string',num2str(obj.resolution(2)),'tag','y',...
                'units','characters','callback',@obj.resolutionCallback,...
                'horizontalalignment','left','position',[19 spacing*(num_lines-line) 10 1.5]);
            line = 4;
            uicontrol(panelH,'style','checkbox','string','ZigZag','horizontalalignment','right',...
                'units','characters','position',[2 spacing*(num_lines-line) 18 1.25],...
                'value',obj.zigzag,'callback',@obj.ZigZagCallback);
           
        end
        function ZigZagCallback(obj,hObj,~)
            obj.zigzag = get(hObj,'Value');
        end
        function dwellCallback(obj,hObj,varargin)
            val = str2double((get(hObj,'string')));
            obj.dwell = val;
        end
        function resolutionCallback(obj,hObj,~)
            val = str2double((get(hObj,'string')));
            if strcmp(get(hObj,'tag'),'x')
                pos = 1;
            else
                pos = 2;
            end
            obj.resolution(pos) = val;
        end
        function StartCounterCallback(obj,varargin)
            if ~isvalid(obj.counter)
                obj.counter = Drivers.Counter.instance('APD1','CounterSync');
            end
            obj.counter.start;
        end
        function mirrorUp(obj)
            obj.ni.WriteDOLines('WidefieldMirror',0)
            obj.ni.WriteDOLines('WidefieldMirror',1)
        end
        function mirrorDown(obj)
            obj.ni.WriteDOLines('WidefieldMirror',1)
            obj.ni.WriteDOLines('WidefieldMirror',0)
        end
        function mirrorUpdate(obj,varargin)
            line = obj.ni.getLines('WidefieldMirror','out');
            obj.mirror_up = logical(line.state);
            if obj.mirror_up
                obj.mirrorUp;
            else
                obj.mirrorDown;
            end
        end
    end
end

