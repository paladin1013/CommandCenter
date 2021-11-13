function [methodinfo,structs,enuminfo,ThunkLibName]=nidaqmxprototype(varargin)
%NIDAQMXPROTOTYPE Create structures to define interfaces found in 'NIDAQmx'.

%This function was generated by loadlibrary.m parser version  on Thu Jan 29 14:15:43 2015
%perl options:'NIDAQmx.i -outfile=nidaqmxprototype.m -thunkfile=nicaiu_thunk_pcwin64.c -header=NIDAQmx.h'
ival={cell(1,0)}; % change 0 to the actual number of functions to preallocate the data.
structs=[];enuminfo=[];fcnNum=1;
fcns=struct('name',ival,'calltype',ival,'LHS',ival,'RHS',ival,'alias',ival,'thunkname', ival);
MfilePath=fileparts(mfilename('fullpath'));
ThunkLibName=fullfile(MfilePath,'nicaiu_thunk_pcwin64');
%% Task Control
% int32 __stdcall DAQmxSelfTestDevice ( const char deviceName []); 
fcns.thunkname{fcnNum}='longcstringThunk';fcns.name{fcnNum}='DAQmxSelfTestDevice'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxTaskControl ( TaskHandle taskHandle , int32 action ); 
fcns.thunkname{fcnNum}='longvoidPtrlongThunk';fcns.name{fcnNum}='DAQmxTaskControl'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxResetDevice ( const char deviceName []); 
fcns.thunkname{fcnNum}='longcstringThunk';fcns.name{fcnNum}='DAQmxResetDevice'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxGetErrorString ( int32 errorCode , char errorString [], uInt32 bufferSize ); 
fcns.thunkname{fcnNum}='longlongcstringulongThunk';fcns.name{fcnNum}='DAQmxGetErrorString'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'long', 'cstring', 'ulong'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxGetExtendedErrorInfo ( char errorString [], uInt32 bufferSize ); 
fcns.thunkname{fcnNum}='longcstringulongThunk';fcns.name{fcnNum}='DAQmxGetExtendedErrorInfo'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring', 'ulong'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxClearTask ( TaskHandle taskHandle ); 
fcns.thunkname{fcnNum}='longvoidPtrThunk';fcns.name{fcnNum}='DAQmxClearTask'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateTask ( const char taskName [], TaskHandle * taskHandle ); 
fcns.thunkname{fcnNum}='longcstringvoidPtrThunk';fcns.name{fcnNum}='DAQmxCreateTask'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring', 'voidPtrPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxStartTask ( TaskHandle taskHandle ); 
fcns.thunkname{fcnNum}='longvoidPtrThunk';fcns.name{fcnNum}='DAQmxStartTask'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxStopTask ( TaskHandle taskHandle ); 
fcns.thunkname{fcnNum}='longvoidPtrThunk';fcns.name{fcnNum}='DAQmxStopTask'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxClearTask ( TaskHandle taskHandle ); 
fcns.thunkname{fcnNum}='longvoidPtrThunk';fcns.name{fcnNum}='DAQmxClearTask'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxWaitUntilTaskDone ( TaskHandle taskHandle , float64 timeToWait ); 
fcns.thunkname{fcnNum}='longvoidPtrdoubleThunk';fcns.name{fcnNum}='DAQmxWaitUntilTaskDone'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'double'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxIsTaskDone ( TaskHandle taskHandle , bool32 * isTaskDone ); 
fcns.thunkname{fcnNum}='longvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxIsTaskDone'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxGetSysTasks ( char * data , uInt32 bufferSize ); 
fcns.thunkname{fcnNum}='longcstringulongThunk';fcns.name{fcnNum}='DAQmxGetSysTasks'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring', 'ulong'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetWriteRegenMode ( TaskHandle taskHandle , int32 data ); 
fcns.thunkname{fcnNum}='longvoidPtrlongThunk';fcns.name{fcnNum}='DAQmxSetWriteRegenMode'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetWriteRelativeTo ( TaskHandle taskHandle , int32 data ); 
fcns.thunkname{fcnNum}='longvoidPtrlongThunk';fcns.name{fcnNum}='DAQmxSetWriteRelativeTo'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetWriteOffset ( TaskHandle taskHandle , int32 data ); 
fcns.thunkname{fcnNum}='longvoidPtrlongThunk';fcns.name{fcnNum}='DAQmxSetWriteOffset'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long'};fcnNum=fcnNum+1;

