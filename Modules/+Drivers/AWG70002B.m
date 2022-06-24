%%
classdef AWG70002B < Modules.Driver
    %%% updated: 03.07.2022
    %%% Kevin C. Chen (inherited Ed Chen/Matt Trusheim's AWG code)
    %%% Main changes:
    %%% - TCP/IP VISA object for initialization
    %%% - Sequence --> Sequence List
    %%% - basic waveform Sinewave
    properties
        SerialPort
        %         inherited properties
        SocketHandle  % handle associated with Protocol class
        IPAddress  % Device IP Address for TCP/IP control
        TCPPort  % Port for TCP/IP control
        Timeout % TimeoutTime
        InputBufferSize
        OutputBufferSize
        SampleRate
        Amplitude     % Vpp; array of 4, 1 per channel output
        Offset        % V
        Frequency     % in Hz; array of 4, 1 per channel output
        MinFreq       %Hz
        MaxFreq       %Hz
        MinAmp        %dBm
        MaxAmp        %dBm
        MinSampleRate %Samples per second
        MaxSampleRate %Samples per second
        %%%NEW
        Protocol %tcp/ip OR GPIB
        RunMode
        CurrentSeqLength %length of the seq sequence
        CurrentSeq
        SubTbl
        WfmTbl
        PrepValid
        phaseOffset
        maxRepeats = 65536
        %%%end NEW
        %max_seq_length = 8000; % In sequence mode, seq has at most 8000 segments; currently not used
        MAX_number_of_reps = 2^16;  %max number of repetition loops per sequence segment
        %MIN_number_of_wfm_points = 1; % for hardware sequencer mode, a waveform must have at least 250 pts, vs 1 pt for software sequencer mode
        MarkerHighVoltage = 2.7; % Voltage when markers are high
        TotalChannels = 4;
        PulseFileDir = 'Z:\Experiments\AWG70002B\waveforms';
        %%NEW NEW
        HWChanNameToNumMap
        Resolution = 8
        
    end

    methods(Static)
        function obj = instance(Protocal, IPAddress)
            mlock;
            persistent Objects
            if isempty(Objects)
                Objects = Drivers.AWG70002B.empty(1,0);
            end
            [~,host_resolved] = resolvehost(IPAddress);

            for i = 1:length(Objects)
                if isvalid(Objects(i)) && isequal(host_resolved, Objects(i).singleton_id)
                    obj = Objects(i);
                    return
                end
            end
            obj = Drivers.AWG70002B(Protocal, IPAddress);
            obj.singleton_id = host_resolved;
            Objects(end+1) = obj;
        end
    end

    methods(Access=private)
           function [obj] = AWG70002B(varargin)
            %init the tables that hold the waveform names and subsequence
            %names
            obj.PrepValid = 'invalid';
            obj.CurrentSeqLength = 0;
            obj.CurrentSeq = {};
            obj.MinSampleRate = 10e6;
            obj.MaxSampleRate = 25e9;
            
            obj.MinAmp = -69.0776; % dBm (-10dBm = 0.020 Vpp, 50 ohm)
            obj.MaxAmp = 39.2445; % dBm (39.24dBm = 4.5 Vpp, 50 ohm)
            
            Protocol = varargin{1};
            switch Protocol
                case 'visa'
                    obj.Protocol = 'visa';
                    obj.IPAddress = varargin{2};
                    obj.init();
                    
                otherwise
                    error('Only protocol `tek VISA` is currently supported');
            end
            chNames =   {'ch1', 'ch1mkr1', 'ch1mkr2', 'ch2', 'ch2mkr1', 'ch2mkr2',...
                'ch3', 'ch3mkr1','ch3mkr2', 'ch4', 'ch4mkr1', 'ch4mkr2'};
            chNums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
            obj.HWChanNameToNumMap = containers.Map(chNames, chNums);
            
           end
        end

    methods
        % Inherited Methods
        function init(obj)
            try
                % VISA Protocol MATLAB
%                 obj.SocketHandle = visa('tek', ['TCPIP0::' obj.IPAddress '::INSTR']);
%                 set(obj.SocketHandle,'Timeout',obj.Timeout); %units? seconds?
%                 set(obj.SocketHandle,'InputBufferSize',obj.InputBufferSize); %units? bytes?
%                 set(obj.SocketHandle,'OutputBufferSize',obj.OutputBufferSize); %units? bytes?
                
                obj.SocketHandle=visadev("TCPIP0::"+ obj.IPAddress+"::INSTR");
                disp('TCP/IP Protocol Initialized for AWG70002B');
            catch exception
                % disp('Error to init TCP/IP Protocol for AWG70002B');
                assert(false, 'Error to init TCP/IP Protocol for AWG70002B');
            end
        end
        
        function open(obj)
            try
                fopen(obj.SocketHandle);
                disp('TCP/IP connection to AWG70002B opened.');
            catch exception
                disp('Error to open AWG70002B');
                disp(getReport(exception));
            end
        end
        
        function close(obj)
            try
                fclose(obj.SocketHandle);
                disp('TCP/IP connection to AWG70002B closed');
            catch exception
                disp('Error to close AWG70002B');
            end
        end
        
        function reset(obj)
            obj.writeToSocket('*RST');
            disp('AWG70002B reset');
        end
        
        function delete(obj)
            try
                delete(obj.SocketHandle);
            catch exception
                disp('error to delete AWG');
            end
        end
        
        function writeToSocket(obj,string)
            write(obj.SocketHandle,string,"string");
        end
        
        function [output] = writeReadToSocket(obj,string)
            output = writeread(obj.SocketHandle,string);
        end
        
         function AWGTell(obj,command)
            obj.writeToSocket(command);
        end
        
        %%%%% AWG settings %%%%%
        
        function AWGStart(obj)
            obj.writeToSocket('AWGC:RUN:IMM');
        end
        
        function AWGTrig(obj)
            obj.writeToSocket('*TRIG');
        end
        
        function AWGStop(obj)
            obj.writeToSocket('AWGC:STOP');
        end
        
        function set(obj)
            obj.reset();
            obj.setExtRefClock();
            obj.setSampleRate(1, obj.SampleRate);
            obj.setSampleRate(2, obj.SampleRate);
        end
        
        function setExtRefClock(obj)
            % External 10MHz reference clock from signal generator
            obj.writeToSocket(sprintf('SOUR:ROSC:SOUR EXT'));
        end
        
        function [err] = setSampleRate(obj,channel,  sampleRate_Hz)
            err = 0;
            if sampleRate_Hz < obj.MinSampleRate || sampleRate_Hz > obj.MaxSampleRate
                uiwait(warndlg({'AWG Sample Rate out of range. Aborted.'}));
                err = 1;
                return;
            end
            obj.writeToSocket(sprintf('SOUR%d:FREQ %fe9', channel, sampleRate_Hz/1e9));
        end
        
        % changes the run mode of the AWG valid inputs are 'S', 'G',
        % 'T', 'C', 'Continuous', 'Triggered', 'Gated', 'Sequence',
        % 'COnt', 'seq', 'Trig', 'gat'
        % case insensitive
        function setRunMode(obj, channel, runMode)
            obj.writeReadToSocket('SYST:ERR:ALL?');
            switch lower(runMode)
                case {'s','sequence', 'seq'}
                    obj.writeToSocket(sprintf('SOUR%d:RMOD SEQ', channel));
                case {'g', 'gated', 'gat'}
                    obj.writeToSocket(sprintf('SOUR%d:RMOD GAT', channel));
                case {'t', 'triggered', 'trig'}
                    obj.writeToSocket(sprintf('SOUR%d:RMOD TRIG', channel));
                case {'c', 'continuous', 'cont'}
                    obj.writeToSocket(sprintf('SOUR%d:RMOD CONT', channel));
                otherwise
                    error('RunMode can only be C, T, G, S')
            end
            obj.RunMode = runMode;
            
        end
        
        function setTriggerSource(obj, channel, triggerSource)
            switch lower(triggerSource)
                case {'a'}
                    obj.writeToSocket(sprintf('SOUR%d:TINP ATR', channel));
                case {'b'}
                    obj.writeToSocket(sprintf('SOUR%d:TINP BTR', channel));
                case {'i', 'internal'}
                    obj.writeToSocket(sprintf('SOUR%d:TINP ITR', channel));
                otherwise
                    error('triggerSource should only be A, B, I');
            end
        end

        %%%%% Channels %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function setChannelOn(obj,channel)
            obj.writeToSocket(sprintf('OUTP%d ON',uint32(channel)));
        end
        
        function setAllChannelsOn(obj)
            obj.writeToSocket('OUTP1 ON; OUTP2 ON; OUTP3 ON; OUTP4 ON');
        end
        
        function setChannelOff(obj,channel)
            obj.writeToSocket(sprintf('OUTP%d OFF',uint32(channel)));
        end
        
        function setAllChannelsOff(obj)
            obj.writeToSocket('OUTP1 OFF; OUTP2 OFF; OUTP3 OFF; OUTP4 OFF');
        end
        
        function setmarker(obj,channelnum,markernum,low,high)
            obj.writeToSocket(sprintf('SOUR%d:MARK%d:VOLT:LOW %d;HIGH %d',channelnum,markernum,low,high));
        end

        function setmarkerOffset(obj,channelnum,markernum,offset)
            obj.writeToSocket(sprintf('SOUR%d:MARK%d:VOLT:OFFS %d',channelnum,markernum,offset));
        end

        function setmarkerAmplitude(obj,channelnum,markernum,amplitude)
            obj.writeToSocket(sprintf('SOUR%d:MARK%d:VOLT:AMPL %d',channelnum,markernum,amplitude));
        end
        
        function setResolution(obj, channel, resolution)
            obj.writeToSocket(sprintf("SOUR%d:DAC:RES %d", channel, resolution));
            obj.writeReadToSocket("*OPC?");
            loadedResolution = obj.writeReadToSocket(sprintf('SOUR%d:DAC:RES?', channel));
            if resolution ~= str2num(loadedResolution)
                assert(sprintf("Set resolution failed! Should be %d instead of %d", resolution, loadedResolution))
            end
        end

        
        %%%%% Waveforms %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function create_SineWave(obj,frequency,amplitude,wave_name)
            % create sine wave using basic waveform plug-in
            obj.writeToSocket(sprintf('BWAV:FUNC "sine"'));
            obj.writeToSocket(sprintf('BWAV:FREQ "%s"',frequency));
            obj.writeToSocket(sprintf('BWAV:AMPL "%s"',amplitude));
            obj.writeToSocket(sprintf('BWAV:SRAT %f',obj.SampleRate));
            % saves sine waveform at each frequency 
            obj.writeToSocket(sprintf('BWAV:COMP:NAME "%s"',wave_name));
            % compile waveform
            obj.writeToSocket(sprintf('BWAV:COMP'));
        end
        
        function create_waveform(obj,name,shape,marker1,marker2)           
            %Delete the old wavefrom if it was there
            obj.writeToSocket(sprintf('WLISt:WAV:DEL "%s"',name));
            %Create the new waveform
            obj.writeToSocket('*WAI');

            % using format REAL
            obj.writeToSocket(sprintf('WLISt:WAV:NEW "%s", %d, REAL',name,length(shape)));

            for i = 1:3
                %Load the actual waveform
%                 binblockwrite(obj.SocketHandle,obj.shapeToAWGInt(shape,marker1,marker2),'uint32',sprintf('WLISt:WAVeform:DATA "%s", ',name));
%                 writebinblock(obj.SocketHandle,obj.shapeToAWGInt(shape,marker1,marker2),'uint16');
            write(obj.SocketHandle,dec2bin(obj.shapeToAWGInt(shape,marker1,marker2),10),'string');
                
                % need to send LF to finish bbw
%                 obj.writeToSocket('');
                obj.writeReadToSocket('*OPC?');
                seqLen = obj.writeReadToSocket(sprintf('WLISt:WAVeform:LENGth? "%s"',name));

                if str2num(seqLen) == length(shape)
                    break
                else
                    disp(['Fail ' num2str(i)]);
                end
            end
        end
    
        function [err] = setAmplitude(obj,channel, amplitude)
            err = 0;           

            % send the set amplitude command
            obj.writeToSocket(sprintf('SOUR%d:VOLT %f',channel,amplitude));
        end
        
        function [err] = loadWaveform(obj,channel, waveformName)
            % waveform name should not ends with .txt (only the file name is enough)
            if contains(waveformName, '.txt')
                expression = "(\w+)\.txt";
                tokens = regexp(waveformName, expression, "tokens");
                waveformName = tokens{1};
            end
            err = 0;           
            retryTimes = 0;
            while true
                
                obj.writeToSocket(sprintf('MMEM:OPEN:TXT "%s\\%s.txt",ANAL', obj.PulseFileDir, waveformName))
                obj.writeReadToSocket('*OPC?');
                if(channel == 1 || channel == 2)
                obj.writeToSocket(sprintf('SOUR%d:WAV "%s"',channel,waveformName));
                elseif (channel == 0)
                    obj.writeToSocket(sprintf('SOUR%d:WAV "%s"',1,waveformName));
                    obj.writeToSocket(sprintf('SOUR%d:WAV "%s"',2,waveformName));
                    obj.writeToSocket("RCC 1");
                else
                    assert(false, "Channel should be 0(for both channels) 1 or 2.");
                end
                obj.writeReadToSocket('*OPC?');
                pause(0.5);
                loadedName = char(obj.writeReadToSocket(sprintf("SOUR%d:WAV?", channel)));
                if ~isempty(loadedName(2:end-1)) && strcmp(waveformName, loadedName(2:end-1))
                    break
                end
                pause(0.5);
                retryTimes = retryTimes + 1;
                if retryTimes > 5
                    err = 1;
                    assert(false, 'AWG waveform is not successfully loaded.\n Should be %s, but got %s instead. Aborted', waveformName, loadedName(2:end-1));
                    % uiwait(warndlg({sprintf('AWG waveform is not successfully loaded.\n Should be %s, but got %s instead. Aborted', waveformName, loadedName(2:end-1))}));
                    % return;
                end
            end
        end

        function [err] = setOffset(obj,channel)
            err = 0;
            if obj.Offset(channel) < -2.25 || obj.Offset(channel) > 2.25
                uiwait(warndlg({'AWG Offset out of range. Aborted.'}));
                err = 1;
                return;
            end
            obj.writeToSocket(sprintf('SOUR%d:VOLT:OFFS %f',channel,obj.Offset(channel)));
        end

        
        %%%%% Sequences %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        function initSequence(obj,SeqName,length)
            obj.writeToSocket(sprintf('SLIS:SEQ:NEW "%s", %d',SeqName,length));
        end
        
        function addWaveformToSequence(obj,segnum, channel, SeqName, WaveName)
            obj.writeToSocket(sprintf('SLIS:SEQ:STEP%d:TASS%d:WAV "%s","%s"',segnum,channel,SeqName,WaveName));
        end
        
%         function addWaveformToSubSequence(obj,segnum, channel, WaveName)
%             obj.writeToSocket(sprintf('SLIST:SUBS:ELEM%d:WAVE%d "%s"',segnum,channel,WaveName));
%         end
     
%         function addLoopToSubSequence(obj,segnum,number)
%             if number == 0
%                 obj.writeToSocket(sprintf('SEQ:ELEM%d:LOOP:INF 1',segnum));
%             else
%                 obj.writeToSocket(sprintf('SLIST:SUBS:ELEM%d:LOOP:COUN %d',segnum,number));
%             end
%         end
        
%         function initSubSequence(obj,name, length)
%             obj.writeToSocket(sprintf('SLIST:SUBS:NEW %s,%d',name,length));
%         end
%         
        function addLoopToSequenceStep(obj,SeqName,segnum,loop_number)
            if loop_number == 0
                obj.writeToSocket(sprintf('SLIS:SEQ:STEP%d:RCO "%s", INF',segnum,SeqName));
            else
                obj.writeToSocket(sprintf('SLIS:SEQ:STEP%d:RCO "%s", %d',segnum,SeqName,loop_number));
            end
        end
        


        function binData = shapeToAWGInt(obj,shape,marker1,marker2)
            %Check pulse-in to make sure it is between -1 and 1
            if(max(abs(shape)) > 1)
                errordlg('Pulse is outside the range [-1, 1].');
                binData = 0;
                return;
            end

            % Convert decimal shape on [-1,1] to binary on [0,2^10 (1023)]
            binData =  127.5*shape + 127.5;
            
            % attempt to engineer uint10
            binDatatemp=double(binData');
            tVec=cell2mat(repelem({'00'},numel(binData))');
            foo=[tVec,dec2bin(binDatatemp)];
            binData =bin2dec(foo(:,:))';

            % set markers - bits 9 and 10 of each point
            % see PDF page 280 ("[SOURce[n]:]DAC:RESolution")
            binData = bitset(binData,9,marker1);
            binData = bitset(binData,10,marker2);
%             binData = binData*64;
%             dec2bin(binData)

            % TEK AWG5014B requires the binary block data in little endian
            % (LSB first) byte ordering, but binblockwrite seems to ignore
            % the byte ordering so manually swap it
            % ed had to comment this out for AWG5014B (2013-07-21)
%             if strcmp(obj.Protocol, 'tcpip')
%                 binData = swapbytes(binData);
%             end
        end
    end
end