
%%
AWG=AWG70002B('visa',"18.25.28.214");
%% Setting up AWG parameters
AWG.Amplitude = 1;   %Normalized units
AWG.SampleRate =1*1e9;
AWG.phaseOffset = 0;
sampling = AWG.SampleRate;
phase = AWG.phaseOffset;
vpp = AWG.Amplitude;
%
AWG.SetSampleRate();
AWG.setRunMode('c');
freq_start = 0.01;  % in GHz
freq_end = 0.3;    % in GHz
points=15;
loops=1000;
%
repumpTime_set= 0.5 % in us
resTime_set= 1 % in us
paddingTime_set=0.5; % in us
resDuration = linspace(0,resTime_set*1e-06,resTime_set*1e-06*sampling);
%
ple_type='fast';
repump_type='Every Sweep';
%
% define time durations in AWG units
repumpTime = ceil(repumpTime_set*sampling*1e-06);
resTime = ceil(resTime_set*sampling*1e-06);
paddingTime = ceil(paddingTime_set*sampling*1e-06);    % delay between repump and res


            if strcmp(ple_type,'fast')
                if strcmp(repump_type,'Every Point')
                SeqName=['PLE_' ple_type '_EP_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
                else
                SeqName=['PLE_' ple_type '_ES_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
                end
            else 
                SeqName=['PLE_' ple_type '_fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_pts_' num2str(points) '_lps_' num2str(loops)];           
            end
            
            % Basic waveform compiling setting - change to compile only
            % otherwise, the for loop chokes up and errors
            AWG.writeToSocket(sprintf('BWAV:COMP:CASS 0'));
            AWG.writeToSocket(sprintf('BWAV:COMP:CHAN NONE'));

            % 8 bit DAC resolution, 2 marker bits
            AWG.writeToSocket(sprintf('SOUR1:DAC:RES 8')); % channel 1
            AWG.writeToSocket(sprintf('SOUR2:DAC:RES 8')); % channel 2

           
            freqList =1e09.* linspace(freq_start, freq_end,points);
            
            savePath='H:\\AWG70002B';% for local computer to save to Houston
            load_dir='Z:\\Experiments\\AWG70002B'; % for AWG to retrieve the data from
            %SAVE directly to AWG
            
            mkdir([savePath '\\' ple_type '\\'], ['fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)]);
            % Makes waveform save directory
            dir_save=[savePath '\\' ple_type '\\fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)];
            load_dir=[load_dir '\\' ple_type '\\fs_' num2str(sampling*1e-09) '_fst_' num2str(freq_start) '_fen_' num2str(freq_end) '_points_' num2str(points)];
            seq_save_dir=['Z:\\Experiments\\AWG70002B\\sequences\\' ple_type '\\'];
            
%%           
                if strcmp(ple_type,'fast') % one long waveform, looping "samples" times
                    AWG.initSequence(SeqName,1)
                    channel1 = [];
                    channel2 = [];
                    c1m1=[];
                    c1m2=[];
                    c2m1=[];
                    c2m2=[];
                    if strcmp(repump_type,'Every Point')
                        for i = 1:points
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

                        timeId= ['PLE_' ple_type '_EP_' datestr(now,'mm_dd_yy_HHMM')];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
                           
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  '\\' fName{1}, '",TXT8']));
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        %AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
                        %AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);

                        AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
                        AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});

                        AWG.addLoopToSequenceStep(SeqName,1,loops);

                    elseif strcmp(repump_type,'Every Sweep')
                        channel1 = [channel1 zeros(1,repumpTime)];
                        channel2 = [channel2 zeros(1,repumpTime)];
                        c1m1 = [c1m1 zeros(1,repumpTime)];
                        c1m2 = [c1m2 ones(1,repumpTime)];
                        c2m1 = [c2m1 zeros(1,repumpTime)];
                        c2m2 = [c2m2 zeros(1,repumpTime)];
                        for i = 1:  points
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

                        timeId= ['PLE_'   ple_type '_ES_' datestr(now,'mm_dd_yy_HHMM')];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
                           
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1},'", "' load_dir  '\\' fName{1}, '",TXT8']));
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2},'", "' load_dir  '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        %AWG.create_waveform(sequenceList{1},channel1,c1m1,c1m2);
                        %AWG.create_waveform(sequenceList{2},channel2,c2m1,c2m2);

                        pause(1);

                        AWG.addWaveformToSequence(1, 1, SeqName, sequenceList{1});
                        AWG.addWaveformToSequence(1, 2, SeqName, sequenceList{2});

                        AWG.addLoopToSequenceStep(SeqName,1,loops);
                    else
                        fprintf('Defined repump type incorrectly!');
                        err;
                    end


                else % sequence containing numPoints steps, each step is a sine waveform
                    AWG.initSequence(SeqName,points)
                    for i = 1:  points
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

                        timeId= ['PLE_' , ple_type, datestr(now,'mm_dd_yy'), '_wav',num2str(i)];

                        fName{1}=[ timeId '_chn1.txt'];
                        fName{2}=[ timeId '_chn2.txt'];

                        writeWavHouston([dir_save '\\' fName{1}],channel1,c1m1,c1m2);% writes to .txt file on Houston 
                        writeWavHouston([dir_save '\\' fName{2}],channel2,c2m1,c2m2);% writes to .txt file on Houston 
                           
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{1,i},'", "' load_dir  '\\' fName{1}, '",TXT8']));
                        AWG.writeToSocket(sprintf(['MMEM:IMP "', sequenceList{2,i},'", "' load_dir  '\\' fName{2}, '",TXT8']));
                        % Loads from .txt file on Houston 

                        pause(1);

                        AWG.addWaveformToSequence(i, 1, SeqName, sequenceList{1,i});
                        AWG.addWaveformToSequence(i, 2, SeqName, sequenceList{2,i});

                        AWG.addLoopToSequenceStep(SeqName ,i,loops);
                        % Set wait behavior to OFF
                        AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:WINP "%s", %s',...
                            i, SeqName, 'OFF'));

                        disp(['Uploaded freq point ' num2str(i)]);
                    end
                    % writing the last step to jump to 1st step
                    AWG.writeToSocket(sprintf('SLIS:SEQ:STEP%d:GOTO "%s", %s',...
                        i, SeqName, 'FIRS'));
                end
            AWG.writeToSocket(sprintf(['MMEM:SAVE:SEQUENCE "', SeqName, '", "' seq_save_dir  '\\' SeqName '.SEQX"']));

        
        %writeWavHouston(obj,fileName,channel,mrk1,mrk2)
        function writeWavHouston(fileName,channel,mrk1,mrk2)
            if isfile(fileName)
                disp('Warning! Existing file will be overwritten!');
            end
            fid = fopen(fileName, 'wt' );
            for wL= 1:numel(channel)
                fprintf(fid, '%f,%f,%f\n', channel(wL), mrk1(wL), mrk2(wL));
            end
            fclose(fid);
        end