classdef AWGWriteWaveform < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        WritetoAWG                      matlab.ui.Figure
        GridLayout                      matlab.ui.container.GridLayout
        LeftPanel                       matlab.ui.container.Panel
        SavePathEditField               matlab.ui.control.EditField
        SavePathEditFieldLabel          matlab.ui.control.Label
        AWGIPEditField                  matlab.ui.control.EditField
        AWGIPEditFieldLabel             matlab.ui.control.Label
        RunningCharacteristicsLabel     matlab.ui.control.Label
        AmplitudeMax2EditField          matlab.ui.control.NumericEditField
        AmplitudeMax2EditFieldLabel     matlab.ui.control.Label
        WriteWaveformsButton            matlab.ui.control.Button
        CompileandPlotButton            matlab.ui.control.Button
        PaddingDurationusEditField      matlab.ui.control.NumericEditField
        PaddingDurationusEditFieldLabel  matlab.ui.control.Label
        ResonantDurationusEditField     matlab.ui.control.NumericEditField
        ResonantDurationusEditFieldLabel  matlab.ui.control.Label
        RepumpDurationusEditField       matlab.ui.control.NumericEditField
        RepumpDurationusEditFieldLabel  matlab.ui.control.Label
        RepumpTypeButtonGroup           matlab.ui.container.ButtonGroup
        SweepButton                     matlab.ui.control.RadioButton
        PointButton                     matlab.ui.control.RadioButton
        ScanTypeButtonGroup             matlab.ui.container.ButtonGroup
        SlowButton                      matlab.ui.control.RadioButton
        FastButton                      matlab.ui.control.RadioButton
        FreqPointsEditField             matlab.ui.control.NumericEditField
        FreqPointsEditFieldLabel        matlab.ui.control.Label
        EndFreqGHzEditField             matlab.ui.control.NumericEditField
        EndFreqGHzEditFieldLabel        matlab.ui.control.Label
        StartFreqGHzEditField           matlab.ui.control.NumericEditField
        StartFreqGHzEditFieldLabel      matlab.ui.control.Label
        SamplingRateGSsEditField        matlab.ui.control.NumericEditField
        SamplingRateGSsEditFieldLabel   matlab.ui.control.Label
        RightPanel                      matlab.ui.container.Panel
        markerplots_repump              matlab.ui.control.UIAxes
        markerplots_resonant            matlab.ui.control.UIAxes
        channel1plot                    matlab.ui.control.UIAxes
    end

    % Properties that correspond to apps with auto-reflow
    properties (Access = private)
        onePanelWidth = 576;
    end

    
    properties (Access = private)
        channel1
        channel2
        c1m1
        c1m2
        c2m1
        c2m2
        % Description
    end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: CompileandPlotButton
        function CompileandPlotButtonPushed(app, event)
             amplitude = app.AmplitudeMax2EditField.Value;   %Normalized units
            sampling  = app.SamplingRateGSsEditField.Value*1e09;
            phaseOffset = 0;
            vpp = amplitude;
            freq_start = app.StartFreqGHzEditField.Value;  % in GHz
            freq_end = app.EndFreqGHzEditField.Value;    % in GHz
            points=app.FreqPointsEditField.Value;
            %loops=1000;
            repumpTime_set= app.RepumpDurationusEditField.Value; % in us
            resTime_set= app.ResonantDurationusEditField.Value;% in us
            paddingTime_set=app.PaddingDurationusEditField.Value; % in us
            resDuration = linspace(0,resTime_set*1e-06,resTime_set*1e-06*sampling);
      
            if app.FastButton.Value
                ple_type='fast';
                if app.SweepButton.Value
                    repump_type='Every Sweep';
                else
                    repump_type='Every Point';
                end
            else
                ple_type='slow';
            end
            %define time durations in AWG units
            repumpTime = ceil(repumpTime_set*sampling*1e-06);
            resTime = ceil(resTime_set*sampling*1e-06);
            paddingTime = ceil(paddingTime_set*sampling*1e-06);
            %
