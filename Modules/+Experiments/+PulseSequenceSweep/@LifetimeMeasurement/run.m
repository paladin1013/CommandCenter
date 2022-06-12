function run( obj,status,managers,ax)
    % Main run method (callback for CC run button)
    
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
    
    
    nPulseWidths = length(obj.PulseWidths_ns);
    nBins = ceil(obj.PulsePeriod_ns/obj.bin_width_ns);

    
    assert(numel(obj.nCounterBins)==1 && isnumeric(obj.nCounterBins) && floor(obj.nCounterBins)==obj.nCounterBins,...
        'Property "nCounterBins" should be a single integer');
    assert(~isempty(obj.picoharpH), "PicoHarp300 is not connected");
    obj.SetPHconfig;
    
    if (isempty(obj.AWG)|| ~isvalid(obj.AWG))
        try
            obj.set_AWG_IP;
        catch exception
            assert(false, 'AWG driver is not intialized properly.');
        end
    end
    assert(~isempty(obj.pbH)&&isvalid(obj.pbH),'PulseBluster driver is not intialized properly.');
    
    
    %prepare axes for plotting
    ax = plotyy(ax,[0], [-1], [0], [0]);
    
    line([0], [-2], 'Parent', ax(1), 'Color', 'c');
    
    set(ax(2),'YLim',[0 inf])
    set(ax(2), 'XLim', [0 obj.PulsePeriod_ns])
    set(ax(1),'YLim',[0 inf])
    set(ax(1), 'XLim', [0 inf]) 
    %             set(ax(2).XLabel,'String','Time (ns)')
    set(ax(2).YLabel,'String','Time Bin Probability')
    set(ax(1).XLabel,'String','PulseWidth (ns)')
    set(ax(1).YLabel,'String','Total Probability')
    ax(2).Box = 'off';
    ax(1).Box = 'off';
    ax(1).XColor = ax(1).YColor;
    ax(2).XColor = ax(2).YColor;
    
    status.String = 'Experiment started';
    obj.abort_request = false;
    drawnow;
    
    obj.data.counts = NaN([nPulseWidths, obj.averages, obj.samples,obj.nCounterBins]);
    obj.data.timeTags = cell([nPulseWidths, obj.averages, obj.samples,obj.nCounterBins]);
    obj.data.timeBinResults = zeros([nPulseWidths, nBins]);
    obj.data.sectionProbability = zeros([1, nPulseWidths]);
    obj.data.totalProbability = zeros([1, nPulseWidths]);
    
    if obj.recordAllTimeTags
        obj.data.rawTimeTags0 = cell([nPulseWidths, obj.averages]);
        obj.data.rawTimeTags1 = cell([nPulseWidths, obj.averages]);
    end
    
    obj.meta.prefs = obj.prefs2struct;
    
    obj.meta.PulseWidths = obj.PulseWidths_ns;
    
    obj.meta.position = managers.Stages.position; % Stage position
    
    f = figure('visible','off','name',mfilename);
    a = axes('Parent',f);
    p = plot(NaN,'Parent',a);
    
    
    try
        obj.PreRun(status,managers,ax);
        
        % Construct APDPulseSequence once, and update apdPS.seq
        % Not only will this be faster than constructing many times,
        % APDPulseSequence upon deletion closes PulseBlaster connection
        
        if obj.MergeSequence == false
            obj.runSeparatedSeq(ax, p, status);
        
        else 
            % Enabling merge sequence option. This will compile all pulsewidths into the same waveform. 
            
            obj.runMergedSeq(ax, p, status);
                    
    
    
    
        end
    
        obj.picoharpH.PH_StopMeas;
    
    catch err
    end
    delete(f);

    if exist('err','var')
        rethrow(err)
    end
end
    