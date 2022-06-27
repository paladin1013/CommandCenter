 function run(obj,status,managers,ax)
            % Main run method (callback for CC run button)
            obj.abort_request = false;
            status.String = 'Experiment started';
            drawnow;

            obj.data.rawCounts = NaN([obj.averages,obj.samples]);
            obj.data.sumCounts = NaN([obj.averages,obj.points]);
            obj.data.stdCounts = NaN([obj.averages,obj.points]);

            obj.meta.prefs = obj.prefs2struct;
            obj.meta.position = managers.Stages.position; % Stage position

            % Invisible figure to handle pulsestream
            f = figure('visible','off','name',mfilename);
            a = axes('Parent',f);
            p = plot(NaN,'Parent',a);
            
            %%%% ATTEMPT AT BYPASSING APDPulseSequence
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            try
%               name = obj.sequenceName(); % UNCERTAIN WHAT THIS IS; this is the linked list created by the APD Pulse Sequence Command
                obj.PreRun(status,managers,ax);
%                 apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder')); %create an instance of apdpulsesequence to avoid recreating in loop
%                 pulseSeq = obj.BuildPulseSequence();

                    % INSERT RUN AWG here so triggers can be sent to tasks
                    % This is the AWG run mode setup code
                    obj.AWG.writeToSocket(sprintf('SOURCE:RCCOUPLE 1'));
                    obj.AWG.writeToSocket(sprintf('AWGC:RUN:IMM'));%Sets it to the play mode; waiting for trigger
                    
                for j = 1:obj.averages % ABOVE AWG SCRIPT ASSUMED AVERAGE=1
                    drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
                    status.String = sprintf('\nProgress (%i/%i averages):\n  ',j,obj.averages);

%                     % NEED TO CHANGE, FIND LINE NAMES AUTOMATICALLY
                    trigger_line = obj.nidaqH.InLines(2).name; % from AWG (PFI8 'APDgate' on M4)
                    counter_line = obj.nidaqH.InLines(1).name; % from APD (PFI0 'APD1' on M4)
%                     
                    %%%%%%% APDPulseSequence 'Start' equivalent
