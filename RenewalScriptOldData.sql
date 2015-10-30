declare @date datetime = getdate()

DECLARE @userData TABLE(
    UserId int NOT NULL,
    CustomerPLanId int NOT NULL,
	IsCurrent bit NOT NULL,
    RenewalType varchar(30) NOT NULL,
	range varchar(30) NOT NULL,
    AllowedRenewals int NULL,
	RenewalCount int NOT NULL,
    Name varchar(30) NOT NULL,
	Address varchar(300) NOT NULL , 
	Month int not null , 
	Year int not null
);

insert into @userData
select PU.UserId , 
	PU.CustomerPLanId , 
	PU.IsCurrent , 
	P.RenewalType,
	P.range  , 
	CP.AllowedRenewals as AllowedRenewals,
	isnull(PU.RenewalCount,0) as RenewalCount, U.Name , U.Address , 
	PU.Month , PU.Year
from Prov.PlanUsage PU 
inner join prov.CustomerPlan CP on 
	CP.CustomerPlanId = PU.CustomerplanId and PU.IsCurrent = 1
inner join prov.v_Plan P on 
	P.PlanId = CP.PlanId and P.Range = 'Monthly'
inner join users U  on 
	U.userid = PU.UserId;

---- insert new record
insert into prov.PlanUsage(CreateDate,ChangeNotes,CustomerPlanId,
							EndDate,IsCurrent,ModifiedDate,
							Month,RenewalCount,RenewDate,
							StartDate,UnitsSent,UserId,Year,IsInUse)
select @date , 'Plan Renewed',R.CustomerPlanId,
		DATEADD(s, -1, DATEADD(m, DATEDIFF(m, 0, @date) + 1, 0)),1,@date , 
		10, R.RenewalCount + 1,@date,
		DATEADD(month, DATEDIFF(month, 0, @date), 0),0,R.UserId , 2015,1
from @userData R 
where (R.AllowedRenewals is null or 
(R.AllowedRenewals > R.RenewalCount))
and R.Range = 'Monthly' and R.RenewalType = 'Auto'
and R.USerID not in ( select userid from prov.PlanUsage PPU
where  R.Month = 10 )

--select * from @userData where AllowedRenewals is null
Update prov.PlanUsage 
	set ModifiedDate = @date , 
		IsCurrent = 0 ,IsInUse = 0
	from prov.PlanUsage PU 
	inner join @userData R on 
		PU.CustomerPlanId = R.CustomerPLanId and
		PU.UserId = R.UserId and 
		PU.IsCurrent = 1 and 
		R.Range = 'Monthly' and PU.[Month] = 9 and PU.[Year] = 2015

-- already existing record
;with cte as (select rnk = ROW_NUMBER() OVER(partition by UserId ORDER BY createdate desc) 
,UserId , CustomerPlanId 
from prov.PlanUsage where 
month = 10 and year = 2015 and IsCurrent = 0
)
Update PU set IsCurrent = 1 ,IsInUse=1, ModifiedDate = @date,
ChangeNotes = ChangeNotes + ' ; Plan Started'
from prov.PlanUsage PU inner join cte U 
on U.UserId = PU.UserId and U.rnk = 1
and PU.CustomerPlanId = U.CustomerPlanId
and month = 10 and year = 2015 and IsCurrent = 0




