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
assert(~isempty(obj.picoharpH), "PicoHarp300 is not connected");

numVars = length(obj.vars);
varLength = NaN(1,numVars);
for i = 1:numVars
    varLength(i) = length(obj.(obj.vars{i}));
end

obj.data.counts = NaN([obj.averages,varLength, obj.samples,obj.nCounterBins]);
obj.data.diff = NaN([obj.averages,varLength, obj.samples,obj.nCounterBins]);
obj.data.timeTags = cell([obj.averages, varLength, obj.samples,obj.nCounterBins]);
if obj.recordAllTimeTags
    obj.data.rawTimeTags0 = cell([obj.averages, varLength]);
    obj.data.rawTimeTags1 = cell([obj.averages, varLength]);
end

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
    apdPS = APDPulseSequence(obj.nidaqH,obj.pbH,sequence('placeholder'), obj.picoharpH); %create an instance of apdpulsesequence to avoid recreating in loop
    statusString = cell(1,numVars);
    
    % offsetMax = 10;
    % diff = zeros(1, offsetMax*2+1);
    % countSum = zeros(1, offsetMax*2+1);
    % bias = zeros(1, offsetMax*2+1);
    % for syncPulseBias = -offsetMax:offsetMax
        % obj.syncPulseBias = syncPulseBias/10;
        for j = 1:obj.averages
            for i = 1:prod(varLength)

                drawnow('limitrate'); assert(~obj.abort_request,'User aborted.');
                [indices{:}] = ind2sub(varLength,i); % this does breadth-first
                for k=1:numVars
                    statusString{k} = sprintf('%s = %g (%i/%i)',obj.vars{k},obj.(obj.vars{k})(indices{k}),indices{k},varLength(k));
                end
                status.String = [sprintf('Progress (%i/%i averages):\n  ',j,obj.averages),strjoin(statusString,'\n  ')];
                
                % BuildPulseSequence must take in vars in the order listed
                pulseSeq = obj.BuildPulseSequence(indices{:});
                if pulseSeq ~= false % Interpret a return of false as skip this one (leaving in NaN)
                    pulseSeq.repeat = obj.samples;
                    apdPS.seq = pulseSeq;
                    t = tic;
                    % obj.picoharpH.PH_StartMeas(3000);
                    apdPS.start(1000); % hard coded
                    % pause(0.2);
                    [rawTttrData0,rawTttrData1] = obj.picoharpH.PH_GetTimeTags;

                    
                    apdPS.stream(p);
                    

                    % Retrieve data from picoharp and process to fit the two APD bins
                    obj.picoharpH.PH_StopMeas;
                    


                    assert(length(rawTttrData0) == 9*obj.samples - 3, sprintf("Number of time tag from PB should be exactly %d, but now got %d",9*obj.samples - 3, length(rawTttrData0)))
                    for k = 1:obj.samples
                        obj.data.timeTags{j, indices{:}, k, 1} = rawTttrData1((rawTttrData1>rawTttrData0(k*9-8)) & (rawTttrData1<rawTttrData0(k*9-7)))-rawTttrData0(k*9-8);
                        obj.data.timeTags{j, indices{:}, k, 2} = rawTttrData1((rawTttrData1>rawTttrData0(k*9-6)) & (rawTttrData1<rawTttrData0(k*9-5)))-rawTttrData0(k*9-6);
                        obj.data.timeTags{j, indices{:}, k, 3} = rawTttrData1((rawTttrData1>rawTttrData0(k*9-4)) & (rawTttrData1<rawTttrData0(k*9-3)))-rawTttrData0(k*9-4);
                    end


                    dat = reshape(p.YData,obj.nCounterBins,[])';
                    obj.data.counts(j,indices{:},:,:) = dat;
                    for k = 1:obj.samples
                        obj.data.diff(j, indices{:}, k, 1) = length(obj.data.timeTags{j, indices{:}, k, 1}) - obj.data.counts(j, indices{:}, k, 1);
                        obj.data.diff(j, indices{:}, k, 2) = length(obj.data.timeTags{j, indices{:}, k, 2}) - obj.data.counts(j, indices{:}, k, 2);
                        obj.data.diff(j, indices{:}, k, 3) = length(obj.data.timeTags{j, indices{:}, k, 3}) - obj.data.counts(j, indices{:}, k, 3);
                    end
                    if obj.recordAllTimeTags
                        obj.data.rawTimeTags0{j, indices{:}} = rawTttrData0;
                        obj.data.rawTimeTags1{j, indices{:}} = rawTttrData1;
                    end

                end
                obj.UpdateRun(status,managers,ax,j,indices{:});
            end
        % end
        % diff(syncPulseBias+offsetMax+1) = sum(abs(obj.data.diff), 'all');
        % countSum(syncPulseBias+offsetMax+1) = sum(obj.data.counts, 'all');
        % fprintf('Time delay: %.2f(us), count difference: %d, total count: %d, ratio: %.4d\n', syncPulseBias/10, diff(syncPulseBias+offsetMax+1), countSum(syncPulseBias+offsetMax+1),  diff(syncPulseBias+offsetMax+1)/countSum(syncPulseBias+offsetMax+1));
        
    end
    obj.PostRun(status,managers,ax);
catch err
end
delete(f);
if exist('err','var')
    rethrow(err)
end
end
