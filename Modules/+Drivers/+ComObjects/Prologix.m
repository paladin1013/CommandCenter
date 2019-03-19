classdef Prologix < Drivers.ComObjects.ComDevice & Modules.Driver
    
    % Matlab Object Class implementing control for Prologix GPIB
    % to USB devices.
    %
    % Communication can be established by first downloading and installing the correct drivers
    % Software can be downloaded from http://prologix.biz/resources.html and
    % selecting the Prologix GPIB Configurator program.
    
    % ComPortNum can be determined through Windows Device Manager which has
    % a list of available ComPorts shown.
    % 
    % GPIBnum can be determined from your devices. Check its setting to determine the address. 
    %
    % Primary purpose of this is to control the talk to various devices.
    % When a device's drivers are instantiation, they should call the
    % helper function Connect_Device. Connect_Device will ask the user to
    % select which communication driver he would like. 
    
    properties
       Timeout = 2;      % TimeoutTime
       InputBufferSize = 2^16;
       OutputBufferSize = 2^16;  
       BaudRate = 9600;
       Terminator = 'LF';
       Parity = 'none'
       DataBits = 8;
       StopBits = 1;
    end
    
    properties(SetAccess=private)
        ComHandle  % handle 
        comPortNum    % communication (COM) port number
        GPIBnum       % GPIB Channel
    end
    
     properties(Constant)
        InputArg={'comPortNum','GPIBnum'}
     end
    
    methods(Static)
      
         function obj = instance(comPortNum,GPIBnum)
            comPortNum = upper(comPortNum);
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.ComObjects.Prologix.empty(1,0);
            end
            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal({comPortNum,GPIBnum},Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj =Drivers.ComObjects.Prologix(comPortNum,GPIBnum);
            obj.singleton_id = {comPortNum,GPIBnum};
            Objects(end+1) = obj;
        end 
       
    end

    
    methods(Access=private)

        function [obj] = Prologix(comPortNum,GPIBnum)
            obj.comPortNum = comPortNum;
            obj.GPIBnum = GPIBnum; 
            
            obj.ComHandle = serial(['COM',obj.comPortNum]);
            
            obj.set_ComPort_properties;
            fclose(obj.ComHandle);
            try
                fopen( obj.ComHandle);
            catch
                instruments=instrfind;
                for index=1:length(instruments)
                    if strcmp(instruments(index).name,obj.ComHandle.name)
                        if  strcmp(instruments(index).status,'closed')
                            delete(instruments(index))
                        elseif  strcmp(instruments(index).status,'open')
                            obj.ComHandle=instruments(index);
                        end
                    end
                end
                
            end
        end
        
         function set_ComPort_properties(obj)
            %must set these properties before opening!
            set(obj.ComHandle,'Terminator',obj.Terminator);
            set(obj.ComHandle,'Timeout',obj.Timeout);
            set(obj.ComHandle,'BaudRate',obj.BaudRate);
            set(obj.ComHandle,'Parity',obj.Parity);
            set(obj.ComHandle,'DataBits',obj.DataBits);
            set(obj.ComHandle,'StopBits',obj.StopBits);
            set(obj.ComHandle,'InputBufferSize',obj.InputBufferSize);
            set(obj.ComHandle,'OutputBufferSize',obj.OutputBufferSize);
         end
        
        function read_setting(obj)
            fprintf(obj.ComHandle,'++auto 1');
        end
        
        function write_setting(obj)
            fprintf(obj.ComHandle,'++auto 0');
        end

        function add_setting(obj)
            msg = sprintf(['++addr ',obj.GPIBnum]);
            fprintf(obj.ComHandle,msg);
        end            
    end
    
    methods
        
        function delete(obj)
            fclose(obj.ComHandle);
            delete(obj.ComHandle);
        end
        
        function reset(obj)
            obj.Timeout = 2;      % TimeoutTime
            obj.InputBufferSize = 2^16;
            obj.OutputBufferSize = 2^16;
            obj.BaudRate = 9600;
            obj.Terminator = 'LF';
            obj.Parity = 'none';
            obj.DataBits = 8;
            obj.StopBits = 1;
        end
        
        function writeOnly(obj,string)
            fclose(obj.ComHandle);
            obj.set_ComPort_properties;
            fopen(obj.ComHandle);
            obj.write_setting();
            obj.add_setting();
            fprintf(obj.ComHandle,string);
            fclose(obj.ComHandle);%close after writing.
        end
        
        function [output] = writeRead(obj,string)
            fclose(obj.ComHandle);%close after writing.
            obj.set_ComPort_properties;
            fopen(obj.ComHandle);
            obj.read_setting();
            obj.add_setting();
            fprintf(obj.ComHandle,string);
            output = fscanf(obj.ComHandle);
            fclose(obj.ComHandle);%close after writing.
        end

    end
end