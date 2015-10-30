-- script to renew plans / update planusage

-- insert
declare @date datetime = getdate()
insert into prov.PlanUsage(CreateDate,ChangeNotes,CustomerPlanId,
							EndDate,IsCurrent,ModifiedDate,
							Month,RenewalCount,RenewDate,
							StartDate,UnitsSent,UserId,Year)
select @date , 'Plan Renewed',Cp.CustomerPlanId,
		DATEADD(d, -1, DATEADD(m, DATEDIFF(m, 0, @date) + 1, 0)),1,@date , 
		9,1,@date,
		DATEADD(month, DATEDIFF(month, 0, @date), 0),0,PU.UserId , 2015
from prov.PlanUsage PU 
	inner join prov.CustomerPlan CP on
			PU.CustomerPlanId = Cp.CustomerPlanId  and CP.IsActive = 1 and PU.IsCurrent = 1
	inner join prov.v_Plan P on P.PlanId = CP.PlanId
		and P.RenewalType = 'Auto' and P.Range = 'Monthly'

-- update
Update prov.PlanUsage set IsCurrent = 0 where month= 8 and year = 2015