%% Pin Write
% int32 __stdcall DAQmxCreateDOChan ( TaskHandle taskHandle , const char lines [], const char nameToAssignToLines [], int32 lineGrouping ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlongThunk';fcns.name{fcnNum}='DAQmxCreateDOChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateDIChan ( TaskHandle taskHandle , const char lines [], const char nameToAssignToLines [], int32 lineGrouping ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlongThunk';fcns.name{fcnNum}='DAQmxCreateDIChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxWriteDigitalLines ( TaskHandle taskHandle , int32 numSampsPerChan , bool32 autoStart , float64 timeout , bool32 dataLayout , const uInt8 writeArray [], int32 * sampsPerChanWritten , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrlongulongdoubleulongvoidPtrvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxWriteDigitalLines'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'ulong', 'double', 'ulong', 'uint8Ptr', 'longPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateAOVoltageChan ( TaskHandle taskHandle , const char physicalChannel [], const char nameToAssignToChannel [], float64 minVal , float64 maxVal , int32 units , const char customScaleName []); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringdoubledoublelongcstringThunk';fcns.name{fcnNum}='DAQmxCreateAOVoltageChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'double', 'double', 'long', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxWriteAnalogScalarF64 ( TaskHandle taskHandle , bool32 autoStart , float64 timeout , float64 value , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrulongdoubledoublevoidPtrThunk';fcns.name{fcnNum}='DAQmxWriteAnalogScalarF64'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'ulong', 'double', 'double', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxWriteAnalogF64 ( TaskHandle taskHandle , int32 numSampsPerChan , bool32 autoStart , float64 timeout , bool32 dataLayout , const float64 writeArray [], int32 * sampsPerChanWritten , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrlongulongdoubleulongvoidPtrvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxWriteAnalogF64'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'ulong', 'double', 'ulong', 'doublePtr', 'longPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetDOOutputDriveType ( TaskHandle taskHandle , const char channel [], int32 data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringlongThunk';fcns.name{fcnNum}='DAQmxSetDOOutputDriveType'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateDIChan ( TaskHandle taskHandle , const char lines [], const char nameToAssignToLines [], int32 lineGrouping ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlongThunk';fcns.name{fcnNum}='DAQmxCreateDIChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long'};fcnNum=fcnNum+1;

%% Pin Read
% int32 __stdcall DAQmxCreateAIVoltageChan ( TaskHandle taskHandle , const char physicalChannel [], const char nameToAssignToChannel [], int32 terminalConfig , float64 minVal , float64 maxVal , int32 units , const char customScaleName []); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlongdoubledoublelongcstringThunk';fcns.name{fcnNum}='DAQmxCreateAIVoltageChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long', 'double', 'double', 'long', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxReadAnalogScalarF64 ( TaskHandle taskHandle , float64 timeout , float64 * value , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrdoublevoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxReadAnalogScalarF64'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'double', 'doublePtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxReadAnalogF64 ( TaskHandle taskHandle , int32 numSampsPerChan , float64 timeout , bool32 fillMode , float64 readArray [], uInt32 arraySizeInSamps , int32 * sampsPerChanRead , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrlongdoubleulongvoidPtrulongvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxReadAnalogF64'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'double', 'ulong', 'doublePtr', 'ulong', 'longPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxReadCounterScalarU32 ( TaskHandle taskHandle , float64 timeout , uInt32 * value , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrdoublevoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxReadCounterScalarU32'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'double', 'ulongPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxGetReadAvailSampPerChan ( TaskHandle taskHandle , uInt32 * data ); 
fcns.thunkname{fcnNum}='longvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxGetReadAvailSampPerChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxReadCounterU32 ( TaskHandle taskHandle , int32 numSampsPerChan , float64 timeout , uInt32 readArray [], uInt32 arraySizeInSamps , int32 * sampsPerChanRead , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrlongdoublevoidPtrulongvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxReadCounterU32'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'double', 'ulongPtr', 'ulong', 'longPtr', 'ulongPtr'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxReadDigitalLines ( TaskHandle taskHandle , int32 numSampsPerChan , float64 timeout , bool32 fillMode , uInt8 readArray [], uInt32 arraySizeInBytes , int32 * sampsPerChanRead , int32 * numBytesPerSamp , bool32 * reserved ); 
fcns.thunkname{fcnNum}='longvoidPtrlongdoubleulongvoidPtrulongvoidPtrvoidPtrvoidPtrThunk';fcns.name{fcnNum}='DAQmxReadDigitalLines'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'double', 'ulong', 'uint8Ptr', 'ulong', 'longPtr', 'longPtr', 'ulongPtr'};fcnNum=fcnNum+1;

%% Clock/Counter
% int32 __stdcall DAQmxCfgSampClkTiming ( TaskHandle taskHandle , const char source [], float64 rate , int32 activeEdge , int32 sampleMode , uInt64 sampsPerChan ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringdoublelonglonguint64Thunk';fcns.name{fcnNum}='DAQmxCfgSampClkTiming'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'double', 'long', 'long', 'uint64'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateCOPulseChanFreq ( TaskHandle taskHandle , const char counter [], const char nameToAssignToChannel [], int32 units , int32 idleState , float64 initialDelay , float64 freq , float64 dutyCycle ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlonglongdoubledoubledoubleThunk';fcns.name{fcnNum}='DAQmxCreateCOPulseChanFreq'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long', 'long', 'double', 'double', 'double'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCfgImplicitTiming ( TaskHandle taskHandle , int32 sampleMode , uInt64 sampsPerChan ); 
fcns.thunkname{fcnNum}='longvoidPtrlonguint64Thunk';fcns.name{fcnNum}='DAQmxCfgImplicitTiming'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'long', 'uint64'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetCOPulseTerm ( TaskHandle taskHandle , const char channel [], const char * data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringThunk';fcns.name{fcnNum}='DAQmxSetCOPulseTerm'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateCICountEdgesChan ( TaskHandle taskHandle , const char counter [], const char nameToAssignToChannel [], int32 edge , uInt32 initialCount , int32 countDirection ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringlongulonglongThunk';fcns.name{fcnNum}='DAQmxCreateCICountEdgesChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'long', 'ulong', 'long'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetCICountEdgesTerm ( TaskHandle taskHandle , const char channel [], const char * data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringThunk';fcns.name{fcnNum}='DAQmxSetCICountEdgesTerm'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCreateCIPulseWidthChan ( TaskHandle taskHandle , const char counter [], const char nameToAssignToChannel [], float64 minVal , float64 maxVal , int32 units , int32 startingEdge , const char customScaleName []); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringdoubledoublelonglongcstringThunk';fcns.name{fcnNum}='DAQmxCreateCIPulseWidthChan'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring', 'double', 'double', 'long', 'long', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetCIPulseWidthTerm ( TaskHandle taskHandle , const char channel [], const char * data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringThunk';fcns.name{fcnNum}='DAQmxSetCIPulseWidthTerm'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetCICtrTimebaseSrc ( TaskHandle taskHandle , const char channel [], const char * data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringcstringThunk';fcns.name{fcnNum}='DAQmxSetCICtrTimebaseSrc'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'cstring'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxSetCIDupCountPrevent ( TaskHandle taskHandle , const char channel [], bool32 data ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringulongThunk';fcns.name{fcnNum}='DAQmxSetCIDupCountPrevent'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'ulong'};fcnNum=fcnNum+1;
% int32 __stdcall DAQmxCfgDigEdgeStartTrig ( TaskHandle taskHandle , const char triggerSource [], int32 triggerEdge ); 
fcns.thunkname{fcnNum}='longvoidPtrcstringlongThunk';fcns.name{fcnNum}='DAQmxCfgDigEdgeStartTrig'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'voidPtr', 'cstring', 'long'};fcnNum=fcnNum+1;

%% Device Info
% int32 __stdcall DAQmxGetDevCOPhysicalChans ( const char device [], char * data , uInt32 bufferSize ); 
fcns.thunkname{fcnNum}='longcstringcstringulongThunk';fcns.name{fcnNum}='DAQmxGetDevCOPhysicalChans'; fcns.calltype{fcnNum}='Thunk'; fcns.LHS{fcnNum}='long'; fcns.RHS{fcnNum}={'cstring', 'cstring', 'ulong'};fcnNum=fcnNum+1;


methodinfo=fcns;