function s = BuildPulseSequence(obj)
s = sequence('LifetimeMeasurement');
repumpChannel = channel('repump','color','g','hardware',obj.repumpLaser.PB_line-1);
resTriggerChannel = channel('resonant trigger','color','r','hardware',obj.AWGPBline-1);
resChannel = channel('resonant', 'color', 'r', 'hardware', obj.resLaser.PB_line-1);
APDchannel = channel('APDgate','color','b','hardware',obj.APDline-1,'counter','APD1');
% MWChannel = channel('MW', 'color', 'k', 'hardware', obj.MWline - 1);

SyncChannel = channel('PicoHarpSync', 'color', 'c', 'hardware', obj.SyncPBLine-1);
% s.channelOrder = [repumpChannel, resTriggerChannel, APDchannel,MWChannel, SyncChannel];
s.channelOrder = [repumpChannel, resTriggerChannel, resChannel, APDchannel, SyncChannel];

g = node(s.StartNode,repumpChannel,'delta',0);
g = node(g,repumpChannel,'units','us','delta',obj.repumpTime_us);



%if obj.invert_MW_line
%     g = node(g,MWChannel,'units','us','delta',0);
%end


PBTriggerTime_us = 0.01;    


r_s1 = node(g,resTriggerChannel,'units','us','delta',obj.resOffset_us);
node(r_s1, resChannel, 'units', 'us', 'delta', 0);
node(r_s1,APDchannel,'units','us', 'delta',0);

% m = node(r_s1,MWChannel, 'units','us','delta',0);

% r_s1_begin_sync = node(r_s1,SyncChannel,'units','us', 'delta',obj.syncPulseBias_begin);
% test = node(r_s1_begin_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);



r_s1_begin_sync = node(r_s1,SyncChannel,'units','us', 'delta',-1.5+obj.syncPulseBias_begin);
test = node(r_s1_begin_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);

for sync_space_distance = 1:3
    test = node(test, SyncChannel,'units','us', 'delta', 0.5-obj.SyncPulseWidth_us);
    test = node(test, SyncChannel,'units','us', 'delta', obj.SyncPulseWidth_us);
end





r_e1 = node(r_s1,APDchannel,'units','us','delta',obj.PulsePeriod_ns*obj.PulseRepeat /1000);
node(r_e1, resChannel, 'units','us','delta', 0);
node(r_s1,resTriggerChannel,'units','us','delta',PBTriggerTime_us);
% m = node(r_e1,MWChannel, 'units','us','delta',0);


r_s1_end_sync = node(r_e1,SyncChannel,'units','us', 'delta',obj.syncPulseBias_end);
node(r_s1_end_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);
% node(r_e1,APDchannel,'units','us','delta',-obj.CounterLength_us);
% node(r_e1,APDchannel,'units','us','delta',0);
% r_s2 = node(r_e1,resTriggerChannel,'units','us','delta',obj.readoutPulseDelay_us);
% node(r_s2,APDchannel,'units','us','delta',0);

% r_s2_begin_sync = node(r_s2,SyncChannel,'units','us', 'delta',obj.syncPulseBias_begin);
% node(r_s2_begin_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);

% node(r_s2,APDchannel,'units','us','delta',obj.CounterLength_us);


% r_e2 = node(r_s2,resTriggerChannel,'units','us','delta',obj.readoutPulseTime_us);


% r_s2_end_sync = node(r_e2,SyncChannel,'units','us', 'delta',obj.syncPulseBias_end);
% node(r_s2_end_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);
% % node(r_e2,APDchannel,'units','us','delta',0);
% % node(r_e2,APDchannel,'units','us','delta',-obj.CounterLength_us);

% % m = node(r_e0,MWChannel, 'units','us','delta',obj.readoutPulseDelay_us/2);


% if obj.UseMW
%     m = node(r_e2,MWChannel, 'units','us','delta',0);
% end

% % 

% r_s3 = node(r_e2, resTriggerChannel, 'units', 'us', 'delta', obj.readoutPulseDelay_us);
% node(r_s3,APDchannel,'units','us','delta',0);

% r_s3_begin_sync = node(r_s3,SyncChannel,'units','us', 'delta',obj.syncPulseBias_begin);
% node(r_s3_begin_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);


% r_e3 = node(r_s3, resTriggerChannel, 'units', 'us', 'delta', obj.readoutPulseTime_us);
% node(r_e3, APDchannel,'units','us','delta',0);

% r_s3_end_sync = node(r_e3,SyncChannel,'units','us', 'delta',obj.syncPulseBias_end);
% node(r_s3_end_sync,SyncChannel,'units','us', 'delta',obj.SyncPulseWidth_us);
% m = node(r_e3,MWChannel, 'units','us','delta',0);


% g = node(r_e3,repumpChannel,'units','us','delta',0);
% s.draw
end