%                     % Get the gate channels
%                     gate_chans = obj.seq.getSequenceChannels;
%                     gate_chans(cellfun(@(a)isempty(a),{gate_chans.counter}))=[];

                    % Configure pulse width
                    nidaq_tasks = Drivers.NIDAQ.task.empty(0);
                    obj.nidaqH.ClearAllTasks();

                    nidaq_tasks(end+1) = obj.nidaqH.CreateTask([trigger_line]);
                    ind=1;
                    nidaq_tasks(ind).UserData.N = obj.samples;
                    nidaq_tasks(ind).UserData.raw_data = NaN(nidaq_tasks(ind).UserData.N,1);
                    nidaq_tasks(ind).UserData.ii = 0;
                    MaxCounts = 1000; % hardcoded
                    try
                        nidaq_tasks(ind).ConfigurePulseWidthCounterIn(counter_line,trigger_line,nidaq_tasks(ind).UserData.N,0,MaxCounts)
                        %nidaq_tasks(ind+1).ConfigureStartTrigger(trigger_line,'rising')
                    catch err
                        nidaq_tasks(ind).Clear;
                        nidaq_tasks(ind+1).Clear;
                        %nidaq_tasks(ind) = Drivers.NIDAQ.task.empty(0);
                        rethrow(err)
                    end
                    %setups NIDAQ tasks
                    
                    nidaq_tasks(ind).Start;%NIDAQ signal 
                    triggerMode=0; %0 for looped-single triggers; 1 for continuous trigger i.e. overfill NIDAQ
                    
                    if triggerMode == 1
                        obj.AWG.writeToSocket(sprintf('SOURCE1:RMOD TRIG'));% Since the run modes are coupled, we only need to set one (CONT|TRIG|TCON)
                        %for i=1:ceil(obj.samples/obj.points)
                        %obj.AWG.writeToSocket(sprintf('TRIG:IMM')); %Triggers once; In a loop 
                        %end
                    else 
                        obj.AWG.writeToSocket(sprintf('SOURCE1:RMOD TCON'));% Since the run modes are coupled, we only need to set one (CONT|TRIG|TCON)
                        obj.AWG.writeToSocket(sprintf('TRIG:IMM')); %Triggers once 
                    end   
               
                    %%          
                    %%%%%%% APDPulseSequence 'Stream' equivalent
                    % Inputs are line objects (one for each counter)
                    % Samples would be the number of times res laser (nidaq 'clock') goes active; ideally it should be  
                    
                    assert(~isempty(nidaq_tasks),'Nothing setup!')
                    err = [];
                    
                    time0 = tic;
                    timeLimit = 30;
                    k=1;
                   
                    try
                        while ~isempty(nidaq_tasks) && toc(time0)< timeLimit
                                if triggerMode==0
                                    obj.AWG.writeToSocket(sprintf('TRIG:IMM'));
                                end

                                if nidaq_tasks(ind).IsTaskDone
                                    clearFlag = 1;
                                else
                                    clearFlag = 0;
                                end

                                SampsAvail=nidaq_tasks(ind).AvailableSamples;
                                if SampsAvail
                                    ii = nidaq_tasks(ind).UserData.ii;
                                    % Change to counts per second;                    
                                    counts = nidaq_tasks(ind).ReadCounter(SampsAvail);
                                    %Saves counts to rawData
                                    nidaq_tasks(ind).UserData.raw_data(ii+1:ii+SampsAvail) = counts;
                                    nidaq_tasks(ind).UserData.ii = nidaq_tasks(ind).UserData.ii + SampsAvail;
                                    set(p,'ydata',nidaq_tasks(ind).UserData.raw_data,...
                                        'xdata',1:numel(nidaq_tasks(ind).UserData.raw_data))
                                    drawnow;
                                    disp(sprintf(['Acc. Counts:' num2str(sum( nidaq_tasks(ind).UserData.raw_data,'omitnan')) ' \n Samples Available:' num2str(SampsAvail) '; Iter:' num2str(k)]));
                                    k=k+1;
                                end

                                if clearFlag
                                    nidaq_tasks(ind).Clear
                                    nidaq_tasks(ind) = [];
                                    
                                end
                            
                        end
                    catch err
                    end
                    %assert(toc(time0)>timeLimit,"Timed out!!"); 
                    %nidaq_tasks(ind).Clear;
                    nidaq_tasks = Drivers.NIDAQ.task.empty(0);
                    if ~isempty(err)
                        rethrow(err)
                    end
                    %%%%%%% end 'Stream'
                    
                    
       %            dat = reshape(p.YData,obj.samples,[])';
                    dat = p.YData'; 
                    % 'dat' may not have enough elements to be n_points * runs long
                    datC=reshape(dat(1:end-mod(numel(dat),obj.points)),obj.points,[])';%Conditioned Data
                    % Gives an array with obj.points number of columns; 
                    % the number of rows are based on how mnay samples were acquired: mod(numel(dat),obj.points) are the excee points
                    obj.data.rawCounts(j,:) = dat;%Stores all raw counts; won't be used for processing
                    %reshape(datC,obj.points,[]);
                    %dat((j-1)*obj.points+1:j*obj.points);
                    %disp(sprintf(['Reported Acc. Counts:' num2str(sum(obj.data.rawCounts,'omitnan')) ]));
                    obj.data.sumCounts(j,:) = sum(datC,'omitnan');%replaces nansum
                    obj.data.stdCounts(j,:) = std(datC,'omitnan');%replaces nanstd

                    obj.ctsbefore2 = obj.ctsbefore1;
                    obj.ctsbefore1 = sum(sum(datC));
                    obj.UpdateRun(status,managers,ax);
                    obj.AWG.writeToSocket(sprintf('AWGC:STOP:IMM'));
                end
                
                obj.PostRun(status,managers,ax);

            catch err
            end
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%             try
%                 name = obj.sequenceName();
%                 obj.PreRun(status,managers,ax);
%                 apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder')); %create an instance of apdpulsesequence to avoid recreating in loop
% 
% %                 pulseSeq = obj.BuildPulseSequence();
%                     
%                 for j = 1:obj.averages
%                     drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
%                     status.String = sprintf('%s\nProgress (%i/%i averages):\n  ', name,j,obj.averages);
% 
%                     %%%%%%%%%%%%%%%%%%%%%%%%%%
%                     % OUR ATTEMPT TO GRAB COUNTS DIRECTLY FROM NIDAQ
%                     % to be changed:
%                     trigger_line = ;
%                     counter_line = ;
%                     
%                     % Question 1:
%                     % What is the index i referred below?
%                     % i = 1:numel(gate_chans) in "APDPulseSequence.m", line 78
%                     % gate_chans = obj.seq.getSequenceChannels; line 73
%                     
%                     obj.tasks(i)=Drivers.NIDAQ.task.empty(0);
%                     obj.tasks(i).UserData.N = obj.count_bins(s,GateLineName);
%                     
%                     % Question 2:
%                     % Is UserData.N the number of counter bins?
%                     % In our case, number of ``samples'' (if avg=1)?
%                     
%                     % Question 3:
%                     % Why is MaxCounts hard coded to be 1000 before?
%                     % see below: apdPS.start(1000)
%                     MaxCounts=1000;
%                     obj.tasks(i).ConfigurePulseWidthCounterIn(trigger_liine,counter_line,obj.tasks(i).UserData.N,0,MaxCounts)
%                     
%                     % Question 4:
%                     % Below, we should be able to grab counts without going
%                     % through the figure handle?
%                     
%                     SampsAvail = obj.tasks(i).AvailableSamples;
%                     counts = obj.tasks(i).ReadCounter(SampsAvail);
%                     %%%%%%%%%%%%%%%%%%%%%%%%%%
%                     
%                     % BuildPulseSequence must take in vars in the order listed
%                     if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)
%                         pulseSeq.repeat = obj.samples;
%                         apdPS.seq = pulseSeq;
%                         try
%                             apdPS.start(1000); % hard coded
%                         catch
%                             apdPS.start(1000); % hard coded
%                         end
%                         apdPS.stream(p);
%                         dat = reshape(p.YData,obj.points,[])';
% 
%                         obj.data.rawCounts(((j-1)*obj.samples + 1):(j*obj.samples),:) = dat;
%                         obj.data.sumCounts(j,:) = sum(dat);
%                         obj.data.stdCounts(j,:) = std(dat);
% 
%                         obj.ctsbefore2 = obj.ctsbefore1;
%                         obj.ctsbefore1 = sum(sum(dat));
%                     end
%                     
%                     obj.UpdateRun(status,managers,ax);
%                 end
%                 obj.PostRun(status,managers,ax);
% 
%             catch err
%             end
            delete(f);
            if exist('err','var') && ~isempty(err)
                rethrow(err)
            end
        end