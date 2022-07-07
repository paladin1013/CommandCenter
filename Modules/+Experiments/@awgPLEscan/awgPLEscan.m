classdef awgPLEscan < Modules.Experiment
    %UltraFastScan
    
    properties
        prefs = {'averages','samples','pb_IP','awg_IP','NIDAQ_dev', 'repumpLaser','resLaser', 'APDline','freq_start', 'freq_end', 'points','repump_type'};
    end
    properties(SetObservable,GetObservable)
        averages =  Prefs.Integer(1,'min',1, ...
                        'help_text','Number of times to perform entire sweep');
        samples =   Prefs.Integer(1000,'min',1, ...
                        'help_text','Number of samples per run. Setting this to be low will incur more overhead. Setting high will reduce feedback.');
        pb_IP =     Prefs.String('None Set','set','set_pb_IP', ...
                        'help_text','Hostname for computer running pulseblaster server');
        awg_IP =    Prefs.String('None Set','set','set_awg_IP', ...
                        'help_text','AWG IP for TCP connection');
        NIDAQ_dev = Prefs.String('None Set','set','set_NIDAQ_dev', ...
                        'help_text','Device name for NIDAQ (found/set in NI-MAX)');
        
        repumpLaser = Modules.Source.empty(1,0);
        resLaser = Modules.Source.empty(1,0); % Allow selection of source
        APDline = Prefs.Integer(1,'min',1);
        
        %%% CHECK TRIGGER LINE
        TRIGline = Prefs.Integer(1,'min',1);
        
        freq_start =    Prefs.Double(2, 'unit', 'GHz', 'help_text', 'Sweep start frequenecy. Used in linspace(s,e,p).');
        freq_end =      Prefs.Double(4, 'unit', 'GHz', 'help_text', 'Sweep start frequenecy. Used in linspace(s,e,p).');
        points =        Prefs.Integer(1,'min',1,        'help_text', 'Number of points per frequency sweep. Used in linspace(s,e,p).');
        
        repumpTime =    Prefs.Double(1, 'unit', 'us',  'help_text', 'Length of time to turn the repump laser on');
        paddingTime =   Prefs.Double(1, 'unit', 'us',  'help_text', 'Length of time inbetween laser pulses');
        resTime =       Prefs.Double(10, 'unit', 'us', 'help_text', 'Length of time to turn the resonant laser on');

        Amplitude =     Prefs.Double(0.05, 'unit', 'V',  'help_text', 'AWG Vpp');
        SampleRate =    Prefs.Double(2.5, 'unit', 'GHz',  'help_text', 'AWG sample rate');
        phaseOffset =   Prefs.Double(0, 'unit', 'rad', 'help_text', 'Phase offset for AWG waveforms');
        
        repump_type =   Prefs.MultipleChoice('Off', 'choices', {'Off', 'Once', 'Every Sweep', 'Every Point'}, ...
                            'help_text', sprintf(   ['Where to put repump pulses.\n - Off ==> repump disabled.\n - Once ==> only at the very start (software-triggered).\n', ...
                                                    ' - Every Sweep ==> before every frequency sweep. - Every Point ==> at every point in the frequency sweep.']));
        ple_type =   Prefs.MultipleChoice('slow', 'choices', {'slow', 'fast'}, ...
                            'help_text', sprintf(   ['How to run PLE sweep.\n - slow ==> Sampling N times at a frequency point before moving to the next.\n',...
                                                    ' - fast ==> Sampling entire frequency sweep N times.']));
    end
    properties(SetAccess=protected,Hidden)
        data = [] % subclasses should not set this; it can be manipulated in GetData if necessary
        meta = [] % Store experimental settings
        abort_request = false; % Flag that will be set to true upon abort. Used in run method.
        pbH; % Handle to pulseblaster
        AWG; % Handle to AWG
        nidaqH; % Handle to NIDAQ
    end
    properties(Hidden)
        ctsbefore1 = NaN
        ctsbefore2 = NaN
    end
    
   % properties(SetAccess=private)
       % timeout         % Padded timeout (sec).
   % end
    
    methods(Static)
        function obj = instance()
            mlock;
            persistent Object
            if isempty(Object) || ~isvalid(Object)
                Object = Experiments.awgPLEscan();
            end
            obj = Object;
        end
    end
    methods(Access=private)
        function obj = awgPLEscan()
            obj.loadPrefs;
        end
    end
    methods
        
        run(obj,status,managers,ax) %run function moved to a separate file for ease of debug
        
        function abort(obj)
            % Callback for when user presses abort in CC
            obj.abort_request = true;
        end
        
        function dat = GetData(obj,~,~)
            % Callback for saving methods (note, lots more info in the two managers input!)
            dat.data = obj.data;
            dat.meta = obj.meta;
        end
        
        function val = set_pb_IP(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.pbH = [];
            end
            try
                obj.pbH = Drivers.PulseBlaster.instance(val);
            catch err
                obj.pbH = [];
                obj.pb_IP = 'None Set';
                rethrow(err);
            end
        end
        function val = set_NIDAQ_dev(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.nidaqH = [];
            end
            try
                obj.nidaqH = Drivers.NIDAQ.dev.instance(val);
            catch err
                obj.nidaqH = [];
                obj.NIDAQ_dev = 'None Set';
                rethrow(err);
            end
        end
        
        function val = set_awg_IP(obj,val,~)
            if strcmp(val,'None Set') % Short circuit
                obj.AWG = [];
            end
            if isempty(obj.AWG)
                try
                    % currently '18.25.28.214'; 6/22/2022
                    obj.AWG=AWG70002B('visa',obj.awg_IP);
    %                 obj.AWG=visa('tek', ['TCPIP0::' obj.awg_IP '::INSTR']);
    %                 fopen(obj.AWG);
                catch err
                    rmfield(obj,'AWG');
    %                 obj.AWG = [];
                    obj.awg_IP = 'None Set';
                    rethrow(err);
                end
            end
        end
        
        %% Subclasses should overload these methods

        % Short circuit the following methods [no need to be fatal]
        function PreRun(obj,~,~,ax)
            % Load program to AWG
            obj.data.freqs = linspace(obj.freq_start, obj.freq_end, obj.points);
            % obj.setupAWG(); % Comment out for now, debugging APD-related
                
            %prepare axes for plotting
            hold(ax,'off');
            %plot data
            yyaxis(ax,'left');
            colors = lines(2);
            % plot signal
            plotH = errorfill(obj.data.freqs,...
                              obj.data.sumCounts(1,:,1),...
                              obj.data.stdCounts(1,:,1),...
                              'parent',ax,'color',colors(1,:));
                          
            xlabel(ax,'Detuning Frequency [GHz]');
            ylabel(ax,'Intensity [a.u.]');
            
            % Store for UpdateRun
            ax.UserData.plots = plotH;
            hold(ax,'off');
            set(ax,'xlimmode','auto','ylimmode','auto','ytickmode','auto')
        end
        function UpdateRun(obj,~,~,ax)
            if obj.averages > 1
                %averagedData = squeeze(nanmean(obj.data.rawCounts,1))*obj.pts*obj.averages;
                %meanError = squeeze(nanstd(obj.data.rawCounts,0,1))*sqrt(obj.samples*obj.averages);
                averagedData = mean(obj.data.sumCounts,'omitnan');
                meanError = mean(obj.data.stdCounts,'omitnan')*sqrt(obj.samples);
            else
                averagedData = obj.data.sumCounts;
                meanError = obj.data.stdCounts*sqrt(obj.samples);
            end
            
            %grab handles to data from axes plotted in PreRun
            ax.UserData.plots.YData = averagedData;
            ax.UserData.plots.YNegativeDelta = meanError;
            ax.UserData.plots.YPositiveDelta = meanError;
            ax.UserData.plots.update()
            
            drawnow limitrate;
        end
        function PostRun(obj,varargin)
        end
        
        function name = sequenceName(obj)
            name = sprintf('PLE_fs=%f_fe=%f_n=%i_%s', obj.freq_start, obj.freq_end, obj.points, obj.ple_type);
        end
        
        %setupAWG(obj) %Code segment moved to separated file for ease of debugging
        function sequenceList = setupAWG(obj)
            % Setting up AWG parameters
            obj.AWG.Amplitude = obj.Amplitude; % Vpp
            obj.AWG.SampleRate = obj.SampleRate*1e9;
            obj.AWG.phaseOffset = obj.phaseOffset;
            sampling = obj.AWG.SampleRate;
            phase = obj.AWG.phaseOffset;
            vpp = obj.AWG.Amplitude;
            
            obj.AWG.SetSampleRate();
            obj.AWG.setRunMode('c');

            % define time durations in AWG units
            repumpTime = ceil(obj.repumpTime*sampling*1e-06);
            resTime = ceil(obj.resTime*sampling*1e-06);
            resDuration = linspace(0,obj.resTime*1e-06,1/sampling);
            paddingTime = ceil(obj.paddingTime*sampling*1e-06);    % delay between repump and res

            % initialize sequence
            SeqName = obj.sequenceName();
            %obj.AWG.initSequence(SeqName,obj.points+1);

            % Basic waveform compiling setting - change to compile only
            % otherwise, the for loop chokes up and errors
            obj.AWG.writeToSocket(sprintf('BWAV:COMP:CASS 0'));
            obj.AWG.writeToSocket(sprintf('BWAV:COMP:CHAN NONE'));

            % 8 bit DAC resolution, 2 marker bits
            obj.AWG.writeToSocket(sprintf('SOUR1:DAC:RES 8')); % channel 1
            obj.AWG.writeToSocket(sprintf('SOUR2:DAC:RES 8')); % channel 2

            % define frequencies in AWG unit
            AWGFreq_low = obj.freq_start/sampling;
            AWGFreq_high = obj.freq_end/sampling;

            freqList = linspace(AWGFreq_low, AWGFreq_high, obj.points);
            
            % CHECK IF SEQUENCE ALREADY EXISTS
            size_seq_list=str2num(obj.AWG.writeReadToSocket('SLIS:SIZE?'));
            seq_exists=0;
            for ind=1:size_seq_list
                s_name=char(obj.AWG.writeReadToSocket(['SLIS:NAME? ' num2str(ind)]));
                if strcmp(SeqName,s_name(2:end-1))
                    seq_exists=1;
                    disp(['"' SeqName '" already exists!']);
                end
            end
            
            savePath='H:\\AWG70002B\\';% for local computer to save to Houston
            load_dir='Z:\\Experiments\\AWG70002B\\'; % for AWG to retrieve the data from
            
            if ~seq_exists
                if strcmp(obj.ple_type,'fast') % one long waveform, looping "samples" times
                    obj.AWG.initSequence(SeqName,1);
                    channel1 = [];
                    channel2 = [];
                    c1m1=[];
                    c1m2=[];
                    c2m1=[];
                    c2m2=[];
                    if strcmp(obj.repump_type,'Every Point')
                        for i = 1:obj.points
                            resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phase);
                            % AWG to EOM (sideband frequencies)
                            channel1 = [channel1 zeros(1,repumpTime+paddingTime) resDrive];
                            channel2 = [channel2 zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                            %%% markers
                            % EMM (AOM)
                            c1m1 = [c1m1 zeros(1,repumpTime+paddingTime) ones(1,resTime)];
                            % Cobolt
                            c1m2 = [c1m2 ones(1,repumpTime) zeros(1,paddingTime+resTime)];
                            % APD
                            c2m1 = [c2m1 zeros(1,repumpTime+paddingTime) ones(1,resTime)];

                            c2m2 = [c2m2 zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                        end

                        sequenceList{1} = ['PLEC1'];
                        sequenceList{2} = ['PLEC2'];

                        timeId= ['PLE_' obj.ple_type '_EP_' datestr(now,'mm_dd_yy_HHMM')];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
                           
                       
                        
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  obj.ple_type '\\' fName{1}, '",TXT8']));
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  obj.ple_type '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        %obj.AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
                        %obj.AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);

                        obj.AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
                        obj.AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});

                        obj.AWG.addLoopToSequenceStep(SeqName,1,ceil(obj.samples/obj.points));

                    elseif strcmp(obj.repump_type,'Every Sweep')
                        obj.AWG.initSequence(SeqName,1);
                        channel1 = [channel1 zeros(1,repumpTime)];
                        channel2 = [channel2 zeros(1,repumpTime)];
                        c1m1 = [c1m1 zeros(1,repumpTime)];
                        c1m2 = [c1m2 ones(1,repumpTime)];
                        c2m1 = [c2m1 zeros(1,repumpTime)];
                        c2m2 = [c2m2 zeros(1,repumpTime)];
                        for i = 1:obj.points
                            resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phase);

                            % AWG to EOM (sideband frequencies)
                            channel1 = [channel1 zeros(1,paddingTime) resDrive];
                            channel2 = [channel2 zeros(1,paddingTime+resTime)]; % do nothing
                            %%% markers
                            % EMM (AOM)
                            c1m1 = [c1m1 zeros(1,paddingTime) ones(1,resTime)];
                            % Cobolt
                            c1m2 = [c1m2 zeros(1,paddingTime+resTime)];
                            % APD
                            c2m1 = [c2m1 zeros(1,paddingTime) ones(1,resTime)];

                            c2m2 = [c2m2 zeros(1,paddingTime+resTime)]; % do nothing
                        end

                        sequenceList{1} = ['PLEC1'];
                        sequenceList{2} = ['PLEC2'];

                        timeId= ['PLE_' obj.ple_type '_ES_' datestr(now,'mm_dd_yy_HHMM')];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 

                        
                        
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  obj.ple_type '\\' fName{1}, '",TXT8']));
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  obj.ple_type '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        %obj.AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
                        %obj.AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);

                        pause(1);

                        obj.AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
                        obj.AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});

                        obj.AWG.addLoopToSequenceStep(SeqName,1,ceil(obj.samples/obj.points));
                    else
                        fprintf('Defined repump type incorrectly!');
                        err;
                    end


                else % sequence containing numPoints steps, each step is a sine waveform
                    obj.AWG.initSequence(SeqName,obj.points);
                    for i = 1:obj.points
                        resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phase);

                        % AWG to EOM (sideband frequencies)
                        channel1 = [zeros(1,repumpTime+paddingTime) resDrive];
                        channel2 = [zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                        %%% markers
                        % EMM (AOM)
                        c1m1 = [zeros(1,repumpTime+paddingTime) ones(1,resTime)];
                        % Cobolt
                        c1m2 = [ones(1,repumpTime) zeros(1,paddingTime+resTime)];
                        % APD
                        c2m1 = [zeros(1,repumpTime+paddingTime) ones(1,resTime)];

                        c2m2 = [zeros(1,repumpTime+paddingTime+resTime)]; % do nothing

                        sequenceList{1,i} = ['PLEC1Step' num2str(i)];
                        sequenceList{2,i} = ['PLEC2Step' num2str(i)];

                        timeId= ['PLE_' ,obj.ple_type, datestr(now,'mm_dd_yy'), '_wav',num2str(i)];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        obj.writeWavHouston([savePath obj.ple_type '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
                        
                       
                        
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1,i},'", "' load_dir  obj.ple_type '\\' fName{1}, '",TXT8']));
                        obj.AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2,i},'", "' load_dir  obj.ple_type '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        pause(1);

                        obj.AWG.addWaveformToSequence(i, 1, SeqName, sequenceList{1,i});
                        obj.AWG.addWaveformToSequence(i, 2, SeqName, sequenceList{2,i});

                        obj.AWG.addLoopToSequenceStep(SeqName,i,obj.samples/obj.points);
                        % Set wait behavior to OFF
                        obj.AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:WINP "%s", %s',...
                            i, SeqName, 'OFF'));

                        disp(['Uploaded freq point ' num2str(i)]);
                    end
                    % writing the last step to jump to 1st step
                    obj.AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:GOTO "%s", %s',...
                        i, SeqName, 'FIRS'));
                end
            end
        end
        
        %writeWavHouston(obj,fileName,channel,mrk1,mrk2)
        function writeWavHouston(obj,fileName,channel,mrk1,mrk2)
            if isfile(fileName)
                disp('Warning! Existing file will be overwritten!');
            end
            fid = fopen(fileName, 'wt' );
            for wL= 1:numel(channel)
                fprintf(fid, '%f,%f,%f\n', channel(wL), mrk1(wL), mrk2(wL));
            end
            fclose(fid);
        end
    end
end
