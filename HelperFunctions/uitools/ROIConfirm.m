function ROIConfirm(hObj, event)
    if isprop(event, 'Button') && event.Button == 3
        uiresume;
        return;
    end
    if isprop(event, 'Key') && strcmp(event.Key, 'return')
        uiresume;
        return;
    end
end