%             if strcmp(ple_type,'fast')
%                 if strcmp(repump_type,'Every Point')
%                 SeqName=['PLE_' ple_type '_EP_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
%                 else
%                 SeqName=['PLE_' ple_type '_ES_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
%                 end
%             else 
%                 SeqName=['PLE_' ple_type '_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
%             end
%             
%             % Basic waveform compiling setting - change to compile only
%             % otherwise, the for loop chokes up and errors
%             AWG.writeToSocket(sprintf('BWAV:COMP:CASS 0'));
%             AWG.writeToSocket(sprintf('BWAV:COMP:CHAN NONE'));
% 
%             % 8 bit DAC resolution, 2 marker bits
%             AWG.writeToSocket(sprintf('SOUR1:DAC:RES 8')); % channel 1
%             AWG.writeToSocket(sprintf('SOUR2:DAC:RES 8')); % channel 2

           
            freqList =1e09.* linspace(freq_start, freq_end,points);
            
            %savePath='H:\\AWG70002B';% for local computer to save to Houston
            %load_dir='Z:\\Experiments\\AWG70002B'; % for AWG to retrieve the data from
            %SAVE directly to AWG
            
%             mkdir([savePath '\\' ple_type '\\'], ['fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)]);
%             % Makes waveform save directory
%             dir_save=[savePath '\\' ple_type '\\fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)];
%             load_dir=[load_dir '\\' ple_type '\\fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)];
%             seq_save_dir=['Z:\\Experiments\\AWG70002B\\sequences\\' ple_type '\\'];
%             
% %%           
                if strcmp(ple_type,'fast') % one long waveform, looping "samples" times
                    
                    app.channel1 = []; app.channel2 = [];
                    app.c1m1=[]; app.c1m2=[];
                    app.c2m1=[];app.c2m2=[];
                    if strcmp(repump_type,'Every Point')
                        for i = 1:points
                            resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phaseOffset);
                            % AWG to EOM (sideband frequencies)
                            app.channel1 = [app.channel1 zeros(1,repumpTime+paddingTime) resDrive];
                            app.channel2 = [app.channel2 zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                            %%% markers
                            % EMM (AOM)
                            app.c1m1 = [app.c1m1 zeros(1,repumpTime+paddingTime) ones(1,resTime)];
                            % Cobolt
                            app.c1m2 = [app.c1m2 ones(1,repumpTime) zeros(1,paddingTime+resTime)];
                            % APD
                            app.c2m1 = [app.c2m1 zeros(1,repumpTime+paddingTime) ones(1,resTime)];
                            app.c2m2 = [app.c2m2 zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                        end

%                         sequenceList{1} = ['PLEC1'];
%                         sequenceList{2} = ['PLEC2'];
% 
%                         timeId= ['PLE_' ple_type '_EP_' datestr(now,'mm_dd_yy_HHMM')];
% 
%                         fName{1}=[ timeId '_chn1.txt'];
%                         fName{2}=[ timeId '_chn2.txt'];
% 
%                         writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
%                         writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
%                            
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  '\\' fName{1}, '",TXT8']));
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  '\\' fName{2}, '",TXT8']));
%                         % Loads from .txt file on Houston 
% 
%                         %AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
%                         %AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);
% 
%                         AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
%                         AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});
% 
%                         AWG.addLoopToSequenceStep(SeqName,1,loops);

                    elseif strcmp(repump_type,'Every Sweep')
                        app.channel1 = [app.channel1 zeros(1,repumpTime)];
                        app.channel2 = [app.channel2 zeros(1,repumpTime)];
                        app.c1m1 = [app.c1m1 zeros(1,repumpTime)];
                        app.c1m2 = [app.c1m2 ones(1,repumpTime)];
                        app.c2m1 = [app.c2m1 zeros(1,repumpTime)];
                        app.c2m2 = [app.c2m2 zeros(1,repumpTime)];
                        for i = 1:  points
                            resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phaseOffset);

                            % AWG to EOM (sideband frequencies)
                            app.channel1 = [app.channel1 zeros(1,paddingTime) resDrive];
                            app.channel2 = [app.channel2 zeros(1,paddingTime+resTime)]; % do nothing
                            %%% markers
                            % EMM (AOM)
                            app.c1m1 = [app.c1m1 zeros(1,paddingTime) ones(1,resTime)];
                            % Cobolt
                            app.c1m2 = [app.c1m2 zeros(1,paddingTime+resTime)];
                            % APD
                            app.c2m1 = [app.c2m1 zeros(1,paddingTime) ones(1,resTime)];

                            app.c2m2 = [app.c2m2 zeros(1,paddingTime+resTime)]; % do nothing
                        end

