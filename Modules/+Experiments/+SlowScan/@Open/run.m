function run( obj,status,managers,ax)
    % Main run method (callback for CC run button)
    obj.abort_request = false;
    status.String = 'Experiment started';
    drawnow;
    % Edit here down (save data to obj.data)
    % Tips:
    % - If using a loop, it is good practice to call:
    %     drawnow; assert(~obj.abort_request,'User aborted.');
    %     as frequently as possible
    % - try/catch/end statements useful for cleaning up
    % - You can get a figure-like object (to create subplots) by:
    %     panel = ax.Parent; delete(ax);
    %     ax(1) = subplot(1,2,1,'parent',panel);
    % - drawnow can be used to update status box message and any plots
    
    % Assert user implemented abstract properties correctly
    assert(iscell(obj.vars)&&~isempty(obj.vars)&&min(size(obj.vars))==1,'Property "vars" should be a 1D cell array with at least one value!');
    assert(all(cellfun(@ischar,obj.vars)),'Property "vars" should only contain strings');
    check_prop_exists = cellfun(@(a)isprop(obj,a),obj.vars);
    assert(all(check_prop_exists),sprintf('Properties not found in obj that are listed in "vars":\n%s',...
        strjoin(obj.vars(check_prop_exists),newline)));
    assert(numel(obj.nCounterBins)==1 && isnumeric(obj.nCounterBins) && floor(obj.nCounterBins)==obj.nCounterBins,...
        'Property "nCounterBins" should be a single integer');
    
    numVars = length(obj.vars);
    varLength = NaN(1,numVars);
    for i = 1:numVars
        varLength(i) = length(obj.(obj.vars{i}));
    end
    
    obj.data.sumCounts = NaN([obj.averages,varLength,obj.nCounterBins]);
    % obj.data.completeCounts = NaN([obj.averages,varLength,obj.samples]);
    obj.data.stdCounts = NaN([obj.averages,varLength,obj.nCounterBins]);
    
    obj.meta.prefs = obj.prefs2struct;
    for i = 1:length(obj.vars)
        obj.meta.vars(i).name = obj.vars{i};
        obj.meta.vars(i).vals = obj.(obj.vars{i});
    end
    obj.meta.position = managers.Stages.position; % Stage position
    
    f = figure('visible','off','name',mfilename);
    a = axes('Parent',f);
    p = plot(NaN,'Parent',a);
    
    try
        obj.PreRun(status,managers,ax);
        
        % Construct APDPulseSequence once, and update apdPS.seq
        % Not only will this be faster than constructing many times,
        % APDPulseSequence upon deletion closes PulseBlaster connection
        indices = num2cell(ones(1,numVars));
        apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder')); %create an instance of apdpulsesequence to avoid recreating in loop
        statusString = cell(1,numVars);
        t = tic;
        for j = 1:obj.averages
            for i = 1:prod(varLength)
                fprintf("time1: %f\n", toc(t));
                drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
                [indices{:}] = ind2sub(varLength,i); % this does breadth-first
                for k=1:numVars
                    statusString{k} = sprintf('%s = %g (%i/%i)',obj.vars{k},obj.(obj.vars{k})(indices{k}),indices{k},varLength(k));
                end
                status.String = [sprintf('Progress (%i/%i averages):\n  ',j,obj.averages),strjoin(statusString,'\n  ')];
                fprintf("time2: %f\n", toc(t));
                % BuildPulseSequence must take in vars in the order listed
                pulseSeq = obj.BuildPulseSequence(indices{:});
                fprintf("time3: %f\n", toc(t));
                if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)
                    pulseSeq.repeat = obj.samples;
                    apdPS.seq = pulseSeq;
                    fprintf("time4: %f\n", toc(t));
                    if(i == 1)
                        apdPS.start(1000); % hard coded
                    else
                        apdPS.start(1000, false, true); % overrideMinDuration=false, usePrevSeq=true to save compiling and upload time

                    end
                    apdPS.stream(p);
                    fprintf("time5: %f\n", toc(t));
                    dat = reshape(p.YData,obj.nCounterBins,[])';
                    if size(dat,1)==1
                        obj.data.sumCounts(j,indices{:},:) = dat;
                        obj.data.stdCounts(j,indices{:},:) = dat;
                    else
                        obj.data.sumCounts(j,indices{:},:) = sum(dat);
                        obj.data.stdCounts(j,indices{:},:) = std(dat);
                        % obj.data.completeCounts(j,indices{:},:) = dat;
                    end
                    fprintf("time6: %f\n", toc(t));
                end
                obj.UpdateRun(status,managers,ax,j,indices{:});
                fprintf("time7: %f\n", toc(t));
            end
        end
        obj.PostRun(status,managers,ax);
        
    catch err
    end
    delete(f);
    if exist('err','var')
        rethrow(err)
    end
    end
    