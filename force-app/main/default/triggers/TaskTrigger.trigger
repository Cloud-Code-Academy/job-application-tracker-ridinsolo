trigger TaskTrigger on Task (after update) {
    if (Trigger.isAfter && Trigger.isUpdate) {
        WeeklyTaskHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}