%                         sequenceList{1} = ['PLEC1'];
%                         sequenceList{2} = ['PLEC2'];
% 
%                         timeId= ['PLE_'   ple_type '_ES_' datestr(now,'mm_dd_yy_HHMM')];
% 
%                         fName{1}=[ timeId '_chn1.txt'];
%                         fName{2}=[ timeId '_chn2.txt'];
% 
%                         writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
%                         writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
%                            
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  '\\' fName{1}, '",TXT8']));
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  '\\' fName{2}, '",TXT8']));
%                         % Loads from .txt file on Houston 
% 
%                         %AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
%                         %AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);
% 
%                         pause(1);
% 
%                         AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
%                         AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});
% 
%                         AWG.addLoopToSequenceStep(SeqName,1,loops);
                    else
                        fprintf('Defined repump type incorrectly!');
                        err;
                    end


                else % sequence containing numPoints steps, each step is a sine waveform
                    %AWG.initSequence(SeqName,points)
                    for i = 1:  points
                        resDrive = (vpp/2).*sin(2*pi*freqList(i).*resDuration+phaseOffset);

                        % AWG to EOM (sideband frequencies)
                        app.channel1 = [zeros(1,repumpTime+paddingTime) resDrive];
                        app.channel2 = [zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
                        %%% markers
                        % EMM (AOM)
                        app.c1m1 = [zeros(1,repumpTime+paddingTime) ones(1,resTime)];
                        % Cobolt
                        app.c1m2 = [ones(1,repumpTime) zeros(1,paddingTime+resTime)];
                        % APD
                        app.c2m1 = [zeros(1,repumpTime+paddingTime) ones(1,resTime)];

                        app.c2m2 = [zeros(1,repumpTime+paddingTime+resTime)]; % do nothing
%                         sequenceList{1,i} = ['PLEC1Step' num2str(i)];
%                         sequenceList{2,i} = ['PLEC2Step' num2str(i)];
% 
%                         timeId= ['PLE_' , ple_type, datestr(now,'mm_dd_yy'), '_wav',num2str(i)];
% 
%                         fName{1}=[ timeId '_chn1.txt'];
%                         fName{2}=[ timeId '_chn2.txt'];
% 
%                         writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
%                         writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
%                            
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1,i},'", "' load_dir  '\\' fName{1}, '",TXT8']));
%                         AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2,i},'", "' load_dir  '\\' fName{2}, '",TXT8']));
%                         % Loads from .txt file on Houston 
% 
%                         pause(1);
% 
%                         AWG.addWaveformToSequence(i, 1, SeqName, sequenceList{1,i});
%                         AWG.addWaveformToSequence(i, 2, SeqName, sequenceList{2,i});
% 
%                         AWG.addLoopToSequenceStep(SeqName ,i,loops);
%                         % Set wait behavior to OFF
%                         AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:WINP "%s", %s',...
%                             i, SeqName, 'OFF'));
% 
%                         disp(['Uploaded freq point ' num2str(i)]);
                    end
                    % writing the last step to jump to 1st step
                    %AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:GOTO "%s", %s',i, SeqName, 'FIRS'));
                end
                
                plot(app.channel1plot,1:numel(app.channel1),app.channel1,'LineWidth',2);
                
                plot(app.markerplots_resonant,1:numel(app.c1m1),app.c1m1,'Color','r','LineWidth',2);
                
                plot(app.markerplots_repump,1:numel(app.c1m2),app.c1m2,'Color','k','LineWidth',2);
               
        end

        % Changes arrangement of the app based on UIFigure width
        function updateAppLayout(app, event)
            currentFigureWidth = app.WritetoAWG.Position(3);
            if(currentFigureWidth <= app.onePanelWidth)
                % Change to a 2x1 grid
                app.GridLayout.RowHeight = {643, 643};
                app.GridLayout.ColumnWidth = {'1x'};
                app.RightPanel.Layout.Row = 2;
                app.RightPanel.Layout.Column = 1;
            else
                % Change to a 1x2 grid
                app.GridLayout.RowHeight = {'1x'};
                app.GridLayout.ColumnWidth = {277, '1x'};
                app.RightPanel.Layout.Row = 1;
                app.RightPanel.Layout.Column = 2;
            end
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create WritetoAWG and hide until all components are created
            app.WritetoAWG = uifigure('Visible', 'off');
            app.WritetoAWG.AutoResizeChildren = 'off';
            app.WritetoAWG.Position = [100 100 784 643];
            app.WritetoAWG.Name = 'Write Waveform to AWG';
            app.WritetoAWG.SizeChangedFcn = createCallbackFcn(app, @updateAppLayout, true);

            % Create GridLayout
            app.GridLayout = uigridlayout(app.WritetoAWG);
            app.GridLayout.ColumnWidth = {277, '1x'};
            app.GridLayout.RowHeight = {'1x'};
            app.GridLayout.ColumnSpacing = 0;
            app.GridLayout.RowSpacing = 0;
            app.GridLayout.Padding = [0 0 0 0];
            app.GridLayout.Scrollable = 'on';

            % Create LeftPanel
            app.LeftPanel = uipanel(app.GridLayout);
            app.LeftPanel.Layout.Row = 1;
            app.LeftPanel.Layout.Column = 1;
            app.LeftPanel.Scrollable = 'on';

            % Create SamplingRateGSsEditFieldLabel
            app.SamplingRateGSsEditFieldLabel = uilabel(app.LeftPanel);
            app.SamplingRateGSsEditFieldLabel.HorizontalAlignment = 'right';
            app.SamplingRateGSsEditFieldLabel.Position = [7 578 121 22];
            app.SamplingRateGSsEditFieldLabel.Text = 'Sampling Rate (GS/s)';

            % Create SamplingRateGSsEditField
            app.SamplingRateGSsEditField = uieditfield(app.LeftPanel, 'numeric');
            app.SamplingRateGSsEditField.Limits = [0 10];
            app.SamplingRateGSsEditField.ValueDisplayFormat = '%8.f';
            app.SamplingRateGSsEditField.Position = [143 578 100 22];
            app.SamplingRateGSsEditField.Value = 1;

            % Create StartFreqGHzEditFieldLabel
            app.StartFreqGHzEditFieldLabel = uilabel(app.LeftPanel);
            app.StartFreqGHzEditFieldLabel.HorizontalAlignment = 'right';
            app.StartFreqGHzEditFieldLabel.Position = [36 546 92 22];
            app.StartFreqGHzEditFieldLabel.Text = 'Start Freq (GHz)';

            % Create StartFreqGHzEditField
            app.StartFreqGHzEditField = uieditfield(app.LeftPanel, 'numeric');
            app.StartFreqGHzEditField.Limits = [0 1];
            app.StartFreqGHzEditField.Position = [143 546 100 22];
            app.StartFreqGHzEditField.Value = 0.01;

            % Create EndFreqGHzEditFieldLabel
            app.EndFreqGHzEditFieldLabel = uilabel(app.LeftPanel);
            app.EndFreqGHzEditFieldLabel.HorizontalAlignment = 'right';
            app.EndFreqGHzEditFieldLabel.Position = [15 513 112 22];
            app.EndFreqGHzEditFieldLabel.Text = 'End Freq (GHz)';

            % Create EndFreqGHzEditField
            app.EndFreqGHzEditField = uieditfield(app.LeftPanel, 'numeric');
            app.EndFreqGHzEditField.Limits = [0 1];
            app.EndFreqGHzEditField.ValueDisplayFormat = '%.3f';
            app.EndFreqGHzEditField.Position = [142 513 100 22];
            app.EndFreqGHzEditField.Value = 0.4;

            % Create FreqPointsEditFieldLabel
            app.FreqPointsEditFieldLabel = uilabel(app.LeftPanel);
            app.FreqPointsEditFieldLabel.HorizontalAlignment = 'right';
            app.FreqPointsEditFieldLabel.Position = [15 482 112 22];
            app.FreqPointsEditFieldLabel.Text = 'Freq Points';

            % Create FreqPointsEditField
            app.FreqPointsEditField = uieditfield(app.LeftPanel, 'numeric');
            app.FreqPointsEditField.Limits = [1 100];
            app.FreqPointsEditField.RoundFractionalValues = 'on';
            app.FreqPointsEditField.ValueDisplayFormat = '%.0f';
            app.FreqPointsEditField.Position = [142 482 100 22];
            app.FreqPointsEditField.Value = 5;

            % Create ScanTypeButtonGroup
            app.ScanTypeButtonGroup = uibuttongroup(app.LeftPanel);
            app.ScanTypeButtonGroup.TitlePosition = 'centertop';
            app.ScanTypeButtonGroup.Title = 'Scan Type';
            app.ScanTypeButtonGroup.Position = [16 382 100 71];

            % Create FastButton
            app.FastButton = uiradiobutton(app.ScanTypeButtonGroup);
            app.FastButton.Text = 'Fast';
            app.FastButton.Position = [11 25 45 22];
            app.FastButton.Value = true;

            % Create SlowButton
            app.SlowButton = uiradiobutton(app.ScanTypeButtonGroup);
            app.SlowButton.Text = 'Slow';
            app.SlowButton.Position = [11 3 48 22];

            % Create RepumpTypeButtonGroup
            app.RepumpTypeButtonGroup = uibuttongroup(app.LeftPanel);
            app.RepumpTypeButtonGroup.TitlePosition = 'centertop';
            app.RepumpTypeButtonGroup.Title = 'Repump Type';
            app.RepumpTypeButtonGroup.Position = [143 382 100 71];

            % Create PointButton
            app.PointButton = uiradiobutton(app.RepumpTypeButtonGroup);
            app.PointButton.Text = 'Point';
            app.PointButton.Position = [11 25 50 22];
            app.PointButton.Value = true;

            % Create SweepButton
            app.SweepButton = uiradiobutton(app.RepumpTypeButtonGroup);
            app.SweepButton.Text = 'Sweep';
            app.SweepButton.Position = [11 3 59 22];

            % Create RepumpDurationusEditFieldLabel
            app.RepumpDurationusEditFieldLabel = uilabel(app.LeftPanel);
            app.RepumpDurationusEditFieldLabel.HorizontalAlignment = 'right';
            app.RepumpDurationusEditFieldLabel.Position = [19 284 122 22];
            app.RepumpDurationusEditFieldLabel.Text = 'Repump Duration (us)';

            % Create RepumpDurationusEditField
            app.RepumpDurationusEditField = uieditfield(app.LeftPanel, 'numeric');
            app.RepumpDurationusEditField.Limits = [0 10];
            app.RepumpDurationusEditField.ValueDisplayFormat = '%.0f';
            app.RepumpDurationusEditField.Position = [156 284 100 22];
            app.RepumpDurationusEditField.Value = 1;

            % Create ResonantDurationusEditFieldLabel
            app.ResonantDurationusEditFieldLabel = uilabel(app.LeftPanel);
            app.ResonantDurationusEditFieldLabel.HorizontalAlignment = 'right';
            app.ResonantDurationusEditFieldLabel.Position = [14 250 128 22];
            app.ResonantDurationusEditFieldLabel.Text = 'Resonant Duration (us)';

            % Create ResonantDurationusEditField
            app.ResonantDurationusEditField = uieditfield(app.LeftPanel, 'numeric');
            app.ResonantDurationusEditField.Limits = [0 10];
            app.ResonantDurationusEditField.ValueDisplayFormat = '%.0f';
            app.ResonantDurationusEditField.Position = [157 250 100 22];
            app.ResonantDurationusEditField.Value = 1;

            % Create PaddingDurationusEditFieldLabel
            app.PaddingDurationusEditFieldLabel = uilabel(app.LeftPanel);
            app.PaddingDurationusEditFieldLabel.HorizontalAlignment = 'right';
            app.PaddingDurationusEditFieldLabel.Position = [21 210 121 22];
            app.PaddingDurationusEditFieldLabel.Text = 'Padding Duration (us)';

            % Create PaddingDurationusEditField
            app.PaddingDurationusEditField = uieditfield(app.LeftPanel, 'numeric');
            app.PaddingDurationusEditField.Limits = [0 10];
            app.PaddingDurationusEditField.ValueDisplayFormat = '%.0f';
            app.PaddingDurationusEditField.Position = [157 210 100 22];
            app.PaddingDurationusEditField.Value = 1;

            % Create CompileandPlotButton
            app.CompileandPlotButton = uibutton(app.LeftPanel, 'push');
            app.CompileandPlotButton.ButtonPushedFcn = createCallbackFcn(app, @CompileandPlotButtonPushed, true);
            app.CompileandPlotButton.BackgroundColor = [0.9608 0.8314 0.7765];
            app.CompileandPlotButton.Position = [21 20 108 22];
            app.CompileandPlotButton.Text = 'Compile and Plot';

            % Create WriteWaveformsButton
            app.WriteWaveformsButton = uibutton(app.LeftPanel, 'push');
            app.WriteWaveformsButton.BackgroundColor = [0.7843 0.9216 0.6902];
            app.WriteWaveformsButton.Position = [151 20 107 22];
            app.WriteWaveformsButton.Text = 'Write Waveforms';

            % Create AmplitudeMax2EditFieldLabel
            app.AmplitudeMax2EditFieldLabel = uilabel(app.LeftPanel);
            app.AmplitudeMax2EditFieldLabel.HorizontalAlignment = 'right';
            app.AmplitudeMax2EditFieldLabel.Position = [25 608 103 22];
            app.AmplitudeMax2EditFieldLabel.Text = 'Amplitude (Max:2)';

            % Create AmplitudeMax2EditField
            app.AmplitudeMax2EditField = uieditfield(app.LeftPanel, 'numeric');
            app.AmplitudeMax2EditField.Limits = [0 2];
            app.AmplitudeMax2EditField.ValueDisplayFormat = '%8.f';
            app.AmplitudeMax2EditField.Position = [143 608 100 22];
            app.AmplitudeMax2EditField.Value = 1;

            % Create RunningCharacteristicsLabel
            app.RunningCharacteristicsLabel = uilabel(app.LeftPanel);
            app.RunningCharacteristicsLabel.FontWeight = 'bold';
            app.RunningCharacteristicsLabel.Position = [26 312 144 22];
            app.RunningCharacteristicsLabel.Text = 'Running Characteristics';

            % Create AWGIPEditFieldLabel
            app.AWGIPEditFieldLabel = uilabel(app.LeftPanel);
            app.AWGIPEditFieldLabel.HorizontalAlignment = 'right';
            app.AWGIPEditFieldLabel.Position = [25 159 55 22];
            app.AWGIPEditFieldLabel.Text = 'AWG IP:';

            % Create AWGIPEditField
            app.AWGIPEditField = uieditfield(app.LeftPanel, 'text');
            app.AWGIPEditField.Position = [111 159 146 18];

            % Create SavePathEditFieldLabel
            app.SavePathEditFieldLabel = uilabel(app.LeftPanel);
            app.SavePathEditFieldLabel.HorizontalAlignment = 'right';
            app.SavePathEditFieldLabel.Position = [24 120 57 22];
            app.SavePathEditFieldLabel.Text = 'SavePath';

            % Create SavePathEditField
            app.SavePathEditField = uieditfield(app.LeftPanel, 'text');
            app.SavePathEditField.Position = [111 120 146 18];

            % Create RightPanel
            app.RightPanel = uipanel(app.GridLayout);
            app.RightPanel.Layout.Row = 1;
            app.RightPanel.Layout.Column = 2;
            app.RightPanel.Scrollable = 'on';

            % Create channel1plot
            app.channel1plot = uiaxes(app.RightPanel);
            title(app.channel1plot, 'Channel 1 OP')
            xlabel(app.channel1plot, 'AWG Ticks')
            ylabel(app.channel1plot, 'Amplitude')
            app.channel1plot.XGrid = 'on';
            app.channel1plot.YGrid = 'on';
            app.channel1plot.Box = 'on';
            app.channel1plot.Position = [59 467 389 142];

            % Create markerplots_resonant
            app.markerplots_resonant = uiaxes(app.RightPanel);
            title(app.markerplots_resonant, 'Marker 1 OP (Resonant and NIDAQ)')
            xlabel(app.markerplots_resonant, 'AWG Ticks')
            ylabel(app.markerplots_resonant, 'State')
            app.markerplots_resonant.YLim = [0 2];
            app.markerplots_resonant.XGrid = 'on';
            app.markerplots_resonant.YGrid = 'on';
            app.markerplots_resonant.ColorOrderIndex = 2;
            app.markerplots_resonant.Box = 'on';
            app.markerplots_resonant.Position = [59 250 389 142];

            % Create markerplots_repump
            app.markerplots_repump = uiaxes(app.RightPanel);
            title(app.markerplots_repump, 'Marker 2 OP (Repump)')
            xlabel(app.markerplots_repump, 'AWG Ticks')
            ylabel(app.markerplots_repump, 'Amplitude')
            app.markerplots_repump.YLim = [0 2];
            app.markerplots_repump.XGrid = 'on';
            app.markerplots_repump.YGrid = 'on';
            app.markerplots_repump.ColorOrderIndex = 3;
            app.markerplots_repump.SortMethod = 'depth';
            app.markerplots_repump.Box = 'on';
            app.markerplots_repump.Position = [59 35 389 142];

            % Show the figure after all components are created
            app.WritetoAWG.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = WriteToAWG_exported_Jul1

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.WritetoAWG)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.WritetoAWG)
        end
    end
end